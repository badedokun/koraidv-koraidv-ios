import XCTest
@testable import KoraIDV

final class ConfigurationTests: XCTestCase {

    // MARK: - Environment Auto-Detection

    func testSandboxKeyPrefixCKDetectsSandbox() {
        let config = Configuration(apiKey: "ck_sandbox_abc123", tenantId: "tenant-1")
        XCTAssertEqual(config.environment, .sandbox)
    }

    func testSandboxKeyPrefixKoraDetectsSandbox() {
        let config = Configuration(apiKey: "kora_sandbox_xyz789", tenantId: "tenant-1")
        XCTAssertEqual(config.environment, .sandbox)
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

    func testAllDocumentTypesCountIs12() {
        XCTAssertEqual(DocumentType.allCases.count, 12)
    }

    // MARK: - API Environment URLs

    func testProductionEnvironmentBaseURL() {
        let url = APIEnvironment.production.baseURL
        XCTAssertEqual(url.absoluteString, "https://koraidv-identity-kendyplisq-uc.a.run.app/api/v1")
    }

    func testSandboxEnvironmentBaseURL() {
        let url = APIEnvironment.sandbox.baseURL
        XCTAssertEqual(url.absoluteString, "https://koraidv-identity-kendyplisq-uc.a.run.app/api/v1")
    }
}
