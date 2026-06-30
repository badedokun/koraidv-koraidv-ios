import UIKit
import Vision
import CoreImage

/// Detects the document quadrilateral in a captured photo and perspective-warps
/// it to a frame-filling ID-1 (1.586:1) image so the review frame is always
/// edge-to-edge regardless of how the user held the camera — and IDENTICAL for
/// front and back.
///
/// **Port of the Android `DocumentDewarper`** (OpenCV Canny + findContours +
/// warpPerspective). iOS gets the same result from built-in frameworks, with a
/// two-stage detector chain:
///
///  1. `VNDetectDocumentSegmentationRequest` (iOS 15+) — Apple's purpose-built
///     document detector. It segments the whole card as one region regardless
///     of its internal content, so it nails the barcode-dominated DL BACK that
///     defeats generic rectangle detection (the back is a mostly-white card
///     whose strongest edges are the barcodes themselves).
///  2. `VNDetectRectanglesRequest` — fallback for the rare frame the segmenter
///     can't resolve (and a safety net on edge OSes).
///
/// `CIPerspectiveCorrection` then rectifies the detected quad to ID-1.
///
/// Returns `nil` when neither stage finds a convincing quad (the caller keeps
/// its existing crop / the original capture), so this can only improve framing.
enum DocumentDewarper {

    private static let outputWidth: CGFloat = 1600
    private static let id1Aspect: CGFloat = 1.586
    private static let minBoxAreaFraction: CGFloat = 0.18   // ≈ Android MIN_AREA_FRACTION

    static func dewarp(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let ci = CIImage(cgImage: cgImage)
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)

        _ = ci  // (CIImage no longer needed — see cropToQuad note)
        // Stage 1 — document segmentation (best for the white/back card).
        if #available(iOS 15.0, *), let quad = detectWithSegmentation(cgImage) {
            if let out = cropToQuad(cgImage: cgImage, w: w, h: h, quad: quad) { return out }
        }
        // Stage 2 — generic rectangle detector.
        if let quad = detectWithRectangles(cgImage) {
            if let out = cropToQuad(cgImage: cgImage, w: w, h: h, quad: quad) { return out }
        }
        KoraIDV.log("DocumentDewarper: no quadrilateral found")
        return nil
    }

    // MARK: - Detection

    @available(iOS 15.0, *)
    private static func detectWithSegmentation(_ cgImage: CGImage) -> VNRectangleObservation? {
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            KoraIDV.log("DocumentDewarper: segmentation request failed: \(error)")
            return nil
        }
        guard let obs = request.results?.first,
              obs.confidence >= 0.5,
              (obs.boundingBox.width * obs.boundingBox.height) >= minBoxAreaFraction
        else { return nil }
        return obs
    }

    private static func detectWithRectangles(_ cgImage: CGImage) -> VNRectangleObservation? {
        // Vision aspect ratios are short-edge / long-edge (≤ 1). ID-1 ≈ 0.63.
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.45
        request.maximumAspectRatio = 0.85
        request.minimumSize = Float(minBoxAreaFraction)
        request.minimumConfidence = 0.5
        request.maximumObservations = 8
        request.quadratureTolerance = 35

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            KoraIDV.log("DocumentDewarper: rectangles request failed: \(error)")
            return nil
        }
        // Largest by normalized bounding-box area.
        return request.results?.max(by: {
            ($0.boundingBox.width * $0.boundingBox.height) <
            ($1.boundingBox.width * $1.boundingBox.height)
        })
    }

    // MARK: - Crop

    /// **Tight axis-aligned crop to the detected document (passport stretch
    /// fix, 2026-06-30).** Replaces the previous `CIPerspectiveCorrection`
    /// warp, which forced/мis-sized the output aspect and stretched non-card
    /// documents (a passport data page is ~1.42:1, not the ID-1 1.586:1 a
    /// card is). A pure crop to the detected quad's bounding box CANNOT
    /// distort the aspect — it returns the document at its true proportions,
    /// just tightly framed (the same un-stretched look as the legacy fallback,
    /// but tighter). It still fixes the loose/overshoot framing the dewarp was
    /// added for. We trade away perspective de-skew for a guarantee of no
    /// stretch; documents are held roughly flat in the card window, so residual
    /// tilt is minimal and acceptable.
    private static func cropToQuad(cgImage: CGImage, w: CGFloat, h: CGFloat, quad: VNRectangleObservation) -> UIImage? {
        let xs = [quad.topLeft.x, quad.topRight.x, quad.bottomLeft.x, quad.bottomRight.x]
        let ys = [quad.topLeft.y, quad.topRight.y, quad.bottomLeft.y, quad.bottomRight.y]

        // Vision normalized → pixels (Vision origin is BOTTOM-LEFT).
        var minX = (xs.min() ?? 0) * w
        var maxX = (xs.max() ?? 0) * w
        var minY = (ys.min() ?? 0) * h
        var maxY = (ys.max() ?? 0) * h

        // Small symmetric padding so we don't shave the document edge.
        let padX = (maxX - minX) * 0.02
        let padY = (maxY - minY) * 0.02
        minX = max(0, minX - padX); maxX = min(w, maxX + padX)
        minY = max(0, minY - padY); maxY = min(h, maxY + padY)

        // **Keep the MRZ; widen to the capture-frame aspect (BanffPay v1.9.7
        // retest, 2026-06-30).** For a passport the machine-readable zone (MRZ)
        // runs along the BOTTOM of the data page and is the critical region —
        // it must ALWAYS be in view, more important than excluding the adjacent
        // page. So we preserve the FULL detected document HEIGHT (never trim
        // height to reach the aspect — that was clipping the MRZ) and only WIDEN
        // to the 1.586:1 capture-frame aspect for review consistency. A passport
        // (~1.42:1) gets a small symmetric side margin to reach 1.586 (which may
        // include a sliver of the facing page — acceptable). If the required
        // width would exceed the image, we keep a slightly taller-than-1.586
        // frame rather than lose the MRZ. Still a pure crop → no stretch.
        let aspect: CGFloat = 1.586
        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2
        let ch = min(maxY - minY, h)
        var cw = ch * aspect
        if cw > w { cw = w }                 // accept a touch taller than 1.586 to keep the MRZ
        guard cw > 1, ch > 1 else { return nil }
        var cropX = cx - cw / 2
        var cropYv = cy - ch / 2   // Vision (bottom-left) pixel coords
        cropX = min(max(0, cropX), w - cw)
        cropYv = min(max(0, cropYv), h - ch)

        // CGImage cropping uses a TOP-LEFT origin, so flip Y.
        let cropRect = CGRect(x: cropX, y: h - (cropYv + ch), width: cw, height: ch)
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: cropped)
    }
}
