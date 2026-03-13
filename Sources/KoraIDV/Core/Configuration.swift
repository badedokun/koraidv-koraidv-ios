import Foundation
import UIKit

/// SDK Configuration
public struct Configuration {

    // MARK: - Required Properties

    /// API key for authentication
    public let apiKey: String

    /// Tenant ID for multi-tenant support
    public let tenantId: String

    // MARK: - Optional Properties

    /// API environment
    public var environment: APIEnvironment

    /// Custom base URL override (e.g., for self-hosted or Cloud Run deployments)
    public var baseURL: URL?

    /// Resolved base URL: uses custom `baseURL` if provided, otherwise falls back to `environment` default.
    public var resolvedBaseURL: URL {
        baseURL ?? environment.baseURL
    }

    /// Allowed document types for verification
    public var documentTypes: [DocumentType]

    /// Liveness detection mode
    public var livenessMode: LivenessMode

    /// Custom theme for UI customization
    public var theme: KoraTheme

    /// Locale for localization
    public var locale: Locale

    /// Session timeout in seconds
    public var timeout: TimeInterval

    /// Enable debug logging
    public var debugLogging: Bool

    // MARK: - Initialization

    /// Initialize SDK configuration
    /// - Parameters:
    ///   - apiKey: Your API key (starts with ck_live_, ck_sandbox_, kora_live_, or kora_sandbox_)
    ///   - tenantId: Your tenant ID (UUID)
    ///   - environment: API environment (auto-detected from API key if not specified)
    ///   - baseURL: Custom base URL override (optional, overrides environment URL if provided)
    public init(
        apiKey: String,
        tenantId: String,
        environment: APIEnvironment? = nil,
        baseURL: URL? = nil
    ) {
        self.apiKey = apiKey
        self.tenantId = tenantId

        // Reject non-HTTPS custom base URLs to prevent credential leakage
        if let baseURL = baseURL {
            precondition(
                baseURL.scheme?.lowercased() == "https",
                "KoraIDV: baseURL must use HTTPS. Received: \(baseURL.absoluteString)"
            )
        }
        self.baseURL = baseURL

        // Auto-detect environment from API key prefix
        if let env = environment {
            self.environment = env
        } else if apiKey.hasPrefix("ck_sandbox_") || apiKey.hasPrefix("kora_sandbox_") {
            self.environment = .sandbox
        } else {
            self.environment = .production
        }

        // Set defaults
        self.documentTypes = DocumentType.allCases
        self.livenessMode = .active
        self.theme = KoraTheme()
        self.locale = Locale.current
        self.timeout = 600 // 10 minutes
        self.debugLogging = false
    }
}

// MARK: - Environment

/// API Environment
public enum APIEnvironment {
    case production
    case sandbox

    var baseURL: URL {
        switch self {
        case .production:
            return URL(string: "https://koraidv-identity-kendyplisq-uc.a.run.app/api/v1")!
        case .sandbox:
            return URL(string: "https://koraidv-identity-kendyplisq-uc.a.run.app/api/v1")!
        }
    }
}

// MARK: - Document Types

/// Supported document types.
///
/// Maintained for backward compatibility so that existing integrations that
/// reference specific cases (e.g. `DocumentType.internationalPassport`) continue
/// to compile. The SDK now fetches the canonical list of document types
/// dynamically from the API at runtime via `GET /document-types`. Any document
/// type returned by the API whose raw value does not match a case in this enum
/// is silently ignored, keeping the SDK forward-compatible when new types are
/// added on the backend.
public enum DocumentType: String, CaseIterable, Codable {
    // US Documents
    case usDriversLicense = "us_drivers_license"
    case usStateId = "us_state_id"
    case usGreenCard = "us_green_card"

    // Passport (all countries)
    case internationalPassport = "international_passport"

    // EU ID Cards
    case euIdGermany = "eu_id_de"
    case euIdFrance = "eu_id_fr"
    case euIdSpain = "eu_id_es"
    case euIdItaly = "eu_id_it"

    // Africa
    case ghanaCard = "ghana_card"
    case nigeriaNin = "ng_nin"
    case nigeriaDriversLicense = "ng_drivers_license"
    case ghanaDriversLicense = "gh_drivers_license"
    case kenyaId = "ke_id"
    case kenyaDriversLicense = "ke_drivers_license"
    case southAfricaId = "za_id"
    case southAfricaDriversLicense = "za_drivers_license"

    // UK
    case ukDriversLicense = "uk_drivers_license"

    // Canada
    case canadaDriversLicense = "ca_drivers_license"

    // India
    case indiaDriversLicense = "in_drivers_license"

    /// Display name for the document type
    public var displayName: String {
        switch self {
        case .usDriversLicense: return "Driver's License"
        case .usStateId: return "State ID Card"
        case .usGreenCard: return "Permanent Resident Card"
        case .internationalPassport: return "Passport"
        case .euIdGermany: return "National ID Card (Germany)"
        case .euIdFrance: return "National ID Card (France)"
        case .euIdSpain: return "National ID Card (Spain)"
        case .euIdItaly: return "National ID Card (Italy)"
        case .ghanaCard: return "Ghana Card"
        case .nigeriaNin: return "NIN Slip"
        case .nigeriaDriversLicense: return "Driver's License"
        case .ghanaDriversLicense: return "Driver's License"
        case .kenyaId: return "National ID"
        case .kenyaDriversLicense: return "Driver's License"
        case .southAfricaId: return "Smart ID Card"
        case .southAfricaDriversLicense: return "Driver's License"
        case .ukDriversLicense: return "Driver's License"
        case .canadaDriversLicense: return "Driver's License"
        case .indiaDriversLicense: return "Driver's License"
        }
    }

    /// Whether this document type has MRZ
    public var hasMRZ: Bool {
        switch self {
        case .internationalPassport:
            return true
        case .euIdGermany, .euIdFrance, .euIdSpain, .euIdItaly:
            return true
        default:
            return false
        }
    }

    /// Whether this document requires back capture
    public var requiresBack: Bool {
        switch self {
        case .usDriversLicense, .usStateId, .usGreenCard, .kenyaId:
            return true
        case .euIdGermany, .euIdFrance, .euIdSpain, .euIdItaly:
            return true
        case .ghanaCard, .southAfricaId:
            return true
        case .nigeriaDriversLicense, .ghanaDriversLicense, .kenyaDriversLicense,
             .southAfricaDriversLicense, .ukDriversLicense, .canadaDriversLicense,
             .indiaDriversLicense:
            return true
        default:
            return false
        }
    }
}

// MARK: - Liveness Mode

/// Liveness detection mode
public enum LivenessMode {
    /// Active liveness with challenge-response (blink, smile, turn)
    case active
    /// Passive liveness (single selfie analysis)
    case passive
}
