import UIKit
import Accelerate

/// Quality validation result
struct QualityValidationResult {
    let isValid: Bool
    let issues: [QualityIssue]
    let metrics: QualityMetrics
}

/// Quality issue
struct QualityIssue {
    let type: QualityIssueType
    let message: String
    let severity: QualityIssueSeverity
}

/// Quality issue type
enum QualityIssueType {
    case blur
    case tooDark
    case tooBright
    case glare
    case faceNotDetected
    case faceTooSmall
    case faceOffCenter
    case multipleFaces
    case documentNotDetected
    case documentPartiallyVisible
}

/// Quality issue severity
enum QualityIssueSeverity {
    case error
    case warning
}

/// Quality metrics
struct QualityMetrics {
    let blurScore: Double
    let brightness: Double
    let glarePercentage: Double
    let faceSize: Double?
    let faceConfidence: Double?
    let faceCenterOffset: CGPoint?
}

/// Quality thresholds
struct QualityThresholds {
    let minBlurScore: Double
    let minBrightness: Double
    let maxBrightness: Double
    let maxGlarePercentage: Double
    let minFaceSizePercentage: Double
    let minFaceConfidence: Double

    static let `default` = QualityThresholds(
        minBlurScore: 100,
        minBrightness: 0.3,
        maxBrightness: 0.85,
        maxGlarePercentage: 0.05,
        minFaceSizePercentage: 0.2,
        minFaceConfidence: 0.7
    )

    static let relaxed = QualityThresholds(
        minBlurScore: 50,
        minBrightness: 0.2,
        maxBrightness: 0.9,
        maxGlarePercentage: 0.1,
        minFaceSizePercentage: 0.15,
        minFaceConfidence: 0.5
    )
}

/// Quality Validator for captured images
final class QualityValidator {

    // MARK: - Properties

    var thresholds: QualityThresholds

    // MARK: - Initialization

    init(thresholds: QualityThresholds = .default) {
        self.thresholds = thresholds
    }

    // MARK: - Validation

    /// Validate document image quality
    func validateDocumentImage(_ image: UIImage) -> QualityValidationResult {
        var issues: [QualityIssue] = []

        guard let cgImage = image.cgImage else {
            return QualityValidationResult(
                isValid: false,
                issues: [QualityIssue(type: .documentNotDetected, message: "Invalid image", severity: .error)],
                metrics: QualityMetrics(blurScore: 0, brightness: 0, glarePercentage: 0, faceSize: nil, faceConfidence: nil, faceCenterOffset: nil)
            )
        }

        // Calculate blur score
        let blurScore = calculateBlurScore(cgImage)
        if blurScore < thresholds.minBlurScore {
            issues.append(QualityIssue(
                type: .blur,
                message: "Image is too blurry. Hold the device steady.",
                severity: .error
            ))
        }

        // Calculate brightness
        let brightness = calculateBrightness(cgImage)
        if brightness < thresholds.minBrightness {
            issues.append(QualityIssue(
                type: .tooDark,
                message: "Image is too dark. Move to a brighter area.",
                severity: .error
            ))
        } else if brightness > thresholds.maxBrightness {
            issues.append(QualityIssue(
                type: .tooBright,
                message: "Image is too bright. Reduce lighting.",
                severity: .warning
            ))
        }

        // Calculate glare
        let glarePercentage = calculateGlarePercentage(cgImage)
        if glarePercentage > thresholds.maxGlarePercentage {
            issues.append(QualityIssue(
                type: .glare,
                message: "Glare detected. Adjust angle to reduce reflections.",
                severity: .warning
            ))
        }

        let metrics = QualityMetrics(
            blurScore: blurScore,
            brightness: brightness,
            glarePercentage: glarePercentage,
            faceSize: nil,
            faceConfidence: nil,
            faceCenterOffset: nil
        )

        let hasErrors = issues.contains { $0.severity == .error }

        return QualityValidationResult(
            isValid: !hasErrors,
            issues: issues,
            metrics: metrics
        )
    }

