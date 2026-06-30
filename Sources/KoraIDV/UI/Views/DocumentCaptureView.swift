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
            viewModel.startCapture(detectBarcode: side == .back) { imageData in
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
            // **Card-WINDOW capture (BanffPay v1.9.6 iOS alignment fix,
            // 2026-06-29).** The camera is no longer a full-screen preview with
            // a small card OUTLINE drawn over it (which let the document overflow
            // the outline — Olabode "document falls outside the guide"). Instead
            // the camera is clipped INTO the ID-1 card frame inside
            // `documentViewfinder`, exactly like Android, so whatever the user
            // holds fills the window and can't fall outside it. Background is a
            // flat dark fill.
            Color.black.ignoresSafeArea()

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
                // Camera clipped INTO the ID-1 card window (1.586:1) — the
                // document the user holds fills the window, mirroring Android's
                // `aspectRatio(1.586).clip(...)` preview. Detection still runs
                // on the full camera frame and capture is the full-res still
                // cropped to the detected document bbox; this clip is a framing
                // aid only.
                CameraPreviewView(cameraManager: viewModel.cameraManager)
                    .frame(width: maxWidth, height: frameHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .accessibilityLabel("Camera viewfinder")
                    .accessibilityAddTraits(.isImage)

                // Document frame border
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 260)
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
            //
            // **v1.9.0-rc6.7 → 2026-06-16.** rc6.7 fit the image inside a
            // FIXED 40%-height box, which left empty bands around a wide DL.
            // A first pass used `.fill`, but that zoomed/cropped the document
            // and ballooned the card (BanffPay 2026-06-16: "the original
            // picture frame should not be resized… fill the taken picture
            // within that frame, not enlarge everything"). Correct approach:
            // keep `.fit` (true dimensions — no zoom, no crop) and let the
            // card adopt the IMAGE's own aspect ratio while filling the
            // available width. So a wide DL fills width with no side/vertical
            // padding, at its real proportions; a portrait doc is capped by
            // maxHeight. No fixed box, no resizing the picture.
            VStack(spacing: 16) {
                if let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(uiImage.size, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: UIScreen.main.bounds.height * 0.45)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 16)
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
//
// `CameraPreviewView` (the SwiftUI camera-preview wrapper) moved to
// `Capture/CameraPreviewView.swift` so the SPM unit-test target — which
// excludes this ML-Kit-dependent file — can still use it from
// SelfieCaptureView.

// MARK: - View Model

class DocumentCaptureViewModel: ObservableObject {
    @Published var isDocumentDetected = false
    @Published var feedbackMessage: String?
    @Published var isProcessing = false
    @Published var isFlashOn = false

    // **v1.9.0-rc6.1 — re-enable document crop, bbox-based this time.**
    // rc5's centered-geometric crop clipped face/name regions; rc5.1
    // reverted to no crop (DL small in portrait frame); rc6.1 finally
    // does it right: snapshot the detected document bbox at capture
    // trigger time and pass it to CameraManager so the crop uses the
    // ACTUAL detected document location (with 5% padding). This is the
    // permanent fix for the chronic "DL too small in review screen"
    // issue. The bbox is set on `cameraManager.documentBbox` inside
    // `captureManually()` below — see that method for the trigger-time
    // snapshot.
    let cameraManager: CameraManager = {
        let m = CameraManager()
        m.documentMode = true
        return m
    }()
    private let documentScanner = DocumentScanner()
    private let qualityValidator = QualityValidator()

    private var onCapture: ((Data) -> Void)?
    private var isCapturing = false

    /// When true, the document scanner also runs live PDF417 barcode
    /// detection and folds the barcode bbox into the document region, and the
    /// captured photo is cropped to the detected card rectangle. Set for the
    /// BACK side (barcode-dominated, sparse text) so it auto-captures as
    /// reliably as the text-dense front. See DocumentScanner.detectDocument.
    private var detectBarcodeForCapture = false

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

    /// **v1.9.0-rc6.2 — camera settle delay.** Minimum time between
    /// camera-start and any capture firing. Without this, the auto-
    /// capture path fires immediately when the detector sees a
    /// document — but at camera-start the document is often
    /// partially in frame from the user's reach, and the SDK
    /// snapshots a bad framing before the user has settled the
    /// phone into position. Stratum Remit 2026-06-06 feedback: "when
    /// the camera first opens to the front of the DL, it fires too
    /// quickly when it detects the doc in the frame. perhaps a 1 or
    /// 2 seconds delay may allow the user fill the frame correctly."
    ///
    /// 1.5 seconds — long enough for the user to bring the document
    /// into a stable frame, short enough that it doesn't feel
    /// sluggish for users who pre-positioned the document before
    /// the camera opened.
    private let cameraSettleDelay: TimeInterval = 1.5

    /// **v1.9.0-rc6.2** — set when the camera session starts; used
    /// by the capture-trigger gate in `cameraManager(_:didOutput:)`.
    private var cameraStartedAt: Date?

    /// **Capture cooldown (BanffPay "camera fires multiple times",
    /// 2026-06-29).** Timestamp of the last auto-capture attempt. A capture
    /// that fails the post-shot quality check reopens the auto-capture gate
    /// (`isCapturing=false`, no `hasPendingReview`); if the document is still
    /// stable the very next frame re-fires immediately, machine-gunning the
    /// shutter while continuous AF settles. Suppress auto-capture for
    /// `captureCooldown` after each attempt so the lens can settle and the
    /// next shot is sharp instead of a rapid burst of soft rejects.
    private var lastCaptureAttemptAt: Date?
    private let captureCooldown: TimeInterval = 1.3

    func startCapture(detectBarcode: Bool = false, onCapture: @escaping (Data) -> Void) {
        self.onCapture = onCapture
        self.detectBarcodeForCapture = detectBarcode

        cameraManager.delegate = self
        cameraManager.requestPermission { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                self.feedbackMessage = "Camera access required"
                return
            }

            self.cameraManager.configure(position: .back) { [weak self] result in
                if case .success = result {
                    self?.cameraManager.start()
                    // rc6.2: snapshot start time so the settle-delay
                    // gate in the frame callback can suppress capture
                    // for the first 1.5 seconds.
                    self?.cameraStartedAt = Date()
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
        // **v1.9.0-rc6.2** — re-arm the settle delay on retake so the
        // user gets the same "frame your document" headroom they had
        // on the initial capture instead of the SDK firing
        // immediately the moment they reposition.
        cameraStartedAt = Date()
    }

    func captureManually() {
        guard !isCapturing, !hasPendingReview else { return }
        isCapturing = true
        isProcessing = true
        lastCaptureAttemptAt = Date()

        // **v1.9.0-rc6.1** — snapshot the detector's last known
        // bounding box (normalized 0–1) and hand it to CameraManager
        // for use during the photo-capture crop. Without this, the
        // CameraManager falls back to the centered ID-1 heuristic
        // that rc5 shipped and that clipped face/name regions when
        // the user placed the DL where the viewfinder guides them
        // (upper portion of the screen) rather than at the geometric
        // center of the photo. With this, the crop tightly matches
        // the document the SDK was already detecting on every frame.
        //
        cameraManager.documentBbox = documentScanner.lastBoundsFractional()
        // **2026-06-16 — back side crops to the detected CARD RECTANGLE.** The
        // FRONT's text spans the whole card, so its content bbox already equals
        // the card and fills the review. The BACK's text+barcode only covers
        // the upper-middle, so a content crop is too small and a centered crop
        // leaves tablecloth margins (confirmed by pulling the actual capture
        // from GCS). For the back, detect the card's edges and crop to those
        // for a tight, full-card image that fills the review like the front.
        // Falls back to documentBbox / centered crop if no card rect is found.
        cameraManager.useCardRectCrop = detectBarcodeForCapture
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
        guard UIImage(data: imageData) != nil else {
            DispatchQueue.main.async {
                self.isProcessing = false
                self.isCapturing = false
                self.firstDetectedTime = nil
                self.feedbackMessage = "Invalid image. Try again."
            }
            return
        }

        // **Capture once, then review — Android parity (BanffPay "camera fires
        // multiple times", 2026-06-29).** iOS used to re-run the quality
        // validator HERE and, on a soft/glare frame, REOPEN the auto-capture
        // gate (no `hasPendingReview`, `isCapturing=false`, deadline reset) and
        // let the very next stable frame re-fire — machine-gunning the shutter,
        // made worse once continuous AF started producing the occasional soft
        // frame. Android never does this: it captures once and always shows the
        // review, where the on-screen quality checks + Retake let the user
        // decide. Match that — always go to review, hold the gate via
        // `hasPendingReview` until the user retakes.
        DispatchQueue.main.async {
            self.isProcessing = false
            self.hasPendingReview = true
            self.isCapturing = false
            self.onCapture?(imageData)
        }
    }

    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer) {
        guard !isCapturing, !hasPendingReview else { return }

        // v1.9.0: DocumentScanner now accepts CMSampleBuffer directly
        // (uses Google ML Kit which takes VisionImage(buffer:)). Saves
        // the CVPixelBuffer extraction round-trip we used to do for
        // Apple Vision's VNDetectDocumentSegmentationRequest.
        documentScanner.detectDocument(in: sampleBuffer, detectBarcode: self.detectBarcodeForCapture) { [weak self] result in
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

                // **Android parity fix (BanffPay iOS DL-back, 2026-06-16).**
                // The force-capture deadline measures HOW LONG THE DOCUMENT
                // HAS BEEN PRESENT — not how long framing has been perfect —
                // so start it on first detection, BEFORE the framing-guidance
                // gate, and reset it only when no document is detected (the
                // `result == nil` branch above).
                //
                // Previously iOS reset this timer on every "move closer"
                // guidance frame. On a barcode-dominated DL back, ML Kit text
                // coverage flickers in and out of range, so `qualityGuidance`
                // toggled frame-to-frame and the 3s timer never accumulated —
                // the force-capture safety net never fired, and with iOS's
                // stricter 3-consecutive-stable-frame requirement the back
                // only snapped when the stars briefly aligned ("unpredictable
                // when it snaps"). Android resets firstDetectedTime ONLY when
                // the document isn't detected (CaptureScreens.kt:267-268) and
                // leaves the timer running through guidance frames, which is
                // why its back is as reliable as its front. Match that.
                if self.firstDetectedTime == nil {
                    self.firstDetectedTime = Date()
                }

                // Coverage gate runs BEFORE stability. If framing is
                // unworkable (doc too small/large or clipped at an edge),
                // surface the guidance and suppress auto-capture regardless of
                // stability — but DO NOT reset the deadline timer (parity fix
                // above; forceCapture is still gated on guidance == nil below,
                // exactly like Android).
                if let guidance = result.qualityGuidance {
                    self.feedbackMessage = guidance
                    return
                }

                let elapsed = self.firstDetectedTime.map { Date().timeIntervalSince($0) } ?? 0
                let forceCapture = elapsed >= self.forceCaptureDeadline

                // **v1.9.0-rc6.2 — camera settle delay gate.** Suppress
                // capture firing for the first 1.5 seconds after
                // camera start, even if the detector says stable.
                // Without this, the auto-capture path fires the
                // instant the detector picks up the document — which
                // is often mid-reach when the user is still bringing
                // the document into the frame, producing a captured
                // photo with the doc partially out of frame.
                let timeSinceCameraStart = self.cameraStartedAt.map { Date().timeIntervalSince($0) } ?? .infinity
                let pastSettleDelay = timeSinceCameraStart >= self.cameraSettleDelay

                // Capture cooldown — after an auto-capture attempt, hold off
                // re-firing for `captureCooldown` so a soft (mid-AF) shot that
                // failed validation doesn't immediately machine-gun the shutter
                // before the lens settles (BanffPay "fires multiple times").
                let sinceLastCapture = self.lastCaptureAttemptAt.map { Date().timeIntervalSince($0) } ?? .infinity
                let pastCooldown = sinceLastCapture >= self.captureCooldown

                // `result.hasBarcode` (back side) is treated as capture-ready
                // on its own: a detected PDF417 is a high-confidence
                // "real document, correctly framed" signal (Vision won't read
                // a motion-blurred/partial barcode), so the back snaps as soon
                // as the barcode is in frame — matching the front — instead of
                // waiting on the 3-consecutive-stable-text-frame burst that the
                // sparse-text back rarely satisfies. The framing-guidance gate
                // (handled by the early return above) and the 1.5s camera
                // settle delay still apply, so this can't fire mid-reach.
                // Capture only when focus is LOCKED (not mid-ramp) so the still
                // is sharp — the key lever for crisp document text. The 3-second
                // force-capture deadline bypasses this so a device that never
                // fully settles isn't stuck forever.
                let focusLocked = !self.cameraManager.isAdjustingFocus
                let readyAndFocused = (result.isStable || result.hasBarcode) && focusLocked

                let shouldCapture = (readyAndFocused || forceCapture) &&
                                    pastSettleDelay &&
                                    pastCooldown &&
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
