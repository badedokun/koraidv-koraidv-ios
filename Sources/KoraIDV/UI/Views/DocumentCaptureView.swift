import SwiftUI
import UIKit
import AVFoundation

/// Document capture view - matches mockup screens 4-6
struct DocumentCaptureView: View {
    let documentType: DocumentType
    let side: DocumentSide
    let theme: KoraTheme
    let onCapture: (Data) -> Void
    let onCancel: () -> Void
    /// REQ-003 · render VisualGuide.docFront / .docBack overlay alongside
    /// the dashed capture frame. Defaults to false to preserve existing
    /// minimal-icon UI for callers that don't opt in.
    var showVisualGuides: Bool = false

    @StateObject private var viewModel = DocumentCaptureViewModel()
    @State private var showReview = false
    @State private var capturedImageData: Data?

    var body: some View {
        ZStack {
            if showReview, let imageData = capturedImageData {
                documentReviewView(imageData: imageData)
            } else {
                documentCaptureView
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

    private var documentCaptureView: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(cameraManager: viewModel.cameraManager)
                .ignoresSafeArea()
                .accessibilityLabel("Camera viewfinder")
                .accessibilityAddTraits(.isImage)

            // Dark overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar (step 3/5, dark)
                StepProgressBar(total: 5, current: 3, isDark: true)

                // Header
                DarkScreenHeader(
                    title: side == .front ? L10n.tr("koraidv.capture.front") : L10n.tr("koraidv.capture.back"),
                    subtitle: documentType.displayName,
                    onClose: onCancel
                )

                Spacer()

                // Document viewfinder
                documentViewfinder

                Spacer().frame(height: 16)

                // Step pills
                HStack(spacing: 8) {
                    StepPill(
                        text: L10n.tr("koraidv.capture.step.front"),
                        state: side == .front ? .active : .done
                    )
                    if documentType.requiresBack {
                        StepPill(
                            text: L10n.tr("koraidv.capture.step.back"),
                            state: side == .back ? .active : .inactive
                        )
                    }
                }

                Spacer().frame(height: 16)

                if showVisualGuides {
                    VisualGuide(kind: side == .front ? .docFront : .docBack)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 12)
                }

                // Guidance pill.
                //
                // v1.8.6-rc5: prefer `viewModel.feedbackMessage` when set so
                // the framing-guidance strings the detector emits ("Move
                // closer to the document" / "Move further from the
                // document") actually surface to the user. Pre-rc5 the badge
                // was binary between hold_steady / scanning L10n keys and
                // never read feedbackMessage at all — the qualityGuidance
                // work shipped in rc2/rc3/rc4 was running in the background
                // but invisible to users, so they had no indication of how
                // close or far to hold the document (Stratum Remit 2026-
                // 06-03 report). Falls back to the L10n binary strings
                // when feedbackMessage is unset (defensive — feedbackMessage
                // is virtually always set post-rc4 but the fallback keeps
                // the localized copy as the baseline).
                //
                // L10n debt: the framing-guidance strings emitted by
                // DocumentScanner.swift are inline-Swift strings, not L10n
                // keys, so they won't translate. Acceptable for a hotfix;
                // proper key extraction is a follow-up.
                GuidancePill(
                    text: viewModel.feedbackMessage
                        ?? (viewModel.isDocumentDetected
                            ? L10n.tr("koraidv.capture.hold_steady")
                            : L10n.tr("koraidv.capture.scanning")),
                    variant: viewModel.isDocumentDetected ? .ready : .scanning
                )

                Spacer().frame(height: 40)
            }

            // Processing overlay
            if viewModel.isProcessing {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .accentColor(.white)
                    Text(L10n.tr("koraidv.capture.processing"))
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                }
            }
        }
        .background(KoraColors.DarkBg)
    }

    private var documentViewfinder: some View {
        GeometryReader { geometry in
            let maxWidth: CGFloat = min(342, geometry.size.width - 48)
            let frameHeight = maxWidth / 1.586

            ZStack {
                // Document frame
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        viewModel.isDocumentDetected ? KoraColors.Teal : Color.white.opacity(0.3),
                        lineWidth: 2
                    )
                    .frame(width: maxWidth, height: frameHeight)

                // Corner brackets
                CornerBrackets(
                    width: maxWidth,
                    height: frameHeight,
                    color: KoraColors.Teal,
                    length: 28,
                    lineWidth: 3
                )

                // Scan line animation
                if !viewModel.isDocumentDetected {
                    ScanLineView()
                        .frame(width: maxWidth - 20, height: frameHeight - 20)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 250)
    }

    // MARK: - Review View

    private func documentReviewView(imageData: Data) -> some View {
        VStack(spacing: 0) {
            StepProgressBar(total: 5, current: 3, isDark: true)

            DarkScreenHeader(
                title: L10n.tr("koraidv.capture.review.title"),
                onClose: onCancel
            )

            Spacer()

            // Review card
            VStack(spacing: 16) {
                if let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 300, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("Captured document photo")
                }

                ReviewBadge(text: L10n.tr("koraidv.capture.review.quality"))

                // Quality checks
                HStack(spacing: 20) {
                    ReviewQualityCheck(label: L10n.tr("koraidv.capture.review.sharp"))
                    ReviewQualityCheck(label: L10n.tr("koraidv.capture.review.well_lit"))
                    ReviewQualityCheck(label: L10n.tr("koraidv.capture.review.no_glare"))
                }
                .accessibilityElement(children: .combine)
            }

            Spacer()

            // Buttons
            HStack(spacing: 12) {
                KoraButton(
                    text: L10n.tr("koraidv.capture.retake"),
                    action: {
                        showReview = false
                        capturedImageData = nil
                        // Re-enable auto-capture: the view-model's
                        // hasPendingReview gate is set on every committed
                        // capture (v1.6.2 fix for the doc-recapture race)
                        // and must be cleared explicitly here, otherwise
                        // Retake would leave the gate closed forever and
                        // the camera would never auto-capture again.
                        viewModel.clearPendingReview()
                    },
                    variant: .darkOutline
                )
                .frame(maxWidth: .infinity)
                .accessibilityHint("Double tap to retake the photo")

                KoraButton(
                    text: L10n.tr("koraidv.capture.looks_good"),
                    action: { onCapture(imageData) }
                )
                .frame(maxWidth: .infinity)
                .accessibilityHint("Double tap to accept this photo")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(KoraColors.DarkBg)
    }
}

// MARK: - Scan Line

private struct ScanLineView: View {
    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            KoraColors.Teal.opacity(0),
                            KoraColors.Teal.opacity(0.4),
                            KoraColors.Teal.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)
                .offset(y: offset)
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                        offset = geo.size.height
                    }
                }
        }
    }
}

