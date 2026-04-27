// WalletQRCode.swift
// KoraIDV Wallet — QR code generation for credential presentations

import Foundation

#if canImport(CoreImage)
import CoreImage
#endif

#if canImport(UIKit)
import UIKit
#endif

/// Generates QR codes and deep links for Verifiable Presentations.
public final class WalletQRCode {

    /// Maximum payload size (bytes) for inline QR data. Larger payloads use a reference deep link.
    private static let maxInlineSize = 2048

    /// Generate a deep link URL for the given presentation.
    ///
    /// If the JSON payload fits within 2 KB, it is base64url-encoded inline.
    /// Otherwise a reference link with credential ID and profile name is produced.
    public static func deepLink(
        for presentation: WalletPresentation,
        profile: DisclosureProfile = .full
    ) -> URL? {
        guard let data = try? JSONEncoder().encode(presentation) else { return nil }

        if data.count <= maxInlineSize {
            let encoded = data.base64URLEncoded()
            return URL(string: "korastratum://present?data=\(encoded)")
        }

        // Fallback: reference link
        let credId = presentation.verifiableCredential.first?.id ?? "unknown"
        let profileName = profile.name
        return URL(string: "korastratum://present?ref=\(credId)&profile=\(profileName)")
    }

    /// Generate QR code image data (PNG) for a presentation.
    ///
    /// Returns `nil` on platforms where CoreImage is unavailable.
    public static func generate(
        from presentation: WalletPresentation,
        profile: DisclosureProfile = .full,
        size: CGFloat = 300
    ) -> Data? {
        guard let url = deepLink(for: presentation, profile: profile) else { return nil }
        return generateQR(for: url.absoluteString, size: size)
    }

    /// Generate a QR code for an arbitrary string payload.
    public static func generateQR(for string: String, size: CGFloat = 300) -> Data? {
        #if canImport(CoreImage)
        guard let data = string.data(using: .utf8) else { return nil }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }

        let scaleX = size / ciImage.extent.width
        let scaleY = size / ciImage.extent.height
        let transformed = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        #if canImport(UIKit)
        let uiImage = UIImage(ciImage: transformed)
        return uiImage.pngData()
        #else
        // macOS fallback: return CIImage representation
        let context = CIContext()
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
        #endif
        #else
        return nil
        #endif
    }
}

// MARK: - Base64URL Encoding

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
