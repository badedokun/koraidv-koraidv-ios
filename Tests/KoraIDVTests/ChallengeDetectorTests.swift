import XCTest
@testable import KoraIDV

final class ChallengeDetectorTests: XCTestCase {

    private var detector: ChallengeDetector!

    override func setUp() {
        super.setUp()
        detector = ChallengeDetector()
    }

    override func tearDown() {
        detector = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Create a DetectedFace with specified yaw, pitch, and optional landmarks.
    private func makeFace(
        yaw: CGFloat? = 0.0,
        pitch: CGFloat? = 0.0,
        roll: CGFloat? = nil,
        confidence: Float = 0.95,
        landmarks: FaceLandmarks? = nil,
        boundingBox: CGRect = CGRect(x: 100, y: 100, width: 200, height: 200)
    ) -> DetectedFace {
        return DetectedFace(
            boundingBox: boundingBox,
            confidence: confidence,
            landmarks: landmarks,
            yaw: yaw,
            pitch: pitch,
            roll: roll
        )
    }

    /// Create FaceLandmarks with specified mouth points and default eye points.
    /// Eye points default to "open" positions (high EAR).
    private func makeLandmarks(
        mouthPoints: [CGPoint]? = nil,
        leftEye: [CGPoint]? = nil,
        rightEye: [CGPoint]? = nil
    ) -> FaceLandmarks {
        let defaultOpenEye: [CGPoint] = [
            CGPoint(x: 0, y: 0),    // p1 (left corner)
            CGPoint(x: 1, y: 5),    // p2 (upper-left)
            CGPoint(x: 3, y: 5),    // p3 (upper-right)
            CGPoint(x: 4, y: 0),    // p4 (right corner)
            CGPoint(x: 3, y: -5),   // p5 (lower-right)
            CGPoint(x: 1, y: -5)    // p6 (lower-left)
        ]

        let defaultMouth: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 1),
            CGPoint(x: 2, y: 2),
            CGPoint(x: 3, y: 1),
            CGPoint(x: 4, y: 0),
            CGPoint(x: 3, y: -1),
            CGPoint(x: 2, y: -2),
            CGPoint(x: 1, y: -1)
        ]