// MARK: - Corner Brackets

struct CornerBrackets: View {
    let width: CGFloat
    let height: CGFloat
    let color: Color
    var length: CGFloat = 28
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            CornerShape(position: .topLeft, length: length)
                .stroke(color, lineWidth: lineWidth)
            CornerShape(position: .topRight, length: length)
                .stroke(color, lineWidth: lineWidth)
            CornerShape(position: .bottomLeft, length: length)
                .stroke(color, lineWidth: lineWidth)
            CornerShape(position: .bottomRight, length: length)
                .stroke(color, lineWidth: lineWidth)
        }
        .frame(width: width, height: height)
    }
}

struct CornerShape: Shape {
    enum Position {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    let position: Position
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        switch position {
        case .topLeft:
            path.move(to: CGPoint(x: 0, y: length))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: length, y: 0))
        case .topRight:
            path.move(to: CGPoint(x: rect.width - length, y: 0))
            path.addLine(to: CGPoint(x: rect.width, y: 0))
            path.addLine(to: CGPoint(x: rect.width, y: length))
        case .bottomLeft:
            path.move(to: CGPoint(x: 0, y: rect.height - length))
            path.addLine(to: CGPoint(x: 0, y: rect.height))
            path.addLine(to: CGPoint(x: length, y: rect.height))
        case .bottomRight:
            path.move(to: CGPoint(x: rect.width - length, y: rect.height))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height - length))
        }

        return path
    }
}

// MARK: - Camera Preview View

