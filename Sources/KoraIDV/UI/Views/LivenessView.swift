import SwiftUI
import AVFoundation

/// Liveness check view - matches mockup screen 9
struct LivenessView: View {
    let session: LivenessSession
    let theme: KoraTheme
    let onChallengeComplete: (LivenessChallenge, Data) -> Void
    let onAllComplete: () -> Void
    let onCancel: () -> Void

    @StateObject private var viewModel: LivenessViewModel

    init(
        session: LivenessSession,
        theme: KoraTheme,
        onChallengeComplete: @escaping (LivenessChallenge, Data) -> Void,
        onAllComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.session = session
        self.theme = theme
        self.onChallengeComplete = onChallengeComplete
        self.onAllComplete = onAllComplete
        self.onCancel = onCancel
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

struct LivenessCameraPreviewView: UIViewRepresentable {
    let livenessManager: LivenessManager

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = livenessManager.createPreviewLayer(for: view)
        view.layer.addSublayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.bounds
        }
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
        DispatchQueue.main.async {
            self.completedChallenges += 1
            self.onChallengeComplete?(challenge, imageData ?? Data())
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
