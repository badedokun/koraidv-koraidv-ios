import XCTest
@testable import KoraIDV

final class KoraErrorTests: XCTestCase {

    // MARK: - Helpers

    /// All KoraError cases with representative associated values where needed.
    private var allErrorCases: [KoraError] {
        let sampleError = NSError(domain: "TestDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: "test error"])
        return [
            .notConfigured,
            .invalidAPIKey,
            .invalidTenantId,
            .networkError(sampleError),
            .timeout,
            .noInternet,
            .unauthorized,
            .forbidden,
            .notFound,
            .validationError(nil),
            .rateLimited,
            .serverError(500),
            .httpError(418),
            .invalidResponse,
            .noData,
            .decodingError(sampleError),
            .encodingError(sampleError),
            .cameraAccessDenied,
            .cameraNotAvailable,
            .captureFailed("lens blocked"),
            .qualityValidationFailed(["blurry", "too dark"]),
            .documentNotDetected,
            .documentTypeNotSupported,
            .mrzReadFailed,
            .faceNotDetected,
            .multipleFacesDetected,
            .faceMatchFailed,
            .livenessCheckFailed,
            .challengeNotCompleted("blink"),
            .sessionExpired,
            .verificationExpired,
            .verificationAlreadyCompleted,
            .invalidVerificationState("pending"),
            .unknown("something went wrong"),
            .userCancelled,
        ]
    }

    // MARK: - errorDescription

    func testErrorDescriptionIsNonNilForAllCases() {
        for error in allErrorCases {
            XCTAssertNotNil(
                error.errorDescription,
                "errorDescription should not be nil for \(error.errorCode)"
            )
        }
    }

    func testErrorDescriptionIsNonEmptyForAllCases() {
        for error in allErrorCases {
            let desc = error.errorDescription ?? ""
            XCTAssertFalse(
                desc.isEmpty,
                "errorDescription should not be empty for \(error.errorCode)"
            )
        }
    }

    // MARK: - errorCode Uniqueness

    func testAllErrorCodesAreUnique() {
        let codes = allErrorCases.map { $0.errorCode }
        let uniqueCodes = Set(codes)
        XCTAssertEqual(
            codes.count, uniqueCodes.count,
            "Duplicate error codes found: \(codes.filter { code in codes.filter({ $0 == code }).count > 1 })"
        )
    }

    // MARK: - errorCode Format (SCREAMING_SNAKE_CASE)

    func testErrorCodesAreScreamingSnakeCase() {
        let pattern = "^[A-Z][A-Z0-9]*(_[A-Z0-9]+)*$"
        let regex = try! NSRegularExpression(pattern: pattern)
        for error in allErrorCases {
            let code = error.errorCode
            let range = NSRange(code.startIndex..<code.endIndex, in: code)
            let match = regex.firstMatch(in: code, range: range)
            XCTAssertNotNil(
                match,
                "errorCode '\(code)' is not SCREAMING_SNAKE_CASE"
            )
        }
    }

    // MARK: - recoverySuggestion

    func testCameraAccessDeniedHasRecoverySuggestion() {
        XCTAssertNotNil(KoraError.cameraAccessDenied.recoverySuggestion)
    }

    func testNoInternetHasRecoverySuggestion() {
        XCTAssertNotNil(KoraError.noInternet.recoverySuggestion)
    }

    func testTimeoutHasRecoverySuggestion() {
        XCTAssertNotNil(KoraError.timeout.recoverySuggestion)
    }

    func testServerErrorHasRecoverySuggestion() {
        XCTAssertNotNil(KoraError.serverError(500).recoverySuggestion)
    }

    func testRateLimitedHasRecoverySuggestion() {
        XCTAssertNotNil(KoraError.rateLimited.recoverySuggestion)
    }

    func testDocumentNotDetectedHasRecoverySuggestion() {
        XCTAssertNotNil(KoraError.documentNotDetected.recoverySuggestion)
    }

    func testFaceNotDetectedHasRecoverySuggestion() {
        XCTAssertNotNil(KoraError.faceNotDetected.recoverySuggestion)
    }

    func testQualityValidationFailedHasRecoverySuggestion() {
        XCTAssertNotNil(KoraError.qualityValidationFailed(["blur"]).recoverySuggestion)
    }

    func testNotConfiguredHasNoRecoverySuggestion() {
        XCTAssertNil(KoraError.notConfigured.recoverySuggestion)
    }

    func testInvalidAPIKeyHasNoRecoverySuggestion() {
        XCTAssertNil(KoraError.invalidAPIKey.recoverySuggestion)
    }

    func testUnauthorizedHasNoRecoverySuggestion() {
        XCTAssertNil(KoraError.unauthorized.recoverySuggestion)
    }

    func testUserCancelledHasNoRecoverySuggestion() {
        XCTAssertNil(KoraError.userCancelled.recoverySuggestion)
    }

    // MARK: - code property

    func testCodeRawValueMatchesErrorCode() {
        for error in allErrorCases {
            XCTAssertEqual(
                error.code.rawValue, error.errorCode,
                "code.rawValue should match errorCode for \(error.errorCode)"
            )
        }
    }

    // MARK: - message property

    func testMessageMatchesErrorDescription() {
        for error in allErrorCases {
            let expected = error.errorDescription ?? "Unknown error"
            XCTAssertEqual(
                error.message, expected,
                "message should match errorDescription for \(error.errorCode)"
            )
        }
    }

    func testMessageIsNeverUnknownErrorForKnownCases() {
        for error in allErrorCases {
            // The .unknown case is allowed to have its custom message
            XCTAssertNotEqual(
                error.message, "Unknown error",
                "message should not be the fallback for \(error.errorCode)"
            )
        }
    }

    // MARK: - Specific errorCode Values

    func testNotConfiguredErrorCode() {
        XCTAssertEqual(KoraError.notConfigured.errorCode, "NOT_CONFIGURED")
    }

    func testNetworkErrorErrorCode() {
        let err = NSError(domain: "test", code: 0)
        XCTAssertEqual(KoraError.networkError(err).errorCode, "NETWORK_ERROR")
    }

    func testCameraAccessDeniedErrorCode() {
        XCTAssertEqual(KoraError.cameraAccessDenied.errorCode, "CAMERA_ACCESS_DENIED")
    }

    func testUserCancelledErrorCode() {
        XCTAssertEqual(KoraError.userCancelled.errorCode, "USER_CANCELLED")
    }

    // MARK: - Associated Values in errorDescription

    func testServerErrorIncludesStatusCodeInDescription() {
        let error = KoraError.serverError(503)
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("503"), "serverError description should include status code")
    }

    func testValidationErrorWithErrorsFormatsFieldMessages() {
        let validationErrors = [ValidationError(field: "email", message: "is invalid")]
        let error = KoraError.validationError(validationErrors)
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("email"), "Should contain field name")
        XCTAssertTrue(desc.contains("is invalid"), "Should contain error message")
    }
}