/// SwiftUI bridge to the AVFoundation camera preview.
///
/// v1.8.6: rewritten to use `CameraPreviewUIView` (see CameraManager.swift),
/// whose root layer IS an `AVCaptureVideoPreviewLayer`. UIKit's layout system
/// resizes the layer automatically as the SwiftUI parent resolves geometry.
///
/// The previous pattern (`UIView(frame: .zero)` + `addSublayer` + manual
/// frame management in `updateUIView`) left the preview layer at zero-size
/// because `updateUIView` doesn't fire on initial bounds resolution — every
/// document/selfie/liveness preview rendered dark to the user. See the
/// `CameraPreviewUIView` docstring for the full root cause.
///
/// Reused by `SelfieCaptureView` — fixing this struct fixes selfie preview
/// automatically (it's the same UIViewRepresentable).
struct CameraPreviewView: UIViewRepresentable {
    let cameraManager: CameraManager

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.videoPreviewLayer.session = cameraManager.captureSession
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // No-op: UIKit auto-resizes the preview layer as the view's bounds
        // change because the layer IS the root layer.
    }
}

// MARK: - View Model

class DocumentCaptureViewModel: ObservableObject {
    @Published var isDocumentDetected = false
    @Published var feedbackMessage: String?
    @Published var isProcessing = false
    @Published var isFlashOn = false

    let cameraManager: CameraManager = {
        let m = CameraManager()
        // v1.9.0-rc5: tell CameraManager to apply the ID-1 centered
        // crop (1.586:1 horizontal card) on top of orientation
        // normalization and aspect crop. Without this the captured
        // photo includes the full portrait viewfinder area and the
        // DL appears as a small card in a sea of background; with
        // it the photo is card-shaped and fills the review viewport.
        m.documentMode = true
        return m
    }()
    private let documentScanner = DocumentScanner()
    private let qualityValidator = QualityValidator()

    private var onCapture: ((Data) -> Void)?
    private var isCapturing = false

    /// Set once a captured frame passes validation and is handed to the
    /// review UI. Blocks subsequent auto-capture firings while the user
    /// is reviewing the committed image. Without this guard the camera
    /// session keeps running through review, the document detector keeps
    /// firing on every stable frame, `captureManually()` re-fires, and
    /// the displayed review image is silently replaced — the BanffPay
    /// "rapid doc snapping" defect (see v1.6.2 release notes 2026-05-27).
    ///
    /// Mirrors the Android double-gate pattern in
    /// `koraidv-android/koraidv/.../ui/compose/CaptureScreens.kt:263`
    /// (`!isCapturing && capturedImageBytes == null`), which is why the
    /// Pixel 9 Pro XL testing did not surface the bug — Android already
    /// had the equivalent guard.
    private var hasPendingReview = false

    /// Timestamp of the first frame in the current detection burst.
    /// Cleared whenever detection drops (result is nil) and on retake.
    /// Used by the v1.8.6 3-second force-capture gate to fire even
    /// when per-frame stability never converges — matches Android's
    /// `firstDetectedTime` deadline pattern in CaptureScreens.kt. Without
    /// this fallback, iPhones with slightly noisier detection output
    /// would loop forever in "Scanning document..." even with the
    /// stability tolerance relaxed (Stratum Remit reproduction
    /// 2026-06-01).
    private var firstDetectedTime: Date?

    /// Force-capture deadline once a document has been continuously
    /// detected for this long with acceptable coverage. Same value
    /// Android uses (3000ms in CaptureScreens.kt).
    private let forceCaptureDeadline: TimeInterval = 3.0

    func startCapture(onCapture: @escaping (Data) -> Void) {
        self.onCapture = onCapture

        cameraManager.delegate = self
        cameraManager.requestPermission { [weak self] granted in
            guard granted else {
                self?.feedbackMessage = "Camera access required"
                return
            }

            self?.cameraManager.configure(position: .back) { result in
                if case .success = result {
                    self?.cameraManager.start()
                }
            }
        }
    }

    func stopCapture() {
        cameraManager.stop()
    }

    /// Re-enable auto-capture after the user dismisses the review
    /// (e.g. taps Retake). Without this the gate stays closed forever
    /// and the SDK can't recapture even on user request.
    func clearPendingReview() {
        hasPendingReview = false
        isProcessing = false
        // Reset the force-capture deadline so retake starts fresh
        // instead of inheriting a stale timestamp from the prior burst.
        firstDetectedTime = nil
        documentScanner.resetStability()
    }

    func captureManually() {
        guard !isCapturing, !hasPendingReview else { return }
        isCapturing = true
        isProcessing = true
        cameraManager.capturePhoto()
    }
}

