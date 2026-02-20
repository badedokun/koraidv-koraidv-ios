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
}

/// Liveness Manager for challenge-response verification
final class LivenessManager: NSObject {

    // MARK: - Properties

    weak var delegate: LivenessManagerDelegate?

    private let cameraManager = CameraManager()
    private let faceDetector = FaceDetector()
    private let challengeDetector = ChallengeDetector()
    private let ciContext = CIContext()

    /// Serial queue to protect mutable state from data races
    private let stateQueue = DispatchQueue(label: "com.koraidv.liveness.state")

    private var session: LivenessSession?
    private var _currentChallengeIndex = 0
    private var _challengeResults: [ChallengeResultItem] = []
    private var _isProcessing = false

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

    /// Thread-safe append to challengeResults
    private func appendChallengeResult(_ result: ChallengeResultItem) {
        stateQueue.sync { _challengeResults.append(result) }
    }

    /// Thread-safe read of challengeResults
    private var challengeResults: [ChallengeResultItem] {
        stateQueue.sync { _challengeResults }
    }

    /// Current challenge being processed
    var currentChallenge: LivenessChallenge? {
        guard let session = session else { return nil }
        let index = currentChallengeIndex
        guard index < session.challenges.count else { return nil }
        return session.challenges[index]
    }

    // MARK: - Public Methods

    /// Start liveness session
    func start(session: LivenessSession, completion: @escaping (Result<Void, KoraError>) -> Void) {
        self.session = session
        stateQueue.sync {
            _currentChallengeIndex = 0
            _challengeResults = []
            _isProcessing = false
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
        session = nil
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
        challengeDetector.startDetecting(challengeType: challenge.type)

        delegate?.livenessManager(self, didStartChallenge: challenge)
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
        isProcessing = true

        faceDetector.detectFaces(in: sampleBuffer) { [weak self] result in
            guard let self = self else { return }

            defer { self.isProcessing = false }

            guard let faceResult = result, let face = faceResult.faces.first else {
                return
            }

            // Process challenge detection
            let detectionResult = self.challengeDetector.process(
                face: face,
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
        // Convert sample buffer to image data
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            recordChallengeResult(challenge: challenge, passed: false, confidence: 0, imageData: nil)
            return
        }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)

        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            recordChallengeResult(challenge: challenge, passed: false, confidence: 0, imageData: nil)
            return
        }

        let image = UIImage(cgImage: cgImage)
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
