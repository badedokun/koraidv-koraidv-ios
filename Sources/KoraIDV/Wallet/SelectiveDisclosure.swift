// SelectiveDisclosure.swift
// KoraIDV Wallet — Selective disclosure profiles for Verifiable Presentations

import Foundation

// MARK: - Disclosure Profile

public enum DisclosureProfile: Equatable {
    case full
    case onboarding
    case ageOnly
    case nationalityOnly
    case verificationOnly
    case custom(Set<DisclosureClaim>)

    /// Machine-readable name for deep link encoding.
    public var name: String {
        switch self {
        case .full: return "full"
        case .onboarding: return "onboarding"
        case .ageOnly: return "ageOnly"
        case .nationalityOnly: return "nationalityOnly"
        case .verificationOnly: return "verificationOnly"
        case .custom: return "custom"
        }
    }
}

// MARK: - Disclosure Claims

public enum DisclosureClaim: String, CaseIterable, Hashable {
    case fullName
    case dateOfBirth
    case nationality
    case verificationLevel
    case documentType
    case documentCountry
    case biometricMatch
    case livenessCheck
    case governmentDbVerified
    case verifiedAt
    case confidenceScore
}

// MARK: - Selective Disclosure Engine

public struct SelectiveDisclosureEngine {

    /// Apply a disclosure profile to a credential, returning a new credential
    /// containing only the disclosed claims in its subject.
    public static func apply(
        profile: DisclosureProfile,
        to credential: WalletCredential
    ) -> WalletCredential {
        let claims: Set<DisclosureClaim>
        switch profile {
        case .full:
            claims = Set(DisclosureClaim.allCases)
        case .onboarding:
            claims = [.fullName, .dateOfBirth, .nationality, .verificationLevel, .documentType, .documentCountry]
        case .ageOnly:
            claims = [.dateOfBirth]
        case .nationalityOnly:
            claims = [.nationality]
        case .verificationOnly:
            claims = [.verificationLevel, .verifiedAt, .confidenceScore]
        case .custom(let selected):
            claims = selected
        }

        let subject = credential.credentialSubject
        let disclosed = WalletCredentialSubject(
            id: subject.id,
            fullName: claims.contains(.fullName) ? subject.fullName : "",
            dateOfBirth: claims.contains(.dateOfBirth) ? subject.dateOfBirth : nil,
            nationality: claims.contains(.nationality) ? subject.nationality : nil,
            verificationLevel: claims.contains(.verificationLevel) ? subject.verificationLevel : "",
            documentType: claims.contains(.documentType) ? subject.documentType : "",
            documentCountry: claims.contains(.documentCountry) ? subject.documentCountry : "",
            biometricMatch: claims.contains(.biometricMatch) ? subject.biometricMatch : false,
            livenessCheck: claims.contains(.livenessCheck) ? subject.livenessCheck : false,
            governmentDbVerified: claims.contains(.governmentDbVerified) ? subject.governmentDbVerified : false,
            verifiedAt: claims.contains(.verifiedAt) ? subject.verifiedAt : "",
            confidenceScore: claims.contains(.confidenceScore) ? subject.confidenceScore : 0.0
        )

        return WalletCredential(
            context: credential.context,
            id: credential.id,
            type: credential.type,
            issuer: credential.issuer,
            issuanceDate: credential.issuanceDate,
            expirationDate: credential.expirationDate,
            credentialSubject: disclosed,
            credentialStatus: credential.credentialStatus,
            proof: credential.proof
        )
    }

    /// For ageOnly profile, compute a derived claim.
    public static func computeAgeOver18(dateOfBirth: String?) -> Bool {
        guard let dob = dateOfBirth else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        guard let birthDate = formatter.date(from: dob)
            ?? DateFormatter.yyyyMMdd.date(from: dob) else {
            return false
        }
        let years = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
        return years >= 18
    }
}

// MARK: - DateFormatter helper

private extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