extension DocumentCaptureViewModel: CameraManagerDelegate {
    func cameraManager(_ manager: CameraManager, didCapturePhoto imageData: Data) {
        // **v1.9.0-rc3 — fix "camera snaps twice" race.** rc2 reset
        // `isCapturing = false` synchronously here, then dispatched
        // validation to main. The detector callback also runs on main
        // and arrives at ~30fps; in the window between this synchronous
        // reset and the main-queue dispatch executing `hasPendingReview
        // = true`, the next frame would see *both gates open* and call
        // `captureManually` a second time — producing the double-shutter
        // and the doubly-clipped review screen Stratum reported on
        // 2026-06-06. Moving the `isCapturing` reset into the same main
        // async block as `hasPendingReview` closes the race: while the
        // main dispatch is queued, `isCapturing` stays true; when it
        // runs, whichever gate is appropriate (review for success,
        // deadline reset for failure) is set BEFORE `isCapturing`
        // drops. Single shutter, every time.
        guard let image = UIImage(data: imageData) else {
            DispatchQueue.main.async {
                self.isProcessing = false
                self.isCapturing = false
                self.firstDetectedTime = nil
                self.feedbackMessage = "Invalid image. Try again."
            }
            return
        }

        let validation = qualityValidator.validateDocumentImage(image)

        DispatchQueue.main.async {
            self.isProcessing = false

            if validation.isValid {
                // Close the auto-capture gate BEFORE firing onCapture.
                // The view will switch to review on the callback; while
                // it does, the camera session is still running and the
                // detector will still see the document as stable. Without
                // this gate, the detector re-fires captureManually and
                // silently replaces the displayed review image. The gate
                // is released on retake via clearPendingReview().
                self.hasPendingReview = true
                self.isCapturing = false
                self.onCapture?(imageData)
            } else {
                // Quality reject path — release the capture gate AND
                // reset the force-capture deadline. Without the deadline
                // reset, the very next acceptable detection would see
                // `elapsed >= forceCaptureDeadline` (because the timer
                // started 3+ seconds ago, before this failed capture)
                // and re-fire immediately with the same framing. Reset
                // forces the user to hold steady for a fresh 3-second
                // window before another shutter triggers.
                self.firstDetectedTime = nil
                self.isCapturing = false
                self.feedbackMessage = validation.issues.first?.message ?? "Quality check failed"
            }
        }
    }

    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer) {
        guard !isCapturing, !hasPendingReview else { return }

        // v1.9.0: DocumentScanner now accepts CMSampleBuffer directly
        // (uses Google ML Kit which takes VisionImage(buffer:)). Saves
        // the CVPixelBuffer extraction round-trip we used to do for
        // Apple Vision's VNDetectDocumentSegmentationRequest.
        documentScanner.detectDocument(in: sampleBuffer) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }

                guard let result = result else {
                    self.isDocumentDetected = false
                    self.feedbackMessage = "Position document within the frame"
                    // Detection dropped — reset the force-capture deadline
                    // so a brief flicker doesn't accidentally satisfy the
                    // 3-second window on the next frame.
                    self.firstDetectedTime = nil
                    return
                }

                self.isDocumentDetected = true

                // v1.8.6: coverage gate runs BEFORE stability. If framing
                // is unworkable (doc too small or too large), surface the
                // guidance and suppress auto-capture regardless of how
                // stable the user's hands are. Matches Android.
                if let guidance = result.qualityGuidance {
                    self.feedbackMessage = guidance
                    self.firstDetectedTime = nil
                    return
                }

                // Coverage is acceptable. Start (or continue) the
                // force-capture deadline timer.
                if self.firstDetectedTime == nil {
                    self.firstDetectedTime = Date()
                }

                let elapsed = self.firstDetectedTime.map { Date().timeIntervalSince($0) } ?? 0
                let forceCapture = elapsed >= self.forceCaptureDeadline

                let shouldCapture = (result.isStable || forceCapture) &&
                                    !self.isCapturing &&
                                    !self.hasPendingReview

                if shouldCapture {
                    self.feedbackMessage = "Hold steady..."
                    self.captureManually()
                } else {
                    // Detection + acceptable coverage but waiting on
                    // stability or the deadline. Keep the user oriented.
                    self.feedbackMessage = "Hold steady..."
                }
            }
        }
    }

    func cameraManager(_ manager: CameraManager, didFail error: KoraError) {
        DispatchQueue.main.async {
            self.isProcessing = false
            self.feedbackMessage = error.localizedDescription
        }
    }
}
