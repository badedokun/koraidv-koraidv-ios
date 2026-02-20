import XCTest
@testable import KoraIDV

final class AntiSpoofCheckTests: XCTestCase {

    private var checker: AntiSpoofCheck!

    override func setUp() {
        super.setUp()
        checker = AntiSpoofCheck()
    }

    override func tearDown() {
        checker = nil
        super.tearDown()
    }

    // MARK: - Solid color image: no texture, flagged as spoof

    func testSolidColorImageIsFlaggedAsSpoof() {
        let image = createSolidColorImage(color: .red, size: CGSize(width: 64, height: 64))
        let result = checker.analyze(image)
        XCTAssertFalse(result.isLikelyReal, "Solid color image should be flagged as spoof")
    }

    func testSolidColorImageHasLowTextureScore() {
        let image = createSolidColorImage(color: .blue, size: CGSize(width: 64, height: 64))
        guard let cgImage = image.cgImage else {
            XCTFail("Failed to create CGImage")
            return
        }
        let score = checker.analyzeTexture(cgImage)
        XCTAssertLessThan(score, 0.1, "Solid color should have very low texture score")
    }

    func testSolidColorImageHasZeroColorScore() {
        let image = createSolidColorImage(color: .green, size: CGSize(width: 64, height: 64))
        guard let cgImage = image.cgImage else {
            XCTFail("Failed to create CGImage")
            return
        }
        let score = checker.analyzeColorDistribution(cgImage)
        XCTAssertEqual(score, 0.0, accuracy: 0.001, "Uniform color should have zero color score")
    }

    // MARK: - Checkerboard image: high texture

    func testCheckerboardImageHasHighTextureScore() {
        let image = createCheckerboardImage(size: 64)
        guard let cgImage = image.cgImage else {
            XCTFail("Failed to create CGImage")
            return
        }
        let score = checker.analyzeTexture(cgImage)
        XCTAssertGreaterThan(score, 0.5, "Checkerboard should have high texture score, got \(score)")
    }

    func testCheckerboardImageHasHighFrequencyScore() {
        let image = createCheckerboardImage(size: 64)
        guard let cgImage = image.cgImage else {
            XCTFail("Failed to create CGImage")
            return
        }
        let score = checker.analyzeFrequency(cgImage)
        XCTAssertGreaterThan(score, 0.0, "Checkerboard should have measurable frequency score, got \(score)")
    }

    // MARK: - Score range validation

    func testTextureScoreAlwaysInZeroToOneRange() {
        let images = [
            createSolidColorImage(color: .black, size: CGSize(width: 64, height: 64)),
            createSolidColorImage(color: .white, size: CGSize(width: 64, height: 64)),
            createCheckerboardImage(size: 64),
            createGradientImage(size: 64)
        ]

        for image in images {
            guard let cgImage = image.cgImage else { continue }
            let score = checker.analyzeTexture(cgImage)
            XCTAssertGreaterThanOrEqual(score, 0.0, "Texture score \(score) should be >= 0")
            XCTAssertLessThanOrEqual(score, 1.0, "Texture score \(score) should be <= 1")
        }
    }

    func testFrequencyScoreAlwaysInZeroToOneRange() {
        let images = [
            createSolidColorImage(color: .black, size: CGSize(width: 64, height: 64)),
            createSolidColorImage(color: .white, size: CGSize(width: 64, height: 64)),
            createCheckerboardImage(size: 64),
            createGradientImage(size: 64)
        ]

        for image in images {
            guard let cgImage = image.cgImage else { continue }
            let score = checker.analyzeFrequency(cgImage)
            XCTAssertGreaterThanOrEqual(score, 0.0, "Frequency score \(score) should be >= 0")
            XCTAssertLessThanOrEqual(score, 1.0, "Frequency score \(score) should be <= 1")
        }
    }

    func testColorScoreAlwaysInZeroToOneRange() {
        let images = [
            createSolidColorImage(color: .black, size: CGSize(width: 64, height: 64)),
            createSolidColorImage(color: .white, size: CGSize(width: 64, height: 64)),
            createCheckerboardImage(size: 64),
            createGradientImage(size: 64)
        ]

        for image in images {
            guard let cgImage = image.cgImage else { continue }
            let score = checker.analyzeColorDistribution(cgImage)
            XCTAssertGreaterThanOrEqual(score, 0.0, "Color score \(score) should be >= 0")
            XCTAssertLessThanOrEqual(score, 1.0, "Color score \(score) should be <= 1")
        }
    }

    // MARK: - Overall score weighted formula verification

    func testOverallScoreMatchesWeightedFormula() {
        let image = createCheckerboardImage(size: 64)
        let result = checker.analyze(image)

        let expected = result.textureScore * 0.45 + result.frequencyScore * 0.30 + result.colorScore * 0.25
        XCTAssertEqual(result.overallScore, expected, accuracy: 0.0001,
                       "Overall score should match weighted formula")
    }

    func testSolidImageOverallScoreMatchesWeightedFormula() {
        let image = createSolidColorImage(color: .gray, size: CGSize(width: 64, height: 64))
        let result = checker.analyze(image)

        let expected = result.textureScore * 0.45 + result.frequencyScore * 0.30 + result.colorScore * 0.25
        XCTAssertEqual(result.overallScore, expected, accuracy: 0.0001,
                       "Overall score should match weighted formula")
    }

    // MARK: - Small image does not crash

    func testAnalysisCompletesOnSmallImages() {
        let tinyImage = createSolidColorImage(color: .orange, size: CGSize(width: 4, height: 4))
        let result = checker.analyze(tinyImage)
        // Just verify it completes without crashing and produces valid scores
        XCTAssertGreaterThanOrEqual(result.overallScore, 0.0)
        XCTAssertLessThanOrEqual(result.overallScore, 1.0)
    }

    func testAnalysisCompletesOnOneByOneImage() {
        let tinyImage = createSolidColorImage(color: .cyan, size: CGSize(width: 1, height: 1))
        let result = checker.analyze(tinyImage)
        XCTAssertGreaterThanOrEqual(result.overallScore, 0.0)
        XCTAssertLessThanOrEqual(result.overallScore, 1.0)
    }

    // MARK: - Helper functions

    private func createSolidColorImage(color: UIColor, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func createCheckerboardImage(size: Int) -> UIImage {
        let cgSize = CGSize(width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: cgSize)
        return renderer.image { context in
            let ctx = context.cgContext
            for y in 0..<size {
                for x in 0..<size {
                    if (x + y) % 2 == 0 {
                        ctx.setFillColor(UIColor.white.cgColor)
                    } else {
                        ctx.setFillColor(UIColor.black.cgColor)
                    }
                    ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }

    private func createGradientImage(size: Int) -> UIImage {
        let cgSize = CGSize(width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: cgSize)
        return renderer.image { context in
            let ctx = context.cgContext
            for y in 0..<size {
                for x in 0..<size {
                    let r = CGFloat(x) / CGFloat(size - 1)
                    let g = CGFloat(y) / CGFloat(size - 1)
                    let b = CGFloat(x + y) / CGFloat(2 * (size - 1))
                    ctx.setFillColor(UIColor(red: r, green: g, blue: b, alpha: 1.0).cgColor)
                    ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }
}
