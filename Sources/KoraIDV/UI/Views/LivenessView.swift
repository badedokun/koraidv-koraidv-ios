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
                //
                // **v1.9.0-rc6** — oval color now reflects face-detected
                // state from LivenessManager:
                //   - grey  (`Color.white.opacity(0.2)`): no face detected
                //   - green (`Color.green`)              : face in confident range
                // Without this signal users had no way to know the SDK
                // was seeing them, and the countdown fired to an empty
                // viewport (Stratum Remit 2026-06-06 report: "grey oval
                // never turns green").
                ZStack {
                    // Background oval — color reflects face state
                    Ellipse()
                        .stroke(viewModel.isFaceDetected ? Color.green : Color.white.opacity(0.2), lineWidth: 3)
                        .frame(width: 240, height: 300)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.isFaceDetected)

                    // Progress ring
                    Ellipse()
                        .trim(from: 0, to: CGFloat(viewModel.challengeProgress))
                        .stroke(KoraColors.Teal, lineWidth: 5)
                        .frame(width: 248, height: 308)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.1), value: viewModel.challengeProgress)
                        .accessibilityLabel("Challenge progress")
                        .accessibilityValue("\(Int(viewModel.challengeProgress * 100)) percent")

                    // Countdown badge (only fires once face is detected)
                    if viewModel.countdown > 0 {
                        CountdownBadge(count: viewModel.countdown)
                            .offset(y: -130)
                            .accessibilityLabel("Starting in \(viewModel.countdown)")
                    }

                    // **v1.9.0-rc6.7** — challenge-complete checkmark
                    // overlay. Renders briefly (~0.6s) when a challenge
                    // completes with valid imageData, paired with a
                    // medium haptic in the view model. Lets the user
                    // know the gesture registered before the next
                    // challenge prompt arrives, eliminating the
                    // "looking up when next countdown is at 1"
                    // confusion Stratum reported 2026-06-07.
                    if viewModel.showChallengeCompleteCheck {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.85))
                                .frame(width: 100, height: 100)
                            Image(systemName: "checkmark")
                                .font(.system(size: 50, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Challenge completed")
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: viewModel.showChallengeCompleteCheck)

                Spacer().frame(height: 20)

                // Dynamic guidance — explicit positioning + encouragement
                // (BanffPay v1.9.6 item 2B). Amber = "get your face in the
                // circle", teal = "you're set, go".
                Text(viewModel.guidanceText)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(viewModel.guidanceIsReady ? KoraColors.Teal : Color(red: 1.0, green: 0.82, blue: 0.35))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .frame(minHeight: 24)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.guidanceText)
                    .accessibilityLabel(viewModel.guidanceText)

                Spacer().frame(height: 16)

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

    /// **v1.9.0-rc6** — published face-detected state from LivenessManager.
    /// Drives the oval color (grey when false, green when true) and
    /// gates the countdown (paused while false). Updated via the new
    /// `livenessManager(_:didChangeFaceDetected:)` delegate callback.
    @Published var isFaceDetected: Bool = false

    let livenessManager = LivenessManager()
    private let session: LivenessSession
    private var onChallengeComplete: ((LivenessChallenge, Data) -> Void)?
    private var onAllComplete: (() -> Void)?

    /// **v1.9.0-rc6** — tracks whether the countdown for the current
    /// challenge has been started. Once a challenge begins (via
    /// `didStartChallenge`), the countdown waits for face-detected to
    /// flip true before starting; this flag prevents re-arming if face
    /// briefly drops and reappears.
    private var countdownStartedForCurrentChallenge = false

    /// **v1.9.0-rc6.7** — shows the green-checkmark overlay briefly
    /// (~0.6s) between challenges. Set true in
    /// `didCompleteChallenge` with valid imageData; auto-cleared by
    /// the timer in the same callback. The LivenessView body binds
    /// to this and renders an overlay above the oval when true.
    @Published var showChallengeCompleteCheck: Bool = false

    /// **Dynamic guidance (BanffPay v1.9.6, item 2B — clearer in-app guidance).**
    /// One state-aware line shown below the oval so the user always knows what
    /// to do RIGHT NOW: an explicit positioning prompt when their face isn't in
    /// the circle, "hold still" during the countdown, the action cue while the
    /// challenge is active, and an encouraging word the instant it registers.
    var guidanceText: String {
        if showChallengeCompleteCheck { return "Nice! 👍" }
        if !isFaceDetected { return "Move your face into the circle" }
        if countdown > 0 { return "Perfect — hold still" }
        if let type = currentChallenge?.type { return Self.actionCue(for: type) }
        return "Hold still"
    }

    /// Teal (ready) vs amber (needs positioning) tint for `guidanceText`.
    var guidanceIsReady: Bool {
        isFaceDetected || showChallengeCompleteCheck
    }

    private static func actionCue(for type: ChallengeType) -> String {
        switch type {
        case .blink: return "Now blink a few times"
        case .smile: return "Now give a big smile 😊"
        case .turnLeft: return "Now slowly turn your head left"
        case .turnRight: return "Now slowly turn your head right"
        case .nodUp: return "Now gently look up"
        case .nodDown: return "Now gently look down"
        }
    }

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
            // **v1.9.0-rc6** — show 3 in the UI but DON'T tick down
            // yet. The countdown waits for the user's face to be in
            // confident range before it starts. Before rc6 the
            // countdown fired immediately on challenge start regardless
            // of face state, so it raced down 3→2→1→0 to an empty
            // viewport while the user was still re-acquiring the
            // camera.
            self.countdown = 3
            self.countdownStartedForCurrentChallenge = false

            // **v1.9.0-rc6.1 — fix "stuck on challenge 2".** rc6 reset
            // `self.isFaceDetected = false` here, which masked the
            // current face state. The LivenessManager's
            // `didChangeFaceDetected` callback only fires on state
            // *transitions*, so if the face was already detected from
            // the previous challenge (almost always the case — user
            // doesn't drop out of frame between challenges), the
            // manager has no transition to report. The view sat
            // waiting for a face-detected callback that would never
            // come; countdown never started; user stuck. Don't reset
            // — the view's `isFaceDetected` reflects current camera
            // state and shouldn't lie about it just because the
            // challenge prompt changed. If face IS already detected,
            // start the countdown immediately (the same code path
            // that `didChangeFaceDetected` would have taken).
            if self.isFaceDetected && self.countdown > 0 {
                self.countdownStartedForCurrentChallenge = true
                self.startCountdown()
            }
        }
    }

    /// **v1.9.0-rc6** — face-detected state changed. Update the oval
    /// color and, if this is the first time face is detected for the
    /// current challenge, start the countdown.
    func livenessManager(_ manager: LivenessManager, didChangeFaceDetected detected: Bool) {
        DispatchQueue.main.async {
            self.isFaceDetected = detected
            if detected
                && !self.countdownStartedForCurrentChallenge
                && self.currentChallenge != nil
                && self.countdown > 0
            {
                self.countdownStartedForCurrentChallenge = true
                self.startCountdown()
            }
        }
    }

    /// **v1.9.0-rc6** — challenge activated by the SDK; user can now
    /// perform the gesture. No UI change needed beyond what
    /// `didChangeFaceDetected` already showed; the activation signal
    /// exists so the SDK side can switch on gesture scoring (no
    /// auto-completion on micro-movements during countdown).
    func livenessManager(_ manager: LivenessManager, didActivateChallenge challenge: LivenessChallenge) {
        KoraIDV.log("LivenessView: challenge=\(challenge.type) activated — gesture scoring on")
    }

    func livenessManager(_ manager: LivenessManager, didUpdateProgress progress: Float, for challenge: LivenessChallenge) {
        DispatchQueue.main.async {
            self.challengeProgress = progress
        }
    }

    func livenessManager(_ manager: LivenessManager, didCompleteChallenge challenge: LivenessChallenge, passed: Bool, imageData: Data?) {
        // **v1.9.0-rc6.7** — haptic + visual signal so the user knows a
        // challenge completed before the next prompt appears. Stratum
        // Remit 2026-06-07: "in some case you are asked to look up and
        // by the time you turn your head back the next challenge has
        // begun and the count down is at 1." Haptic fires regardless
        // of pass/fail (the user did SOMETHING — they should know it
        // registered). Visual checkmark is set on the view model and
        // auto-dismissed after 0.6s by the SwiftUI animation in the
        // body. Only fires when there's real imageData so the
        // nil-suppression path (rc3 guard) doesn't trigger spurious
        // feedback for invisible-to-user events.
        if let imageData = imageData, !imageData.isEmpty {
            DispatchQueue.main.async {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                self.showChallengeCompleteCheck = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.showChallengeCompleteCheck = false
                }
            }
        }
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
            } else {
                // **v1.9.0-rc6** — countdown finished. Signal the SDK
                // that gesture scoring can begin. ChallengeDetector
                // frames before this call were ignored, preventing
                // auto-completion from micro-movements during the
                // 3-second countdown.
                self.livenessManager.activateChallenge()
            }
        }
    }
}
