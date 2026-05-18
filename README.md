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
pod 'KoraIDV', :git => 'https://github.com/badedokun/koraidv-koraidv-ios.git', :tag => '1.5.5'
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
    .package(url: "https://github.com/badedokun/koraidv-koraidv-ios.git", from: "1.5.5")
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
| `baseURL` | URL? | Custom base URL override (e.g., for self-hosted deployments) |
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

## Image Persistence & Compliance (v1.1.0+)

Starting with v1.1.0, KoraIDV automatically persists all captured images (document front/back, selfie, liveness frames) to secure cloud storage as part of the verification pipeline. This is required for regulatory compliance — regulators (FinCEN, state MSB examiners) can request examination of original identity documents at any time.

### How It Works

Image persistence is **fully automatic** and requires no changes to your integration. When your end-user captures a document, takes a selfie, or completes a liveness challenge, the image is uploaded to KoraIDV's secure storage before the response is returned.

Each upload response now includes an `imagePersisted` field confirming durable storage:

```swift
// The SDK handles this internally — these are the server response models
// DocumentUploadResponse.imagePersisted  → Bool?
// SelfieUploadResponse.imagePersisted    → Bool?
// LivenessChallengeResponse.imagePersisted → Bool?
```

- `true` — Image was successfully persisted to cloud storage
- `false` or `nil` — Image was not stored (sandbox mode, or server not configured)

### Retrieving Images for Your Compliance Dashboard

To display captured images in your own admin/compliance dashboard, use the tenant-scoped image retrieval API. These endpoints are authenticated with your tenant credentials and scoped to your verifications only.

#### Step 1: List Available Images

```swift
// GET /api/v1/verifications/{verificationId}/images
// Header: X-Tenant-ID: {your-tenant-uuid}

// Response:
// {
//   "images": [
//     { "type": "document_front", "available": true },
//     { "type": "document_back", "available": true },
//     { "type": "selfie", "available": true },
//     { "type": "liveness_blink", "available": true }
//   ]
// }
```

#### Step 2: Get a Signed URL for Each Image

```swift
// GET /api/v1/verifications/{verificationId}/images/{imageType}
// Header: X-Tenant-ID: {your-tenant-uuid}

// Response:
// {
//   "imageType": "document_front",
//   "url": "https://storage.googleapis.com/...",
//   "expiresIn": 900
// }
```

The signed URL is valid for **15 minutes**. Load it directly in a `UIImageView`, `AsyncImage`, or web view. Request a new URL after expiry.

#### Valid Image Types

| Image Type | Description |
|------------|-------------|
| `document_front` | Front of the identity document |
| `document_back` | Back of the identity document |
| `selfie` | Selfie photo |
| `liveness_blink` | Liveness challenge: blink |
| `liveness_smile` | Liveness challenge: smile |
| `liveness_turn_left` | Liveness challenge: turn left |
| `liveness_turn_right` | Liveness challenge: turn right |
| `liveness_nod_up` | Liveness challenge: nod up |
| `liveness_nod_down` | Liveness challenge: nod down |

#### Example: Display Images in a Swift Admin App

```swift
import Foundation

struct ImageInfo: Decodable {
    let type: String
    let available: Bool
}

struct ImageURL: Decodable {
    let imageType: String
    let url: String
    let expiresIn: Int
}

class ComplianceImageService {
    let baseURL: URL
    let tenantId: String

    init(baseURL: URL, tenantId: String) {
        self.baseURL = baseURL
        self.tenantId = tenantId
    }

    /// Fetch the list of available images for a verification
    func listImages(verificationId: String) async throws -> [ImageInfo] {
        var request = URLRequest(url: baseURL.appendingPathComponent(
            "api/v1/verifications/\(verificationId)/images"))
        request.setValue(tenantId, forHTTPHeaderField: "X-Tenant-ID")

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode([String: [ImageInfo]].self, from: data)
        return response["images"] ?? []
    }

    /// Get a signed URL for a specific image
    func getImageURL(verificationId: String, imageType: String) async throws -> ImageURL {
        var request = URLRequest(url: baseURL.appendingPathComponent(
            "api/v1/verifications/\(verificationId)/images/\(imageType)"))
        request.setValue(tenantId, forHTTPHeaderField: "X-Tenant-ID")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(ImageURL.self, from: data)
    }
}

// Usage in a SwiftUI view:
// let service = ComplianceImageService(baseURL: apiURL, tenantId: "your-tenant-uuid")
// let images = try await service.listImages(verificationId: "ver_xxx")
// for img in images where img.available {
//     let signed = try await service.getImageURL(verificationId: "ver_xxx", imageType: img.type)
//     AsyncImage(url: URL(string: signed.url))
// }
```

### Important Notes

- **No backfill:** Only verifications created after v1.1.0 deployment will have stored images.
- **Sandbox mode:** `imagePersisted` will be `false` in sandbox — images are not stored for synthetic test data.
- **Tenant isolation:** You can only access images for your own verifications. Cross-tenant access is not possible.
- **Retention:** Images are retained according to your regulatory requirements (configured server-side).

## Changelog

### 1.1.0
- Added `imagePersisted` field to `DocumentUploadResponse`, `SelfieUploadResponse`, and `LivenessChallengeResponse`
- Confirms whether captured images were durably stored server-side for regulatory compliance
- Aligned version numbering with Android SDK

### 1.0.1
- Added `baseURL` configuration option for custom API endpoint override
- Added `kora_sandbox_` API key prefix detection for automatic sandbox environment
- Fixed API connectivity when using self-hosted or Cloud Run deployments

### 1.0.0 (8f2b2ad)
- Initial release
- Document capture with auto-detection
- Selfie capture with face detection
- Active and passive liveness detection
- MRZ reading for passports
- Renamed `Environment` to `APIEnvironment` to avoid SwiftUI conflicts
- Added `.code` and `.message` compatibility properties to `KoraError`

## License

MIT — see [LICENSE](./LICENSE). Copyright © 2026 Korastratum, Inc.
