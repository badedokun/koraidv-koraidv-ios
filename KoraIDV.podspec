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
  DESC

  s.homepage         = 'https://github.com/badedokun/koraidv-koraidv-ios'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Korastratum' => 'support@korastratum.com' }
  s.source           = { :git => 'https://github.com/badedokun/koraidv-koraidv-ios.git', :tag => "v#{s.version}" }

  s.ios.deployment_target = '15.0'
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
