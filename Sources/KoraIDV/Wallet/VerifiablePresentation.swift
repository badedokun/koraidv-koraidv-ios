// VerifiablePresentation.swift
// KoraIDV Wallet — VP creation with selective disclosure

import Foundation

/// Factory for building W3C Verifiable Presentations.
public struct WalletPresentationBuilder {

    /// Create a Verifiable Presentation from a stored credential with selective disclosure.
    ///
    /// - Parameters:
    ///   - credential: The full Verifiable Credential.
    ///   - profile: The disclosure profile to apply.
    ///   - holder: Optional holder DID.
    ///   - audience: The intended verifier domain or DID.
    ///   - nonce: A challenge nonce from the verifier for replay protection.
    /// - Returns: A `WalletPresentation` ready for transmission.
    public static func create(
        credential: WalletCredential,
        profile: DisclosureProfile,
        holder: String? = nil,
        audience: String? = nil,
        nonce: String? = nil
    ) -> WalletPresentation {
        let disclosed = SelectiveDisclosureEngine.apply(profile: profile, to: credential)
        let now = ISO8601DateFormatter().string(from: Date())

        return WalletPresentation(
            context: ["https://www.w3.org/ns/credentials/v2"],
            type: ["VerifiablePresentation"],
            holder: holder,
            verifiableCredential: [disclosed],
            created: now,
            audience: audience,
            challenge: nonce
        )
    }

    /// Serialize a presentation to JSON Data.
    public static func encode(_ presentation: WalletPresentation) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(presentation)
    }

    /// Deserialize a presentation from JSON Data.
    public static func decode(from data: Data) throws -> WalletPresentation {
        return try JSONDecoder().decode(WalletPresentation.self, from: data)
    }
}
