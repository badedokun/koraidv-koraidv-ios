import Vision
import UIKit
import CoreGraphics

/// Enforces the KoraIDV eyeglasses policy at capture time: the subject's eyes
/// MUST be clearly visible in the selfie. Rejects sunglasses — dark, tinted,
/// AND mirrored/reflective — and heavy glare. Clear prescription glasses pass.
///
/// Heuristic (no ML model): measure the eye region against the rest of the
/// face on FOUR signals, because no single one catches every lens:
///   • DARK lenses   → eye region much darker than the face.
///   • MIRRORED      → eye region BRIGHTER than the face, and/or many specular
///                     (blown-out) pixels from reflections of the scene.
///   • TINTED/colour → eye region noticeably more colour-saturated than the
///                     face skin (a real eye's sclera is neutral white).
///   • FLAT          → eye region with almost no contrast (no eye structure).
///
/// Every capture logs its metrics (`eye-check: …`) when debug logging is on, so
/// thresholds can be calibrated from real device data rather than guessed.
enum EyeVisibilityChecker {

    enum Outcome {
        case clear
        case sunglasses     // dark lenses
        case reflective     // mirrored / reflective / strong glare
        case tinted         // colour tint over the eyes
        case obscured       // flat — no eye structure
        case noFace         // no face — let other gates handle it
        case tooDark        // scene too dark to confirm eye visibility → retake in light

        // FAIL CLOSED: anything that isn't a confirmed-clear eye blocks the
        // capture — including .noFace. The old fail-open on .noFace let
        // sunglasses through whenever face detection blipped on a frame
        // (cold first capture / rapid retakes), which is exactly the
        // "hammer it enough and it slips through" pattern (BanffPay 2026-06-30).
        var rejects: Bool { self != .clear }
        var message: String {
            switch self {
            case .tooDark: return L10n.tr("koraidv.selfie.too_dark")
            default:       return L10n.tr("koraidv.selfie.remove_sunglasses")
            }
        }
    }

    // Tunable thresholds (BanffPay strict mode, 2026-06-30). CALIBRATED from
    // on-device readings — mirrored sunglasses vs. bare eyes, same subject/room:
    //   sunglasses: lumaR 0.70  bright 0.06  satR 0.82
    //   bare eyes : lumaR 0.88  bright 0.00  satR 1.19
    // Two independent signals separate them with margin: specular fraction
    // (reflections) and saturation ratio (a real eye is ≥ face-skin colour; a
    // neutral reflective/dark lens is much less).
    // TIGHTENED (BanffPay 2026-06-30, "make it fail closed every time"). The
    // gate must POSITIVELY confirm a clear eye; the old thresholds let mirrored
    // lenses slip through under some lighting/angles. Margins are set against the
    // measured bare-eye band (lumaR 0.88–0.98, bright 0.00, satR 1.13–1.19) so a
    // real eye still passes, but anything dimmer / more reflective / less colour
    // than that rejects. (Sunglasses measured at lumaR 0.70, bright 0.06,
    // satR 0.82 — now caught on all three signals, with headroom for variation.)
    private static let darkRatioReject: Double    = 0.78   // eyes < 78% of face brightness → lens (was 0.62)
    private static let brightRatioReject: Double  = 1.08   // eyes > 108% of face brightness → bright reflective
    private static let specularFracReject: Double = 0.025  // ≥2.5% blown-out pixels → reflections (was 0.035)
    private static let satLowReject: Double       = 0.95   // eye colour < 95% of face → neutral lens (was 0.85)
    private static let satHighReject: Double      = 1.6    // eye colour >> face → colour tint
    private static let satHighAbs: Double         = 0.30   // …and absolutely colourful
    private static let minEyeContrast: Double     = 0.10   // eye-region std below this → flat tint
    // Low-light fail-closed (BanffPay night test, 2026-06-30). In the dark the
    // lens and face are both dim so the brightness RATIO can't separate them and
    // there are no reflections to catch — the only safe move is to require
    // enough light to actually see the eyes. Measured: night captures fMean
    // 0.27–0.28 (both sunglasses AND bare eyes), a usable dim selfie ≈ 0.36.
    private static let lowLightFloor: Double      = 0.30   // face-region mean luma below this → too dark

    /// Last computed metric line — surfaced on the review screen under debug
    /// logging so QA can read real numbers off a screenshot for calibration.
    static var lastDebug: String = ""

    static func check(_ image: UIImage) -> Outcome {
        guard let cg = image.cgImage else {
            lastDebug = "eye: no cgImage → reject (fail-closed)"; return .noFace
        }
        let imageSize = CGSize(width: cg.width, height: cg.height)

        // Detect the face, retrying a few times. Vision can transiently return
        // no result (cold first call, resource pressure) and the captured still
        // can differ from the settled preview. A real selfie ALWAYS has a face
        // (capture auto-fired on a stable one), so if we still can't find it the
        // frame is unusable — we FAIL CLOSED (→ retake) rather than pass it
        // unchecked.
        var face: VNFaceObservation?
        for _ in 0..<3 {
            let req = VNDetectFaceLandmarksRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try handler.perform([req]) } catch { continue }
            if let f = req.results?.max(by: {
                ($0.boundingBox.width * $0.boundingBox.height) < ($1.boundingBox.width * $1.boundingBox.height)
            }) { face = f; break }
        }
        guard let face = face else {
            lastDebug = "eye: no face after retries → reject (fail-closed)"
            KoraIDV.log(lastDebug)
            return .noFace
        }

