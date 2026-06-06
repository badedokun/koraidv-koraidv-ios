Pod::Spec.new do |s|
  s.name             = 'KoraIDV'
  s.version          = '1.9.0'
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
end
