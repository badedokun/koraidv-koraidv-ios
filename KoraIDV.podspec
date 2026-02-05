Pod::Spec.new do |s|
  s.name             = 'KoraIDV'
  s.version          = '1.0.0'
  s.summary          = 'Kora IDV Identity Verification SDK for iOS'
  s.description      = <<-DESC
    KoraIDV SDK enables seamless identity verification in your iOS applications.
    Features include document capture, selfie capture, liveness detection, and
    MRZ reading with full API integration.
  DESC

  s.homepage         = 'https://github.com/koraidv/koraidv-ios'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Kora IDV' => 'support@koraidv.com' }
  s.source           = { :git => 'https://github.com/koraidv/koraidv-ios.git', :tag => s.version.to_s }

  s.ios.deployment_target = '14.0'
  s.swift_version = '5.7'

  s.source_files = 'Sources/KoraIDV/**/*.swift'
  s.resources = 'Sources/KoraIDV/UI/Localization/*.lproj'

  s.frameworks = 'UIKit', 'SwiftUI', 'AVFoundation', 'Vision', 'CoreImage', 'Accelerate'
end
