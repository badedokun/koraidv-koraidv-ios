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

        // Stage 1 — document segmentation (best for the white/back card).
        if #available(iOS 15.0, *), let quad = detectWithSegmentation(cgImage) {
            if let out = warp(ci: ci, w: w, h: h, quad: quad) { return out }
        }
        // Stage 2 — generic rectangle detector.
        if let quad = detectWithRectangles(cgImage) {
            if let out = warp(ci: ci, w: w, h: h, quad: quad) { return out }
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

    // MARK: - Warp

    private static func warp(ci: CIImage, w: CGFloat, h: CGFloat, quad: VNRectangleObservation) -> UIImage? {
        // Vision corners: normalized (0–1), origin BOTTOM-LEFT — same convention
        // as CIImage, so scaling by pixel dimensions maps straight across.
        func px(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * w, y: p.y * h) }

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: px(quad.topLeft)), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: px(quad.topRight)), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: px(quad.bottomLeft)), forKey: "inputBottomLeft")
        filter.setValue(CIVector(cgPoint: px(quad.bottomRight)), forKey: "inputBottomRight")

        guard let corrected = filter.outputImage else { return nil }
        let ext = corrected.extent
        guard ext.width > 1, ext.height > 1, ext.width.isFinite, ext.height.isFinite else {
            return nil
        }

        let outW = outputWidth
        let outH = (outputWidth / id1Aspect).rounded()
        let scaled = corrected
            .transformed(by: CGAffineTransform(translationX: -ext.origin.x, y: -ext.origin.y))
            .transformed(by: CGAffineTransform(scaleX: outW / ext.width, y: outH / ext.height))

        let context = CIContext(options: nil)
        guard let outCG = context.createCGImage(
            scaled,
            from: CGRect(x: 0, y: 0, width: outW, height: outH)
        ) else {
            return nil
        }
        return UIImage(cgImage: outCG)
    }
}
