import UIKit
import AVFoundation

/// Liveness check result
struct LivenessResult {
    let passed: Bool
    let challenges: [ChallengeResultItem]
    let sessionId: String
}

/// Challenge result item
struct ChallengeResultItem {
    let challenge: LivenessChallenge
    let passed: Bool
    let confidence: Double
    let imageData: Data?
}

/// Liveness manager delegate
protocol LivenessManagerDelegate: AnyObject {
    func livenessManager(_ manager: LivenessManager, didStartChallenge challenge: LivenessChallenge)
    func livenessManager(_ manager: LivenessManager, didUpdateProgress progress: Float, for challenge: LivenessChallenge)
    func livenessManager(_ manager: LivenessManager, didCompleteChallenge challenge: LivenessChallenge, passed: Bool, imageData: Data?)
    func livenessManager(_ manager: LivenessManager, didComplete result: LivenessResult)
    func livenessManager(_ manager: LivenessManager, didFail error: KoraError)

    /// **v1.9.0-rc6** — emitted whenever the face-detected state
    /// changes (true = face is visible in front of the camera with
    /// confidence ≥ `FaceDetector.minimumConfidence`; false = not).
    /// LivenessView uses this to color the oval guide (grey when no
    /// face, green when face detected) and to gate the countdown so
    /// it doesn't fire 3-2-1 to an empty viewport. Without this
    /// signal there was no way for the UI to know the SDK was seeing
    /// the user, which produced Stratum Remit's 2026-06-06 report
    /// "grey oval never turns green and the count down goes from 3
    /// to 1 and just transition to another challenge."
    func livenessManager(_ manager: LivenessManager, didChangeFaceDetected detected: Bool)

    /// **v1.9.0-rc6** — emitted when the SDK is ready for the user to
    /// perform the current challenge gesture. Fires after the countdown
    /// completes AND the face is in confident range. The UI should
    /// show a "Go!" indicator at this point; ChallengeDetector begins
    /// scoring gestures only after this signal. Without this gate,
    /// ChallengeDetector picked up natural micro-movements during the
    /// 3-second countdown and silently auto-completed challenges
    /// before the user could react.
    func livenessManager(_ manager: LivenessManager, didActivateChallenge challenge: LivenessChallenge)
}

// MARK: - Default delegate implementations (for backwards compat)
//
// rc6 added two new delegate methods. Default no-op implementations
// keep existing in-tree conformers (LivenessViewModel) compiling
// even if they don't yet implement the new callbacks — and protect
// any external test mocks from breaking.
extension LivenessManagerDelegate {
    func livenessManager(_ manager: LivenessManager, didChangeFaceDetected detected: Bool) {}
    func livenessManager(_ manager: LivenessManager, didActivateChallenge challenge: LivenessChallenge) {}
}

/// Liveness Manager for challenge-response verification
final class LivenessManager: NSObject {

    // MARK: - Properties

    weak var delegate: LivenessManagerDelegate?

    /// CameraManager visibility relaxed from `private` to internal in v1.8.6
    /// so `LivenessCameraPreviewView` can read its `captureSession` directly
    /// when binding the SwiftUI preview. Matches `SelfieCapture.cameraManager`
    /// which has always been internal. See `CameraPreviewUIView` docstring in
    /// CameraManager.swift for the full Bug 1 root cause.
    let cameraManager = CameraManager()
    private let faceDetector = FaceDetector()
    private let challengeDetector = ChallengeDetector()
    private let antiSpoofCheck = AntiSpoofCheck()
    private let ciContext = CIContext()

    /// Serial queue to protect mutable state from data races
    private let stateQueue = DispatchQueue(label: "com.koraidv.liveness.state")

    private var _session: LivenessSession?
    private var _currentChallengeIndex = 0
    private var _challengeResults: [ChallengeResultItem] = []
    private var _isProcessing = false
    private var _frameCount = 0
    private var _isFaceDetected = false
    private var _isChallengeActive = false

