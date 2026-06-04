import Vision
import UIKit
import CoreImage

/// Document detection result
struct DocumentDetectionResult {
    let observation: VNRectangleObservation
    let confidence: Float
    let corners: [CGPoint]
    let isStable: Bool
    /// User-facing guidance when the document is detected but its framing
    /// would produce a poor capture. `nil` when framing is acceptable.
    ///
    /// Mirrors Android `DocumentDetectionResult.qualityGuidance` — the
    /// auto-capture gate in `DocumentCaptureView` suppresses firing when
    /// this is non-nil regardless of stability. Without this gate the SDK
    /// would let users tap "Looks good" on a capture where the document
    /// occupies ~6% of the frame, then send the unusable image to server
    /// OCR (BanffPay/Stratum Remit reproduction 2026-06-01).
    let qualityGuidance: String?
}

/// Document Scanner using Vision framework
final class DocumentScanner {

    // MARK: - Properties

    /// Cached CIContext for image processing (expensive to create)
    private let ciContext = CIContext()

    private var lastObservation: VNRectangleObservation?
    private var stabilityCounter = 0

    // v1.8.6-rc3: tolerate transient detection misses without resetting the
    // detection burst. Vision's segmentation is intermittent on busy or
    // patterned backgrounds (Stratum Remit reproduction: NJ DL on a floral
    // tablecloth) — without this counter, every single missed frame reset
    // `firstDetectedTime` upstream, so the 3-second force-capture deadline
    // never elapsed and auto-capture only fired by accident at moments
    // when stability and detection both happened to align with the user's
    // hand mid-motion (hence "captures outside the frame"). Matches
    // Android's `noDetectionThreshold = 3` in DocumentScanner.kt.
    private var noDetectionCounter = 0
    private let noDetectionThreshold = 3

    /// Most recent successful detection result. Returned to callers when
    /// the current frame's detection misses but the miss count is still
    /// under threshold — keeps the detection burst alive across single-
    /// frame Vision dropouts. Cleared when miss count >= threshold OR
    /// when `resetStability()` is called (retake path).
    private var lastDetectionResult: DocumentDetectionResult?

    // v1.8.6: stability gate relaxed to match Android (koraidv-android
    // DocumentScanner.kt: `stabilityThreshold = 1`, `stabilityTolerance = 0.10f`).
    //
    // Pre-1.8.6 iOS required `2` consecutive stable frames where every
    // corner moved less than `0.02` ABSOLUTE distance in normalized
    // [0..1] coords — i.e. < 2% of frame width. That's tighter than
    // natural hand jitter on a handheld phone, so stability never
    // converged and auto-capture never fired even though the detector
    // was correctly locating the document (Stratum Remit reproduction
    // 2026-06-01, iPhone 12 and iPhone 15 Pro Max both affected).
    // Android's 10% RELATIVE tolerance + 1 stable frame has been
    // shipping cleanly through real handheld captures. Porting parity.
    private let stabilityThreshold = 1
    private let stabilityTolerance: CGFloat = 0.10

    // v1.8.6: coverage thresholds for the new `qualityGuidance` gate.
    // Below the lower bound = document too small for usable OCR /
    // PDF417; above the upper = clipped at frame edges. Caller's
    // auto-capture gate suppresses firing when coverage is out of
    // range AND surfaces the guidance string to the user so they know
    // how to recover.
    //
    // v1.8.6-rc4: lower bound relaxed from 0.35 → 0.20. Android uses
    // 0.35 against an ML-Kit text-block bounding box that aggregates
    // every text block on the document AND is padded by 10 % — that
    // gives a larger reported bbox area than Apple Vision's
    // `VNDetectDocumentSegmentationRequest`, which tightly segments
    // the physical document edge. Same physical document framed the
    // same way produces Android coverage ≈ 0.40 but iOS coverage
    // ≈ 0.30. Capping iOS to 0.20 keeps the "tiny doc on big desk"
    // 6 %-coverage reject (Stratum Remit screenshot 114) while
    // letting through the merely-not-aggressive framings that real
    // users do on iPhone 12 (Stratum Remit 2026-06-03 regression).
    // Also see: cropToVideoAspect in CameraManager.swift and the
    // 10 %-padding addition further down in this file.
    private let minCoverage: CGFloat = 0.20
    private let maxCoverage: CGFloat = 0.85

