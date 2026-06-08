import Foundation
import CoreImage

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

    /// Head turn threshold (radians) — relaxed for front-camera jitter
    private let turnThreshold: Float = 0.17

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

    /// **v1.9.0-rc6.8** — Core Image face detector for smile + eye-blink.
    /// Apple Vision (the framework the rest of the SDK uses) does not
    /// expose smile or blink probability — only landmarks. The prior
    /// implementation computed mouth aspect ratio and eye aspect ratio
    /// (EAR) from those landmarks, but server-log analysis showed it
    /// never worked reliably:
    ///   - Smile: 0 submissions in 7 days across all sessions
    ///   - Blink: 1 submission in last few hours (vs 14 turns, 9 nods)
    /// Core Image's `CIDetectorTypeFace` with `CIDetectorSmile` +
    /// `CIDetectorEyeBlink` enabled provides Apple's production smile
    /// classifier and per-eye open/closed booleans. Has been a stable
    /// API since iOS 7. Lazy-created on first use; gated to only run
    /// when current challenge is `.smile` or `.blink` so turn/nod
    /// challenges keep their Vision-only path with no per-frame
    /// overhead change.
    private lazy var coreImageFaceDetector: CIDetector? = {
        return CIDetector(
            ofType: CIDetectorTypeFace,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
    }()

    /// **v1.9.0-rc6.8** — minimal two-state machine for the CIDetector
    /// blink path. Cleaner than the EAR-threshold 4-state machine
    /// because the inputs are discrete (eye is closed or not) instead
    /// of noisy floating-point landmark math.
    private enum CoreImageBlinkState {
        case waitingForClose  // eyes are open; waiting for them to close
        case waitingForReopen // eyes are closed; waiting for them to reopen
    }
    private var coreImageBlinkState: CoreImageBlinkState = .waitingForClose

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

    /// Process a face detection frame.
    ///
    /// **v1.9.0-rc6.8** — `ciImage` parameter added. For `.smile` and
    /// `.blink` challenges the detector runs Core Image's classifier
    /// on this image; if `ciImage` is nil (e.g. caller didn't construct
    /// one — defensive only), falls back to the legacy Vision-landmark
    /// heuristic. For turn/nod challenges, `ciImage` is ignored and
    /// the existing Vision-based yaw/pitch path runs unchanged.
    func process(face: DetectedFace, ciImage: CIImage? = nil, challengeType: ChallengeType) -> ChallengeDetectionResult {
        frameCount += 1

        let detected: Bool

        switch challengeType {
        case .blink:
            // Try CIDetector first (reliable); fall back to EAR if unavailable.
            detected = detectBlinkViaCoreImage(ciImage: ciImage) ?? detectBlink(face: face)
        case .smile:
            detected = detectSmileViaCoreImage(ciImage: ciImage) ?? detectSmile(face: face)
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
        // **v1.9.0-rc6.8** — reset CIDetector-path blink state too,
        // so the next challenge starts fresh.
        coreImageBlinkState = .waitingForClose
    }

    // MARK: - Core Image-Based Detection (v1.9.0-rc6.8)

    /// Detect smile using Apple's CIDetector. Returns:
    ///   - `true`  → smile detected (sticky once observed for the
    ///     current challenge; cleared by `reset()`)
    ///   - `false` → no smile yet this challenge
    ///   - `nil`   → CIDetector unavailable or no ciImage; caller
    ///     should fall back to the legacy heuristic
    ///
    /// Compared to the mouth-aspect heuristic this replaces:
    /// Apple's smile classifier was trained on millions of faces and
    /// handles head pose, lighting, partial occlusion, and natural
    /// vs forced smiles. The heuristic compared landmark distances
    /// with noisy thresholds that Apple Vision's outerLips ordering
    /// didn't reliably support. Server-log evidence: 0 smile
    /// submissions in 7 days under the old detector.
    private func detectSmileViaCoreImage(ciImage: CIImage?) -> Bool? {
        guard let ciImage = ciImage, let detector = coreImageFaceDetector else {
            return nil
        }
        let features = detector.features(in: ciImage, options: [CIDetectorSmile: true])
        guard let face = features.first as? CIFaceFeature else {
            return smileDetected  // no face this frame, return cached state
        }
        if face.hasSmile {
            smileDetected = true
        }
        return smileDetected
    }

    /// Detect blink using Apple's CIDetector. Two-state machine on
    /// discrete Bool inputs (eyes closed / not) — much simpler and
    /// more reliable than the four-state EAR machine it replaces.
    ///
    /// Requires the full open → both-eyes-closed → both-eyes-open
    /// cycle to register, so static eyes-closed images don't count
    /// as a blink. Sticky once observed (matches turn/nod pattern).
    ///
    /// Returns `nil` if CIDetector unavailable; caller falls back to
    /// the EAR heuristic.
    private func detectBlinkViaCoreImage(ciImage: CIImage?) -> Bool? {
        guard let ciImage = ciImage, let detector = coreImageFaceDetector else {
            return nil
        }
        let features = detector.features(in: ciImage, options: [CIDetectorEyeBlink: true])
        guard let face = features.first as? CIFaceFeature else {
            return blinkDetected  // no face this frame, return cached state
        }
        let bothClosed = face.leftEyeClosed && face.rightEyeClosed
        let bothOpen = !face.leftEyeClosed && !face.rightEyeClosed
        switch coreImageBlinkState {
        case .waitingForClose:
            if bothClosed {
                coreImageBlinkState = .waitingForReopen
            }
        case .waitingForReopen:
            if bothOpen {
                coreImageBlinkState = .waitingForClose
                blinkDetected = true
            }
        }
        return blinkDetected
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
            // **v1.9.0-rc6.7** — lowered open-completion threshold from
            // `* 1.5` to `* 1.2`. A natural human blink doesn't always
            // fully return EAR to 1.5× the closed threshold within the
            // detection window — partial recovery (eyes ~80% open) is
            // common, especially under indoor lighting where landmark
            // estimation has more noise. With the prior 1.5× threshold,
            // the state machine often stuck in .opening and never
            // declared the blink complete, so even though the user did
            // blink, the challenge took many seconds (or never
            // registered) before the consecutive-frames counter
            // accumulated. Stratum Remit 2026-06-07: "blink lags for
            // several seconds before it transition." Lower threshold
            // = more reliable cycle completion. blinkDetected stays
            // sticky-true once set (same pattern as rc6.6 smile fix).
            if avgEAR > earBlinkThreshold * 1.2 {
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
        // **v1.9.0-rc6.6 — sticky smile + lower threshold.** Apple
        // Vision doesn't expose a `smilingProbability` like Android's
        // ML Kit, so iOS uses a landmark-based mouth-aspect ratio
        // heuristic. Two issues with the prior implementation:
        //
        // 1. `smileDetected` was reassigned every frame (`=` instead of
        //    `||=`). Mouth shape fluctuates during a smile — lips
        //    spread, teeth show/hide, jaw moves — so the ratio dips
        //    below threshold momentarily and `smileDetected` flips
        //    back to false. Compare to `nodDetected` / `turnDetected`
        //    which stay true once the gesture is observed (sticky).
        //
        // 2. The outer `requiredConsecutiveDetections = 5` requires
        //    five consecutive frames at ratio > threshold. A natural
        //    100ms smile is ~3 frames at 30fps — never enough.
        //
        // Stratum Remit 2026-06-06 rc6.5: "when smile challenge is #3,
        // the transition to processing is delayed." Not position-
        // specific — happens whenever smile is the challenge.
        //
        // Fix: once ratio crosses threshold, set `smileDetected = true`
        // and *keep it true* for the remainder of this challenge
        // (sticky). This matches the turn/nod pattern. Reset happens
        // in `reset()` when the next challenge starts. Result: as soon
        // as the user smiles enough to cross threshold once, return
        // true for every subsequent frame, so the 5-frame consecutive
        // counter ramps up quickly even if the mouth shape fluctuates.
        //
        // Threshold itself unchanged (`smileThreshold = 0.35`, so
        // ratio > 2.35) — this was already tuned reasonably; the
        // problem was the resetting behavior, not the trigger level.
        guard let landmarks = face.landmarks else { return false }

        let mouth = landmarks.mouth
        guard mouth.count >= 8 else { return false }

        let width = distance(mouth[0], mouth[4])
        let height = distance(mouth[2], mouth[6])

        guard height > 0 else { return false }

        let ratio = Float(width / height)

        if ratio > (2.0 + smileThreshold) {
            smileDetected = true
        }
        // Sticky — once true, stays true until `reset()` (next challenge).

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
        // face.pitch requires iOS 15+. When unavailable, fall back to
        // tracking vertical nose position relative to face bounding box.
        let pitchValue: Float
        if let pitch = face.pitch {
            pitchValue = Float(pitch)
        } else if let landmarks = face.landmarks, landmarks.nose.count >= 2 {
            // Approximate pitch from nose tip Y position relative to face center.
            // As head tilts down, nose moves below center; up, above center.
            let noseTip = landmarks.nose[landmarks.nose.count / 2]
            let faceCenterY = face.boundingBox.midY
            pitchValue = Float(noseTip.y - faceCenterY) * 2.0
        } else {
            return false
        }

        // Initialize baseline
        if initialPitch == nil {
            initialPitch = pitchValue
            return false
        }

        let delta = pitchValue - (initialPitch ?? 0)

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
