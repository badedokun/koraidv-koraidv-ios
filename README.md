# Kora IDV iOS SDK

Native iOS SDK for identity verification with document capture, selfie capture, and liveness detection.

## Requirements

- iOS 14.0+ (iOS 15.0+ recommended for full feature support)
- Xcode 14.0+
- Swift 5.7+

## Installation

### CocoaPods (Recommended)

Add to your `Podfile`:

```ruby
pod 'KoraIDV', :git => 'https://github.com/badedokun/koraidv-koraidv-ios.git', :commit => '8f2b2ad'
```

Then run:

```bash
pod install
```

> **Important:** Ensure your iOS deployment target is set to iOS 14.0 or higher in both your Podfile and Xcode project settings.

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/badedokun/koraidv-koraidv-ios.git", from: "1.0.0")
]
```

Or in Xcode: File → Add Package Dependencies → Enter the repository URL.

## Quick Start

### 1. Configure the SDK

```swift
import KoraIDV

// In your AppDelegate or early in app lifecycle
let config = Configuration(
    apiKey: "kora_your_api_key_here",
    tenantId: "your-tenant-uuid",
    environment: .sandbox  // Use .production for live
)

KoraIDV.configure(with: config)
```

### 2. Start Verification

```swift
KoraIDV.startVerification(
    externalId: "user-123",
    tier: .standard,
    from: self
) { result in
    switch result {
    case .success(let verification):
        print("Verification ID: \(verification.id)")
        print("Status: \(verification.status)")

    case .failure(let error):
        print("Error Code: \(error.code.rawValue)")
        print("Error Message: \(error.message)")

    case .cancelled:
        print("User cancelled verification")
    }
}
```

### 3. Resume an Existing Verification

```swift
KoraIDV.resumeVerification(
    verificationId: "ver_existing_id",
    from: self
) { result in
    // Handle result same as above
}
```

## Configuration Options

| Option | Type | Description |
|--------|------|-------------|
| `apiKey` | String | Your Kora IDV API key (required, starts with `kora_`) |
| `tenantId` | String | Your tenant UUID (required) |
| `environment` | APIEnvironment | `.production` or `.sandbox` |
| `documentTypes` | [DocumentType] | Allowed document types |
| `livenessMode` | LivenessMode | `.passive` or `.active` |
| `theme` | KoraTheme | UI customization |
| `timeout` | TimeInterval | Session timeout in seconds |

## Supported Documents

### Priority 1 (v1.0)
- US Passport
- US Driver's License
- US State ID
- International Passport
- UK Passport
- EU ID Cards (Germany, France, Spain, Italy)

### Priority 2 (v1.1)
- Ghana Card
- Nigeria NIN
- Kenya ID
- South Africa ID

## Theme Customization

```swift
let theme = KoraTheme(
    primaryColor: .systemBlue,
    backgroundColor: .systemBackground,
    textColor: .label,
    secondaryTextColor: .secondaryLabel,
    borderColor: .separator,
    successColor: .systemGreen,
    errorColor: .systemRed,
    warningColor: .systemOrange,
    cornerRadius: 12
)

// Apply when configuring
let config = Configuration(
    apiKey: "kora_xxx",
    tenantId: "tenant-uuid",
    environment: .sandbox
)
// config.theme = theme  // If using custom theme

KoraIDV.configure(with: config)
```

## Error Handling

```swift
case .failure(let error):
    // Get error code as string
    let errorCode = error.code.rawValue  // e.g., "NETWORK_ERROR"

    // Get human-readable message
    let message = error.message  // e.g., "Network error: ..."

    // Check specific error types
    switch error {
    case .networkError:
        // Handle network issues
    case .cameraAccessDenied:
        // Prompt user to enable camera in Settings
    case .sessionExpired:
        // Session timed out, restart verification
    case .documentTypeNotSupported:
        // Selected document type not allowed
    case .userCancelled:
        // User cancelled the flow
    default:
        // Show generic error
    }

    // Show recovery suggestion if available
    if let suggestion = error.recoverySuggestion {
        print(suggestion)
    }
```

## Privacy Permissions

Add the following to your `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required to capture your ID document and selfie for identity verification.</string>
```

## Localization

The SDK supports English and French out of the box. To add additional languages, provide translations for the keys in `Localizable.strings`.

## Troubleshooting

### "Enum 'Environment' cannot be used as an attribute"

This error occurs if your project has a type named `Environment` that conflicts with SwiftUI's `@Environment` property wrapper. The SDK uses `APIEnvironment` for the environment configuration to avoid this conflict.

### iOS Deployment Target Mismatch

If you see an error like "Compiling for iOS 13.0, but module 'KoraIDV' has a minimum deployment target of iOS 14.0", update your iOS deployment target:

1. In your `Podfile`, ensure: `platform :ios, '14.0'` (or higher)
2. In Xcode project settings, set iOS Deployment Target to 14.0+
3. In `ios/Flutter/AppFrameworkInfo.plist` (Flutter apps), set `MinimumOSVersion` to `14.0`

### CocoaPods Cache Issues

If changes aren't being picked up:

```bash
cd ios
rm -rf Pods/KoraIDV
pod cache clean KoraIDV --all
pod update KoraIDV
```

## Example Integration (Flutter/Native Bridge)

```swift
// In AppDelegate.swift
import KoraIDV

// Configure SDK
let koraEnvironment: APIEnvironment = environment == "sandbox" ? .sandbox : .production
let config = Configuration(
    apiKey: apiKey,
    tenantId: tenantId,
    environment: koraEnvironment
)
KoraIDV.configure(with: config)

// Start verification
KoraIDV.resumeVerification(
    verificationId: verificationId,
    from: rootViewController
) { result in
    switch result {
    case .success(let verification):
        // Handle success
        let data: [String: Any] = [
            "success": true,
            "verificationId": verification.id,
            "status": verification.status.rawValue
        ]

    case .failure(let error):
        // Handle error
        let data: [String: Any] = [
            "success": false,
            "errorCode": error.code.rawValue,
            "errorMessage": error.message
        ]

    case .cancelled:
        // Handle cancellation
        break
    }
}
```

## Changelog

### 1.0.0 (8f2b2ad)
- Initial release
- Document capture with auto-detection
- Selfie capture with face detection
- Active and passive liveness detection
- MRZ reading for passports
- Renamed `Environment` to `APIEnvironment` to avoid SwiftUI conflicts
- Added `.code` and `.message` compatibility properties to `KoraError`

## License

Copyright 2025 Kora IDV. All rights reserved.
