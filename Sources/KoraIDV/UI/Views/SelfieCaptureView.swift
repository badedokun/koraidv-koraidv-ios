import SwiftUI
import AVFoundation

/// Selfie capture view - matches mockup screens 7-8
struct SelfieCaptureView: View {
    let theme: KoraTheme
    let onCapture: (Data) -> Void
    let onCancel: () -> Void
    /// REQ-003 · render the rich VisualGuide illustration above the oval
    /// when set. Defaults to false to preserve existing minimal-icon UI
    /// for callers that don't opt in.
    var showVisualGuides: Bool = false

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
                .accessibilityLabel("Front camera for selfie")
                .accessibilityAddTraits(.isImage)

            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar (step 4/5, dark)
                StepProgressBar(total: 5, current: 4, isDark: true)

                DarkScreenHeader(
                    title: L10n.tr("koraidv.selfie.title"),
                    onClose: onCancel
                )

                Spacer().frame(height: 16)

                // Title
                Text(L10n.tr("koraidv.selfie.face_camera"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .accessibilityAddTraits(.isHeader)

                Text(L10n.tr("koraidv.selfie.neutral"))
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, 4)

                if showVisualGuides {
                    VisualGuide(kind: .selfie)
                        .padding(.horizontal, 32)
                        .padding(.top, 12)
                }

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
                            .accessibilityLabel("Capture progress")
                            .accessibilityValue("\(Int(viewModel.captureProgress * 100)) percent")
                    }
                }

                Spacer().frame(height: 24)

                // Guidance pill
                GuidancePill(
                    text: viewModel.isFaceDetected ? L10n.tr("koraidv.selfie.hold_still") : L10n.tr("koraidv.selfie.detecting"),
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
                    Text(L10n.tr("koraidv.selfie.processing"))
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
                title: L10n.tr("koraidv.selfie.review"),
                onClose: onCancel
            )

            Spacer().frame(height: 16)

            Text(L10n.tr("koraidv.selfie.review.title"))
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .accessibilityAddTraits(.isHeader)

            Text(L10n.tr("koraidv.selfie.review.subtitle"))
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
                        .accessibilityLabel("Captured selfie photo")
                }

                Ellipse()
                    .stroke(KoraColors.Teal, lineWidth: 3)
                    .frame(width: 240, height: 300)
            }

            Spacer().frame(height: 12)

            ReviewBadge(text: L10n.tr("koraidv.selfie.review.detected"))

            Spacer().frame(height: 16)

            // Quality checks
            HStack(spacing: 20) {
                ReviewQualityCheck(label: L10n.tr("koraidv.selfie.review.clear"))
                ReviewQualityCheck(label: L10n.tr("koraidv.selfie.review.centered"))
                ReviewQualityCheck(label: L10n.tr("koraidv.selfie.review.well_lit"))
            }
            .accessibilityElement(children: .combine)

            Spacer()

            // Buttons
            HStack(spacing: 12) {
                KoraButton(
                    text: L10n.tr("koraidv.selfie.retake"),
                    action: {
                        showReview = false
                        capturedImageData = nil
                        // Re-arm the capture engine so auto-capture can fire
                        // again — without this, the isCapturing gate held
                        // through the first capture stays latched and the
                        // camera never re-triggers (see SelfieCapture.swift
                        // resetForRetake docstring).
                        viewModel.selfieCapture.resetForRetake()
                    },
                    variant: .darkOutline
                )
                .frame(maxWidth: .infinity)
                .accessibilityHint("Double tap to retake the selfie")

                KoraButton(
                    text: L10n.tr("koraidv.selfie.use_this"),
                    action: { onCapture(imageData) }
                )
                .frame(maxWidth: .infinity)
                .accessibilityHint("Double tap to use this selfie")
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