    /// **v1.9.0-rc6** — bumped 300 → 600. At 30fps that's 20s of
    /// per-challenge budget instead of 10s. The 10s budget was too
    /// tight: countdown (3s) + face-acquire (1–3s) + react (1s) +
    /// perform-gesture (2–4s) = 7–11s in real-world testing.
    /// Stratum Remit's 2026-06-06 rc5 test hit the 10s ceiling on
    /// every challenge — frame budget exhausted before the user could
    /// complete the gesture, recordChallengeResult fired with nil
    /// imageData, the rc3 LivenessView guard suppressed the bad
    /// submission, and the SDK silently advanced. 20s gives enough
    /// headroom that a deliberate user can finish.
    ///
    /// rc6 also gates the budget — see `processFrame` — so frames
    /// processed during the countdown don't burn this allowance.
    private let maxFramesPerChallenge = 600

    /// Thread-safe access to currentChallengeIndex
    private var currentChallengeIndex: Int {
        get { stateQueue.sync { _currentChallengeIndex } }
        set { stateQueue.sync { _currentChallengeIndex = newValue } }
    }

    /// Thread-safe access to isProcessing
    private var isProcessing: Bool {
        get { stateQueue.sync { _isProcessing } }
        set { stateQueue.sync { _isProcessing = newValue } }
    }

    /// Thread-safe access to frameCount
    private var frameCount: Int {
        get { stateQueue.sync { _frameCount } }
        set { stateQueue.sync { _frameCount = newValue } }
    }

    /// **v1.9.0-rc6** — true while the user's face is visible in the
    /// camera with sufficient confidence. Drives the LivenessView oval
    /// color (grey → green) and gates the countdown so it doesn't
    /// fire to an empty viewport. Updated on every detector callback;
    /// delegate is notified only on state transitions.
    private var isFaceDetected: Bool {
        get { stateQueue.sync { _isFaceDetected } }
        set { stateQueue.sync { _isFaceDetected = newValue } }
    }

    /// **v1.9.0-rc6** — true once LivenessView has signaled that the
    /// countdown completed AND face has been continuously detected.
    /// Until then, frames flow into faceDetector for state updates
    /// only — `challengeDetector.process` is skipped so natural
    /// micro-movements during the 3-second countdown can't
    /// auto-complete the challenge (the rc5 root cause of "challenges
    /// transition before user can react"). Set by the public
    /// `activateChallenge()` method called from LivenessView; reset
    /// by `startNextChallenge()`.
    private var isChallengeActive: Bool {
        get { stateQueue.sync { _isChallengeActive } }
        set { stateQueue.sync { _isChallengeActive = newValue } }
    }

    /// Thread-safe append to challengeResults
    private func appendChallengeResult(_ result: ChallengeResultItem) {
        stateQueue.sync { _challengeResults.append(result) }
    }

    /// Thread-safe read of challengeResults
    private var challengeResults: [ChallengeResultItem] {
        stateQueue.sync { _challengeResults }
    }

    /// Thread-safe access to session
    private var session: LivenessSession? {
        get { stateQueue.sync { _session } }
        set { stateQueue.sync { _session = newValue } }
    }

    /// Current challenge being processed
    var currentChallenge: LivenessChallenge? {
        return stateQueue.sync {
            guard let session = _session else { return nil }
            let index = _currentChallengeIndex
            guard index < session.challenges.count else { return nil }
            return session.challenges[index]
        }
    }

    // MARK: - Public Methods

