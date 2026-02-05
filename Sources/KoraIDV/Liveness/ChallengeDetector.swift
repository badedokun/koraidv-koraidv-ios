import Foundation

/// Challenge detection result
struct ChallengeDetectionResult {
    let progress: Float
    let completed: Bool
    let confidence: Float
}

/// Challenge Detector for liveness verification
final class ChallengeDetector {

    // MARK: - Properties

    private var currentChallengeType: ChallengeType?
    private var frameCount = 0
    private var detectionHistory: [Bool] = []

    /// Number of consecutive detections required
    private let requiredConsecutiveDetections = 5

    /// Eye Aspect Ratio threshold for blink detection
    private let earBlinkThreshold: Float = 0.2

    /// Smile detection threshold
    private let smileThreshold: Float = 0.3

    /// Head turn threshold (radians)
    private let turnThreshold: Float = 0.25

    /// Head nod threshold (radians)
    private let nodThreshold: Float = 0.15

    // MARK: - State

    private var blinkState: BlinkState = .open
    private var blinkDetected = false

    private var initialYaw: Float?
    private var turnDetected = false

    private var initialPitch: Float?
    private var nodDetected = false

    private var smileDetected = false

    private enum BlinkState {
        case open
        case closing
        case closed
        case opening
    }

    // MARK: - Public Methods

    /// Start detecting a specific challenge type
    func startDetecting(challengeType: ChallengeType) {
        currentChallengeType = challengeType
        reset()
    }

    /// Process a face detection frame
    func process(face: DetectedFace, challengeType: ChallengeType) -> ChallengeDetectionResult {
        frameCount += 1

        let detected: Bool

        switch challengeType {
        case .blink:
            detected = detectBlink(face: face)
        case .smile:
            detected = detectSmile(face: face)
        case .turnLeft:
            detected = detectTurn(face: face, direction: .left)
        case .turnRight:
            detected = detectTurn(face: face, direction: .right)
        case .nodUp:
            detected = detectNod(face: face, direction: .up)
        case .nodDown:
            detected = detectNod(face: face, direction: .down)
        }

        detectionHistory.append(detected)

        // Keep only recent history
        if detectionHistory.count > requiredConsecutiveDetections * 2 {
            detectionHistory.removeFirst()
        }

        // Check if we have enough consecutive detections
        let recentDetections = detectionHistory.suffix(requiredConsecutiveDetections)
        let consecutiveCount = recentDetections.filter { $0 }.count
        let progress = Float(consecutiveCount) / Float(requiredConsecutiveDetections)
        let completed = consecutiveCount >= requiredConsecutiveDetections

        return ChallengeDetectionResult(
            progress: min(progress, 1.0),
            completed: completed,
            confidence: face.confidence
        )
    }

    /// Reset detector state
    func reset() {
        frameCount = 0
        detectionHistory = []
        blinkState = .open
        blinkDetected = false
        initialYaw = nil
        turnDetected = false
        initialPitch = nil
        nodDetected = false
        smileDetected = false
    }

    // MARK: - Blink Detection

    private func detectBlink(face: DetectedFace) -> Bool {
        guard let landmarks = face.landmarks else { return false }

        // Calculate Eye Aspect Ratio (EAR)
        let leftEAR = calculateEAR(eye: landmarks.leftEye)
        let rightEAR = calculateEAR(eye: landmarks.rightEye)
        let avgEAR = (leftEAR + rightEAR) / 2.0

        // State machine for blink detection
        switch blinkState {
        case .open:
            if avgEAR < earBlinkThreshold {
                blinkState = .closing
            }
        case .closing:
            if avgEAR < earBlinkThreshold {
                blinkState = .closed
            } else {
                blinkState = .open
            }
        case .closed:
            if avgEAR > earBlinkThreshold {
                blinkState = .opening
            }
        case .opening:
            if avgEAR > earBlinkThreshold * 1.5 {
                blinkState = .open
                blinkDetected = true
            }
        }

        return blinkDetected
    }

    /// Calculate Eye Aspect Ratio
    private func calculateEAR(eye: [CGPoint]) -> Float {
        guard eye.count >= 6 else { return 1.0 }

        // EAR = (|p2-p6| + |p3-p5|) / (2 * |p1-p4|)
        // Using approximation with available landmarks
        let vertical1 = distance(eye[1], eye[5])
        let vertical2 = distance(eye[2], eye[4])
        let horizontal = distance(eye[0], eye[3])

        guard horizontal > 0 else { return 1.0 }

        return Float((vertical1 + vertical2) / (2.0 * horizontal))
    }

    // MARK: - Smile Detection

    private func detectSmile(face: DetectedFace) -> Bool {
        guard let landmarks = face.landmarks else { return false }

        // Calculate mouth aspect ratio
        let mouth = landmarks.mouth
        guard mouth.count >= 8 else { return false }

        // Approximate smile by measuring mouth width vs height
        let width = distance(mouth[0], mouth[4])
        let height = distance(mouth[2], mouth[6])

        guard height > 0 else { return false }

        let ratio = Float(width / height)

        // A smile typically has a higher width-to-height ratio
        smileDetected = ratio > (2.0 + smileThreshold)

        return smileDetected
    }

    // MARK: - Turn Detection

    private enum TurnDirection {
        case left
        case right
    }

    private func detectTurn(face: DetectedFace, direction: TurnDirection) -> Bool {
        guard let yaw = face.yaw else { return false }

        let yawFloat = Float(yaw)

        // Initialize baseline
        if initialYaw == nil {
            initialYaw = yawFloat
            return false
        }

        let delta = yawFloat - (initialYaw ?? 0)

        switch direction {
        case .left:
            turnDetected = delta > turnThreshold
        case .right:
            turnDetected = delta < -turnThreshold
        }

        return turnDetected
    }

    // MARK: - Nod Detection

    private enum NodDirection {
        case up
        case down
    }

    private func detectNod(face: DetectedFace, direction: NodDirection) -> Bool {
        guard let pitch = face.pitch else { return false }

        let pitchFloat = Float(pitch)

        // Initialize baseline
        if initialPitch == nil {
            initialPitch = pitchFloat
            return false
        }

        let delta = pitchFloat - (initialPitch ?? 0)

        switch direction {
        case .up:
            nodDetected = delta > nodThreshold
        case .down:
            nodDetected = delta < -nodThreshold
        }

        return nodDetected
    }

    // MARK: - Utilities

    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        return sqrt(dx * dx + dy * dy)
    }
}