        guard let lm = face.landmarks,
              let leftEye = lm.leftEye, let rightEye = lm.rightEye else {
            KoraIDV.log("eye-check: no eye landmarks → sunglasses")
            return .sunglasses                                  // opaque lenses Vision can't resolve
        }

        guard let sampler = PixelSampler(cgImage: cg) else { return .noFace }

        let eyePts = leftEye.pointsInImage(imageSize: imageSize)
                   + rightEye.pointsInImage(imageSize: imageSize)
        let eye = sampler.stats(forPoints: eyePts, expand: 0.35)
        let faceRef = sampler.stats(forNormalizedRect: face.boundingBox, imageSize: imageSize)

        guard eye.count > 0, faceRef.lumaMean > 0.02 else { return .clear }

        let ratio = eye.lumaMean / faceRef.lumaMean
        let satRatio = eye.satMean / max(faceRef.satMean, 0.01)

        let outcome: Outcome
        if faceRef.lumaMean < lowLightFloor {
            outcome = .tooDark                                      // too dark to confirm eyes → retake in light
        } else if ratio < darkRatioReject {
            outcome = .sunglasses                                   // dark lenses
        } else if ratio > brightRatioReject || eye.brightFraction > specularFracReject {
            outcome = .reflective                                   // bright / mirrored reflections
        } else if satRatio < satLowReject {
            outcome = .reflective                                   // neutral lens — eyes far less colourful than face
        } else if satRatio > satHighReject && eye.satMean > satHighAbs {
            outcome = .tinted                                       // colour tint over the eyes
        } else if eye.lumaStd < minEyeContrast {
            outcome = .obscured                                     // flat — no eye structure
        } else {
            outcome = .clear
        }

        lastDebug = String(format:
            "eye lumaR=%.2f std=%.2f bright=%.2f satR=%.2f fMean=%.2f eMean=%.2f → %@",
            ratio, eye.lumaStd, eye.brightFraction, satRatio, faceRef.lumaMean, eye.lumaMean,
            "\(outcome)")
        KoraIDV.log(lastDebug)
        return outcome
    }
}

/// Luminance + colour-saturation statistics over image regions. Points/rects
/// are in Vision's bottom-left image space; the sampler flips to the buffer's
/// top-left rows internally.
private struct RegionStats {
    let lumaMean: Double
    let lumaStd: Double
    let brightFraction: Double  // fraction of near-blown-out pixels (luma > 0.85)
    let satMean: Double         // mean HSV saturation
    let count: Int
}

private struct PixelSampler {
    let width: Int
    let height: Int
    let rgba: [UInt8]

    init?(cgImage: CGImage) {
        let w = cgImage.width, h = cgImage.height
        guard w > 0, h > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let bitmap = CGImageAlphaInfo.premultipliedLast.rawValue
        let ok = buf.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: space, bitmapInfo: bitmap
            ) else { return false }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        self.width = w; self.height = h; self.rgba = buf
    }

    func stats(forPoints pts: [CGPoint], expand: CGFloat) -> RegionStats {
        guard !pts.isEmpty else { return RegionStats(lumaMean: 0, lumaStd: 0, brightFraction: 0, satMean: 0, count: 0) }
        var minX = pts[0].x, maxX = pts[0].x, minY = pts[0].y, maxY = pts[0].y
        for p in pts { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) }
        let ew = (maxX - minX) * expand, eh = (maxY - minY) * expand
        return statsInRect(minX: minX - ew, maxX: maxX + ew, minYBottom: minY - eh, maxYBottom: maxY + eh)
    }

    func stats(forNormalizedRect r: CGRect, imageSize: CGSize) -> RegionStats {
        statsInRect(minX: r.minX * imageSize.width, maxX: r.maxX * imageSize.width,
                    minYBottom: r.minY * imageSize.height, maxYBottom: r.maxY * imageSize.height)
    }

    private func statsInRect(minX: CGFloat, maxX: CGFloat, minYBottom: CGFloat, maxYBottom: CGFloat) -> RegionStats {
        let x0 = max(0, Int(minX)), x1 = min(width - 1, Int(maxX))
        let yTop0 = max(0, Int(CGFloat(height) - maxYBottom))   // bottom-left → top-left rows
        let yTop1 = min(height - 1, Int(CGFloat(height) - minYBottom))
        guard x1 > x0, yTop1 > yTop0 else { return RegionStats(lumaMean: 0, lumaStd: 0, brightFraction: 0, satMean: 0, count: 0) }
        var sum = 0.0, sumSq = 0.0, satSum = 0.0, n = 0, bright = 0
        var y = yTop0
        while y <= yTop1 {
            let row = y * width * 4
            var x = x0
            while x <= x1 {
                let i = row + x * 4
                let r = Double(rgba[i]), g = Double(rgba[i + 1]), b = Double(rgba[i + 2])
                let luma = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
                let mx = max(r, max(g, b)), mn = min(r, min(g, b))
                let sat = mx > 0 ? (mx - mn) / mx : 0
                sum += luma; sumSq += luma * luma; satSum += sat; n += 1
                if luma > 0.85 { bright += 1 }
                x += 2  // subsample for speed
            }
            y += 2
        }
        guard n > 0 else { return RegionStats(lumaMean: 0, lumaStd: 0, brightFraction: 0, satMean: 0, count: 0) }
        let mean = sum / Double(n)
        let variance = max(0, sumSq / Double(n) - mean * mean)
        return RegionStats(lumaMean: mean, lumaStd: variance.squareRoot(),
                           brightFraction: Double(bright) / Double(n),
                           satMean: satSum / Double(n), count: n)
    }
}
