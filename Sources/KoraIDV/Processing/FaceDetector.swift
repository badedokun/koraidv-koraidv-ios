import Vision
import UIKit
import AVFoundation

/// Face detection result
struct FaceDetectionResult {
    let faces: [DetectedFace]
    let imageSize: CGSize
}

/// Detected face
struct DetectedFace {
    let boundingBox: CGRect
    let confidence: Float
    let landmarks: FaceLandmarks?
    let yaw: CGFloat?
    let pitch: CGFloat?
    let roll: CGFloat?
}

/// Face landmarks
struct FaceLandmarks {
    let leftEye: [CGPoint]
    let rightEye: [CGPoint]
    let nose: [CGPoint]
    let mouth: [CGPoint]
    let leftEyebrow: [CGPoint]
    let rightEyebrow: [CGPoint]
    let faceContour: [CGPoint]
}

/// Face Detector using Vision framework
final class FaceDetector {

    // MARK: - Properties

    /// Minimum confidence for face detection
    var minimumConfidence: Float = 0.5

    /// Whether to detect landmarks
    var detectLandmarks = true

    // MARK: - Detection

    /// Detect faces in image
    func detectFaces(in image: UIImage, completion: @escaping (FaceDetectionResult?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(nil)
            return
        }

        performDetection(on: cgImage, imageSize: image.size, completion: completion)
    }

    /// Detect faces in pixel buffer
    func detectFaces(in pixelBuffer: CVPixelBuffer, completion: @escaping (FaceDetectionResult?) -> Void) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let imageSize = CGSize(width: width, height: height)

        let request: VNImageBasedRequest

