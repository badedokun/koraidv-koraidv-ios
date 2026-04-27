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

    /// Result page mode (REQ-005). In `.simplified` mode the SDK shows only
    /// Success / Failed / Review with no scores or per-check metrics.
    /// Overrides the tenant-level `result_page_mode` setting when set.
    public var resultPageMode: ResultPageMode

    /// Optional per-outcome copy overrides for the simplified result page.
    public var customMessages: ResultPageMessages?

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
        self.resultPageMode = .detailed
        self.customMessages = nil
    }
}

// MARK: - Result Page Mode

/// Controls how the end-user-facing result page is rendered (REQ-005).
public enum ResultPageMode: String {
    /// Full breakdown with scores, per-check metrics, and risk band.
    case detailed
    /// Only Success / Failed / Review with no scores or metrics.
    case simplified
}

/// Optional per-outcome copy overrides for the simplified result page.
/// Any nil value falls back to the SDK's built-in default text.
public struct ResultPageMessages {
    public var successTitle: String?
    public var successMessage: String?
    public var failedTitle: String?
    public var failedMessage: String?
    public var reviewTitle: String?
    public var reviewMessage: String?

    public init(
        successTitle: String? = nil,
        successMessage: String? = nil,
        failedTitle: String? = nil,
        failedMessage: String? = nil,
        reviewTitle: String? = nil,
        reviewMessage: String? = nil
    ) {
        self.successTitle = successTitle
        self.successMessage = successMessage
        self.failedTitle = failedTitle
        self.failedMessage = failedMessage
        self.reviewTitle = reviewTitle
        self.reviewMessage = reviewMessage
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
            return URL(string: "https://api.korastratum.com/api/v1/idv")!
        case .sandbox:
            return URL(string: "https://api.korastratum.com/api/v1/idv")!
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

    // Passport (covers all 197 ICAO-compliant countries)
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
    case canadaPRCard = "ca_pr_card"
    case canadaNationalID = "ca_national_id"

    // India
    case indiaDriversLicense = "in_drivers_license"

    // Liberia
    case lrId = "lr_id"
    case lrDriversLicense = "lr_drivers_license"
    case lrVotersCard = "lr_voters_card"

    // Sierra Leone
    case slId = "sl_id"
    case slDriversLicense = "sl_drivers_license"
    case slVotersCard = "sl_voters_card"

    // Gambia
    case gmId = "gm_id"
    case gmDriversLicense = "gm_drivers_license"

    // Nigeria (additional)
    case ngVotersCard = "ng_voters_card"

    // UK (additional)
    case ukBrp = "uk_brp"

    // EU/EEA Residence Permits
    case deRp = "de_rp"
    case frRp = "fr_rp"
    case itRp = "it_rp"
    case esRp = "es_rp"
    case ieRp = "ie_rp"
    case ptRp = "pt_rp"
    case seRp = "se_rp"
    case dkRp = "dk_rp"
    case noRp = "no_rp"
    case fiRp = "fi_rp"
    case plRp = "pl_rp"

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
        case .canadaPRCard: return "Permanent Resident Card"
        case .canadaNationalID: return "National Identity Card"
        case .indiaDriversLicense: return "Driver's License"
        case .lrId: return "National ID (Liberia)"
        case .lrDriversLicense: return "Driver's License (Liberia)"
        case .lrVotersCard: return "Voter's Card (Liberia)"
        case .slId: return "National ID (Sierra Leone)"
        case .slDriversLicense: return "Driver's License (Sierra Leone)"
        case .slVotersCard: return "Voter's Card (Sierra Leone)"
        case .gmId: return "National ID (Gambia)"
        case .gmDriversLicense: return "Driver's License (Gambia)"
        case .ngVotersCard: return "Voter's Card (Nigeria)"
        case .ukBrp: return "Biometric Residence Permit"
        case .deRp: return "Residence Permit (Germany)"
        case .frRp: return "Residence Permit (France)"
        case .itRp: return "Residence Permit (Italy)"
        case .esRp: return "Residence Permit (Spain)"
        case .ieRp: return "Residence Permit (Ireland)"
        case .ptRp: return "Residence Permit (Portugal)"
        case .seRp: return "Residence Permit (Sweden)"
        case .dkRp: return "Residence Permit (Denmark)"
        case .noRp: return "Residence Permit (Norway)"
        case .fiRp: return "Residence Permit (Finland)"
        case .plRp: return "Residence Permit (Poland)"
        }
    }

    /// Whether this document type has MRZ
    public var hasMRZ: Bool {
        switch self {
        case .internationalPassport:
            return true
        case .euIdGermany, .euIdFrance, .euIdSpain, .euIdItaly:
            return true
        case .canadaPRCard, .canadaNationalID:
            return true
        case .ukBrp:
            return true
        case .deRp, .frRp, .itRp, .esRp, .ieRp, .ptRp, .seRp, .dkRp, .noRp, .fiRp, .plRp:
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
             .canadaPRCard, .indiaDriversLicense:
            return true
        case .lrId, .lrDriversLicense, .slId, .slDriversLicense, .gmId, .gmDriversLicense:
            return true
        case .ukBrp:
            return true
        case .deRp, .frRp, .itRp, .esRp, .ieRp, .ptRp, .seRp, .dkRp, .noRp, .fiRp, .plRp:
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
