# Kora IDV iOS SDK

Native iOS SDK for identity verification with document capture, selfie capture, and liveness detection.

## Requirements

- iOS 14.0+
- Xcode 14.0+
- Swift 5.7+

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/koraidv/koraidv-ios.git", from: "1.0.0")
]
```

Or in Xcode: File → Add Package Dependencies → Enter the repository URL.

### CocoaPods

Add to your `Podfile`:

```ruby
pod 'KoraIDV', '~> 1.0'
```

Then run:

```bash
pod install
```

## Quick Start

### 1. Configure the SDK

```swift
import KoraIDV

// In your AppDelegate or early in app lifecycle
let config = KoraIDV.Configuration(
    apiKey: "ck_live_your_api_key",
    tenantId: "your-tenant-uuid",
    environment: .production
)

// Optional: Customize document types
config.documentTypes = [.usPassport, .usDriversLicense, .internationalPassport]

// Optional: Customize theme
config.theme = KoraTheme(primaryColor: .systemBlue)

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
        print("Error: \(error.message)")

    case .cancelled:
        print("User cancelled verification")
    }
}
```

### 3. Resume an Existing Verification

```swift
KoraIDV.resumeVerification(
    id: "ver_existing_id",
    from: self
) { result in
    // Handle result
}
```

## Configuration Options

| Option | Type | Description |
|--------|------|-------------|
| `apiKey` | String | Your Kora IDV API key (required) |
| `tenantId` | String | Your tenant UUID (required) |
| `environment` | Environment | `.production` or `.sandbox` |
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
- EU ID Cards

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

config.theme = theme
```

## Localization

The SDK supports English and French out of the box. To add additional languages, provide translations for the keys in `Localizable.strings`.

## Error Handling

```swift
case .failure(let error):
    switch error.code {
    case .networkError:
        // Handle network issues
    case .cameraPermissionDenied:
        // Prompt user to enable camera
    case .sessionExpired:
        // Session timed out, restart verification
    case .documentNotSupported:
        // Selected document type not allowed
    default:
        // Show generic error
    }

    // Show recovery suggestion if available
    if let suggestion = error.recoverySuggestion {
        print(suggestion)
    }

    // Retry if possible
    if error.isRetryable {
        // Offer retry option
    }
```

## Privacy

Add the following to your `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required to capture your ID document and selfie for identity verification.</string>
```

## License

Copyright 2025 Kora IDV. All rights reserved.
