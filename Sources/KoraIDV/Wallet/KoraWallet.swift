// KoraWallet.swift
// KoraIDV Wallet — Main wallet class for credential storage, selective disclosure, and presentation

import Foundation

/// Main entry point for the Kora Wallet SDK module.
///
/// Provides credential storage (Keychain-backed), selective disclosure,
/// Verifiable Presentation creation, and QR/deep-link sharing.
public final class KoraWallet {

    private let store: WalletCredentialStore

    /// Create a new KoraWallet instance.
    public init() {
        self.store = WalletCredentialStore()
    }

    // MARK: - Credential Management

    /// Store a Verifiable Credential in the wallet.
    ///
    /// - Parameter credential: The W3C Verifiable Credential to store.
    /// - Returns: The storage ID (same as the credential's `id`).
    @discardableResult
    public func store(credential: WalletCredential) throws -> String {
        let now = ISO8601DateFormatter().string(from: Date())
        let stored = StoredWalletCredential(
            id: credential.id,
            credential: credential,
            storedAt: now,
            issuerDID: credential.issuer,
            subjectName: credential.credentialSubject.fullName,
            expiresAt: credential.expirationDate
        )
        try self.store.save(id: credential.id, credential: stored)
        return credential.id
    }

    /// Retrieve all stored credentials.
    public func getCredentials() -> [StoredWalletCredential] {
        let ids = store.listIds()
        return ids.compactMap { store.load(id: $0) }
    }

    /// Retrieve a single credential by ID.
    public func getCredential(id: String) -> StoredWalletCredential? {
        return store.load(id: id)
    }

    /// Delete a credential from the wallet.
    public func deleteCredential(id: String) throws {
        try store.delete(id: id)
    }

    /// Number of credentials currently stored.
    public var credentialCount: Int {
        return store.listIds().count
    }

    // MARK: - Presentation

    /// Create a Verifiable Presentation with selective disclosure.
    ///
    /// - Parameters:
    ///   - credentialId: ID of the stored credential to present.
    ///   - profile: Disclosure profile controlling which claims are revealed.
    ///   - audience: The intended verifier (domain or DID).
    ///   - nonce: Challenge nonce from the verifier for replay protection.
    /// - Returns: A `WalletPresentation` containing the disclosed credential.
    public func createPresentation(
        credentialId: String,
        profile: DisclosureProfile,
        audience: String? = nil,
        nonce: String? = nil
    ) throws -> WalletPresentation {
        guard let stored = store.load(id: credentialId) else {
            throw WalletError.credentialNotFound
        }
        if isExpired(credentialId: credentialId) {
            throw WalletError.credentialExpired
        }
        return WalletPresentationBuilder.create(
            credential: stored.credential,
            profile: profile,
            audience: audience,
            nonce: nonce
        )
    }

    /// Generate a deep link URL for sharing a presentation.
    public func generateDeepLink(
        presentation: WalletPresentation,
        profile: DisclosureProfile = .full
    ) -> URL? {
        return WalletQRCode.deepLink(for: presentation, profile: profile)
    }

    // MARK: - Expiry

    /// Check whether a stored credential has expired.
    public func isExpired(credentialId: String) -> Bool {
        guard let stored = store.load(id: credentialId) else { return true }
        let formatter = ISO8601DateFormatter()
        guard let expires = formatter.date(from: stored.expiresAt) else { return false }
        return Date() > expires
    }
}