    /// Start liveness session
    func start(session: LivenessSession, completion: @escaping (Result<Void, KoraError>) -> Void) {
        stateQueue.sync {
            _session = session
            _currentChallengeIndex = 0
            _challengeResults = []
            _isProcessing = false
            _frameCount = 0
        }

        // Configure face detector for liveness
        faceDetector.detectLandmarks = true

        cameraManager.delegate = self
        cameraManager.configure(position: .front) { [weak self] result in
            switch result {
            case .success:
                self?.cameraManager.start()
                self?.startNextChallenge()
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Stop liveness session
    func stop() {
        cameraManager.stop()
        challengeDetector.reset()
        stateQueue.sync { _session = nil }
    }

    /// Get preview layer
    func createPreviewLayer(for view: UIView) -> AVCaptureVideoPreviewLayer {
        return cameraManager.createPreviewLayer(for: view)
    }

    /// Skip current challenge (for testing/debug)
    func skipChallenge() {
        guard let challenge = currentChallenge else { return }

        let result = ChallengeResultItem(
            challenge: challenge,
            passed: false,
            confidence: 0,
            imageData: nil
        )
        appendChallengeResult(result)

        delegate?.livenessManager(self, didCompleteChallenge: challenge, passed: false, imageData: nil)
        moveToNextChallenge()
    }

    // MARK: - Private Methods

    private func startNextChallenge() {
        guard let challenge = currentChallenge else {
            completeSession()
            return
        }

        challengeDetector.reset()
        stateQueue.sync {
            _frameCount = 0
            // **v1.9.0-rc6** — challenge starts in *inactive* state.
            // ChallengeDetector frames are suppressed (only face-state
            // updates flow) until LivenessView signals
            // `activateChallenge()` after its countdown completes.
            _isChallengeActive = false
        }
        challengeDetector.startDetecting(challengeType: challenge.type)

        delegate?.livenessManager(self, didStartChallenge: challenge)
    }

    /// **v1.9.0-rc6** — called by LivenessView after its countdown
    /// completes (and only while face is in detected range), signaling
    /// that the SDK should start scoring user gestures for the current
    /// challenge. ChallengeDetector frames before this call are
    /// ignored so the SDK can't auto-complete on user movement during
    /// the countdown.
    ///
    /// Idempotent — safe to call multiple times on the same challenge
    /// (the detector itself debounces).
    func activateChallenge() {
        guard let challenge = currentChallenge else { return }
        let wasActive = isChallengeActive
        isChallengeActive = true
        if !wasActive {
            KoraIDV.log("LivenessManager: activated challenge=\(challenge.type) — gesture scoring on")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.livenessManager(self, didActivateChallenge: challenge)
            }
        }
    }

    private func moveToNextChallenge() {
        currentChallengeIndex += 1
        startNextChallenge()
    }

    private func completeSession() {
        guard let session = session else { return }

        cameraManager.stop()

        let allPassed = challengeResults.allSatisfy { $0.passed }

        let result = LivenessResult(
            passed: allPassed,
            challenges: challengeResults,
            sessionId: session.sessionId
        )

        delegate?.livenessManager(self, didComplete: result)
    }

    private func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard !isProcessing, let challenge = currentChallenge else { return }

        // **v1.9.0-rc6** — frame budget only counts frames *after the
        // challenge becomes active* (i.e. after LivenessView's
        // countdown completes). Frames consumed during the countdown
        // for face-detection updates do NOT burn this allowance, so
        // the 20-second budget represents 20 seconds of *gesture
        // attempt time*, not 20 seconds of total wall clock. Previous
        // behavior counted every frame, so a 3-second countdown +
        // 1-second face-acquire ate 4 seconds of the 10-second budget
        // before the user even saw the prompt.
        if isChallengeActive {
            guard frameCount < maxFramesPerChallenge else {
                KoraIDV.log("LivenessManager: frame budget exhausted (\(maxFramesPerChallenge)) for challenge=\(challenge.type); recording nil imageData")
                recordChallengeResult(challenge: challenge, passed: false, confidence: 0, imageData: nil)
                return
            }
            frameCount += 1
        }
        isProcessing = true

        faceDetector.detectFaces(in: sampleBuffer) { [weak self] result in
            guard let self = self else { return }

            defer { self.isProcessing = false }

            // **v1.9.0-rc6** — always update face-detected state, even
            // when the challenge isn't active yet (LivenessView needs
            // this signal to color the oval green and to start its
            // countdown only once face is in confident range). The
            // ChallengeDetector branch below is what's gated, not face
            // detection.
            let faceVisible = (result?.faces.first != nil)
            let priorFaceState = self.isFaceDetected
            if priorFaceState != faceVisible {
                self.isFaceDetected = faceVisible
                DispatchQueue.main.async {
                    self.delegate?.livenessManager(self, didChangeFaceDetected: faceVisible)
                }
            }

            guard let faceResult = result, let face = faceResult.faces.first else {
                return
            }

            // **v1.9.0-rc6** — gate gesture scoring on isChallengeActive.
            // Frames before activation update face-detected state above
            // (so the UI can react) but don't feed the gesture
            // detector. This is the single most important rc6 change:
            // it stops the SDK from auto-completing challenges on
            // user movement during the 3-second countdown.
            guard self.isChallengeActive else { return }

            // **v1.9.0-rc6.8** — construct CIImage from the pixel
            // buffer so the challenge detector can route smile/blink
            // challenges to CIDetector (Apple's smile + eye-blink
            // classifier). For turn/nod challenges the detector
            // ignores ciImage and uses the existing Vision yaw/pitch
            // path. CIImage init from a CVPixelBuffer is cheap (no
            // copy, just wraps the existing buffer), so the cost on
            // every frame is negligible — the expensive CIDetector
            // call only fires inside the gated detectors.
            let ciImage: CIImage?
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            } else {
                ciImage = nil
            }
            let detectionResult = self.challengeDetector.process(
                face: face,
                ciImage: ciImage,
                challengeType: challenge.type
            )

            DispatchQueue.main.async {
                self.delegate?.livenessManager(self, didUpdateProgress: detectionResult.progress, for: challenge)
            }

            if detectionResult.completed {
                // Capture frame for this challenge
                self.captureFrameForChallenge(challenge, face: face, sampleBuffer: sampleBuffer)
            }
        }
    }

