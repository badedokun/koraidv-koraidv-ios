import SwiftUI
import AVFoundation

/// Selfie capture view - matches mockup screens 7-8
struct SelfieCaptureView: View {
    let theme: KoraTheme
    let onCapture: (Data) -> Void
    let onCancel: () -> Void

    @StateObject private var viewModel = SelfieCaptureViewModel()
    @State private var showReview = false
    @State private var capturedImageData: Data?

    var body: some View {
        ZStack {
            if showReview, let imageData = capturedImageData {
                selfieReviewView(imageData: imageData)
            } else {
                selfieCaptureView
            }
        }
        .onAppear {
            viewModel.startCapture { imageData in
                capturedImageData = imageData
                showReview = true
            }
        }
        .onDisappear {
            viewModel.stopCapture()
        }
    }

    // MARK: - Capture View

    private var selfieCaptureView: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(cameraManager: viewModel.selfieCapture.cameraManager)
                .ignoresSafeArea()

            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar (step 4/5, dark)
                StepProgressBar(total: 5, current: 4, isDark: true)

                DarkScreenHeader(
                    title: "Selfie",
                    onClose: onCancel
                )

                Spacer().frame(height: 16)

                // Title
                Text("Face the camera")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                Text("Keep a neutral expression")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, 4)

                Spacer().frame(height: 24)

                // Oval viewfinder with rotating ring
                ZStack {
                    // Rotating ring animation
                    if viewModel.isFaceDetected {
                        RotatingRingView()
                            .frame(width: 250, height: 310)
                    }

                    // Oval guide
                    Ellipse()
                        .stroke(
                            viewModel.isFaceDetected ? KoraColors.Teal : Color.white.opacity(0.3),
                            lineWidth: 3
                        )
                        .frame(width: 240, height: 300)

                    // Progress ring
                    if viewModel.isFaceDetected {
                        Ellipse()
                            .trim(from: 0, to: CGFloat(viewModel.captureProgress))
                            .stroke(KoraColors.Teal, lineWidth: 4)
                            .frame(width: 248, height: 308)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.1), value: viewModel.captureProgress)
                    }
                }

                Spacer().frame(height: 24)

                // Guidance pill
                GuidancePill(
                    text: viewModel.isFaceDetected ? "Hold still..." : "Detecting face...",
                    variant: viewModel.isFaceDetected ? .ready : .scanning
                )

                Spacer()
            }

            // Processing overlay
            if viewModel.isProcessing {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .accentColor(.white)
                    Text("Processing...")
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                }
            }
        }
        .background(KoraColors.DarkBg)
    }

    // MARK: - Review View

    private func selfieReviewView(imageData: Data) -> some View {
        VStack(spacing: 0) {
            StepProgressBar(total: 5, current: 4, isDark: true)

            DarkScreenHeader(
                title: "Review",
                onClose: onCancel
            )

            Spacer().frame(height: 16)

            Text("Does this look like you?")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)

            Text("Check clarity and lighting")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.5))
                .padding(.top, 4)

            Spacer().frame(height: 24)

            // Oval with captured image
            ZStack {
                if let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 240, height: 300)
                        .clipShape(Ellipse())
                }

                Ellipse()
                    .stroke(KoraColors.Teal, lineWidth: 3)
                    .frame(width: 240, height: 300)
            }

            Spacer().frame(height: 12)

            ReviewBadge(text: "Face detected")

            Spacer().frame(height: 16)

            // Quality checks
            HStack(spacing: 20) {
                ReviewQualityCheck(label: "Clear")
                ReviewQualityCheck(label: "Centered")
                ReviewQualityCheck(label: "Well-lit")
            }

            Spacer()

            // Buttons
            HStack(spacing: 12) {
                KoraButton(
                    text: "Retake",
                    action: {
                        showReview = false
                        capturedImageData = nil
                    },
                    variant: .darkOutline
                )
                .frame(maxWidth: .infinity)

                KoraButton(
                    text: "Use this",
                    action: { onCapture(imageData) }
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(KoraColors.DarkBg)
    }
}

// MARK: - Rotating Ring

private struct RotatingRingView: View {
    @State private var rotation: Double = 0

    var body: some View {
        Ellipse()
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [
                        KoraColors.Teal.opacity(0),
                        KoraColors.Teal.opacity(0.5),
                        KoraColors.Teal.opacity(0)
                    ]),
                    center: .center
                ),
                lineWidth: 4
            )
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - View Model

class SelfieCaptureViewModel: ObservableObject {
    @Published var isFaceDetected = false
    @Published var feedbackMessage: String?
    @Published var isProcessing = false
    @Published var captureProgress: Float = 0

    let selfieCapture = SelfieCapture()
    private var onCapture: ((Data) -> Void)?

    func startCapture(onCapture: @escaping (Data) -> Void) {
        self.onCapture = onCapture

        selfieCapture.delegate = self
        selfieCapture.requestPermission { [weak self] granted in
            guard granted else {
                self?.feedbackMessage = "Camera access required"
                return
            }

            self?.selfieCapture.start { result in
                if case .failure(let error) = result {
                    self?.feedbackMessage = error.localizedDescription
                }
            }
        }
    }

    func stopCapture() {
        selfieCapture.stop()
    }

    func captureManually() {
        isProcessing = true
        selfieCapture.capture()
    }
}

extension SelfieCaptureViewModel: SelfieCaptureDelegate {
    func selfieCapture(_ capture: SelfieCapture, didDetectFace result: FaceDetectionResult) {
        isFaceDetected = !result.faces.isEmpty
    }

    func selfieCapture(_ capture: SelfieCapture, didCapture imageData: Data) {
        DispatchQueue.main.async {
            self.isProcessing = false
            self.onCapture?(imageData)
        }
    }

    func selfieCapture(_ capture: SelfieCapture, didUpdateValidation issues: [String]) {
        DispatchQueue.main.async {
            if issues.isEmpty {
                self.feedbackMessage = nil
                self.captureProgress = min(self.captureProgress + 0.1, 1.0)
            } else {
                self.feedbackMessage = issues.first
                self.captureProgress = 0
            }
        }
    }

    func selfieCapture(_ capture: SelfieCapture, didFail error: KoraError) {
        DispatchQueue.main.async {
            self.isProcessing = false
            self.feedbackMessage = error.localizedDescription
        }
    }
}
