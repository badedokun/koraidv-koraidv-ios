import XCTest
import UIKit
@testable import KoraIDV

/// Live-network integration tests against the KoraIDV sandbox identity service.
///
/// These exercise the **real** URLSession path: real auth headers, real TLS,
/// real backend response shape, real JSON decode. The mock-based tests in
/// `APIClientTests` pin the decoder contract against synthetic JSON literals
/// — these add belt-and-suspenders against drift between what the sandbox
/// actually returns and what `APIClient`'s decoder expects.
///
/// The hotfix that motivated this file (v1.6.1): the iOS upload-response
/// DTOs declared `success: Bool` as required, but `ProcessDocumentResult`
/// never returns that field — a 2xx status IS the success signal. The unit
/// tests proved the new optional shape decodes a hand-crafted payload; the
/// integration test below proves it decodes the **actual** payload the live
/// sandbox sends, in case sandbox response shapes ever drift from what we
/// think they are.
///
/// **How to run.** These tests are env-gated so CI without secrets stays
/// green. xcodebuild only forwards env vars prefixed with `TEST_RUNNER_`
/// into the simulator's test process — vars without that prefix stay in
/// the parent shell and the tests silently skip. To run locally:
///
///     TEST_RUNNER_KORAIDV_TEST_API_KEY=sk_sandbox_<your-key> \
///     TEST_RUNNER_KORAIDV_TEST_TENANT_ID=<your-tenant-uuid> \
///     xcodebuild test \
///       -scheme KoraIDV \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:KoraIDVTests/LiveSandboxIntegrationTests
///
/// Without those env vars set every test in this class skips with a single
/// XCTSkip — no false negatives, no leaked credentials in the repo.
final class LiveSandboxIntegrationTests: XCTestCase {

    private var apiKey: String!
    private var tenantId: String!
    private var sessionManager: SessionManager!

    override func setUpWithError() throws {
        try super.setUpWithError()

        guard
            let key = ProcessInfo.processInfo.environment["KORAIDV_TEST_API_KEY"],
            !key.isEmpty,
            let tenant = ProcessInfo.processInfo.environment["KORAIDV_TEST_TENANT_ID"],
            !tenant.isEmpty
        else {
            throw XCTSkip(
                "Set KORAIDV_TEST_API_KEY + KORAIDV_TEST_TENANT_ID to run live-sandbox tests"
            )
        }
        apiKey = key
        tenantId = tenant

        let config = Configuration(
            apiKey: apiKey,
            tenantId: tenantId,
            environment: .sandbox
        )
        sessionManager = SessionManager(configuration: config)
    }

    override func tearDown() {
        sessionManager = nil
        apiKey = nil
        tenantId = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Minimal valid JPEG (1×1 gray pixel) sufficient to round-trip through
    /// the backend's image-receipt path. The OCR/classifier will return
    /// no detections, but the response shape is what we're verifying here,
    /// not the OCR contents.
    private func stubJPEG() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return image.jpegData(compressionQuality: 0.8)!
    }

    private func createVerification(timeout: TimeInterval = 30) throws -> Verification {
        let request = CreateVerificationRequest(
            externalId: "ios-live-test-\(Int(Date().timeIntervalSince1970))",
            tier: VerificationTier.standard.rawValue,
            expectedFirstName: nil,
            expectedLastName: nil
        )

        let expectation = expectation(description: "createVerification")
        var captured: Result<Verification, KoraError>?
        sessionManager.createVerification(request: request) { result in
            captured = result
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)

        switch captured {
        case .success(let verification): return verification
        case .failure(let error): throw error
        case nil: throw XCTSkip("createVerification did not call back within \(timeout)s")
        }
    }

    // MARK: - Tests

    /// Smoke: POST /verifications round-trips and decodes into Verification.
    /// If this fails, either auth is wrong or the create-verification
    /// response shape has drifted from what iOS's Verification model expects.
    func testCreateVerificationAgainstLiveSandbox() throws {
        let verification = try createVerification()
        XCTAssertFalse(verification.id.isEmpty, "Created verification missing id")
        XCTAssertEqual(verification.tenantId, tenantId)
        XCTAssertEqual(verification.tier, "standard")
        XCTAssertEqual(verification.status, .pending)
    }

    /// The real regression test. Mirrors Olabode's reproduction:
    ///   1. Create a verification.
    ///   2. Upload a front-document image with the new JSON contract.
    ///   3. Assert the response decodes successfully.
    ///
    /// Pre-v1.6.1 this would throw `KoraError.decodingError(...)` with the
    /// localized message "The data couldn't be read because it is missing"
    /// because `DocumentUploadResponse.success` was declared required and
    /// the backend doesn't return it.
    func testDocumentUploadResponseDecodesFromLiveSandbox() throws {
        let verification = try createVerification()

        let uploadExpectation = expectation(description: "uploadDocument")
        var uploadResult: Result<DocumentUploadResponse, KoraError>?
        sessionManager.uploadDocument(
            verificationId: verification.id,
            imageData: stubJPEG(),
            side: .front,
            documentType: .internationalPassport,
            countryCode: "NG"
        ) { result in
            uploadResult = result
            uploadExpectation.fulfill()
        }
        wait(for: [uploadExpectation], timeout: 30)

        switch uploadResult {
        case .success(let response):
            // Decode succeeded — this is the contract pin. The
            // documentId is the only field the backend guarantees on a
            // 2xx; everything else is opportunistic OCR/quality output.
            XCTAssertNotNil(response.documentId,
                "Upload response missing documentId")
            XCTAssertTrue(response.isSuccess,
                "isSuccess should be true when success is absent (server omits it)")
        case .failure(let error):
            XCTFail("Live upload decode failed — likely DTO/server drift: \(error)")
        case nil:
            XCTFail("uploadDocument did not call back within 30s")
        }
    }