    private func captureFrameForChallenge(_ challenge: LivenessChallenge, face: DetectedFace, sampleBuffer: CMSampleBuffer) {
        // rc3: each nil-imageData exit path is now logged so QA can see
        // *which* failure mode is firing in a given session. Previously
        // all four paths (here × 3 + frame budget) folded into the same
        // silent HTTP 400; now Console.app filter `subsystem:com.koraidv.sdk`
        // pinpoints whether it's a capture-side, conversion-side, or
        // anti-spoof rejection.
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            KoraIDV.log("LivenessManager: CMSampleBufferGetImageBuffer returned nil for challenge=\(challenge.type)")
            recordChallengeResult(challenge: challenge, passed: false, confidence: 0, imageData: nil)
            return
        }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)

        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            KoraIDV.log("LivenessManager: createCGImage failed for challenge=\(challenge.type)")
            recordChallengeResult(challenge: challenge, passed: false, confidence: 0, imageData: nil)
            return
        }

        let image = UIImage(cgImage: cgImage)

        // Run anti-spoof check on captured frame
        let spoofResult = antiSpoofCheck.analyze(image)
        if !spoofResult.isLikelyReal {
            KoraIDV.log("LivenessManager: anti-spoof rejected frame for challenge=\(challenge.type) (isLikelyReal=false)")
            recordChallengeResult(challenge: challenge, passed: false, confidence: 0, imageData: nil)
            return
        }

        let imageData = image.jpegData(compressionQuality: 0.8)

        recordChallengeResult(
            challenge: challenge,
            passed: true,
            confidence: Double(face.confidence),
            imageData: imageData
        )
    }

    private func recordChallengeResult(
        challenge: LivenessChallenge,
        passed: Bool,
        confidence: Double,
        imageData: Data?
    ) {
        let result = ChallengeResultItem(
            challenge: challenge,
            passed: passed,
            confidence: confidence,
            imageData: imageData
        )
        appendChallengeResult(result)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.livenessManager(self, didCompleteChallenge: challenge, passed: passed, imageData: imageData)
            self.moveToNextChallenge()
        }
    }
}

// MARK: - CameraManagerDelegate

extension LivenessManager: CameraManagerDelegate {

    func cameraManager(_ manager: CameraManager, didCapturePhoto imageData: Data) {
        // Not used for liveness - we capture from video frames
    }

    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer) {
        processFrame(sampleBuffer)
    }

    func cameraManager(_ manager: CameraManager, didFail error: KoraError) {
        delegate?.livenessManager(self, didFail: error)
    }
}