    /// Minimum confidence for document detection.
    ///
    /// v1.8.6-rc4: lowered 0.7 → 0.5. Apple Vision's
    /// `VNDetectDocumentSegmentationRequest` is conservative on
    /// confidence scores — empirically the same physical document on
    /// the same lighting that Android ML Kit reports as "detected"
    /// can land in Vision's 0.5–0.7 range. Android's text-recognition
    /// detector has no directly-comparable confidence metric; it
    /// returns blocks or it doesn't. 0.5 is still meaningfully strict
    /// (filters obvious noise) while not gating real detections on
    /// the difference between two ML detector confidence scales.
    var minimumConfidence: Float = 0.5

    /// Minimum aspect ratio for valid documents
    var minimumAspectRatio: Float = 0.5

    /// Maximum aspect ratio for valid documents
    var maximumAspectRatio: Float = 2.0

    // MARK: - Detection

    /// Detect document in image
    func detectDocument(in pixelBuffer: CVPixelBuffer, completion: @escaping (DocumentDetectionResult?) -> Void) {
        let request = createDocumentDetectionRequest { [weak self] request, error in
            guard let self = self else { return }

            // v1.8.6-rc4: diagnostic logging at every exit path. Gated by
            // `KoraIDV.log` which itself respects Configuration.debugLogging
            // — production builds with debug logging off pay zero cost.
            // Per Stratum Remit's 2026-06-03 ask: a single 30-second hold
            // tells us which gate is failing on a problem device.

            if let error = error {
                KoraIDV.log("DocumentScanner exit: vision-error — \(error.localizedDescription)")
                self.handleNoDetection(completion: completion)
                return
            }

            guard let observation = request.results?.first as? VNRectangleObservation else {
                KoraIDV.log("DocumentScanner exit: no-observation — vision returned no rectangle")
                self.handleNoDetection(completion: completion)
                return
            }

            // Check confidence
            guard observation.confidence >= self.minimumConfidence else {
                KoraIDV.log("DocumentScanner exit: low-confidence — \(observation.confidence) < \(self.minimumConfidence)")
                self.handleNoDetection(completion: completion)
                return
            }

            // Check aspect ratio
            let aspectRatio = Float(observation.boundingBox.width / observation.boundingBox.height)
            guard aspectRatio >= self.minimumAspectRatio && aspectRatio <= self.maximumAspectRatio else {
                KoraIDV.log("DocumentScanner exit: bad-aspect — \(aspectRatio) not in [\(self.minimumAspectRatio), \(self.maximumAspectRatio)]")
                self.handleNoDetection(completion: completion)
                return
            }

            // Successful detection — clear the miss counter.
            self.noDetectionCounter = 0

            // Check stability
            let isStable = self.checkStability(observation)

            let corners = [
                observation.topLeft,
                observation.topRight,
                observation.bottomRight,
                observation.bottomLeft
            ]

            // v1.8.6-rc4: pad the bounding box by 10 % before computing
            // coverage, matching Android's text-block-padding pattern in
            // koraidv-android/.../DocumentScanner.kt. Apple Vision's tight
            // segmentation bbox underestimates physical document size
            // relative to the user's perception of "the document fills
            // this much of the frame", so the unpadded coverage check
            // suppressed auto-capture on perfectly-framed iPhone 12 holds
            // (Stratum Remit 2026-06-03). Pad keeps iOS coverage math
            // closer to Android's ML-Kit-aggregated-text-block bounds.
            let bbox = observation.boundingBox
            let padX = bbox.width * 0.10
            let padY = bbox.height * 0.10
            let paddedWidth = min(1.0, bbox.width + 2 * padX)
            let paddedHeight = min(1.0, bbox.height + 2 * padY)
            let coverage = paddedWidth * paddedHeight

            let qualityGuidance: String?
            if coverage < self.minCoverage {
                qualityGuidance = "Move closer to the document"
            } else if coverage > self.maxCoverage {
                qualityGuidance = "Move further from the document"
            } else {
                qualityGuidance = nil
            }

            let result = DocumentDetectionResult(
                observation: observation,
                confidence: observation.confidence,
                corners: corners,
                isStable: isStable,
                qualityGuidance: qualityGuidance
            )

            KoraIDV.log("DocumentScanner exit: success — confidence=\(observation.confidence) aspect=\(aspectRatio) coverage=\(String(format: "%.2f", Float(coverage))) isStable=\(isStable) guidance=\(qualityGuidance ?? "nil")")

            // Cache for transient-miss tolerance on subsequent frames.
            self.lastDetectionResult = result
            completion(result)
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            KoraIDV.log("Vision request failed: \(error)")
            completion(nil)
        }
    }

