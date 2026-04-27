// WalletModels.swift
// KoraIDV Wallet — W3C Verifiable Credential types
//
// Types are prefixed with "Wallet" to avoid conflicts with existing KoraIDV types.

import Foundation

// MARK: - Verifiable Credential

public struct WalletCredential: Codable, Equatable {
    public let context: [String]
    public let id: String
    public let type: [String]
    public let issuer: String
    public let issuanceDate: String
    public let expirationDate: String
    public let credentialSubject: WalletCredentialSubject
    public let credentialStatus: WalletCredentialStatus?
    public let proof: WalletDataIntegrityProof?

    enum CodingKeys: String, CodingKey {
        case context = "@context"
        case id, type, issuer, issuanceDate, expirationDate
        case credentialSubject, credentialStatus, proof
    }

    public init(
        context: [String] = ["https://www.w3.org/ns/credentials/v2"],
        id: String,
        type: [String] = ["VerifiableCredential", "KoraIdentityCredential"],
        issuer: String,
        issuanceDate: String,
        expirationDate: String,
        credentialSubject: WalletCredentialSubject,
        credentialStatus: WalletCredentialStatus? = nil,
        proof: WalletDataIntegrityProof? = nil
    ) {
        self.context = context
        self.id = id
        self.type = type
        self.issuer = issuer
        self.issuanceDate = issuanceDate
        self.expirationDate = expirationDate
        self.credentialSubject = credentialSubject
        self.credentialStatus = credentialStatus
        self.proof = proof
    }
}

// MARK: - Credential Subject

public struct WalletCredentialSubject: Codable, Equatable {
    public let id: String
    public let fullName: String
    public let dateOfBirth: String?
    public let nationality: String?
    public let verificationLevel: String
    public let documentType: String
    public let documentCountry: String
    public let biometricMatch: Bool
    public let livenessCheck: Bool
    public let governmentDbVerified: Bool
    public let verifiedAt: String
    public let confidenceScore: Double

    public init(
        id: String,
        fullName: String,
        dateOfBirth: String? = nil,
        nationality: String? = nil,
        verificationLevel: String,
        documentType: String,
        documentCountry: String,
        biometricMatch: Bool,
        livenessCheck: Bool,
        governmentDbVerified: Bool,
        verifiedAt: String,
        confidenceScore: Double
    ) {
        self.id = id
        self.fullName = fullName
        self.dateOfBirth = dateOfBirth
        self.nationality = nationality
        self.verificationLevel = verificationLevel
        self.documentType = documentType
        self.documentCountry = documentCountry
        self.biometricMatch = biometricMatch
        self.livenessCheck = livenessCheck
        self.governmentDbVerified = governmentDbVerified
        self.verifiedAt = verifiedAt
        self.confidenceScore = confidenceScore
    }
}

// MARK: - Credential Status (StatusList2021)

public struct WalletCredentialStatus: Codable, Equatable {
    public let id: String
    public let type: String
    public let statusPurpose: String
    public let statusListIndex: String
    public let statusListCredential: String

    public init(
        id: String,
        type: String = "StatusList2021Entry",
        statusPurpose: String = "revocation",
        statusListIndex: String,
        statusListCredential: String
    ) {
        self.id = id
        self.type = type
        self.statusPurpose = statusPurpose
        self.statusListIndex = statusListIndex
        self.statusListCredential = statusListCredential
    }
}

// MARK: - Data Integrity Proof

public struct WalletDataIntegrityProof: Codable, Equatable {
    public let type: String
    public let cryptosuite: String
    public let created: String
    public let verificationMethod: String
    public let proofPurpose: String
    public let proofValue: String

    public init(
        type: String = "DataIntegrityProof",
        cryptosuite: String = "eddsa-rdfc-2022",
        created: String,
        verificationMethod: String,
        proofPurpose: String = "assertionMethod",
        proofValue: String
    ) {
        self.type = type
        self.cryptosuite = cryptosuite
        self.created = created
        self.verificationMethod = verificationMethod
        self.proofPurpose = proofPurpose
        self.proofValue = proofValue
    }
}

// MARK: - Stored Credential (wrapper with metadata)

public struct StoredWalletCredential: Codable, Equatable {
    public let id: String
    public let credential: WalletCredential
    public let storedAt: String
    public let issuerDID: String
    public let subjectName: String
    public let expiresAt: String

    public init(
        id: String,
        credential: WalletCredential,
        storedAt: String,
        issuerDID: String,
        subjectName: String,
        expiresAt: String
    ) {
        self.id = id
        self.credential = credential
        self.storedAt = storedAt
        self.issuerDID = issuerDID
        self.subjectName = subjectName
        self.expiresAt = expiresAt
    }
}

// MARK: - Verifiable Presentation

public struct WalletPresentation: Codable, Equatable {
    public let context: [String]
    public let type: [String]
    public let holder: String?
    public let verifiableCredential: [WalletCredential]
    public let created: String
    public let audience: String?
    public let challenge: String?

    enum CodingKeys: String, CodingKey {
        case context = "@context"
        case type, holder, verifiableCredential, created, audience, challenge
    }

    public init(
        context: [String] = ["https://www.w3.org/ns/credentials/v2"],
        type: [String] = ["VerifiablePresentation"],
        holder: String? = nil,
        verifiableCredential: [WalletCredential],
        created: String,
        audience: String? = nil,
        challenge: String? = nil
    ) {
        self.context = context
        self.type = type
        self.holder = holder
        self.verifiableCredential = verifiableCredential
        self.created = created
        self.audience = audience
        self.challenge = challenge
    }
}

// MARK: - Errors

public enum WalletError: Error, LocalizedError {
    case storageFailed
    case credentialNotFound
    case credentialExpired
    case encodingFailed
    case decodingFailed
    case invalidDisclosureProfile

    public var errorDescription: String? {
        switch self {
        case .storageFailed: return "Failed to store credential in Keychain."
        case .credentialNotFound: return "Credential not found."
        case .credentialExpired: return "Credential has expired."
        case .encodingFailed: return "Failed to encode credential data."
        case .decodingFailed: return "Failed to decode credential data."
        case .invalidDisclosureProfile: return "Invalid disclosure profile."
        }
    }
}
