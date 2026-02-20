import XCTest
@testable import KoraIDV

final class ValidationErrorParsingTests: XCTestCase {

    // MARK: - ValidationError Struct

    func testValidationErrorFieldAndMessage() {
        let error = ValidationError(field: "email", message: "is required")
        XCTAssertEqual(error.field, "email")
        XCTAssertEqual(error.message, "is required")
    }

    func testValidationErrorDecoding() throws {
        let json = """
        {"field": "name", "message": "too short"}
        """.data(using: .utf8)!

        let error = try JSONDecoder().decode(ValidationError.self, from: json)
        XCTAssertEqual(error.field, "name")
        XCTAssertEqual(error.message, "too short")
    }

    // MARK: - APIErrorResponse (Format 1)

    func testFormat1DecodingWithErrors() throws {
        let json = """
        {
            "message": "Validation failed",
            "errors": [
                {"field": "email", "message": "is invalid"},
                {"field": "name", "message": "is required"}
            ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(APIErrorResponse.self, from: json)
        XCTAssertEqual(response.message, "Validation failed")
        XCTAssertEqual(response.errors?.count, 2)
        XCTAssertEqual(response.errors?[0].field, "email")
        XCTAssertEqual(response.errors?[1].field, "name")
    }

    func testFormat1DecodingWithNilErrors() throws {
        let json = """
        {"message": "Something went wrong"}
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(APIErrorResponse.self, from: json)
        XCTAssertEqual(response.message, "Something went wrong")
        XCTAssertNil(response.errors)
    }

    func testFormat1DecodingWithEmptyErrors() throws {
        let json = """
        {"message": "Validation failed", "errors": []}
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(APIErrorResponse.self, from: json)
        XCTAssertEqual(response.errors?.count, 0)
    }

    // MARK: - KoraError.validationError Integration

    func testKoraValidationErrorWithFieldErrors() {
        let errors = [
            ValidationError(field: "email", message: "is invalid"),
            ValidationError(field: "phone", message: "too short")
        ]
        let error = KoraError.validationError(errors)
        XCTAssertEqual(error.errorCode, "VALIDATION_ERROR")

        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("email"))
        XCTAssertTrue(desc.contains("is invalid"))
        XCTAssertTrue(desc.contains("phone"))
    }

    func testKoraValidationErrorWithNilErrors() {
        let error = KoraError.validationError(nil)
        XCTAssertEqual(error.errorCode, "VALIDATION_ERROR")
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("Validation error"))
    }

    func testKoraValidationErrorWithEmptyErrors() {
        let error = KoraError.validationError([])
        XCTAssertEqual(error.errorCode, "VALIDATION_ERROR")
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("Validation error"))
    }

    // MARK: - Multiple ValidationError Formatting

    func testMultipleFieldErrorsFormattedAsCommaSeparated() {
        let errors = [
            ValidationError(field: "first_name", message: "cannot be blank"),
            ValidationError(field: "last_name", message: "cannot be blank"),
            ValidationError(field: "email", message: "is invalid")
        ]
        let error = KoraError.validationError(errors)
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("first_name"))
        XCTAssertTrue(desc.contains("last_name"))
        XCTAssertTrue(desc.contains("email"))
    }

    func testSingleFieldErrorFormatting() {
        let errors = [ValidationError(field: "document_type", message: "is not supported")]
        let error = KoraError.validationError(errors)
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("document_type"))
        XCTAssertTrue(desc.contains("is not supported"))
    }
}
