import SwiftUI
import AVFoundation

/// Liveness check view - matches mockup screen 9
struct LivenessView: View {
    let session: LivenessSession
    let theme: KoraTheme
    let onChallengeComplete: (LivenessChallenge, Data) -> Void
    let onAllComplete: () -> Void
    let onCancel: () -> Void
    /// REQ-003 · render the per-challenge VisualGuide illustration above
    /// the oval. Defaults to false to preserve existing minimal-icon UI.
    let showVisualGuides: Bool

    @StateObject private var viewModel: LivenessViewModel

    init(
        session: LivenessSession,
        theme: KoraTheme,
        onChallengeComplete: @escaping (LivenessChallenge, Data) -> Void,
        onAllComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        showVisualGuides: Bool = false
    ) {
        self.session = session
        self.theme = theme
        self.onChallengeComplete = onChallengeComplete
        self.onAllComplete = onAllComplete
        self.onCancel = onCancel
        self.showVisualGuides = showVisualGuides
        _viewModel = StateObject(wrappedValue: LivenessViewModel(session: session))
    }

    var body: some View {
        ZStack {
            // Camera preview
            LivenessCameraPreviewView(livenessManager: viewModel.livenessManager)
                .ignoresSafeArea()
                .accessibilityLabel("Front camera for liveness check")
                .accessibilityAddTraits(.isImage)

            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar (step 5/5, dark)
                StepProgressBar(total: 5, current: 5, isDark: true)

                DarkScreenHeader(
                    title: L10n.tr("koraidv.liveness.title"),
                    onClose: onCancel
                )

                Spacer().frame(height: 16)

                // Challenge title
                if let challenge = viewModel.currentChallenge {
                    Text(challenge.instruction)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .accessibilityAddTraits(.isHeader)
                    if showVisualGuides {
                        VisualGuide(kind: challengeToGuide(challenge.type))
                            .padding(.horizontal, 32)
                            .padding(.top, 12)
                    }
                } else {
                    Text(L10n.tr("koraidv.liveness.preparing"))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                }

                Spacer().frame(height: 24)

                // Oval viewfinder with progress ring
                ZStack {
                    // Background oval
                    Ellipse()
                        .stroke(Color.white.opacity(0.2), lineWidth: 3)
                        .frame(width: 240, height: 300)

                    // Progress ring
                    Ellipse()
                        .trim(from: 0, to: CGFloat(viewModel.challengeProgress))
                        .stroke(KoraColors.Teal, lineWidth: 5)
                        .frame(width: 248, height: 308)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.1), value: viewModel.challengeProgress)
                        .accessibilityLabel("Challenge progress")
                        .accessibilityValue("\(Int(viewModel.challengeProgress * 100)) percent")

                    // Countdown badge
                    if viewModel.countdown > 0 {
                        CountdownBadge(count: viewModel.countdown)
                            .offset(y: -130)
                            .accessibilityLabel("Starting in \(viewModel.countdown)")
                    }
                }

                Spacer().frame(height: 24)

                // Challenge progress dots
                ChallengeDots(
                    total: session.challenges.count,
                    currentIndex: viewModel.completedChallenges
                )
                .accessibilityLabel("Challenge \(viewModel.completedChallenges + 1) of \(session.challenges.count)")

                Spacer().frame(height: 12)

                // Challenge info text
                Text(L10n.tr("koraidv.liveness.challenge_of", viewModel.completedChallenges + 1, session.challenges.count))
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))

                Spacer()
            }
        }
        .background(KoraColors.DarkBg)
        .onAppear {
            viewModel.start(
                onChallengeComplete: onChallengeComplete,
                onAllComplete: onAllComplete
            )
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}

// MARK: - Liveness Camera Preview

/// SwiftUI bridge to the AVFoundation camera preview for the liveness flow.
///
/// v1.8.6: rewritten to use `CameraPreviewUIView` (see CameraManager.swift).
/// See the `CameraPreviewUIView` docstring + the parallel `CameraPreviewView`
/// in DocumentCaptureView.swift for the full root cause of the dark-preview
/// bug this fix addresses.
struct LivenessCameraPreviewView: UIViewRepresentable {
    let livenessManager: LivenessManager

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.videoPreviewLayer.session = livenessManager.cameraManager.captureSession
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // No-op: UIKit auto-resizes the preview layer.
    }
}

