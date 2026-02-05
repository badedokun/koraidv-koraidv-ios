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
    ///   - apiKey: Your API key (starts with ck_live_ or ck_sandbox_)
    ///   - tenantId: Your tenant ID (UUID)
    ///   - environment: API environment (auto-detected from API key if not specified)
    public init(
        apiKey: String,
        tenantId: String,
        environment: APIEnvironment? = nil
    ) {
        self.apiKey = apiKey
        self.tenantId = tenantId

        // Auto-detect environment from API key prefix
        if let env = environment {
            self.environment = env
        } else if apiKey.hasPrefix("ck_sandbox_") {
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
            return URL(string: "https://api.koraidv.com/api/v1")!
        case .sandbox:
            return URL(string: "https://sandbox-api.koraidv.com/api/v1")!
        }
    }
}

// MARK: - Document Types

/// Supported document types
public enum DocumentType: String, CaseIterable, Codable {
    // US Documents
    case usPassport = "us_passport"
    case usDriversLicense = "us_drivers_license"
    case usStateId = "us_state_id"

    // International
    case internationalPassport = "international_passport"
    case ukPassport = "uk_passport"

    // EU ID Cards
    case euIdGermany = "eu_id_de"
    case euIdFrance = "eu_id_fr"
    case euIdSpain = "eu_id_es"
    case euIdItaly = "eu_id_it"

    // Africa (Priority 2)
    case ghanaCard = "ghana_card"
    case nigeriaNin = "ng_nin"
    case kenyaId = "ke_id"
    case southAfricaId = "za_id"

    /// Display name for the document type
    public var displayName: String {
        switch self {
        case .usPassport: return "US Passport"
        case .usDriversLicense: return "US Driver's License"
        case .usStateId: return "US State ID"
        case .internationalPassport: return "International Passport"
        case .ukPassport: return "UK Passport"
        case .euIdGermany: return "German ID Card"
        case .euIdFrance: return "French ID Card"
        case .euIdSpain: return "Spanish ID Card"
        case .euIdItaly: return "Italian ID Card"
        case .ghanaCard: return "Ghana Card"
        case .nigeriaNin: return "Nigeria NIN"
        case .kenyaId: return "Kenya ID"
        case .southAfricaId: return "South Africa ID"
        }
    }

    /// Whether this document type has MRZ
    public var hasMRZ: Bool {
        switch self {
        case .usPassport, .internationalPassport, .ukPassport:
            return true
        case .euIdGermany, .euIdFrance, .euIdSpain, .euIdItaly:
            return true // Most EU IDs have MRZ
        default:
            return false
        }
    }

    /// Whether this document requires back capture
    public var requiresBack: Bool {
        switch self {
        case .usDriversLicense, .usStateId, .kenyaId:
            return true
        case .euIdGermany, .euIdFrance, .euIdSpain, .euIdItaly:
            return true // EU IDs typically need back
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
