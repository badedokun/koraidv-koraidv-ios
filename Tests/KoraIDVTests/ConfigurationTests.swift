import XCTest
@testable import KoraIDV

final class ConfigurationTests: XCTestCase {

    // MARK: - Environment Auto-Detection

    // v1.6.0 dropped legacy key prefixes; only `sk_sandbox_` auto-detects
    // sandbox now. Anything else (including the old `ck_sandbox_` /
    // `kora_sandbox_` formats) falls through to .production. These tests
    // pin that contract so a future revert can't quietly resurrect the
    // legacy detection.

    func testSandboxKeyPrefixSKDetectsSandbox() {
        let config = Configuration(apiKey: "sk_sandbox_abc123", tenantId: "tenant-1")
        XCTAssertEqual(config.environment, .sandbox)
    }

    func testLegacyCKSandboxPrefixNoLongerDetectsSandbox() {
        let config = Configuration(apiKey: "ck_sandbox_abc123", tenantId: "tenant-1")
        XCTAssertEqual(config.environment, .production,
            "Legacy ck_sandbox_ prefix was dropped in v1.6.0 and should now fall through to .production")
    }

    func testLegacyKoraSandboxPrefixNoLongerDetectsSandbox() {
        let config = Configuration(apiKey: "kora_sandbox_xyz789", tenantId: "tenant-1")
        XCTAssertEqual(config.environment, .production,
            "Legacy kora_sandbox_ prefix was dropped in v1.6.0 and should now fall through to .production")
    }

    func testLiveKeyPrefixCKDetectsProduction() {
        let config = Configuration(apiKey: "ck_live_abc123", tenantId: "tenant-1")
        XCTAssertEqual(config.environment, .production)
    }

    func testLiveKeyPrefixKoraDetectsProduction() {
        let config = Configuration(apiKey: "kora_live_xyz789", tenantId: "tenant-1")
        XCTAssertEqual(config.environment, .production)
    }

    func testUnknownPrefixDefaultsToProduction() {
        let config = Configuration(apiKey: "unknown_key_abc", tenantId: "tenant-1")
        XCTAssertEqual(config.environment, .production)
    }

    func testExplicitEnvironmentOverridesAutoDetection() {
        // Sandbox key but explicitly set to production
        let config = Configuration(
            apiKey: "ck_sandbox_abc123",
            tenantId: "tenant-1",
            environment: .production
        )
        XCTAssertEqual(config.environment, .production)
    }

    // MARK: - Base URL

    func testCustomHTTPSBaseURLIsUsed() {
        let customURL = URL(string: "https://custom.api.example.com/v1")!
        let config = Configuration(
            apiKey: "ck_live_abc123",
            tenantId: "tenant-1",
            baseURL: customURL
        )
        XCTAssertEqual(config.baseURL, customURL)
        XCTAssertEqual(config.resolvedBaseURL, customURL)
    }

    func testNilBaseURLFallsBackToEnvironmentURL() {
        let config = Configuration(apiKey: "ck_live_abc123", tenantId: "tenant-1")
        XCTAssertNil(config.baseURL)
        XCTAssertEqual(config.resolvedBaseURL, APIEnvironment.production.baseURL)
    }

    // MARK: - Defaults

    func testDefaultTimeoutIs600() {
        let config = Configuration(apiKey: "ck_live_abc123", tenantId: "tenant-1")
        XCTAssertEqual(config.timeout, 600)
    }

    func testDefaultLivenessModeIsActive() {
        let config = Configuration(apiKey: "ck_live_abc123", tenantId: "tenant-1")
        XCTAssertEqual(config.livenessMode, .active)
    }

    func testDebugLoggingDefaultsToFalse() {
        let config = Configuration(apiKey: "ck_live_abc123", tenantId: "tenant-1")
        XCTAssertFalse(config.debugLogging)
    }

    func testDefaultDocumentTypesContainsAllCases() {
        let config = Configuration(apiKey: "ck_live_abc123", tenantId: "tenant-1")
        let allCases = DocumentType.allCases
        XCTAssertEqual(config.documentTypes.count, allCases.count)
        for docType in allCases {
            XCTAssertTrue(config.documentTypes.contains(docType), "Missing document type: \(docType)")
        }
    }

    // MARK: - DocumentType Properties

    func testInternationalPassportHasMRZ() {
        XCTAssertTrue(DocumentType.internationalPassport.hasMRZ)
    }

    func testInternationalPassportDoesNotRequireBack() {
        XCTAssertFalse(DocumentType.internationalPassport.requiresBack)
    }

    func testUSDriversLicenseRequiresBack() {
        XCTAssertTrue(DocumentType.usDriversLicense.requiresBack)
    }

    func testUSDriversLicenseDoesNotHaveMRZ() {
        XCTAssertFalse(DocumentType.usDriversLicense.hasMRZ)
    }

    func testDisplayNameIsNonEmptyForAllTypes() {
        for docType in DocumentType.allCases {
            XCTAssertFalse(
                docType.displayName.isEmpty,
                "\(docType) should have a non-empty displayName"
            )
        }
    }

    func testAllDocumentTypesCountIs42() {
        // 42 ICAO + national IDs + DLs + residence permits + voter cards
        // across US/EU/UK/Canada/Africa/India as of v1.6.x. Bump when adding
        // new countries to keep accidental enum drift visible.
        XCTAssertEqual(DocumentType.allCases.count, 42)
    }

    // MARK: - API Environment URLs

    func testProductionEnvironmentBaseURL() {
        // Raw-API-key IDV endpoint (idv.korastratum.com). NOT api.korastratum.com
        // — that is the console's JWT gateway and rejects raw SDK keys with 401.
        let url = APIEnvironment.production.baseURL
        XCTAssertEqual(url.absoluteString, "https://idv.korastratum.com/api/v1/idv")
    }

    func testSandboxEnvironmentBaseURL() {
        // Sandbox identity-service in the orokii-platform GCP project; must
        // mirror Android's Environment.SANDBOX exactly so cross-platform
        // testers see consistent behavior.
        let url = APIEnvironment.sandbox.baseURL
        XCTAssertEqual(url.absoluteString,
            "https://koraidv-identity-sandbox-626704085312.us-central1.run.app/api/v1")
    }
}