// MARK: - View Model

class LivenessViewModel: ObservableObject {
    @Published var currentChallenge: LivenessChallenge?
    @Published var challengeProgress: Float = 0
    @Published var completedChallenges: Int = 0
    @Published var countdown: Int = 0

    let livenessManager = LivenessManager()
    private let session: LivenessSession
    private var onChallengeComplete: ((LivenessChallenge, Data) -> Void)?
    private var onAllComplete: (() -> Void)?

    init(session: LivenessSession) {
        self.session = session
        self.currentChallenge = session.challenges.first
    }

    func start(
        onChallengeComplete: @escaping (LivenessChallenge, Data) -> Void,
        onAllComplete: @escaping () -> Void
    ) {
        self.onChallengeComplete = onChallengeComplete
        self.onAllComplete = onAllComplete

        livenessManager.delegate = self
        livenessManager.start(session: session) { result in
            if case .failure(let error) = result {
                KoraIDV.log("Liveness start failed: \(error)")
            }
        }
    }

    func stop() {
        livenessManager.stop()
        onChallengeComplete = nil
        onAllComplete = nil
    }
}

extension LivenessViewModel: LivenessManagerDelegate {
    func livenessManager(_ manager: LivenessManager, didStartChallenge challenge: LivenessChallenge) {
        DispatchQueue.main.async {
            self.currentChallenge = challenge
            self.challengeProgress = 0
            self.countdown = 3
            self.startCountdown()
        }
    }

    func livenessManager(_ manager: LivenessManager, didUpdateProgress progress: Float, for challenge: LivenessChallenge) {
        DispatchQueue.main.async {
            self.challengeProgress = progress
        }
    }

    func livenessManager(_ manager: LivenessManager, didCompleteChallenge challenge: LivenessChallenge, passed: Bool, imageData: Data?) {
        // **v1.9.0-rc3 — stop the silent empty-imageBase64 submission.**
        // rc2 (and earlier) used `imageData ?? Data()` here, so when
        // the SDK's capture path produced nil (anti-spoof reject,
        // CMSampleBuffer extraction failure, CGImage create failure,
        // or maxFramesPerChallenge exhaustion) the host received empty
        // bytes, base64-encoded them, and POSTed an empty
        // `imageBase64` to identity-service. The backend's
        // `binding:"required"` rejected in 201µs with a generic 400
        // — the exact symptom Stratum Remit reported on 2026-06-06
        // ("errored out to 400 after about 15 or less seconds").
        //
        // Suppressing the host callback when imageData is nil/empty
        // stops the bad submission at its source. The frame budget
        // (`maxFramesPerChallenge = 300`) will continue to advance;
        // the host's challenge UI is responsible for its own timeout
        // and retry affordance. Better silent in-SDK timeout than
        // visible-but-misleading "HTTP 400" toast.
        //
        // Once a proper retry-in-place path is added (v1.10+ ask:
        // surface `.failure(.captureNotAvailable)` to the host so the
        // UI can offer a specific retry message), this guard can
        // become "convert to failure callback" instead of "suppress."
        guard let imageData = imageData, !imageData.isEmpty else {
            KoraIDV.log("LivenessView: challenge=\(challenge.type) completed with nil/empty imageData — suppressing host callback to avoid empty imageBase64 submission")
            DispatchQueue.main.async {
                self.completedChallenges += 1
            }
            return
        }
        DispatchQueue.main.async {
            self.completedChallenges += 1
            self.onChallengeComplete?(challenge, imageData)
        }
    }

    func livenessManager(_ manager: LivenessManager, didComplete result: LivenessResult) {
        DispatchQueue.main.async {
            self.onAllComplete?()
        }
    }

    func livenessManager(_ manager: LivenessManager, didFail error: KoraError) {
        KoraIDV.log("Liveness failed: \(error)")
    }

    private func startCountdown() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self = self, self.countdown > 0 else { return }
            self.countdown -= 1
            if self.countdown > 0 {
                self.startCountdown()
            }
        }
    }
}
