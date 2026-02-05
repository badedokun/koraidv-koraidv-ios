import SwiftUI
import AVFoundation

/// Liveness check view
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

            // Overlay
            VStack {
                // Header
                headerView

                Spacer()

                // Face guide
                faceGuideView

                Spacer()

                // Challenge instruction
                challengeInstructionView

                // Progress indicator
                progressIndicatorView
            }
        }
        .onAppear {
            viewModel.start(
                onChallengeComplete: onChallengeComplete,
                onAllComplete: onAllComplete
            )
        }
        .onDisappear {
            viewModel.stop()
        }
        .koraTheme(theme)
    }

    private var headerView: some View {
        HStack {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.3))
                    .clipShape(Circle())
            }

            Spacer()

            Text("Liveness Check")
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
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: size, height: size * 1.3)

                // Challenge progress ring
                Ellipse()
                    .trim(from: 0, to: CGFloat(viewModel.challengeProgress))
                    .stroke(theme.successColor, lineWidth: 6)
                    .frame(width: size + 10, height: size * 1.3 + 10)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: viewModel.challengeProgress)

                // Challenge icon
                if let challenge = viewModel.currentChallenge {
                    challengeIcon(for: challenge.type)
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var challengeInstructionView: some View {
        VStack(spacing: 12) {
            if let challenge = viewModel.currentChallenge {
                Text(challenge.instruction)
                    .font(theme.headlineFont)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(12)
            } else {
                Text("Preparing...")
                    .font(theme.bodyFont)
                    .foregroundColor(.white)
            }
        }
        .padding(.bottom, 20)
    }

    private var progressIndicatorView: some View {
        VStack(spacing: 16) {
            // Challenge dots
            HStack(spacing: 8) {
                ForEach(0..<session.challenges.count, id: \.self) { index in
                    Circle()
                        .fill(dotColor(for: index))
                        .frame(width: 12, height: 12)
                }
            }

            Text("Challenge \(viewModel.completedChallenges + 1) of \(session.challenges.count)")
                .font(theme.captionFont)
                .foregroundColor(.white.opacity(0.8))
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

    private func dotColor(for index: Int) -> Color {
        if index < viewModel.completedChallenges {
            return theme.successColor
        } else if index == viewModel.completedChallenges {
            return theme.primaryColor
        } else {
            return Color.white.opacity(0.3)
        }
    }

    @ViewBuilder
    private func challengeIcon(for type: ChallengeType) -> some View {
        switch type {
        case .blink:
            Image(systemName: "eye")
        case .smile:
            Image(systemName: "face.smiling")
        case .turnLeft:
            Image(systemName: "arrow.left")
        case .turnRight:
            Image(systemName: "arrow.right")
        case .nodUp:
            Image(systemName: "arrow.up")
        case .nodDown:
            Image(systemName: "arrow.down")
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
                print("Liveness start failed: \(error)")
            }
        }
    }

    func stop() {
        livenessManager.stop()
    }
}

extension LivenessViewModel: LivenessManagerDelegate {
    func livenessManager(_ manager: LivenessManager, didStartChallenge challenge: LivenessChallenge) {
        DispatchQueue.main.async {
            self.currentChallenge = challenge
            self.challengeProgress = 0
        }
    }

    func livenessManager(_ manager: LivenessManager, didUpdateProgress progress: Float, for challenge: LivenessChallenge) {
        DispatchQueue.main.async {
            self.challengeProgress = progress
        }
    }

    func livenessManager(_ manager: LivenessManager, didCompleteChallenge challenge: LivenessChallenge, passed: Bool) {
        DispatchQueue.main.async {
            self.completedChallenges += 1
        }

        // In a real implementation, we'd pass the image data from the challenge
        // For now, passing empty data as placeholder
        onChallengeComplete?(challenge, Data())
    }

    func livenessManager(_ manager: LivenessManager, didComplete result: LivenessResult) {
        DispatchQueue.main.async {
            self.onAllComplete?()
        }
    }

    func livenessManager(_ manager: LivenessManager, didFail error: KoraError) {
        print("Liveness failed: \(error)")
    }
}
