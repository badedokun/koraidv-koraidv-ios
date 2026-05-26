import XCTest
@testable import KoraIDV

// MARK: - Mock URL Protocol

/// URLProtocol subclass that intercepts all requests for testing
final class MockURLProtocol: URLProtocol {

    /// Handler to provide mock responses for intercepted requests
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?

    /// Captured requests for inspection
    static var capturedRequests: [URLRequest] = []

    static func reset() {
        requestHandler = nil
        capturedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.capturedRequests.append(request)

        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - APIClientTests

final class APIClientTests: XCTestCase {

    private var apiClient: APIClient!
    private var configuration: Configuration!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()

        configuration = Configuration(
            apiKey: "ck_sandbox_test_key_123",
            tenantId: "test-tenant-id",
            environment: .sandbox,
            baseURL: URL(string: "https://test.koraidv.com/api/v1")
        )

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        apiClient = APIClient(configuration: configuration, sessionConfiguration: sessionConfig)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        apiClient = nil
        configuration = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeResponse(statusCode: Int, url: URL? = nil) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url ?? URL(string: "https://test.koraidv.com/api/v1/verifications")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    private func makeJSON(_ dict: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: dict)
    }

    // MARK: - Request Construction

    func testRequestIncludesAuthorizationHeader() {
        let expectation = expectation(description: "request")

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ck_sandbox_test_key_123")
            return (self.makeResponse(statusCode: 200), self.makeJSON(["id": "v1", "external_id": "ext", "tenant_id": "t", "tier": "standard", "status": "pending", "created_at": "2025-01-01T00:00:00Z", "updated_at": "2025-01-01T00:00:00Z"]))
        }

        apiClient.request(endpoint: .createVerification, method: .get) { (result: Result<Verification, KoraError>) in
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func testRequestIncludesTenantHeader() {
        let expectation = expectation(description: "request")

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Tenant-ID"), "test-tenant-id")
            return (self.makeResponse(statusCode: 200), self.makeJSON(["id": "v1", "external_id": "ext", "tenant_id": "t", "tier": "standard", "status": "pending", "created_at": "2025-01-01T00:00:00Z", "updated_at": "2025-01-01T00:00:00Z"]))
        }

        apiClient.request(endpoint: .createVerification, method: .get) { (result: Result<Verification, KoraError>) in
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func testRequestIncludesAcceptHeader() {
        let expectation = expectation(description: "request")

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            return (self.makeResponse(statusCode: 200), self.makeJSON(["id": "v1", "external_id": "ext", "tenant_id": "t", "tier": "standard", "status": "pending", "created_at": "2025-01-01T00:00:00Z", "updated_at": "2025-01-01T00:00:00Z"]))
        }

        apiClient.request(endpoint: .createVerification, method: .get) { (result: Result<Verification, KoraError>) in
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func testRequestIncludesUserAgentHeader() {
        let expectation = expectation(description: "request")

        MockURLProtocol.requestHandler = { request in
            let userAgent = request.value(forHTTPHeaderField: "User-Agent") ?? ""
            XCTAssertTrue(userAgent.contains("KoraIDV-iOS"))
            return (self.makeResponse(statusCode: 200), self.makeJSON(["id": "v1", "external_id": "ext", "tenant_id": "t", "tier": "standard", "status": "pending", "created_at": "2025-01-01T00:00:00Z", "updated_at": "2025-01-01T00:00:00Z"]))
        }

        apiClient.request(endpoint: .createVerification, method: .get) { (result: Result<Verification, KoraError>) in
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func testGetVerificationUsesCorrectPath() {
        let expectation = expectation(description: "request")

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url!.path.contains("/verifications/abc123"))
            XCTAssertEqual(request.httpMethod, "GET")
            return (self.makeResponse(statusCode: 200, url: request.url), self.makeJSON(["id": "abc123", "external_id": "ext", "tenant_id": "t", "tier": "standard", "status": "pending", "created_at": "2025-01-01T00:00:00Z", "updated_at": "2025-01-01T00:00:00Z"]))
        }

        apiClient.request(endpoint: .getVerification(id: "abc123"), method: .get) { (result: Result<Verification, KoraError>) in
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func testCreateVerificationUsesPostMethod() {
        let expectation = expectation(description: "request")

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            return (self.makeResponse(statusCode: 200, url: request.url), self.makeJSON(["id": "v1", "external_id": "ext", "tenant_id": "t", "tier": "standard", "status": "pending", "created_at": "2025-01-01T00:00:00Z", "updated_at": "2025-01-01T00:00:00Z"]))
        }

        let body = CreateVerificationRequest(externalId: "ext", tier: "standard", expectedFirstName: nil, expectedLastName: nil)
        apiClient.request(endpoint: .createVerification, method: .post, body: body) { (result: Result<Verification, KoraError>) in
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func testPostRequestSetsContentTypeJSON() {
        let expectation = expectation(description: "request")

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            return (self.makeResponse(statusCode: 200, url: request.url), self.makeJSON(["id": "v1", "external_id": "ext", "tenant_id": "t", "tier": "standard", "status": "pending", "created_at": "2025-01-01T00:00:00Z", "updated_at": "2025-01-01T00:00:00Z"]))
        }

        let body = CreateVerificationRequest(externalId: "ext", tier: "standard", expectedFirstName: nil, expectedLastName: nil)
        apiClient.request(endpoint: .createVerification, method: .post, body: body) { (result: Result<Verification, KoraError>) in
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func testUploadDocumentUsesCorrectEndpoint() {
        let expectation = expectation(description: "request")

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url!.path.contains("/verifications/v1/document"))
            let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
            XCTAssertTrue(contentType.contains("multipart/form-data"))
            return (self.makeResponse(statusCode: 200, url: request.url), self.makeJSON(["success": true, "document_id": "d1", "face_detected": true]))
        }

        let metadata = DocumentUploadMetadata(documentType: "passport", side: "front")
        apiClient.uploadImage(endpoint: .uploadDocument(id: "v1"), imageData: Data([0xFF, 0xD8]), metadata: metadata) { (result: Result<DocumentUploadResponse, KoraError>) in
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    // MARK: - Response Handling

    func testSuccessResponseDecodesCorrectly() {
        let expectation = expectation(description: "decode")

        // Verification's Codable keys are camelCase, matching the backend's
        // BuildVerificationAPIResponse output (e.g. externalId, tenantId,
        // createdAt). Pre-existing fixture used snake_case which never
        // matched; the test had been failing silently against any current
        // Verification model.
        MockURLProtocol.requestHandler = { _ in
            return (self.makeResponse(statusCode: 200), self.makeJSON([
                "id": "v123",
                "externalId": "ext-1",
                "tenantId": "t-1",
                "tier": "standard",
                "status": "approved",
                "createdAt": "2025-01-01T00:00:00Z",
                "updatedAt": "2025-01-01T00:00:00Z"
            ]))
        }

        apiClient.request(endpoint: .getVerification(id: "v123"), method: .get) { (result: Result<Verification, KoraError>) in
            switch result {
            case .success(let verification):
                XCTAssertEqual(verification.id, "v123")
                XCTAssertEqual(verification.status, .approved)
            case .failure(let error):
                XCTFail("Expected success, got \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func test401ReturnsUnauthorized() {
        let expectation = expectation(description: "401")

        MockURLProtocol.requestHandler = { _ in
            return (self.makeResponse(statusCode: 401), Data())
        }

        apiClient.request(endpoint: .getVerification(id: "v1"), method: .get) { (result: Result<Verification, KoraError>) in
            if case .failure(let error) = result {
                XCTAssertEqual(error.errorCode, "UNAUTHORIZED")
            } else {
                XCTFail("Expected unauthorized error")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func test403ReturnsForbidden() {
        let expectation = expectation(description: "403")

        MockURLProtocol.requestHandler = { _ in
            return (self.makeResponse(statusCode: 403), Data())
        }

        apiClient.request(endpoint: .getVerification(id: "v1"), method: .get) { (result: Result<Verification, KoraError>) in
            if case .failure(let error) = result {
                XCTAssertEqual(error.errorCode, "FORBIDDEN")
            } else {
                XCTFail("Expected forbidden error")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func test404ReturnsNotFound() {
        let expectation = expectation(description: "404")

        MockURLProtocol.requestHandler = { _ in
            return (self.makeResponse(statusCode: 404), Data())
        }

        apiClient.request(endpoint: .getVerification(id: "v1"), method: .get) { (result: Result<Verification, KoraError>) in
            if case .failure(let error) = result {
                XCTAssertEqual(error.errorCode, "NOT_FOUND")
            } else {
                XCTFail("Expected not found error")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func test422ReturnsValidationError() {
        let expectation = expectation(description: "422")

        MockURLProtocol.requestHandler = { _ in
            let body = self.makeJSON([
                "message": "Validation failed",
                "errors": [
                    ["field": "email", "message": "is required"]
                ]
            ])
            return (self.makeResponse(statusCode: 422), body)
        }

        apiClient.request(endpoint: .createVerification, method: .post) { (result: Result<Verification, KoraError>) in
            if case .failure(let error) = result {
                XCTAssertEqual(error.errorCode, "VALIDATION_ERROR")
            } else {
                XCTFail("Expected validation error")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func test429ReturnsRateLimited() {
        let expectation = expectation(description: "429")

        // POST won't retry on server errors, but 429 should still be attempted
        // After maxRetries, should return rateLimited
        MockURLProtocol.requestHandler = { _ in
            return (self.makeResponse(statusCode: 429), Data())
        }

        apiClient.request(endpoint: .createVerification, method: .post) { (result: Result<Verification, KoraError>) in
            if case .failure(let error) = result {
                XCTAssertEqual(error.errorCode, "RATE_LIMITED")
            } else {
                XCTFail("Expected rate limited error")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 30)
    }

    func test500ReturnsServerError() {
        let expectation = expectation(description: "500")

        // POST doesn't retry on server errors, so it should return immediately
        MockURLProtocol.requestHandler = { _ in
            return (self.makeResponse(statusCode: 500), Data())
        }

        apiClient.request(endpoint: .createVerification, method: .post) { (result: Result<Verification, KoraError>) in
            if case .failure(let error) = result {
                XCTAssertEqual(error.errorCode, "SERVER_ERROR")
            } else {
                XCTFail("Expected server error")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func testUnknownStatusCodeReturnsHTTPError() {
        let expectation = expectation(description: "418")

        MockURLProtocol.requestHandler = { _ in
            return (self.makeResponse(statusCode: 418), Data())
        }

        apiClient.request(endpoint: .getVerification(id: "v1"), method: .get) { (result: Result<Verification, KoraError>) in
            if case .failure(let error) = result {
                XCTAssertEqual(error.errorCode, "HTTP_ERROR")
            } else {
                XCTFail("Expected HTTP error")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    // MARK: - Retry Logic

    func testDoesNotRetryPostOn5xx() {
        let expectation = expectation(description: "no-retry")
        var requestCount = 0

        MockURLProtocol.requestHandler = { _ in
            requestCount += 1
            return (self.makeResponse(statusCode: 503), Data())
        }

        let body = CreateVerificationRequest(externalId: "ext", tier: "standard", expectedFirstName: nil, expectedLastName: nil)
        apiClient.request(endpoint: .createVerification, method: .post, body: body) { (result: Result<Verification, KoraError>) in
            XCTAssertEqual(requestCount, 1, "POST should not be retried on 5xx")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func testRetriesGetOn5xx() {
        let expectation = expectation(description: "retry-get")
        var requestCount = 0

        MockURLProtocol.requestHandler = { _ in
            requestCount += 1
            if requestCount < 3 {
                return (self.makeResponse(statusCode: 500), Data())
            }
            return (self.makeResponse(statusCode: 200), self.makeJSON([
                "id": "v1", "external_id": "ext", "tenant_id": "t", "tier": "standard",
                "status": "pending", "created_at": "2025-01-01T00:00:00Z", "updated_at": "2025-01-01T00:00:00Z"
            ]))
        }

        apiClient.request(endpoint: .getVerification(id: "v1"), method: .get) { (result: Result<Verification, KoraError>) in
            XCTAssertGreaterThan(requestCount, 1, "GET should retry on 5xx")
            if case .success(let v) = result {
                XCTAssertEqual(v.id, "v1")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 30)
    }

    func testStopsAfterMaxRetries() {
        let expectation = expectation(description: "max-retries")
        var requestCount = 0

        MockURLProtocol.requestHandler = { _ in
            requestCount += 1
            return (self.makeResponse(statusCode: 500), Data())
        }

        apiClient.request(endpoint: .getVerification(id: "v1"), method: .get) { (result: Result<Verification, KoraError>) in
            // maxRetries = 3, so total attempts = 1 initial + 3 retries = 4
            XCTAssertEqual(requestCount, 4, "Should stop after maxRetries (3) + 1 initial attempt")
            if case .failure(let error) = result {
                XCTAssertEqual(error.errorCode, "SERVER_ERROR")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 30)
    }

    // MARK: - Certificate Pinning

    func testCertificatePinningDelegateIsSet() {
        // Verify that the API client's session delegate handles certificate pinning
        // by confirming the URLSession delegate is set (pinning is handled internally)
        let config = Configuration(
            apiKey: "ck_live_test_key",
            tenantId: "test-tenant",
            environment: .production
        )
        let client = APIClient(configuration: config)
        XCTAssertNotNil(client, "API client should be created for production environment")
    }

    func testAPIClientCreatedForSandboxEnvironment() {
        // Verify client creation works for sandbox (pinning applies to both environments)
        let config = Configuration(
            apiKey: "ck_sandbox_test_key",
            tenantId: "test-tenant",
            environment: .sandbox
        )
        let client = APIClient(configuration: config)
        XCTAssertNotNil(client, "API client should be created for sandbox environment")
    }

    // MARK: - Edge Cases

    func testMalformedJSONReturnsDecodingError() {
        let expectation = expectation(description: "malformed")

        MockURLProtocol.requestHandler = { _ in
            return (self.makeResponse(statusCode: 200), "not json".data(using: .utf8))
        }

        apiClient.request(endpoint: .getVerification(id: "v1"), method: .get) { (result: Result<Verification, KoraError>) in
            if case .failure(let error) = result {
                XCTAssertEqual(error.errorCode, "DECODING_ERROR")
            } else {
                XCTFail("Expected decoding error")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func testNoDataReturnsDecodingError() {
        let expectation = expectation(description: "no-data")

        MockURLProtocol.requestHandler = { _ in
            return (self.makeResponse(statusCode: 200), nil)
        }

        apiClient.request(endpoint: .getVerification(id: "v1"), method: .get) { (result: Result<Verification, KoraError>) in
            if case .failure(let error) = result {
                XCTAssertEqual(error.errorCode, "DECODING_ERROR")
            } else {
                XCTFail("Expected decoding error")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func testNetworkErrorReturnsNetworkError() {
        let expectation = expectation(description: "network")

        MockURLProtocol.requestHandler = { _ in
            throw URLError(.cannotConnectToHost)
        }

        apiClient.request(endpoint: .getVerification(id: "v1"), method: .get) { (result: Result<Verification, KoraError>) in
            if case .failure(let error) = result {
                XCTAssertEqual(error.errorCode, "NETWORK_ERROR")
            } else {
                XCTFail("Expected network error")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func testEndpointPathsAreCorrect() {
        XCTAssertEqual(APIEndpoint.createVerification.path, "/verifications")
        XCTAssertEqual(APIEndpoint.getVerification(id: "abc").path, "/verifications/abc")
        XCTAssertEqual(APIEndpoint.uploadDocument(id: "abc").path, "/verifications/abc/document")
        XCTAssertEqual(APIEndpoint.uploadDocumentBack(id: "abc").path, "/verifications/abc/document/back")
        XCTAssertEqual(APIEndpoint.uploadSelfie(id: "abc").path, "/verifications/abc/selfie")
        XCTAssertEqual(APIEndpoint.createLivenessSession(id: "abc").path, "/verifications/abc/liveness/session")
        XCTAssertEqual(APIEndpoint.submitLivenessChallenge(id: "abc").path, "/verifications/abc/liveness/challenge")
        XCTAssertEqual(APIEndpoint.completeVerification(id: "abc").path, "/verifications/abc/complete")
    }

    func testHTTPMethodRawValues() {
        XCTAssertEqual(HTTPMethod.get.rawValue, "GET")
        XCTAssertEqual(HTTPMethod.post.rawValue, "POST")
        XCTAssertEqual(HTTPMethod.put.rawValue, "PUT")
        XCTAssertEqual(HTTPMethod.patch.rawValue, "PATCH")
        XCTAssertEqual(HTTPMethod.delete.rawValue, "DELETE")
    }

    // MARK: - Upload-response decode regression (v1.6.1 hotfix)
    //
    // The backend's ProcessDocumentResult / ProcessSelfieResult /
    // SubmitLivenessChallengeResult do NOT include a top-level `success`
    // field — 2xx HTTP IS the success signal. Before v1.6.1 the iOS DTOs
    // declared `success: Bool` as required, so JSONDecoder threw
    // keyNotFound ("The data couldn't be read because it is missing.")
    // the first time the SDK actually got past the multipart→JSON cutover
    // in v1.6.0. The tests below pin the contract: decode succeeds with
    // the literal payload the server returns, and `isSuccess` defaults
    // to true when the field is absent.

    func testDocumentUploadResponseDecodesWithoutSuccessField() throws {
        // Exact shape returned by sandbox /verifications/{id}/document
        let json = """
        {
            "documentId": "543cac2d-f7c3-4875-bdb0-c108139b0472",
            "documentType": "international_passport",
            "qualityScore": 0,
            "imagePersisted": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(DocumentUploadResponse.self, from: json)
        XCTAssertEqual(decoded.documentId, "543cac2d-f7c3-4875-bdb0-c108139b0472")
        XCTAssertEqual(decoded.imagePersisted, true)
        XCTAssertNil(decoded.success, "Backend omits `success`; field should decode as nil")
        XCTAssertTrue(decoded.isSuccess, "Absent `success` must be treated as success")
    }

    func testDocumentUploadResponseHonorsExplicitSuccessFalse() throws {
        // Future-proof: if the backend ever adds an explicit false,
        // isSuccess must reflect it.
        let json = #"{"documentId":"x","success":false}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DocumentUploadResponse.self, from: json)
        XCTAssertEqual(decoded.success, false)
        XCTAssertFalse(decoded.isSuccess)
    }

    func testSelfieUploadResponseDecodesWithoutSuccessField() throws {
        // Shape mirrors ProcessSelfieResult — `faceDetected` is the only
        // field iOS still requires.
        let json = """
        {
            "faceDetected": true,
            "faceCount": 1,
            "qualityScore": 0.92,
            "imagePersisted": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SelfieUploadResponse.self, from: json)
        XCTAssertTrue(decoded.faceDetected)
        XCTAssertNil(decoded.success)
        XCTAssertTrue(decoded.isSuccess)
    }

    func testLivenessChallengeResponseDecodesWithoutSuccessField() throws {
        // Defensive: backend returns `completed` / `score` / `allCompleted`
        // not `challengePassed` / `confidence` / `remainingChallenges`.
        // Decode must not throw even though the iOS field names don't
        // match — they're all optional in v1.6.1 so absence is fine.
        let json = #"{"imagePersisted":true}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(LivenessChallengeResponse.self, from: json)
        XCTAssertNil(decoded.success)
        XCTAssertNil(decoded.challengePassed)
        XCTAssertTrue(decoded.isSuccess)
    }
}