    /// Creates document detection request with iOS version compatibility
    private func createDocumentDetectionRequest(completionHandler: @escaping VNRequestCompletionHandler) -> VNImageBasedRequest {
        if #available(iOS 15.0, *) {
            return VNDetectDocumentSegmentationRequest(completionHandler: completionHandler)
        } else {
            let request = VNDetectRectanglesRequest(completionHandler: completionHandler)
            request.minimumAspectRatio = VNAspectRatio(minimumAspectRatio)
            request.maximumAspectRatio = VNAspectRatio(maximumAspectRatio)
            request.minimumConfidence = minimumConfidence
            request.maximumObservations = 1
            return request
        }
    }

    /// Detect document in UIImage
    func detectDocument(in image: UIImage, completion: @escaping (DocumentDetectionResult?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(nil)
            return
        }

        let request = createDocumentDetectionRequest { [weak self] request, error in
            guard let self = self else { return }

            if let error = error {
                KoraIDV.log("Document detection error: \(error)")
                completion(nil)
                return
            }

            guard let observation = request.results?.first as? VNRectangleObservation else {
                completion(nil)
                return
            }

            guard observation.confidence >= self.minimumConfidence else {
                completion(nil)
                return
            }

            let corners = [
                observation.topLeft,
                observation.topRight,
                observation.bottomRight,
                observation.bottomLeft
            ]

            let result = DocumentDetectionResult(
                observation: observation,
                confidence: observation.confidence,
                corners: corners,
                isStable: true, // Single image, always "stable"
                qualityGuidance: nil // Single-image path is not user-handheld
            )

            completion(result)
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            KoraIDV.log("Vision request failed: \(error)")
            completion(nil)
        }
    }

    // MARK: - Image Processing

    /// Apply perspective correction to extract document
    func extractDocument(from image: UIImage, using observation: VNRectangleObservation) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }

        let imageSize = ciImage.extent.size

        // Convert normalized coordinates to image coordinates
        let topLeft = CGPoint(
            x: observation.topLeft.x * imageSize.width,
            y: (1 - observation.topLeft.y) * imageSize.height
        )
        let topRight = CGPoint(
            x: observation.topRight.x * imageSize.width,
            y: (1 - observation.topRight.y) * imageSize.height
        )
        let bottomRight = CGPoint(
            x: observation.bottomRight.x * imageSize.width,
            y: (1 - observation.bottomRight.y) * imageSize.height
        )
        let bottomLeft = CGPoint(
            x: observation.bottomLeft.x * imageSize.width,
            y: (1 - observation.bottomLeft.y) * imageSize.height
        )

        // Apply perspective correction
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }

        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: topLeft), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: topRight), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")
        filter.setValue(CIVector(cgPoint: bottomLeft), forKey: "inputBottomLeft")

        guard let outputImage = filter.outputImage else { return nil }

        guard let cgImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }

    /// Extract document from pixel buffer
    func extractDocument(from pixelBuffer: CVPixelBuffer, using observation: VNRectangleObservation) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let imageSize = ciImage.extent.size

        // Convert normalized coordinates to image coordinates
        let topLeft = CGPoint(
            x: observation.topLeft.x * imageSize.width,
            y: observation.topLeft.y * imageSize.height
        )
        let topRight = CGPoint(
            x: observation.topRight.x * imageSize.width,
            y: observation.topRight.y * imageSize.height
        )
        let bottomRight = CGPoint(
            x: observation.bottomRight.x * imageSize.width,
            y: observation.bottomRight.y * imageSize.height
        )
        let bottomLeft = CGPoint(
            x: observation.bottomLeft.x * imageSize.width,
            y: observation.bottomLeft.y * imageSize.height
        )

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }

        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: topLeft), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: topRight), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")
        filter.setValue(CIVector(cgPoint: bottomLeft), forKey: "inputBottomLeft")

        guard let outputImage = filter.outputImage else { return nil }

        guard let cgImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }

    // MARK: - Private Methods

    private func checkStability(_ observation: VNRectangleObservation) -> Bool {
        guard let last = lastObservation else {
            lastObservation = observation
            stabilityCounter = 1
            // First detection — single-frame stability gate (stabilityThreshold=1)
            // means this counts as stable immediately. The old 2-frame gate
            // returned false here and required a second matching frame.
            return stabilityCounter >= stabilityThreshold
        }

        // v1.8.6: stability check changed from absolute distance (0.02 in
        // normalized [0..1] coords) to relative per-axis tolerance
        // (0.10 * corner position). Matches Android's Math.abs(dx) /
        // corner.x.coerceAtLeast(1f). Real-world handheld jitter on a
        // phone moves corners by ~5-10% per frame; the old absolute
        // threshold of 2% never converged.
        let isStable = isCornerStable(observation.topLeft, last.topLeft) &&
                       isCornerStable(observation.topRight, last.topRight) &&
                       isCornerStable(observation.bottomLeft, last.bottomLeft) &&
                       isCornerStable(observation.bottomRight, last.bottomRight)

        if isStable {
            stabilityCounter += 1
        } else {
            stabilityCounter = 1
        }

        lastObservation = observation

        return stabilityCounter >= stabilityThreshold
    }

    /// Per-axis relative-tolerance corner stability check. Matches the
    /// Android `Math.abs(dx) / corner.x.coerceAtLeast(1f)` pattern.
    /// Uses the current corner position as the denominator (with a
    /// floor of a small epsilon so corners near the origin don't
    /// produce a divide-by-near-zero).
    private func isCornerStable(_ current: CGPoint, _ previous: CGPoint) -> Bool {
        let dx = abs(current.x - previous.x) / max(current.x, 0.001)
        let dy = abs(current.y - previous.y) / max(current.y, 0.001)
        return dx <= stabilityTolerance && dy <= stabilityTolerance
    }

    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        return sqrt(dx * dx + dy * dy)
    }

    /// Reset stability tracking
    func resetStability() {
        lastObservation = nil
        stabilityCounter = 0
        noDetectionCounter = 0
        lastDetectionResult = nil
    }

    /// Unified miss-handling path. On the first `noDetectionThreshold - 1`
    /// misses, returns the last successful detection so the caller's
    /// detection burst stays alive across single-frame Vision dropouts.
    /// On the threshold-th miss, fully clears state and returns nil.
    ///
    /// v1.8.6-rc4: explicitly cold-start safe. If there's no cached
    /// detection result yet (no successful detection has happened in
    /// this session), we return `completion(nil)` immediately rather
    /// than going through the counter-based fallback. The pre-rc4
    /// code was functionally equivalent on cold start (cache was nil
    /// so the "return cache" branch also returned nil) but the
    /// explicit guard makes the cold-start path readable without
    /// having to walk through the math.
    private func handleNoDetection(completion: @escaping (DocumentDetectionResult?) -> Void) {
        // Cold start: no previous successful detection to fall back to.
        // Behave identically to pre-counter logic.
        guard lastDetectionResult != nil else {
            KoraIDV.log("DocumentScanner handleNoDetection: cold-start, no cached result")
            completion(nil)
            return
        }

        noDetectionCounter += 1
        if noDetectionCounter >= noDetectionThreshold {
            KoraIDV.log("DocumentScanner handleNoDetection: \(noDetectionCounter) misses, clearing cache")
            lastObservation = nil
            stabilityCounter = 0
            lastDetectionResult = nil
            completion(nil)
        } else {
            KoraIDV.log("DocumentScanner handleNoDetection: transient miss \(noDetectionCounter)/\(noDetectionThreshold), returning cached result")
            completion(lastDetectionResult)
        }
    }
}
