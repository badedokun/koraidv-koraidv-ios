import XCTest
import UIKit
@testable import KoraIDV

final class QualityValidatorTests: XCTestCase {

    // MARK: - Helpers

    /// Create a solid-color UIImage of the given size.
    private func makeImage(color: UIColor, size: CGSize = CGSize(width: 100, height: 100)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// Create a two-color vertical gradient UIImage.
    private func makeGradientImage(
        topColor: UIColor,
        bottomColor: UIColor,
        size: CGSize = CGSize(width: 100, height: 100)
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let colors = [topColor.cgColor, bottomColor.cgColor] as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: nil) else { return }
            ctx.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: size.width / 2, y: 0),
                end: CGPoint(x: size.width / 2, y: size.height),
                options: []
            )
        }
    }

    // MARK: - Default Thresholds

    func testDefaultThresholdsValues() {
        let t = QualityThresholds.default
        XCTAssertEqual(t.minBlurScore, 100)
        XCTAssertEqual(t.minBrightness, 0.3)
        XCTAssertEqual(t.maxBrightness, 0.85)
        XCTAssertEqual(t.maxGlarePercentage, 0.05)
        XCTAssertEqual(t.minFaceSizePercentage, 0.2)
        XCTAssertEqual(t.minFaceConfidence, 0.7)
    }

    func testRelaxedThresholdsDifferFromDefaults() {
        let d = QualityThresholds.default
        let r = QualityThresholds.relaxed
        XCTAssertNotEqual(d.minBlurScore, r.minBlurScore)
        XCTAssertNotEqual(d.minBrightness, r.minBrightness)
        XCTAssertNotEqual(d.maxBrightness, r.maxBrightness)
        XCTAssertNotEqual(d.maxGlarePercentage, r.maxGlarePercentage)
        XCTAssertNotEqual(d.minFaceSizePercentage, r.minFaceSizePercentage)
        XCTAssertNotEqual(d.minFaceConfidence, r.minFaceConfidence)
    }

    func testRelaxedThresholdsAreMorePermissive() {
        let d = QualityThresholds.default
        let r = QualityThresholds.relaxed
        XCTAssertLessThan(r.minBlurScore, d.minBlurScore)
        XCTAssertLessThan(r.minBrightness, d.minBrightness)
        XCTAssertGreaterThan(r.maxBrightness, d.maxBrightness)
        XCTAssertGreaterThan(r.maxGlarePercentage, d.maxGlarePercentage)
        XCTAssertLessThan(r.minFaceSizePercentage, d.minFaceSizePercentage)
        XCTAssertLessThan(r.minFaceConfidence, d.minFaceConfidence)
    }

    func testInitUsesDefaultThresholds() {
        let validator = QualityValidator()
        XCTAssertEqual(validator.thresholds.minBlurScore, QualityThresholds.default.minBlurScore)
        XCTAssertEqual(validator.thresholds.minBrightness, QualityThresholds.default.minBrightness)
    }

    func testInitAcceptsCustomThresholds() {
        let validator = QualityValidator(thresholds: .relaxed)
        XCTAssertEqual(validator.thresholds.minBlurScore, QualityThresholds.relaxed.minBlurScore)
    }

    // MARK: - Document Validation: Brightness

    func testDarkImageProducesTooDarkIssue() {
        let validator = QualityValidator()
        // A very dark image (close to black) should trigger tooDark
        let darkImage = makeImage(color: UIColor(white: 0.05, alpha: 1.0))
        let result = validator.validateDocumentImage(darkImage)

        let tooDarkIssues = result.issues.filter { $0.type == .tooDark }
        XCTAssertFalse(tooDarkIssues.isEmpty, "Expected a tooDark issue for a nearly black image")
        XCTAssertEqual(tooDarkIssues.first?.severity, .error)
    }

    func testBrightImageProducesTooBrightIssue() {
        let validator = QualityValidator()
        // Pure white image should trigger tooBright
        let brightImage = makeImage(color: .white)
        let result = validator.validateDocumentImage(brightImage)

        let tooBrightIssues = result.issues.filter { $0.type == .tooBright }
        XCTAssertFalse(tooBrightIssues.isEmpty, "Expected a tooBright issue for a pure white image")
        XCTAssertEqual(tooBrightIssues.first?.severity, .warning)
    }

    func testMidBrightnessDocumentHasNoBrightnessIssues() {
        let validator = QualityValidator()
        // A mid-gray image (brightness ~0.5) should not be too dark or too bright
        let midImage = makeImage(color: UIColor(white: 0.5, alpha: 1.0))
        let result = validator.validateDocumentImage(midImage)

        let brightnessIssues = result.issues.filter { $0.type == .tooDark || $0.type == .tooBright }
        XCTAssertTrue(brightnessIssues.isEmpty, "Mid-brightness image should not trigger brightness issues")
    }

    // MARK: - Document Validation: Metrics

    func testDocumentMetricsBrightnessInExpectedRange() {
        let validator = QualityValidator()
        let image = makeImage(color: UIColor(white: 0.5, alpha: 1.0))
        let result = validator.validateDocumentImage(image)

        // Brightness for a 50% gray should be roughly 0.5
        XCTAssertGreaterThan(result.metrics.brightness, 0.3)
        XCTAssertLessThan(result.metrics.brightness, 0.7)
    }

    func testDocumentMetricsBlurScoreIsNonNegative() {
        let validator = QualityValidator()
        let image = makeImage(color: UIColor(white: 0.5, alpha: 1.0))
        let result = validator.validateDocumentImage(image)
        XCTAssertGreaterThanOrEqual(result.metrics.blurScore, 0)
    }

    func testDocumentMetricsGlarePercentageInUnitRange() {
        let validator = QualityValidator()
        let image = makeImage(color: UIColor(white: 0.5, alpha: 1.0))
        let result = validator.validateDocumentImage(image)
        XCTAssertGreaterThanOrEqual(result.metrics.glarePercentage, 0)
        XCTAssertLessThanOrEqual(result.metrics.glarePercentage, 1.0)
    }

    func testDocumentMetricsFaceFieldsAreNil() {
        let validator = QualityValidator()
        let image = makeImage(color: UIColor(white: 0.5, alpha: 1.0))
        let result = validator.validateDocumentImage(image)
        XCTAssertNil(result.metrics.faceSize)
        XCTAssertNil(result.metrics.faceConfidence)
        XCTAssertNil(result.metrics.faceCenterOffset)
    }

    // MARK: - Selfie Validation: Face Detection

    func testSelfieNoFaceDetectionProducesFaceNotDetected() {
        let validator = QualityValidator()
        let image = makeImage(color: UIColor(white: 0.5, alpha: 1.0))
        let result = validator.validateSelfieImage(image, faceDetection: nil)

        let faceIssues = result.issues.filter { $0.type == .faceNotDetected }
        XCTAssertFalse(faceIssues.isEmpty, "Expected faceNotDetected when faceDetection is nil")
        XCTAssertFalse(result.isValid, "Result should be invalid without face detection")
    }

    func testSelfieFaceTooSmallProducesIssue() {
        let validator = QualityValidator()
        let image = makeImage(color: UIColor(white: 0.5, alpha: 1.0))
        // A very small face bounding box (1% of image area)
        let faceDetection: (confidence: Float, boundingBox: CGRect) = (
            confidence: 0.95,
            boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1)
        )
        let result = validator.validateSelfieImage(image, faceDetection: faceDetection)

        let tooSmallIssues = result.issues.filter { $0.type == .faceTooSmall }
        XCTAssertFalse(tooSmallIssues.isEmpty, "Expected faceTooSmall for a tiny bounding box")
    }

    func testSelfieLargeFaceDoesNotProduceFaceTooSmall() {
        let validator = QualityValidator()
        let image = makeImage(color: UIColor(white: 0.5, alpha: 1.0))
        // A large face bounding box (approx 50% of image)
        let faceDetection: (confidence: Float, boundingBox: CGRect) = (
            confidence: 0.95,
            boundingBox: CGRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7)
        )
        let result = validator.validateSelfieImage(image, faceDetection: faceDetection)

        let tooSmallIssues = result.issues.filter { $0.type == .faceTooSmall }
        XCTAssertTrue(tooSmallIssues.isEmpty, "Large face should not trigger faceTooSmall")
    }

    func testSelfieFaceOffCenterProducesWarning() {
        let validator = QualityValidator()
        let image = makeImage(color: UIColor(white: 0.5, alpha: 1.0))
        // Face positioned in top-left corner — off-center by more than 0.2
        let faceDetection: (confidence: Float, boundingBox: CGRect) = (
            confidence: 0.95,
            boundingBox: CGRect(x: 0.0, y: 0.0, width: 0.5, height: 0.5)
        )
        let result = validator.validateSelfieImage(image, faceDetection: faceDetection)

        let offCenterIssues = result.issues.filter { $0.type == .faceOffCenter }
        XCTAssertFalse(offCenterIssues.isEmpty, "Off-center face should produce faceOffCenter warning")
        XCTAssertEqual(offCenterIssues.first?.severity, .warning)
    }

    func testSelfieMetricsContainFaceInfo() {
        let validator = QualityValidator()
        let image = makeImage(color: UIColor(white: 0.5, alpha: 1.0))
        let faceDetection: (confidence: Float, boundingBox: CGRect) = (
            confidence: 0.9,
            boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        )
        let result = validator.validateSelfieImage(image, faceDetection: faceDetection)

        XCTAssertNotNil(result.metrics.faceSize)
        XCTAssertNotNil(result.metrics.faceConfidence)
        XCTAssertNotNil(result.metrics.faceCenterOffset)
        XCTAssertEqual(result.metrics.faceConfidence!, 0.9, accuracy: 0.001)
    }
}
