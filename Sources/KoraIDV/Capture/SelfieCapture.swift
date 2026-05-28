import UIKit
import AVFoundation

/// Selfie capture delegate
protocol SelfieCaptureDelegate: AnyObject {
    func selfieCapture(_ capture: SelfieCapture, didDetectFace result: FaceDetectionResult)
    func selfieCapture(_ capture: SelfieCapture, didCapture imageData: Data)
    func selfieCapture(_ capture: SelfieCapture, didUpdateValidation issues: [String])
    func selfieCapture(_ capture: SelfieCapture, didFail error: KoraError)
}

/// Selfie capture manager
final class SelfieCapture: NSObject {

    // MARK: - Properties

    weak var delegate: SelfieCaptureDelegate?

    /// Camera manager - exposed for preview layer access
    let cameraManager = CameraManager()
    private let faceDetector = FaceDetector()
    private let qualityValidator = QualityValidator()
    private let antiSpoofCheck = AntiSpoofCheck()

    private var isCapturing = false
    private var isAutoCaptureEnabled = true
    private var autoCaptureCounter = 0
    private let autoCaptureThreshold = 10 // Number of valid frames before auto-capture

    /// Minimum face size as percentage of frame
    var minimumFaceSizePercentage: CGFloat = 0.2

    /// Maximum face size as percentage of frame
    var maximumFaceSizePercentage: CGFloat = 0.6

    /// Auto-capture enabled
    var autoCaptureEnabled: Bool {
        get { isAutoCaptureEnabled }
        set { isAutoCaptureEnabled = newValue }
    }

    // MARK: - Initialization

    override init() {
        super.init()
        cameraManager.delegate = self
    }

    // MARK: - Public Methods

    /// Request camera permission
    func requestPermission(completion: @escaping (Bool) -> Void) {
        cameraManager.requestPermission(completion: completion)
    }

    /// Start selfie capture
    func start(completion: @escaping (Result<Void, KoraError>) -> Void) {
        cameraManager.configure(position: .front) { [weak self] result in
            guard let self = self else {
                completion(.failure(.unknown("Selfie capture was released")))
                return
            }
            switch result {
            case .success:
                self.cameraManager.start()
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Stop selfie capture
    func stop() {
        cameraManager.stop()
        autoCaptureCounter = 0
    }

    /// Capture selfie manually
    func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        cameraManager.capturePhoto()
    }

    /// Get preview layer
    func createPreviewLayer(for view: UIView) -> AVCaptureVideoPreviewLayer {
        return cameraManager.createPreviewLayer(for: view)
    }

    /// Reset auto-capture counter
    func resetAutoCapture() {
        autoCaptureCounter = 0
    }

    /// Re-arm the capture engine for a retake. Releases the isCapturing
    /// gate that was held through validation/anti-spoof/delegate and
    /// resets the auto-capture counter so frame accumulation starts
    /// fresh. Call after the user taps Retake on the review screen.
    func resetForRetake() {
        isCapturing = false
        autoCaptureCounter = 0
    }

    // MARK: - Private Methods

    private func processFrame(_ sampleBuffer: CMSampleBuffer) {
        faceDetector.detectFaces(in: sampleBuffer) { [weak self] result in
            guard let self = self else { return }

            if let result = result {
                DispatchQueue.main.async {
                    self.delegate?.selfieCapture(self, didDetectFace: result)
                    self.handleFaceDetection(result)
                }
            } else {
                DispatchQueue.main.async {
                    self.delegate?.selfieCapture(self, didUpdateValidation: ["No face detected"])
                    self.autoCaptureCounter = 0
                }
            }
        }
    }

    private func handleFaceDetection(_ result: FaceDetectionResult) {
        let validation = faceDetector.validateForSelfie(result: result)

        delegate?.selfieCapture(self, didUpdateValidation: validation.issues)

        if validation.isValid && isAutoCaptureEnabled {
            autoCaptureCounter += 1

            if autoCaptureCounter >= autoCaptureThreshold && !isCapturing {
                capture()
            }
        } else {
            autoCaptureCounter = 0
        }
    }
}

// MARK: - CameraManagerDelegate

extension SelfieCapture: CameraManagerDelegate {

    func cameraManager(_ manager: CameraManager, didCapturePhoto imageData: Data) {
        // Keep isCapturing=true through the entire async validation +
        // anti-spoof + compress + delegate.didCapture pipeline. Resetting
        // here would let the sample-buffer path (line ~190) re-enter
        // processFrame → handleFaceDetection → autoCaptureCounter →
        // capture() before the first capture's delegate callback has
        // even fired, causing the multi-shutter "rapid snap" defect
        // BanffPay reported 2026-05-28. Mirrors the gate pattern
        // DocumentCaptureView shipped in v1.6.3 for the same class of
        // bug on the document side. Reset happens via resetForRetake()
        // when the user taps Retake, or via stop() when the flow ends.

        // Validate quality
        guard let image = UIImage(data: imageData) else {
            isCapturing = false
            delegate?.selfieCapture(self, didFail: .captureFailed("Invalid image data"))
            return
        }

        // Get face detection for quality validation
        faceDetector.detectFaces(in: image) { [weak self] result in
            guard let self = self else { return }

            let faceInfo: (confidence: Float, boundingBox: CGRect)?
            if let face = result?.faces.first {
                faceInfo = (face.confidence, face.boundingBox)
            } else {
                faceInfo = nil
            }

            let validation = self.qualityValidator.validateSelfieImage(image, faceDetection: faceInfo)

            if validation.isValid {
                // Run anti-spoof check before accepting
                let spoofResult = self.antiSpoofCheck.analyze(image)
                if !spoofResult.isLikelyReal {
                    DispatchQueue.main.async {
                        self.isCapturing = false
                        self.delegate?.selfieCapture(self, didFail: .qualityValidationFailed(["Image appears to be a photo of a screen or printed image"]))
                        self.resetAutoCapture()
                    }
                    return
                }

                // Compress image. isCapturing remains true — only resetForRetake()
                // or stop() releases the gate so the sample-buffer path can't
                // start a second capture while the ViewModel is on the review
                // screen.
                if let compressedData = image.jpegData(compressionQuality: 0.85) {
                    DispatchQueue.main.async {
                        self.delegate?.selfieCapture(self, didCapture: compressedData)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.delegate?.selfieCapture(self, didCapture: imageData)
                    }
                }
            } else {
                let issues = validation.issues.map { $0.message }
                DispatchQueue.main.async {
                    self.isCapturing = false
                    self.delegate?.selfieCapture(self, didFail: .qualityValidationFailed(issues))
                    self.resetAutoCapture()
                }
            }
        }
    }

    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer) {
        guard !isCapturing else { return }
        processFrame(sampleBuffer)
    }

    func cameraManager(_ manager: CameraManager, didFail error: KoraError) {
        isCapturing = false
        delegate?.selfieCapture(self, didFail: error)
    }
}
