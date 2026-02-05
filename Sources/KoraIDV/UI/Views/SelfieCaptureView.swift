import SwiftUI
import AVFoundation

/// Selfie capture view
struct SelfieCaptureView: View {
    let theme: KoraTheme
    let onCapture: (Data) -> Void
    let onCancel: () -> Void

    @StateObject private var viewModel = SelfieCaptureViewModel()

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(cameraManager: viewModel.selfieCapture.cameraManager)
                .ignoresSafeArea()

            // Overlay
            VStack {
                // Header
                headerView

                Spacer()

                // Face guide
                faceGuideView

                Spacer()

                // Instructions
                instructionsView

                // Capture button
                captureButtonView
            }

            // Processing overlay
            if viewModel.isProcessing {
                processingOverlay
            }
        }
        .onAppear {
            viewModel.startCapture(onCapture: onCapture)
        }
        .onDisappear {
            viewModel.stopCapture()
        }
        .koraTheme(theme)
    }

    private var headerView: some View {
        HStack {
            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.3))
                    .clipShape(Circle())
            }

            Spacer()

            Text("Take a Selfie")
                .font(theme.headlineFont)
                .foregroundColor(.white)

            Spacer()

            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.black.opacity(0.6), Color.clear]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var faceGuideView: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height) * 0.7

            ZStack {
                // Darkened background with oval cutout
                Color.black.opacity(0.5)
                    .mask(
                        Rectangle()
                            .overlay(
                                Ellipse()
                                    .frame(width: size, height: size * 1.3)
                                    .blendMode(.destinationOut)
                            )
                    )

                // Oval guide
                Ellipse()
                    .stroke(
                        viewModel.isFaceDetected ? theme.successColor : Color.white,
                        lineWidth: 4
                    )
                    .frame(width: size, height: size * 1.3)

                // Progress indicator
                if viewModel.isFaceDetected {
                    Ellipse()
                        .trim(from: 0, to: CGFloat(viewModel.captureProgress))
                        .stroke(theme.successColor, lineWidth: 4)
                        .frame(width: size + 10, height: size * 1.3 + 10)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.1), value: viewModel.captureProgress)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var instructionsView: some View {
        VStack(spacing: 8) {
            if let feedback = viewModel.feedbackMessage {
                Text(feedback)
                    .font(theme.bodyFont)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
            } else if viewModel.isFaceDetected {
                Text("Great! Hold still...")
                    .font(theme.bodyFont)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(theme.successColor.opacity(0.8))
                    .cornerRadius(8)
            } else {
                Text("Position your face in the oval")
                    .font(theme.bodyFont)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
            }
        }
        .padding(.bottom, 20)
    }

    private var captureButtonView: some View {
        Button {
            viewModel.captureManually()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 72, height: 72)

                Circle()
                    .fill(Color.white)
                    .frame(width: 60, height: 60)
            }
        }
        .padding(.bottom, 40)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.6)]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))

                Text("Processing...")
                    .font(theme.bodyFont)
                    .foregroundColor(.white)
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

    private var cameraManager: CameraManager {
        // Access the internal camera manager through a computed property
        // In production, this would need proper encapsulation
        return CameraManager()
    }

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

