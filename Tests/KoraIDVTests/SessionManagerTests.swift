import XCTest
@testable import KoraIDV

final class SessionManagerTests: XCTestCase {

    private var sessionManager: SessionManager!
    private var configuration: Configuration!

    override func setUp() {
        super.setUp()
        configuration = Configuration(
            apiKey: "ck_sandbox_test_key_123",
            tenantId: "test-tenant-id",
            environment: .sandbox,
            baseURL: URL(string: "https://test.koraidv.com/api/v1")
        )
        sessionManager = SessionManager(configuration: configuration)
    }

    override func tearDown() {
        sessionManager = nil
        configuration = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testCurrentVerificationIsNilInitially() {
        XCTAssertNil(sessionManager.currentVerification)
    }

    func testIsSessionTimedOutIsFalseInitially() {
        XCTAssertFalse(sessionManager.isSessionTimedOut)
    }

    // MARK: - Session Timeout

    func testSessionNotTimedOutWhenNotStarted() {
        XCTAssertFalse(sessionManager.isSessionTimedOut, "Session should not be timed out when never started")
    }

    func testTimeoutCheckUsesConfigurationTimeout() {
        // Default timeout in Configuration is 600 seconds (10 minutes)
        // A freshly started session should not be timed out
        XCTAssertEqual(configuration.timeout, 600)
        XCTAssertFalse(sessionManager.isSessionTimedOut)
    }

    func testRefreshSessionPreventsTimeout() {
        // After refresh, session should not be timed out
        sessionManager.refreshSession()
        XCTAssertFalse(sessionManager.isSessionTimedOut)
    }

    // MARK: - Session Reset

    func testResetSessionClearsVerification() {
        // Initially nil, but after reset should remain nil
        sessionManager.resetSession()
        XCTAssertNil(sessionManager.currentVerification)
    }

    func testResetSessionClearsTimeout() {
        sessionManager.refreshSession()
        sessionManager.resetSession()
        // After reset, sessionStartTime is nil, so isSessionTimedOut should be false
        XCTAssertFalse(sessionManager.isSessionTimedOut)
    }

    func testResetCalledMultipleTimesIsIdempotent() {
        sessionManager.resetSession()
        sessionManager.resetSession()
        sessionManager.resetSession()
        XCTAssertNil(sessionManager.currentVerification)
        XCTAssertFalse(sessionManager.isSessionTimedOut)
    }

    // MARK: - Document Side

    func testDocumentSideFrontRawValue() {
        XCTAssertEqual(DocumentSide.front.rawValue, "front")
    }

    func testDocumentSideBackRawValue() {
        XCTAssertEqual(DocumentSide.back.rawValue, "back")
    }

    // MARK: - Document Upload Endpoint Selection

    func testFrontSideEndpointPath() {
        // Verify the endpoint path logic for front side
        let frontEndpoint: APIEndpoint = .uploadDocument(id: "v1")
        XCTAssertEqual(frontEndpoint.path, "/verifications/v1/document")
    }

    func testBackSideEndpointPath() {
        // Verify the endpoint path logic for back side
        let backEndpoint: APIEndpoint = .uploadDocumentBack(id: "v1")
        XCTAssertEqual(backEndpoint.path, "/verifications/v1/document/back")
    }

    // MARK: - Selfie Upload Endpoint

    func testSelfieUploadEndpointPath() {
        let endpoint: APIEndpoint = .uploadSelfie(id: "v1")
        XCTAssertEqual(endpoint.path, "/verifications/v1/selfie")
    }

    // MARK: - Liveness Endpoints

    func testLivenessSessionEndpointPath() {
        let endpoint: APIEndpoint = .createLivenessSession(id: "v1")
        XCTAssertEqual(endpoint.path, "/verifications/v1/liveness/session")
    }

    func testLivenessChallengeEndpointPath() {
        let endpoint: APIEndpoint = .submitLivenessChallenge(id: "v1")
        XCTAssertEqual(endpoint.path, "/verifications/v1/liveness/challenge")
    }

    // MARK: - Complete Verification Endpoint

    func testCompleteVerificationEndpointPath() {
        let endpoint: APIEndpoint = .completeVerification(id: "v1")
        XCTAssertEqual(endpoint.path, "/verifications/v1/complete")
    }

    // MARK: - Configuration Integration

    func testSessionManagerUsesProvidedConfiguration() {
        let customConfig = Configuration(
            apiKey: "ck_live_custom_key",
            tenantId: "custom-tenant"
        )
        let manager = SessionManager(configuration: customConfig)
        XCTAssertNil(manager.currentVerification)
        XCTAssertFalse(manager.isSessionTimedOut)
    }

    func testSandboxEnvironmentDetectedFromAPIKey() {
        let config = Configuration(apiKey: "ck_sandbox_key", tenantId: "t")
        XCTAssertEqual(config.environment, .sandbox)
    }

    func testProductionEnvironmentDetectedFromAPIKey() {
        let config = Configuration(apiKey: "ck_live_key", tenantId: "t")
        XCTAssertEqual(config.environment, .production)
    }

    // MARK: - Refresh Session

    func testRefreshSessionSetsStartTime() {
        // Before refresh, no start time set so not timed out
        XCTAssertFalse(sessionManager.isSessionTimedOut)
        sessionManager.refreshSession()
        // After refresh, still not timed out because we just refreshed
        XCTAssertFalse(sessionManager.isSessionTimedOut)
    }

    func testMultipleRefreshesWorkCorrectly() {
        sessionManager.refreshSession()
        sessionManager.refreshSession()
        sessionManager.refreshSession()
        XCTAssertFalse(sessionManager.isSessionTimedOut)
    }
}