        return FaceLandmarks(
            leftEye: leftEye ?? defaultOpenEye,
            rightEye: rightEye ?? defaultOpenEye,
            nose: [CGPoint(x: 2, y: 2), CGPoint(x: 2, y: 3), CGPoint(x: 2, y: 4)],
            mouth: mouthPoints ?? defaultMouth,
            leftEyebrow: [CGPoint(x: 0, y: 6), CGPoint(x: 2, y: 7)],
            rightEyebrow: [CGPoint(x: 4, y: 7), CGPoint(x: 6, y: 6)],
            faceContour: [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 5)]
        )
    }

    /// Create mouth points that produce a smile (width/height ratio > 2.3).
    /// mouth[0] and mouth[4] define width; mouth[2] and mouth[6] define height.
    private func makeSmileMouth() -> [CGPoint] {
        // width = distance(mouth[0], mouth[4]) = 10
        // height = distance(mouth[2], mouth[6]) = 2
        // ratio = 10 / 2 = 5.0, which is > 2.3
        return [
            CGPoint(x: 0, y: 0),    // mouth[0]
            CGPoint(x: 2, y: 0.5),  // mouth[1]
            CGPoint(x: 5, y: 1),    // mouth[2]
            CGPoint(x: 8, y: 0.5),  // mouth[3]
            CGPoint(x: 10, y: 0),   // mouth[4]
            CGPoint(x: 8, y: -0.5), // mouth[5]
            CGPoint(x: 5, y: -1),   // mouth[6]
            CGPoint(x: 2, y: -0.5)  // mouth[7]
        ]
    }

    /// Create mouth points that produce a neutral expression (width/height ratio < 2.3).
    private func makeNeutralMouth() -> [CGPoint] {
        // width = distance(mouth[0], mouth[4]) = 4
        // height = distance(mouth[2], mouth[6]) = 4
        // ratio = 4 / 4 = 1.0, which is < 2.3
        return [
            CGPoint(x: 0, y: 0),    // mouth[0]
            CGPoint(x: 1, y: 1),    // mouth[1]
            CGPoint(x: 2, y: 2),    // mouth[2]
            CGPoint(x: 3, y: 1),    // mouth[3]
            CGPoint(x: 4, y: 0),    // mouth[4]
            CGPoint(x: 3, y: -1),   // mouth[5]
            CGPoint(x: 2, y: -2),   // mouth[6]
            CGPoint(x: 1, y: -1)    // mouth[7]
        ]
    }

    /// Create eye points that are "closed" (low EAR, below 0.2 threshold).
    private func makeClosedEye() -> [CGPoint] {
        // EAR = (|p2-p6| + |p3-p5|) / (2 * |p1-p4|)
        // p1=(0,0), p2=(1,0.1), p3=(3,0.1), p4=(4,0), p5=(3,-0.1), p6=(1,-0.1)
        // vertical1 = distance(p2,p6) = 0.2
        // vertical2 = distance(p3,p5) = 0.2
        // horizontal = distance(p1,p4) = 4.0
        // EAR = (0.2 + 0.2) / (2 * 4.0) = 0.4 / 8.0 = 0.05 -> well below 0.2
        return [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 0.1),
            CGPoint(x: 3, y: 0.1),
            CGPoint(x: 4, y: 0),
            CGPoint(x: 3, y: -0.1),
            CGPoint(x: 1, y: -0.1)
        ]
    }

    /// Create eye points that are wide open (EAR well above 0.3, i.e., > earBlinkThreshold * 1.5).
    private func makeWideOpenEye() -> [CGPoint] {
        // p1=(0,0), p2=(1,4), p3=(3,4), p4=(4,0), p5=(3,-4), p6=(1,-4)
        // vertical1 = distance(p2,p6) = 8.0
        // vertical2 = distance(p3,p5) = 8.0
        // horizontal = distance(p1,p4) = 4.0
        // EAR = (8 + 8) / (2 * 4) = 2.0 -> well above 0.3
        return [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 4),
            CGPoint(x: 3, y: 4),
            CGPoint(x: 4, y: 0),
            CGPoint(x: 3, y: -4),
            CGPoint(x: 1, y: -4)
        ]
    }

    // MARK: - Initial State Tests

    func testInitialProcessReturnsZeroProgress() {
        let face = makeFace(landmarks: makeLandmarks())
        let result = detector.process(face: face, challengeType: .smile)
        XCTAssertEqual(result.progress, 0.0, accuracy: 0.001)
        XCTAssertFalse(result.completed)
    }

    func testInitialProcessNotCompleted() {
        let face = makeFace(yaw: 0.0, landmarks: makeLandmarks())
        let result = detector.process(face: face, challengeType: .turnLeft)
        XCTAssertFalse(result.completed)
    }

    // MARK: - Smile Detection Tests

    func testSmileDetectedWithHighMouthRatio() {
        let landmarks = makeLandmarks(mouthPoints: makeSmileMouth())
        let face = makeFace(landmarks: landmarks)

        // Process enough frames to complete
        for _ in 0..<5 {
            _ = detector.process(face: face, challengeType: .smile)
        }

        let result = detector.process(face: face, challengeType: .smile)
        XCTAssertTrue(result.completed)
    }

    func testSmileNotDetectedWithNeutralMouth() {
        let landmarks = makeLandmarks(mouthPoints: makeNeutralMouth())
        let face = makeFace(landmarks: landmarks)

        for _ in 0..<10 {
            let result = detector.process(face: face, challengeType: .smile)
            XCTAssertFalse(result.completed)
        }
    }

    func testSmileNotDetectedWithoutLandmarks() {
        let face = makeFace(landmarks: nil)

        for _ in 0..<10 {
            let result = detector.process(face: face, challengeType: .smile)
            XCTAssertFalse(result.completed)
        }
    }

    func testSmileNotDetectedWithInsufficientMouthPoints() {
        // Only 4 mouth points, but 8 are required
        let shortMouth = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 5, y: 1),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 5, y: -1)
        ]
        let landmarks = makeLandmarks(mouthPoints: shortMouth)
        let face = makeFace(landmarks: landmarks)

        for _ in 0..<10 {
            let result = detector.process(face: face, challengeType: .smile)
            XCTAssertFalse(result.completed)
        }
    }

    // MARK: - Turn Left Detection Tests

    func testTurnLeftDetectedWithPositiveYawDelta() {
        // First frame establishes baseline yaw
        let baselineFace = makeFace(yaw: 0.0, landmarks: makeLandmarks())
        _ = detector.process(face: baselineFace, challengeType: .turnLeft)

        // Subsequent frames with yaw delta > 0.25
        let turnedFace = makeFace(yaw: 0.4, landmarks: makeLandmarks())
        for _ in 0..<5 {
            _ = detector.process(face: turnedFace, challengeType: .turnLeft)
        }

        let result = detector.process(face: turnedFace, challengeType: .turnLeft)
        XCTAssertTrue(result.completed)
    }

    func testTurnLeftNotDetectedWithSmallYawDelta() {
        let baselineFace = makeFace(yaw: 0.0, landmarks: makeLandmarks())
        _ = detector.process(face: baselineFace, challengeType: .turnLeft)

        // yaw delta of 0.1 is below the 0.25 threshold
        let slightTurn = makeFace(yaw: 0.1, landmarks: makeLandmarks())
        for _ in 0..<10 {
            let result = detector.process(face: slightTurn, challengeType: .turnLeft)
            XCTAssertFalse(result.completed)
        }
    }

    func testTurnLeftNotDetectedWithNilYaw() {
        let face = makeFace(yaw: nil, landmarks: makeLandmarks())
        for _ in 0..<10 {
            let result = detector.process(face: face, challengeType: .turnLeft)
            XCTAssertFalse(result.completed)
        }
    }

    // MARK: - Turn Right Detection Tests

    func testTurnRightDetectedWithNegativeYawDelta() {
        let baselineFace = makeFace(yaw: 0.0, landmarks: makeLandmarks())
        _ = detector.process(face: baselineFace, challengeType: .turnRight)

        let turnedFace = makeFace(yaw: -0.4, landmarks: makeLandmarks())
        for _ in 0..<5 {
            _ = detector.process(face: turnedFace, challengeType: .turnRight)
        }

        let result = detector.process(face: turnedFace, challengeType: .turnRight)
        XCTAssertTrue(result.completed)
    }

    func testTurnRightNotDetectedWithPositiveYawDelta() {
        let baselineFace = makeFace(yaw: 0.0, landmarks: makeLandmarks())
        _ = detector.process(face: baselineFace, challengeType: .turnRight)

        // Positive yaw delta should not trigger turnRight
        let wrongDirection = makeFace(yaw: 0.4, landmarks: makeLandmarks())
        for _ in 0..<10 {
            let result = detector.process(face: wrongDirection, challengeType: .turnRight)
            XCTAssertFalse(result.completed)
        }
    }

    // MARK: - Nod Up Detection Tests

    func testNodUpDetectedWithPositivePitchDelta() {
        let baselineFace = makeFace(pitch: 0.0, landmarks: makeLandmarks())
        _ = detector.process(face: baselineFace, challengeType: .nodUp)

        let noddedFace = makeFace(pitch: 0.3, landmarks: makeLandmarks())
        for _ in 0..<5 {
            _ = detector.process(face: noddedFace, challengeType: .nodUp)
        }

        let result = detector.process(face: noddedFace, challengeType: .nodUp)
        XCTAssertTrue(result.completed)
    }

    func testNodUpNotDetectedWithSmallPitchDelta() {
        let baselineFace = makeFace(pitch: 0.0, landmarks: makeLandmarks())
        _ = detector.process(face: baselineFace, challengeType: .nodUp)

        // pitch delta of 0.1 is below the 0.15 threshold
        let slightNod = makeFace(pitch: 0.1, landmarks: makeLandmarks())
        for _ in 0..<10 {
            let result = detector.process(face: slightNod, challengeType: .nodUp)
            XCTAssertFalse(result.completed)
        }
    }

    // MARK: - Nod Down Detection Tests

    func testNodDownDetectedWithNegativePitchDelta() {
        let baselineFace = makeFace(pitch: 0.0, landmarks: makeLandmarks())
        _ = detector.process(face: baselineFace, challengeType: .nodDown)

        let noddedFace = makeFace(pitch: -0.3, landmarks: makeLandmarks())
        for _ in 0..<5 {
            _ = detector.process(face: noddedFace, challengeType: .nodDown)
        }

        let result = detector.process(face: noddedFace, challengeType: .nodDown)
        XCTAssertTrue(result.completed)
    }

    func testNodDownNotDetectedWithPositivePitchDelta() {
        let baselineFace = makeFace(pitch: 0.0, landmarks: makeLandmarks())
        _ = detector.process(face: baselineFace, challengeType: .nodDown)

        let wrongDirection = makeFace(pitch: 0.3, landmarks: makeLandmarks())
        for _ in 0..<10 {
            let result = detector.process(face: wrongDirection, challengeType: .nodDown)
            XCTAssertFalse(result.completed)
        }
    }

    func testNodDetectionWithNilPitchFallsBackToNoseLandmarks() {
        // When pitch is nil, the detector uses nose landmarks relative to bounding box.
        // boundingBox midY = 200 (y=100, height=200 -> midY=200)
        // noseTip = nose[nose.count/2] = nose[1] at y=3
        // pitchValue = Float(noseTip.y - faceCenterY) * 2.0 = Float(3 - 200) * 2 = -394.0
        // This establishes a large negative baseline.
        let bb = CGRect(x: 100, y: 100, width: 200, height: 200)
        let landmarks1 = FaceLandmarks(
            leftEye: makeWideOpenEye(),
            rightEye: makeWideOpenEye(),
            nose: [CGPoint(x: 200, y: 200), CGPoint(x: 200, y: 200), CGPoint(x: 200, y: 200)],
            mouth: makeNeutralMouth(),
            leftEyebrow: [],
            rightEyebrow: [],
            faceContour: []
        )
        let face1 = makeFace(yaw: 0.0, pitch: nil, landmarks: landmarks1, boundingBox: bb)
        _ = detector.process(face: face1, challengeType: .nodDown)

        // Now shift nose tip downward significantly: pitchValue becomes more negative
        let landmarks2 = FaceLandmarks(
            leftEye: makeWideOpenEye(),
            rightEye: makeWideOpenEye(),
            nose: [CGPoint(x: 200, y: 100), CGPoint(x: 200, y: 100), CGPoint(x: 200, y: 100)],
            mouth: makeNeutralMouth(),
            leftEyebrow: [],
            rightEyebrow: [],
            faceContour: []
        )
        let face2 = makeFace(yaw: 0.0, pitch: nil, landmarks: landmarks2, boundingBox: bb)

        // The delta = new pitchValue - initial pitchValue
        // new pitchValue = (100 - 200) * 2 = -200
        // initial pitchValue = (200 - 200) * 2 = 0
        // delta = -200 - 0 = -200, which is < -0.15 -> nodDown detected
        for _ in 0..<5 {
            _ = detector.process(face: face2, challengeType: .nodDown)
        }

        let result = detector.process(face: face2, challengeType: .nodDown)
        XCTAssertTrue(result.completed)
    }

    // MARK: - Blink Detection Tests

    func testBlinkDetectedThroughFullCycle() {
        // Blink requires: open -> closing -> closed -> opening -> open (blinkDetected = true)
        let openLandmarks = makeLandmarks(leftEye: makeWideOpenEye(), rightEye: makeWideOpenEye())
        let closedLandmarks = makeLandmarks(leftEye: makeClosedEye(), rightEye: makeClosedEye())

        let openFace = makeFace(landmarks: openLandmarks)
        let closedFace = makeFace(landmarks: closedLandmarks)

        // Frame 1: open state, EAR high -> stays open
        _ = detector.process(face: openFace, challengeType: .blink)

        // Frame 2: EAR drops below threshold -> closing
        _ = detector.process(face: closedFace, challengeType: .blink)

        // Frame 3: EAR still low -> closed
        _ = detector.process(face: closedFace, challengeType: .blink)

        // Frame 4: EAR rises above threshold -> opening
        _ = detector.process(face: openFace, challengeType: .blink)

        // Frame 5: EAR rises above threshold * 1.5 -> open, blinkDetected = true
        let result = detector.process(face: openFace, challengeType: .blink)
        // blinkDetected stays true once set, so subsequent frames also return true
        XCTAssertTrue(result.progress > 0)
    }

    func testBlinkNotDetectedWithoutLandmarks() {
        let face = makeFace(landmarks: nil)

        for _ in 0..<10 {
            let result = detector.process(face: face, challengeType: .blink)
            XCTAssertFalse(result.completed)
        }
    }

    func testBlinkRequiresFullCycleToComplete() {
        // Only closing eyes without reopening should not trigger blink detection
        let closedLandmarks = makeLandmarks(leftEye: makeClosedEye(), rightEye: makeClosedEye())
        let closedFace = makeFace(landmarks: closedLandmarks)

        for _ in 0..<10 {
            let result = detector.process(face: closedFace, challengeType: .blink)
            XCTAssertFalse(result.completed)
        }
    }

    // MARK: - Reset Tests

    func testResetClearsDetectionState() {
        // Build up turn detection state
        let baselineFace = makeFace(yaw: 0.0, landmarks: makeLandmarks())
        _ = detector.process(face: baselineFace, challengeType: .turnLeft)

        let turnedFace = makeFace(yaw: 0.4, landmarks: makeLandmarks())
        for _ in 0..<5 {
            _ = detector.process(face: turnedFace, challengeType: .turnLeft)
        }

        // Verify detection was completed
        let beforeReset = detector.process(face: turnedFace, challengeType: .turnLeft)
        XCTAssertTrue(beforeReset.completed)

        // Reset and verify state is cleared
        detector.reset()

        // After reset, the first frame re-establishes baseline, so detection starts over
        let afterReset = detector.process(face: turnedFace, challengeType: .turnLeft)
        XCTAssertFalse(afterReset.completed)
        XCTAssertEqual(afterReset.progress, 0.0, accuracy: 0.001)
    }

    func testStartDetectingResetsState() {
        // Build up some state
        let baselineFace = makeFace(yaw: 0.0, landmarks: makeLandmarks())
        _ = detector.process(face: baselineFace, challengeType: .turnLeft)

        let turnedFace = makeFace(yaw: 0.4, landmarks: makeLandmarks())
        for _ in 0..<6 {
            _ = detector.process(face: turnedFace, challengeType: .turnLeft)
        }

        // startDetecting calls reset internally
        detector.startDetecting(challengeType: .turnRight)

        // State should be cleared: first frame re-establishes baseline
        let result = detector.process(face: turnedFace, challengeType: .turnRight)
        XCTAssertFalse(result.completed)
    }

    // MARK: - Consecutive Detections Tests

    func testRequiresFiveConsecutiveDetections() {
        // First frame establishes baseline
        let baselineFace = makeFace(yaw: 0.0, landmarks: makeLandmarks())
        _ = detector.process(face: baselineFace, challengeType: .turnLeft)

        let turnedFace = makeFace(yaw: 0.4, landmarks: makeLandmarks())

        // After 4 consecutive detections, should NOT be completed
        for _ in 0..<4 {
            _ = detector.process(face: turnedFace, challengeType: .turnLeft)
        }
        let after4 = detector.process(face: turnedFace, challengeType: .turnLeft)
        XCTAssertTrue(after4.completed,
                      "5th consecutive detection (frames 2-6) should complete the challenge")
    }

    func testFourConsecutiveDetectionsNotEnough() {
        let baselineFace = makeFace(yaw: 0.0, landmarks: makeLandmarks())
        _ = detector.process(face: baselineFace, challengeType: .turnLeft)

        let turnedFace = makeFace(yaw: 0.4, landmarks: makeLandmarks())

        // Process exactly 3 frames after baseline (so we have 3 consecutive trues)
        for _ in 0..<3 {
            _ = detector.process(face: turnedFace, challengeType: .turnLeft)
        }

        let result = detector.process(face: turnedFace, challengeType: .turnLeft)
        // 4 consecutive trues after the false baseline frame
        XCTAssertFalse(result.completed,
                       "4 consecutive detections should not be enough; 5 are required")
    }

    func testInterruptedConsecutiveDetectionsResetProgress() {
        let baselineFace = makeFace(yaw: 0.0, landmarks: makeLandmarks())
        _ = detector.process(face: baselineFace, challengeType: .turnLeft)

        let turnedFace = makeFace(yaw: 0.4, landmarks: makeLandmarks())
        let neutralFace = makeFace(yaw: 0.1, landmarks: makeLandmarks())

        // 3 consecutive positive detections
        for _ in 0..<3 {
            _ = detector.process(face: turnedFace, challengeType: .turnLeft)
        }

        // Interrupt with a negative detection
        _ = detector.process(face: neutralFace, challengeType: .turnLeft)

        // 3 more positive detections (total 3 consecutive, not 5)
        for _ in 0..<3 {
            _ = detector.process(face: turnedFace, challengeType: .turnLeft)
        }

        let result = detector.process(face: turnedFace, challengeType: .turnLeft)
        // The last 5 frames are: neutral(false), turned, turned, turned, turned
        // That's 4 out of 5 in the last 5 => consecutive count = 4 (filter counts all trues)
        // Actually the code does: recentDetections.filter { $0 }.count, not strict consecutive
        // So 4 trues out of 5 => progress = 0.8, not completed
        XCTAssertFalse(result.completed)
    }

    // MARK: - Progress Tests

    func testProgressClampedToOne() {
        let landmarks = makeLandmarks(mouthPoints: makeSmileMouth())
        let face = makeFace(landmarks: landmarks)

        // Process many frames beyond what's needed
        for _ in 0..<20 {
            _ = detector.process(face: face, challengeType: .smile)
        }

        let result = detector.process(face: face, challengeType: .smile)
        XCTAssertLessThanOrEqual(result.progress, 1.0)
        XCTAssertTrue(result.completed)
    }

    func testProgressIncreasesWithConsecutiveDetections() {
        let baselineFace = makeFace(yaw: 0.0, landmarks: makeLandmarks())
        _ = detector.process(face: baselineFace, challengeType: .turnLeft)

        let turnedFace = makeFace(yaw: 0.4, landmarks: makeLandmarks())

        var previousProgress: Float = 0.0
        for i in 0..<5 {
            let result = detector.process(face: turnedFace, challengeType: .turnLeft)
            XCTAssertGreaterThanOrEqual(result.progress, previousProgress,
                                        "Progress should not decrease on frame \(i)")
            previousProgress = result.progress
        }
    }

    func testProgressIsZeroOnFirstFrame() {
        let face = makeFace(yaw: 0.0, landmarks: makeLandmarks())
        let result = detector.process(face: face, challengeType: .turnLeft)
        // First frame for turn establishes baseline, returns false
        XCTAssertEqual(result.progress, 0.0, accuracy: 0.001)
    }

    // MARK: - Confidence Tests

    func testResultConfidenceMatchesFaceConfidence() {
        let face = makeFace(confidence: 0.87, landmarks: makeLandmarks())
        let result = detector.process(face: face, challengeType: .smile)
        XCTAssertEqual(result.confidence, 0.87, accuracy: 0.001)
    }

    // MARK: - Edge Case Tests

    func testTurnDetectionWithExactThreshold() {
        // Delta exactly at threshold (0.25) should NOT trigger detection
        // because the check is delta > turnThreshold (strict greater than)
        let baselineFace = makeFace(yaw: 0.0, landmarks: makeLandmarks())
        _ = detector.process(face: baselineFace, challengeType: .turnLeft)

        let edgeFace = makeFace(yaw: 0.25, landmarks: makeLandmarks())
        for _ in 0..<10 {
            let result = detector.process(face: edgeFace, challengeType: .turnLeft)
            XCTAssertFalse(result.completed,
                           "Exact threshold value should not trigger detection (strict inequality)")
        }
    }

    func testNodDetectionWithExactThreshold() {
        let baselineFace = makeFace(pitch: 0.0, landmarks: makeLandmarks())
        _ = detector.process(face: baselineFace, challengeType: .nodUp)

        let edgeFace = makeFace(pitch: 0.15, landmarks: makeLandmarks())
        for _ in 0..<10 {
            let result = detector.process(face: edgeFace, challengeType: .nodUp)
            XCTAssertFalse(result.completed,
                           "Exact threshold value should not trigger nod detection")
        }
    }

    func testNodWithNilPitchAndNoNoseLandmarksReturnsFalse() {
        // When both pitch is nil and nose landmarks are insufficient, detection should fail
        let landmarks = FaceLandmarks(
            leftEye: makeWideOpenEye(),
            rightEye: makeWideOpenEye(),
            nose: [CGPoint(x: 0, y: 0)], // Only 1 nose point, need >= 2
            mouth: makeNeutralMouth(),
            leftEyebrow: [],
            rightEyebrow: [],
            faceContour: []
        )
        let face = makeFace(pitch: nil, landmarks: landmarks)

        for _ in 0..<10 {
            let result = detector.process(face: face, challengeType: .nodUp)
            XCTAssertFalse(result.completed)
        }
    }
}