        if detectLandmarks {
            request = VNDetectFaceLandmarksRequest { [weak self] request, error in
                self?.handleDetectionResults(request: request, error: error, imageSize: imageSize, completion: completion)
            }
        } else {
            request = VNDetectFaceRectanglesRequest { [weak self] request, error in
                self?.handleDetectionResults(request: request, error: error, imageSize: imageSize, completion: completion)
            }
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            KoraIDV.log("Face detection failed: \(error)")
            completion(nil)
        }
    }

    /// Detect faces in sample buffer (for video frames)
    func detectFaces(in sampleBuffer: CMSampleBuffer, completion: @escaping (FaceDetectionResult?) -> Void) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            completion(nil)
            return
        }

        detectFaces(in: pixelBuffer, completion: completion)
    }

    // MARK: - Private Methods

    private func performDetection(on cgImage: CGImage, imageSize: CGSize, completion: @escaping (FaceDetectionResult?) -> Void) {
        let request: VNImageBasedRequest

        if detectLandmarks {
            request = VNDetectFaceLandmarksRequest { [weak self] request, error in
                self?.handleDetectionResults(request: request, error: error, imageSize: imageSize, completion: completion)
            }
        } else {
            request = VNDetectFaceRectanglesRequest { [weak self] request, error in
                self?.handleDetectionResults(request: request, error: error, imageSize: imageSize, completion: completion)
            }
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            KoraIDV.log("Face detection failed: \(error)")
            completion(nil)
        }
    }

    private func handleDetectionResults(
        request: VNRequest,
        error: Error?,
        imageSize: CGSize,
        completion: @escaping (FaceDetectionResult?) -> Void
    ) {
        if let error = error {
            KoraIDV.log("Face detection error: \(error)")
            completion(nil)
            return
        }

        guard let observations = request.results as? [VNFaceObservation] else {
            completion(nil)
            return
        }

        let faces = observations
            .filter { $0.confidence >= minimumConfidence }
            .map { mapFaceObservation($0, imageSize: imageSize) }

        let result = FaceDetectionResult(faces: faces, imageSize: imageSize)
        completion(result)
    }

    private func mapFaceObservation(_ observation: VNFaceObservation, imageSize: CGSize) -> DetectedFace {
        // Convert normalized coordinates to image coordinates
        let boundingBox = CGRect(
            x: observation.boundingBox.origin.x * imageSize.width,
            y: (1 - observation.boundingBox.origin.y - observation.boundingBox.height) * imageSize.height,
            width: observation.boundingBox.width * imageSize.width,
            height: observation.boundingBox.height * imageSize.height
        )

        // Extract landmarks if available
        var landmarks: FaceLandmarks?
        if let vnLandmarks = observation.landmarks {
            landmarks = FaceLandmarks(
                leftEye: convertPoints(vnLandmarks.leftEye?.normalizedPoints, boundingBox: observation.boundingBox, imageSize: imageSize),
                rightEye: convertPoints(vnLandmarks.rightEye?.normalizedPoints, boundingBox: observation.boundingBox, imageSize: imageSize),
                nose: convertPoints(vnLandmarks.nose?.normalizedPoints, boundingBox: observation.boundingBox, imageSize: imageSize),
                mouth: convertPoints(vnLandmarks.outerLips?.normalizedPoints, boundingBox: observation.boundingBox, imageSize: imageSize),
                leftEyebrow: convertPoints(vnLandmarks.leftEyebrow?.normalizedPoints, boundingBox: observation.boundingBox, imageSize: imageSize),
                rightEyebrow: convertPoints(vnLandmarks.rightEyebrow?.normalizedPoints, boundingBox: observation.boundingBox, imageSize: imageSize),
                faceContour: convertPoints(vnLandmarks.faceContour?.normalizedPoints, boundingBox: observation.boundingBox, imageSize: imageSize)
            )
        }

        // pitch is only available on iOS 15.0+
        var pitchValue: CGFloat? = nil
        if #available(iOS 15.0, *) {
            pitchValue = observation.pitch.map { CGFloat($0.doubleValue) }
        }

        return DetectedFace(
            boundingBox: boundingBox,
            confidence: observation.confidence,
            landmarks: landmarks,
            yaw: observation.yaw.map { CGFloat($0.doubleValue) },
            pitch: pitchValue,
            roll: observation.roll.map { CGFloat($0.doubleValue) }
        )
    }

    private func convertPoints(_ points: [CGPoint]?, boundingBox: CGRect, imageSize: CGSize) -> [CGPoint] {
        guard let points = points else { return [] }

        return points.map { point in
            // Points are normalized within the bounding box
            let x = (boundingBox.origin.x + point.x * boundingBox.width) * imageSize.width
            let y = (1 - boundingBox.origin.y - point.y * boundingBox.height) * imageSize.height
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Face Validation

extension FaceDetector {

    /// Validate face detection for selfie capture
    func validateForSelfie(result: FaceDetectionResult) -> (isValid: Bool, issues: [String]) {
        var issues: [String] = []

        // Check face count
        if result.faces.isEmpty {
            return (false, ["No face detected"])
        }

        if result.faces.count > 1 {
            issues.append("Multiple faces detected")
        }

        guard let face = result.faces.first else {
            return (false, issues)
        }

        // **Face CONTAINMENT in the on-screen oval (BanffPay retest #4).**
        // Earlier passes checked only the face CENTRE against an acceptance
        // ellipse, so the SDK snapped the instant the midpoint was in range —
        // a head that was only PARTLY in the oval (shifted to a side, or too
        // close and overflowing the guide) still triggered a capture. Testers
        // wanted it to wait until the WHOLE face is inside. So we now require
        // the face's bounding box to FIT inside the oval: its centre must lie
        // within the oval SHRUNK by the face's own half-extent. When the head
        // is fitted in the oval the (smaller) face box sits comfortably inside
        // → snaps; when only part of the head is in, the box touches the oval
        // edge → it keeps waiting.
        //
        // Oval geometry in image-normalised coords (derived from the 240×300pt
        // guide over the aspect-FILL 1080×1920 preview — see retest #3): centre
        // (0.5, 0.58), half-extents 0.25 horizontal × 0.18 vertical (vertical
        // compresses because the whole image height maps to the whole screen
        // height).
        // **Selfie acceptance — moderate centre region + size band (retest #5).**
        // Strict containment (retest #4) required the face box to fit fully
        // INSIDE the oval, but on-device measurement showed testers' faces FILL
        // the oval (face box ≈ the oval itself), leaving near-zero positional
        // tolerance — so it could never settle and fell through to the 5s
        // force-capture (the "6 seconds"). The new camera settle delay
        // (SelfieCapture) now gives the user ~1.2s to position, so a moderate
        // centre region behaves well: accept a reasonably-centred, reasonably-
        // sized face; reject a grossly off-centre or over-close one.
        //
        // Region centred at (0.5, 0.62) — where a face aligned to the oval
        // actually lands (slightly low). Horizontal half-axis kept generous
        // (0.24) to absorb the front-camera horizontal offset/mirroring we can't
        // measure from here; vertical tighter (0.16). Size band 0.08–0.30
        // rejects too-far / too-close.
        let imageArea = result.imageSize.width * result.imageSize.height
        let faceArea = face.boundingBox.width * face.boundingBox.height
        let faceSizeRatio = imageArea > 0 ? faceArea / imageArea : 0

        let w = result.imageSize.width
        let h = result.imageSize.height
        let faceCenterX = w > 0 ? face.boundingBox.midX / w : 0.5
        let faceCenterY = h > 0 ? face.boundingBox.midY / h : 0.5

        // **Calibrated to on-device readings (BanffPay r7, 2026-06-29).** With
        // the face perfectly in the oval the DETECTOR reports cx≈0.48, cy≈0.67,
        // sz≈0.06 — the live-detection frame has a far wider FOV than the saved
        // still, so the face is MUCH smaller in detection coords (0.06) than it
        // looks in the capture (~0.17). Every prior band was wrong: a 0.08 size
        // floor rejected the perfectly-centred face as "too small", pushing the
        // user closer until the head overflowed; and the centre/spread were off.
        // Centre on (0.48, 0.67); size band 0.035–0.105 around the measured
        // 0.06; positional half-axes 0.13 (to be tightened/loosened from the
        // r6 on-screen readout if needed).
        // Fitted to three on-device readings (r8): in-oval face spans
        // cx 0.47–0.61, cy 0.66–0.78, sz 0.06–0.14 (detection coords). Centre on
        // the centroid (0.52, 0.70) with half-axes 0.13×0.12 so all three points
        // sit inside; size band 0.04–0.16 spans the measured range.
        if faceSizeRatio < 0.04 {
            issues.append("Move closer — fill the oval with your face")
        } else if faceSizeRatio > 0.16 {
            issues.append("Move back — fit your whole head in the oval")
        } else {
            let dx = (faceCenterX - 0.52) / 0.13
            let dy = (faceCenterY - 0.70) / 0.12
            if dx * dx + dy * dy > 1.0 {
                issues.append("Center your face in the oval")
            }
        }

        // Check face angle (if available). v1.9.6: 0.3 → 0.45 — a slight head
        // angle is fine for a selfie (face-match is pose-tolerant), and the
        // strict 0.3 was a frequent cause of counter resets.
        if let yaw = face.yaw {
            if abs(yaw) > 0.45 {
                issues.append("Face the camera directly")
            }
        }

        return (issues.isEmpty, issues)
    }

    /// Whether the face is positioned inside the on-screen selfie oval guide.
    ///
    /// This is a deliberately **forgiving** "face is roughly inside the oval"
    /// gate — NOT the strict quality gate (`validateForSelfie` does that). It
    /// drives the liveness oval-green signal + gesture acceptance and the
    /// selfie force-capture safety net, so it must pass whenever the face is
    /// *visually* in the oval and only reject a face jammed at the frame edge.
    ///
    /// **v1.9.6 retune (BanffPay, 2026-06).** The original ±0.2 / 0.10–0.6
    /// tolerances were too tight: on the front camera the preview is
    /// aspect-FILL cropped, so a face centered in the *on-screen* oval can land
    /// outside ±0.2 in *image* space (especially vertically) and read smaller
    /// than 0.10. With the gate failing, gestures never scored and the 12s
    /// selfie safety net never fired — testers waited 60s+ with the face fully
    /// in the oval. Widened to ratio 0.07–0.65 and center ±0.30. A corner/edge
    /// face (the outside-oval case Olabode reported) still fails.
    ///
    /// **Deliberately excludes the yaw check** — liveness turn challenges
    /// legitimately change yaw, so gating gestures on yaw would break turns.
    func isWithinSelfieOval(face: DetectedFace, imageSize: CGSize) -> Bool {
        let imageArea = imageSize.width * imageSize.height
        guard imageArea > 0 else { return false }

        let faceArea = face.boundingBox.width * face.boundingBox.height
        let ratio = faceArea / imageArea
        guard ratio >= 0.07, ratio <= 0.65 else { return false }

        let centerX = face.boundingBox.midX / imageSize.width
        let centerY = face.boundingBox.midY / imageSize.height
        return abs(centerX - 0.5) <= 0.30 && abs(centerY - 0.5) <= 0.30
    }
}