    /// Validate selfie image quality with face detection info
    func validateSelfieImage(
        _ image: UIImage,
        faceDetection: (confidence: Float, boundingBox: CGRect)?
    ) -> QualityValidationResult {
        var issues: [QualityIssue] = []

        guard let cgImage = image.cgImage else {
            return QualityValidationResult(
                isValid: false,
                issues: [QualityIssue(type: .faceNotDetected, message: "Invalid image", severity: .error)],
                metrics: QualityMetrics(blurScore: 0, brightness: 0, glarePercentage: 0, faceSize: nil, faceConfidence: nil, faceCenterOffset: nil)
            )
        }

        // Calculate blur score
        let blurScore = calculateBlurScore(cgImage)
        if blurScore < thresholds.minBlurScore {
            issues.append(QualityIssue(
                type: .blur,
                message: "Image is too blurry. Hold the device steady.",
                severity: .error
            ))
        }

        // Calculate brightness
        let brightness = calculateBrightness(cgImage)
        if brightness < thresholds.minBrightness {
            issues.append(QualityIssue(
                type: .tooDark,
                message: "Image is too dark. Move to a brighter area.",
                severity: .error
            ))
        }

        // Face detection validation
        var faceSize: Double?
        var faceConfidence: Double?
        var faceCenterOffset: CGPoint?

        if let face = faceDetection {
            faceConfidence = Double(face.confidence)

            if face.confidence < Float(thresholds.minFaceConfidence) {
                issues.append(QualityIssue(
                    type: .faceNotDetected,
                    message: "Face not clearly visible. Ensure good lighting.",
                    severity: .warning
                ))
            }

            // Calculate face size as percentage of image
            let imageArea = CGFloat(cgImage.width * cgImage.height)
            let faceArea = face.boundingBox.width * CGFloat(cgImage.width) * face.boundingBox.height * CGFloat(cgImage.height)
            faceSize = Double(faceArea / imageArea)

            if faceSize! < thresholds.minFaceSizePercentage {
                issues.append(QualityIssue(
                    type: .faceTooSmall,
                    message: "Face is too small. Move closer to the camera.",
                    severity: .error
                ))
            }

            // Check face centering
            let faceCenterX = face.boundingBox.midX
            let faceCenterY = face.boundingBox.midY
            let offsetX = faceCenterX - 0.5
            let offsetY = faceCenterY - 0.5
            faceCenterOffset = CGPoint(x: offsetX, y: offsetY)

            if abs(offsetX) > 0.2 || abs(offsetY) > 0.2 {
                issues.append(QualityIssue(
                    type: .faceOffCenter,
                    message: "Center your face in the frame.",
                    severity: .warning
                ))
            }
        } else {
            issues.append(QualityIssue(
                type: .faceNotDetected,
                message: "Face not detected. Position your face in the frame.",
                severity: .error
            ))
        }

        let metrics = QualityMetrics(
            blurScore: blurScore,
            brightness: brightness,
            glarePercentage: calculateGlarePercentage(cgImage),
            faceSize: faceSize,
            faceConfidence: faceConfidence,
            faceCenterOffset: faceCenterOffset
        )

        let hasErrors = issues.contains { $0.severity == .error }

        return QualityValidationResult(
            isValid: !hasErrors,
            issues: issues,
            metrics: metrics
        )
    }

    // MARK: - Image Analysis

    /// Calculate blur score using Laplacian variance
    private func calculateBlurScore(_ image: CGImage) -> Double {
        let width = image.width
        let height = image.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return 0
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let grayscaleData = context.data else { return 0 }

        let buffer = grayscaleData.assumingMemoryBound(to: UInt8.self)

        // Apply Laplacian kernel
        var laplacianSum: Double = 0
        var laplacianSumSquared: Double = 0
        var count: Double = 0

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * width + x
                let center = Int(buffer[idx])
                let top = Int(buffer[idx - width])
                let bottom = Int(buffer[idx + width])
                let left = Int(buffer[idx - 1])
                let right = Int(buffer[idx + 1])

                let laplacian = Double(-4 * center + top + bottom + left + right)
                laplacianSum += laplacian
                laplacianSumSquared += laplacian * laplacian
                count += 1
            }
        }

        guard count > 0 else { return 0 }

        let mean = laplacianSum / count
        let variance = (laplacianSumSquared / count) - (mean * mean)

        return variance
    }

    /// Calculate average brightness
    private func calculateBrightness(_ image: CGImage) -> Double {
        let width = image.width
        let height = image.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return 0
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return 0 }

        let buffer = data.assumingMemoryBound(to: UInt8.self)
        var totalBrightness: Double = 0
        let pixelCount = width * height

        for i in 0..<pixelCount {
            let offset = i * 4
            let r = Double(buffer[offset])
            let g = Double(buffer[offset + 1])
            let b = Double(buffer[offset + 2])

            // Perceived brightness formula
            let brightness = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            totalBrightness += brightness
        }

        return totalBrightness / Double(pixelCount)
    }

    /// Calculate percentage of overexposed pixels (glare)
    private func calculateGlarePercentage(_ image: CGImage) -> Double {
        let width = image.width
        let height = image.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return 0
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return 0 }

        let buffer = data.assumingMemoryBound(to: UInt8.self)
        var glarePixels = 0
        let pixelCount = width * height
        let glareThreshold: UInt8 = 250

        for i in 0..<pixelCount {
            let offset = i * 4
            let r = buffer[offset]
            let g = buffer[offset + 1]
            let b = buffer[offset + 2]

            if r > glareThreshold && g > glareThreshold && b > glareThreshold {
                glarePixels += 1
            }
        }

        return Double(glarePixels) / Double(pixelCount)
    }
}
