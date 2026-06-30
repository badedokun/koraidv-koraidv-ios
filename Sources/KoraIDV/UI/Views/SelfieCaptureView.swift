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
    /// Phase 1 eyeglasses policy — coach the user to remove glasses for a
    /// more reliable face match. Defaults to true.
    var showEyewearGuidance: Bool = true

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
        // **Oval-WINDOW capture (BanffPay v1.9.6 iOS alignment fix, 2026-06-29).**
        // The camera preview is clipped to a large, centred oval — exactly like
        // Android — so the user's face naturally fills the oval no matter how
        // close they hold the phone. The previous design (full-screen preview +
        // a small oval OUTLINE) let a close/large face overflow the outline
        // ("can't fit my face in the circle"), which no amount of
        // detection-acceptance tuning could fix because it was the wrong layer.
        let ovalW: CGFloat = 270
        let ovalH: CGFloat = 340
        return ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar (step 4/5, dark)
                StepProgressBar(total: 5, current: 4, isDark: true)

                DarkScreenHeader(
                    title: L10n.tr("koraidv.selfie.title"),
                    onClose: onCancel
                )

                Spacer().frame(height: 12)

                // Title
                Text(L10n.tr("koraidv.selfie.face_camera"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .accessibilityAddTraits(.isHeader)

                Text(L10n.tr("koraidv.selfie.neutral"))
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, 4)

                // Eyeglasses coaching (Phase 1 of the eyeglasses policy). The
                // issued ID portrait is glasses-free by government standard, so a
                // glasses-free selfie maximizes match reliability. Soft prompt,
                // not a hard gate.
                if showEyewearGuidance {
                    HStack(spacing: 6) {
                        Image(systemName: "eyeglasses")
                            .font(.system(size: 14))
                        Text(L10n.tr("koraidv.selfie.remove_glasses"))
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(KoraColors.Teal)
                    .padding(.top, 6)
                    .accessibilityElement(children: .combine)
                }

                // Visual guidance illustration (REQ-003 / BanffPay v1.9.6 ②B —
                // BanffPay explicitly asked for the visual guidance to stay).
                if showVisualGuides {
                    VisualGuide(kind: .selfie)
                        .padding(.horizontal, 56)
                        .padding(.top, 10)
                }

                Spacer(minLength: 12)

                // Oval window: camera clipped to the oval; the border is the
                // calm detector signal (grey → dashed teal → solid teal).
                ZStack {
                    CameraPreviewView(cameraManager: viewModel.selfieCapture.cameraManager)
                        .frame(width: ovalW, height: ovalH)
                        .clipShape(Ellipse())
                        .accessibilityLabel("Front camera for selfie")
                        .accessibilityAddTraits(.isImage)
                    Ellipse()
                        .stroke(
                            viewModel.isReady ? KoraColors.Teal : Color.white.opacity(0.5),
                            style: StrokeStyle(
                                lineWidth: viewModel.isReady ? 5 : 3,
                                dash: (viewModel.isFaceDetected && !viewModel.isReady) ? [10, 8] : []
                            )
                        )
                        .frame(width: ovalW, height: ovalH)
                        .animation(.easeInOut(duration: 0.25), value: viewModel.isReady)
                        .animation(.easeInOut(duration: 0.25), value: viewModel.isFaceDetected)
                }

                Spacer(minLength: 16)

                // Guidance pill — surfaces the specific positioning/lighting
                // coaching the detector produces ("Center your face in the oval",
                // "Move closer"/"Move back", "Strong light behind you"), falling
                // back to the ready/scanning state. (BanffPay v1.9.6 item 2B —
                // explicit, real-time guidance.)
                GuidancePill(
                    text: viewModel.feedbackMessage
                        ?? (viewModel.isFaceDetected
                            ? L10n.tr("koraidv.selfie.hold_still")
                            : L10n.tr("koraidv.selfie.detecting")),
                    variant: (viewModel.feedbackMessage == nil && viewModel.isFaceDetected) ? .ready : .scanning
                )

                // Explicit positioning + encouragement help line (BanffPay
                // v1.9.6 ②B). Always visible under the pill so the user is
                // never left without instructions — it tells them WHAT to do
                // (fill the oval, hold still) and that capture is automatic.
                Text(viewModel.isReady
                     ? L10n.tr("koraidv.selfie.help.ready")
                     : L10n.tr("koraidv.selfie.help.position"))
                    .font(.system(size: 14))
                    .foregroundColor(viewModel.isReady
                                     ? KoraColors.Teal
                                     : .white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.top, 10)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.isReady)

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

            // Eye-visibility rejection (sunglasses / tinted / mirrored lenses).
            // A prominent, persistent reason — NOT the transient guidance pill —
            // that pauses auto-capture until the user removes the glasses and
            // taps Retake, so the rejection is unambiguous and never loops.
            if let reason = viewModel.rejectionReason {
                Color.black.opacity(0.88).ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundColor(KoraColors.Teal)
                    Text(L10n.tr("koraidv.selfie.eyes_blocked_title"))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Text(reason)
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Button(action: { viewModel.clearRejectionAndRetake() }) {
                        Text(L10n.tr("koraidv.selfie.retake"))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(KoraColors.Teal)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)
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

// MARK: - View Model

class SelfieCaptureViewModel: ObservableObject {
    @Published var isFaceDetected = false
    @Published var feedbackMessage: String?
    @Published var isProcessing = false
    @Published var captureProgress: Float = 0

    /// Set when a capture is rejected for eye visibility (sunglasses / tinted /
    /// mirrored lenses). Drives the prominent rejection overlay and PAUSES
    /// auto-capture (we deliberately do not re-arm) until the user removes the
    /// glasses and taps Retake — so the same reject can't loop-fire.
    @Published var rejectionReason: String?

    /// Dismiss the eye-visibility rejection and re-arm capture.
    func clearRejectionAndRetake() {
        rejectionReason = nil
        feedbackMessage = nil
        selfieCapture.resetForRetake()
    }

    /// True only when a face is present AND there's no outstanding coaching —
    /// i.e. the face is correctly positioned and the SDK is ready to capture.
    /// Drives the green oval so the colour is a trustworthy "you're set" signal.
    var isReady: Bool { isFaceDetected && feedbackMessage == nil }

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
        // **Enforce eye visibility (sunglasses policy, BanffPay 2026-06-30).**
        // Reject sunglasses / tinted / reflective lenses before the selfie is
        // accepted — the SDK does not rely on the user removing them. On reject,
        // surface coaching and re-arm auto-capture instead of going to review.
        if let image = UIImage(data: imageData) {
            let eyes = EyeVisibilityChecker.check(image)
            if eyes.rejects {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.rejectionReason = eyes.message
                    // Do NOT re-arm here — the prominent overlay requires the
                    // user to remove the glasses and tap Retake, so we never
                    // loop-capture the same rejection.
                }
                return
            }
        }
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
