import Vision
import UIKit
import CoreImage

/// Document detection result
struct DocumentDetectionResult {
    let observation: VNRectangleObservation
    let confidence: Float
    let corners: [CGPoint]
    let isStable: Bool
}

/// Document Scanner using Vision framework
final class DocumentScanner {

    // MARK: - Properties

    private var lastObservation: VNRectangleObservation?
    private var stabilityCounter = 0
    private let stabilityThreshold = 5

    /// Minimum confidence for document detection
    var minimumConfidence: Float = 0.7

    /// Minimum aspect ratio for valid documents
    var minimumAspectRatio: Float = 0.5

    /// Maximum aspect ratio for valid documents
    var maximumAspectRatio: Float = 2.0

    // MARK: - Detection

    /// Detect document in image
    func detectDocument(in pixelBuffer: CVPixelBuffer, completion: @escaping (DocumentDetectionResult?) -> Void) {
        let request = createDocumentDetectionRequest { [weak self] request, error in
            guard let self = self else { return }

            if let error = error {
                print("[KoraIDV] Document detection error: \(error)")
                completion(nil)
                return
            }

            guard let observation = request.results?.first as? VNRectangleObservation else {
                self.lastObservation = nil
                self.stabilityCounter = 0
                completion(nil)
                return
            }

            // Check confidence
            guard observation.confidence >= self.minimumConfidence else {
                completion(nil)
                return
            }

            // Check aspect ratio
            let aspectRatio = Float(observation.boundingBox.width / observation.boundingBox.height)
            guard aspectRatio >= self.minimumAspectRatio && aspectRatio <= self.maximumAspectRatio else {
                completion(nil)
                return
            }

            // Check stability
            let isStable = self.checkStability(observation)

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
                isStable: isStable
            )

            completion(result)
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            print("[KoraIDV] Vision request failed: \(error)")
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
                print("[KoraIDV] Document detection error: \(error)")
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
                isStable: true // Single image, always "stable"
            )

            completion(result)
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            print("[KoraIDV] Vision request failed: \(error)")
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

        let context = CIContext()
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else { return nil }

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

        let context = CIContext()
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }

    // MARK: - Private Methods

    private func checkStability(_ observation: VNRectangleObservation) -> Bool {
        guard let last = lastObservation else {
            lastObservation = observation
            stabilityCounter = 1
            return false
        }

        // Check if corners are similar to last observation
        let threshold: CGFloat = 0.02

        let topLeftDiff = distance(observation.topLeft, last.topLeft)
        let topRightDiff = distance(observation.topRight, last.topRight)
        let bottomLeftDiff = distance(observation.bottomLeft, last.bottomLeft)
        let bottomRightDiff = distance(observation.bottomRight, last.bottomRight)

        let isStable = topLeftDiff < threshold &&
                       topRightDiff < threshold &&
                       bottomLeftDiff < threshold &&
                       bottomRightDiff < threshold

        if isStable {
            stabilityCounter += 1
        } else {
            stabilityCounter = 1
        }

        lastObservation = observation

        return stabilityCounter >= stabilityThreshold
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
    }
}
