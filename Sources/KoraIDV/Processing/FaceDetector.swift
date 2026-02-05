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
            print("[KoraIDV] Face detection failed: \(error)")
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
            print("[KoraIDV] Face detection failed: \(error)")
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
            print("[KoraIDV] Face detection error: \(error)")
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

        return DetectedFace(
            boundingBox: boundingBox,
            confidence: observation.confidence,
            landmarks: landmarks,
            yaw: observation.yaw.map { CGFloat($0.doubleValue) },
            pitch: observation.pitch.map { CGFloat($0.doubleValue) },
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

        // Check face size
        let imageArea = result.imageSize.width * result.imageSize.height
        let faceArea = face.boundingBox.width * face.boundingBox.height
        let faceSizeRatio = faceArea / imageArea

        if faceSizeRatio < 0.15 {
            issues.append("Face is too small. Move closer.")
        } else if faceSizeRatio > 0.6 {
            issues.append("Face is too large. Move back.")
        }

        // Check face position
        let faceCenterX = face.boundingBox.midX / result.imageSize.width
        let faceCenterY = face.boundingBox.midY / result.imageSize.height

        if abs(faceCenterX - 0.5) > 0.2 {
            issues.append("Center your face horizontally")
        }

        if abs(faceCenterY - 0.5) > 0.2 {
            issues.append("Center your face vertically")
        }

        // Check face angle (if available)
        if let yaw = face.yaw {
            if abs(yaw) > 0.3 {
                issues.append("Face the camera directly")
            }
        }

        return (issues.isEmpty, issues)
    }
}