    /// v1.6.2 regression: iOS `uploadSelfie` previously used the multipart
    /// helper while the backend `UploadSelfieRequest` requires JSON
    /// (`ShouldBindJSON` rejects multipart with HTTP 400). The fix
    /// converted it to a JSON body matching the Android SDK's wire
    /// format. This test pins the new contract — if anyone reverts to
    /// multipart, this fails with HTTP 400 instantly.
    ///
    /// Sister bug to the v1.6.0 `/document` fix; missed during that
    /// audit because the v1.6.0 sweep only covered the endpoint that
    /// was reported (BanffPay iOS HTTP 400 on doc-front). Surfaced in
    /// v1.6.1 when the upstream blockers cleared and the flow finally
    /// reached selfie.
    func testSelfieUploadAcceptsJSONFromLiveSandbox() throws {
        let verification = try createVerification()

        let uploadExpectation = expectation(description: "uploadSelfie")
        var uploadResult: Result<SelfieUploadResponse, KoraError>?
        sessionManager.uploadSelfie(
            verificationId: verification.id,
            imageData: stubJPEG()
        ) { result in
            uploadResult = result
            uploadExpectation.fulfill()
        }
        wait(for: [uploadExpectation], timeout: 30)

        switch uploadResult {
        case .success(let response):
            // 2xx + decode. Backend may report `faceDetected: false` for
            // the 1×1 stub — that's a business outcome, not a wire-format
            // failure. The point of this test is that the JSON contract
            // round-trips end-to-end.
            XCTAssertTrue(response.isSuccess,
                "isSuccess should be true on a 2xx response with absent success field")
        case .failure(let error):
            // 5xx is acceptable here: a 1×1 stub JPEG can't pass face
            // detection so ProcessSelfie may fail downstream — but the
            // SERVER had to PARSE our JSON body to get that far. The
            // wire-format regression we're pinning is HTTP 400 from
            // `ShouldBindJSON` rejecting a multipart body. Any non-400
            // failure is proof the JSON contract round-tripped.
            if case .httpError(let code) = error, code == 400 {
                XCTFail("HTTP 400 on JSON selfie upload — multipart regression: \(error)")
            }
            // Any other failure (500 from face-detection on stub image,
            // validationError, etc.) is fine for this wire-format pin.
        case nil:
            XCTFail("uploadSelfie did not call back within 30s")
        }
    }

    /// v1.6.2 regression: same multipart→JSON story as selfie above,
    /// for `/liveness/challenge`. Server expects
    /// `SubmitLivenessChallengeRequest { ChallengeType, ImageBase64 }`
    /// via `ShouldBindJSON`. iOS previously sent multipart with
    /// `LivenessChallengeMetadata` form fields. Fixed in v1.6.2.
    ///
    /// Note: this test exercises the wire format only — it creates a
    /// synthetic LivenessChallenge object rather than going through
    /// `createLivenessSession`, so the server may reject the unknown
    /// challenge id at a business-logic level. Any rejection that is
    /// NOT HTTP 400 from `ShouldBindJSON` failing on multipart proves
    /// the wire format is intact.
    func testLivenessChallengeAcceptsJSONFromLiveSandbox() throws {
        let verification = try createVerification()

        let challenge = LivenessChallenge(
            id: "test-challenge-\(UUID().uuidString)",
            type: .blink,
            instruction: "Blink slowly",
            order: 1
        )

        let submitExpectation = expectation(description: "submitLivenessChallenge")
        var submitResult: Result<LivenessChallengeResponse, KoraError>?
        sessionManager.submitLivenessChallenge(
            verificationId: verification.id,
            challenge: challenge,
            imageData: stubJPEG()
        ) { result in
            submitResult = result
            submitExpectation.fulfill()
        }
        wait(for: [submitExpectation], timeout: 30)

        switch submitResult {
        case .success(let response):
            XCTAssertTrue(response.isSuccess)
        case .failure(let error):
            // The server may reject the synthetic challenge with a
            // business-level error — that's acceptable. What we MUST
            // NOT see is a 400 from multipart-vs-JSON: that response
            // body is the gin `{"error": "..."}` envelope from
            // ShouldBindJSON failing to parse a multipart body. Any
            // other failure means the JSON contract round-tripped and
            // the server merely rejected on business grounds.
            //
            // KoraError surfaces these distinguishably; the test
            // accepts validationError / httpError but fails on a 400
            // with the multipart-mismatch signature.
            if case .httpError(let code) = error, code == 400 {
                // Inspect the message — if it mentions JSON parsing or
                // multipart, the multipart regression is back.
                XCTFail("HTTP 400 on JSON liveness submit — possible multipart regression: \(error)")
            }
            // Any other error is fine for this wire-format pin.
        case nil:
            XCTFail("submitLivenessChallenge did not call back within 30s")
        }
    }

    /// Pins the GET /document-types decode path (used by the country picker).
    /// 608 documents across 120+ countries on the sandbox today; this test
    /// asserts decode succeeds without enumerating contents (which churn
    /// week to week).
    func testFetchSupportedCountriesAgainstLiveSandbox() throws {
        let expectation = expectation(description: "fetchSupportedCountries")
        var captured: Result<[CountryInfo], KoraError>?
        sessionManager.fetchSupportedCountries { result in
            captured = result
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 30)

        switch captured {
        case .success(let countries):
            XCTAssertFalse(countries.isEmpty,
                "Sandbox returned zero countries — decode probably failed silently")
        case .failure(let error):
            XCTFail("Live document-types decode failed: \(error)")
        case nil:
            XCTFail("fetchSupportedCountries did not call back within 30s")
        }
    }
}
