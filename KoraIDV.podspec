Pod::Spec.new do |s|
  s.name             = 'KoraIDV'
  s.version          = '1.9.5'
  s.summary          = 'Kora IDV Identity Verification SDK for iOS'
  s.description      = <<-DESC
    KoraIDV SDK enables seamless identity verification in your iOS applications.
    Features include document capture, selfie capture, liveness detection, and
    MRZ reading with full API integration.

    v1.9.0: document detection rebuilt on Google ML Kit Text Recognition for
    cross-platform behavioral parity with the Android SDK. Same detection
    algorithm, same thresholds, same output as koraidv-android — drops Apple
    Vision's device-sensitive geometric segmentation.

    v1.9.0-rc2: orientation fix — rc1 set VisionImage.orientation = .right,
    double-rotating the already-portrait CameraManager buffer and collapsing
    text-bbox coverage below the 0.35 threshold. Plus os_log migration so
    TestFlight builds can be diagnosed without a debug attach.

    v1.9.0-rc3: addresses Stratum Remit 2026-06-06 device-test report —
    coverage threshold FOV-recalibrated for iPhone wide-angle (0.35 → 0.18),
    selfie face-size floor lowered (0.15 → 0.10), document "snaps twice"
    race fixed, liveness empty-imageBase64 submission suppressed (was
    causing silent HTTP 400 on every nil-capture path). Also ship-blockers
    from rc2: autoclosure compile error in KoraIDV.log resolved, Logger
    level promoted from .debug to .info so TestFlight QA sees output.
    KoraIDV.version constant bumped (rc2 still reported 1.8.3 to backend).

    v1.9.0-rc4: photo capture orientation normalization (AVCapturePhotoOutput
    was delivering sensor-native landscape JPEGs even with .portrait connection
    orientation — selfie and document images uploaded sideways, scoring
    face_match=0 and liveness=0, auto-rejecting every verification).
    VerificationScores.screening field made optional and renamed via CodingKey
    to map backend's `complianceScore` — fixes the "Failed to parse response"
    decode error on /complete responses.

    v1.9.0-rc5: addresses Stratum Remit 2026-06-06 rc4 device test —
    (1) cropToDocument port: CameraManager now applies a centered ID-1
    aspect (1.586:1) crop on top of orientation normalization when
    DocumentCaptureView's documentMode flag is set. Fixes "DL too small
    in review screen" and unblocks document_completeness score
    (rc4 was 60/100, blocked at "Document quality too low"). Mirrors
    Android DocumentScanner.cropToDocument.
    (2) Selfie Match display: result screen was showing "7,893%" because
    ScoreBreakdown.compute multiplied the already-percentage faceMatch
    field by 100. Switched to reading from VerificationScores (typed
    0-100 source) for liveness/face/doc metrics consistently.
    Liveness challenge orchestration deferred to rc6 (separate UX-decision
    scope — fail-session vs retry vs continue).

    v1.9.0-rc5.1: hotfix revert of rc5 cropToDocument activation. rc5
    centered-crop reduced the DL face region to ~100×140px, below the
    backend face-matching ML threshold — faceMatch and nameMatch both
    scored 0, overall dropped from rc4's 76.6 to 49 (auto-reject).
    DocumentCaptureView no longer sets documentMode=true; falls back to
    rc4 behavior (full 1080×1920 portrait DL capture). Selfie Match
    display fix from rc5 stays. Proper bbox-based document cropping
    deferred to rc6.

    v1.9.0-rc5.2: hotfix result-screen score math. Two bugs in
    ScoreBreakdown.compute: (1) Overall was displaying `riskScore`
    directly, but backend sends riskScore as the inverse of final_score
    (100 - final). Fix: invert to recover overall. (2) Name Match was
    a placeholder derived from `faceMatch + 10`; backend now emits a
    typed nameMatch score (we just weren't reading it). Fix: read
    `scores.nameMatch` directly. All four displayed metrics now come
    from the typed `verification.scores` source.

    v1.9.0-rc6: liveness challenge orchestration. ChallengeDetector
    now only scores gestures after LivenessView's countdown completes
    (frames during countdown update face-detected state but don't feed
    the gesture detector — fixes the rc5 root cause of "challenges
    auto-complete from natural micro-movements"). New delegate
    callbacks `didChangeFaceDetected` + `didActivateChallenge` plumb
    face state and activation timing to the UI. Oval color now goes
    grey → green when face is in confident range. Countdown waits to
    start until face is detected (no more 3→2→1 firing to empty
    viewport). Per-challenge frame budget bumped 300 → 600 (20s
    gesture-attempt time instead of 10s wall-clock). Default
    no-op delegate methods preserve backwards compatibility for
    custom LivenessManagerDelegate conformers.

    Document bbox-based crop deferred to rc6.1.

    v1.9.0-rc6.1: two fixes from Stratum Remit 2026-06-06 rc6 device
    test. (1) Liveness "stuck on challenge 2": rc6's LivenessView reset
    isFaceDetected=false in didStartChallenge, but the manager's
    didChangeFaceDetected only fires on state transitions — face was
    continuously detected across challenges, so no transition, so no
    callback, so countdown never restarted. Fix: don't reset; trigger
    countdown immediately if face is already detected when challenge
    starts. (2) Permanent fix for "DL too small in review screen":
    DocumentScanner now exposes lastBoundsFractional (normalized 0–1
    bbox); DocumentCaptureView snapshots it at capture trigger and
    hands to CameraManager via documentBbox property; CameraManager's
    cropToDocument uses the bbox + 5% padding instead of the centered
    geometric heuristic that rc5 shipped (which clipped face/name).
    documentMode re-enabled for DocumentCaptureView. Mirrors Android's
    getLastBoundsFractional pattern.

    v1.9.0-rc6.2: two fixes from Stratum Remit 2026-06-06 rc6.1 device
    test. (1) FIRST EVER AUTO-APPROVED VERIFICATION (final_score
    84.99, decision auto_approve) was invisible to the user because
    iOS VerificationStatus enum had `approved` but backend uses
    `verified`. JSONDecoder failed on the enum decode, surfaced as
    "Failed to parse response: The data couldn't be read because it
    isn't in the correct format." Fix: add `case verified = "verified"`.
    Legacy `approved` retained for backwards compat. (2) Camera
    settle delay: 1.5s minimum from camera-start before auto-capture
    fires, so user can frame the document. Was firing immediately
    when detector saw the document mid-reach.

    v1.9.0-rc6.3: stuck-on-Processing-screen fix. rc6.2 added the
    `.verified` enum case but missed the two downstream switches that
    branch on verification.status — VerificationFlowController.showResult
    only had `.approved` (auto-approve fell to default → ResultView
    pushed), AND ResultView.body's switch ALSO only had `.approved` so
    `.verified` fell to ITS default which renders an infinite
    ProcessingScreen. Stratum Remit 2026-06-06 verification 7f52999f
    auto-approved on server (final_score in passing range) but UI hung
    on Processing for 1+ minute. Added `.verified` to both switches
    paired with `.approved` so both wire strings route to the
    SuccessScreen.

    v1.9.0-rc6.4: US DL baseline-smoothness fixes from rc6.3 device
    test. (1) ProcessingScreen min dwell time 1.5s — was flashing
    invisibly because /complete returns in ~100ms; user perceived
    "did not see the processing page". (2) Race condition fix:
    LivenessView's onAllComplete fired before the final challenge's
    image POST completed, so /complete arrived at the backend before
    challenge N's image and was scored on N-1 challenges. Now tracks
    pendingChallengeSubmissions and defers completeVerification until
    all challenge POSTs are confirmed. Establishes solid US DL
    baseline before cross-document testing (NG passport,
    US passport, mismatch cases, etc.).

    v1.9.0-rc6.5: immediate liveness-to-processing transition. rc6.4
    deferred the ProcessingScreen push until /complete was called,
    which on the liveness path waited for the last challenge POST
    roundtrip (~2s). Stratum 2026-06-06 rc6.4: "the last challenge
    still lags for several seconds after the completion before
    showing the processing page." Fix: push ProcessingScreen on
    LivenessView's onAllComplete (gesture-end), not on /complete-call.
    The 1.5s min-dwell timer now overlaps with /complete latency
    instead of starting after it, so the total perceived flow is
    faster while the processing animation stays visible long enough
    to register.

    v1.9.0-rc6.6: smile-challenge detection sticky-fix. iOS uses a
    landmark mouth-aspect heuristic (Apple Vision has no
    smilingProbability) and was reassigning smileDetected every frame
    instead of latching it true once observed (turn/nod use the
    latched pattern). Result: smile flickered below threshold during
    natural mouth movement, the 5-consecutive-frame counter never
    accumulated, smile challenges took 30+s to register. Stratum
    2026-06-06 rc6.5 device test: "when smile challenge is #3, the
    transition to processing is delayed." Not position-specific —
    happens whenever smile is the challenge. Fix: once ratio crosses
    threshold, set smileDetected = true and keep it true until
    reset() (next challenge). Matches turn/nod pattern.

    v1.9.0 (final): cuts the rc6.8 release candidate. Two-day stabilization
    arc starting from the v1.9.0 ML Kit rewrite (rc1). Highlights of what
    landed across the rc series:
      - Document detection rebuilt on Google ML Kit Text Recognition for
        cross-platform parity with Android (rc1+)
      - Photo capture orientation normalization (rc4)
      - bbox-based document crop using DocumentScanner's detected boundary (rc6.1)
      - Liveness challenge orchestration: face-state oval color, countdown
        gating on face acquisition, post-countdown gesture activation (rc6)
      - Smile + blink challenges now use Apple's CIDetector classifier
        instead of unreliable Vision-landmark heuristics (rc6.8)
      - Result-screen UX: SuccessScreen routing for status="verified",
        decisionReason display on rejections, ProcessingScreen min-dwell,
        challenge-complete haptic + checkmark, ScoreBreakdown math fixes
        (overall = 100 - riskScore, scores.nameMatch direct read), Selfie
        Match display fix (no more 7,893%)
      - Backwards-compat shims throughout (default delegate methods,
        Codable-optional fields with CodingKey remap, legacy detector
        fallbacks for CIDetector path)
    Backend dependencies: koraidv-identity revision 00108-dhz onwards
    (CEngine dual-auth via X-Serverless-Authorization), compliance-gateway
    with koraidv-cloudrun@koraidv on run.invoker allowlist.

    v1.9.0-rc6.8: smile + blink challenges now use Apple's CIDetector
    (CIDetectorSmile + CIDetectorEyeBlink) instead of Vision-landmark
    heuristics. Server-log evidence: 0 smile submissions in 7 days and
    only 1 blink submission in hours under the prior implementation —
    the mouth-aspect ratio and EAR-threshold state machines never
    fired completed=true reliably on Apple Vision's noisy landmark
    output. CIDetector provides Apple's production smile classifier
    (used in iOS smile-burst photography for years) and per-eye
    open/closed booleans. Gated to only run on smile/blink challenges,
    so turn/nod paths keep their Vision-only flow with no per-frame
    overhead change. Falls back to the legacy detectors when CIDetector
    is unavailable (defensive only). User-perceived: smile and blink
    challenges now register within 1-2s instead of never.

    v1.9.0-rc6.7: six fixes from Stratum Remit 2026-06-07 cross-doc
    test matrix. (1) decisionReason plumbing — backend's specific
    rejection messages ("You selected NG but document was issued by
    US") now displayed on RejectedScreen; eliminates user confusion
    where lowest-scoring metric was misread as the cause.
    (2) Blink-challenge sticky-fix — lowered opening-state EAR
    threshold from 1.5× to 1.2× so natural partial-recovery blinks
    complete the cycle reliably (sibling to rc6.6 smile). (3) Capture
    edge-detection — new guidance "Fit the entire document inside
    the frame" when text bbox touches frame edge (within 2% margin);
    suppresses the bad "move closer when already framed" loop that
    forced users to over-fill and clip edges. (4) DocumentScanner
    stability threshold raised 1→3 consecutive frames so capture
    waits for sustained framing instead of firing on a single brief
    stable detection. (5) Document review viewport — scaled image
    from hardcoded 300×200 to fill available real estate (92% width,
    40% screen height). (6) Challenge-complete haptic + green
    checkmark overlay between challenges so user knows their gesture
    registered before the next prompt arrives. iOS version constant
    bumped to 1.9.0-rc6.7.
  DESC

  s.homepage         = 'https://github.com/badedokun/koraidv-koraidv-ios'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Korastratum' => 'support@korastratum.com' }
  s.source           = { :git => 'https://github.com/badedokun/koraidv-koraidv-ios.git', :tag => "v#{s.version}" }

  # v1.9.0-rc3: bumped 15.0 → 15.5 because GoogleMLKit 7.x requires
  # ios 15.5 as its minimum deployment target. Real-world impact: zero;
  # every iPhone capable of running iOS 15.0 also runs 15.5 (it's the
  # same 6s/SE-1st-gen-and-up fleet). Surfaced by `pod lib lint` (full
  # consumer build) during rc3 prep — `pod spec lint --quick` had been
  # green all along because it only validates metadata, not real
  # dependency resolution.
  s.ios.deployment_target = '15.5'
  s.swift_version = '5.7'

  s.source_files = 'Sources/KoraIDV/**/*.swift'
  s.resources = 'Sources/KoraIDV/UI/Localization/*.lproj'

  # Vision framework remains for face detection (liveness pipeline) and
  # for BarcodeScanner.swift's PDF417 path (US/CA DL back). Document
  # detection moved off VNDetectDocumentSegmentationRequest in v1.9.0;
  # the Vision frameworks reference stays for the other consumers.
  s.frameworks = 'UIKit', 'SwiftUI', 'AVFoundation', 'Vision', 'CoreImage', 'Accelerate'

  # v1.9.0: Google ML Kit Text Recognition powers document detection,
  # mirroring koraidv-android. Adds ~30MB to consumer app size (mostly
  # the on-device text-recognition model bundle); same library version
  # range Android uses, so detection behavior is byte-comparable.
  s.dependency 'GoogleMLKit/TextRecognition', '~> 7.0'

  # **v1.9.2 — required for CocoaPods.** Google ML Kit ships as STATIC
  # frameworks. A pod that depends on ML Kit and is built as a dynamic
  # framework fails to link the ML Kit symbols (MLKTextRecognizer,
  # MLKVisionImage, ...) — which is what blocked CocoaPods trunk from v1.9.0
  # onward (last successful push was v1.8.5, before ML Kit was added).
  # Marking the pod static_framework links the static ML Kit symbols in.
  s.static_framework = true
end
