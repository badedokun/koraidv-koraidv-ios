import XCTest
@testable import KoraIDV

final class MRZReaderTests: XCTestCase {

    private var reader: MRZReader!

    override func setUp() {
        super.setUp()
        reader = MRZReader()
    }

    override func tearDown() {
        reader = nil
        super.tearDown()
    }

    // MARK: - detectFormat Tests

    func testDetectFormatTD1() {
        // TD1 range: 91-92 chars
        XCTAssertEqual(reader.detectFormat(String(repeating: "A", count: 91)), .td1)
        XCTAssertEqual(reader.detectFormat(String(repeating: "A", count: 92)), .td1)
    }

    func testDetectFormatTD3() {
        // TD3 range: 86-90 chars (88 is canonical passport length)
        XCTAssertEqual(reader.detectFormat(String(repeating: "A", count: 86)), .td3)
        XCTAssertEqual(reader.detectFormat(String(repeating: "A", count: 88)), .td3)
        XCTAssertEqual(reader.detectFormat(String(repeating: "A", count: 90)), .td3)
    }

    func testDetectFormatTD2() {
        // TD2 range: 70-74 chars (72 is canonical)
        XCTAssertEqual(reader.detectFormat(String(repeating: "A", count: 70)), .td2)
        XCTAssertEqual(reader.detectFormat(String(repeating: "A", count: 72)), .td2)
        XCTAssertEqual(reader.detectFormat(String(repeating: "A", count: 74)), .td2)
    }

    func testDetectFormatReturnsNilForOutOfRange() {
        XCTAssertNil(reader.detectFormat(String(repeating: "A", count: 50)))
        XCTAssertNil(reader.detectFormat(String(repeating: "A", count: 75)))
        XCTAssertNil(reader.detectFormat(String(repeating: "A", count: 100)))
    }

    // MARK: - fixNumericOCR Tests

    func testFixNumericOCRReplacesOWithZero() {
        XCTAssertEqual(reader.fixNumericOCR("12O456"), "120456")
    }

    func testFixNumericOCRReplacesMultipleOs() {
        XCTAssertEqual(reader.fixNumericOCR("OO12OO"), "001200")
    }

    func testFixNumericOCRLeavesCorrectStringUnchanged() {
        XCTAssertEqual(reader.fixNumericOCR("123456"), "123456")
    }

    func testFixNumericOCRHandlesEmptyString() {
        XCTAssertEqual(reader.fixNumericOCR(""), "")
    }

    // MARK: - parseName Tests

    func testParseNameWithDoubleSeparator() {
        let result = reader.parseName("ERIKSSON<<ANNA<MARIA")
        XCTAssertEqual(result.lastName, "ERIKSSON")
        XCTAssertEqual(result.firstName, "ANNA MARIA")
    }

    func testParseNameWithTrailingFillers() {
        let result = reader.parseName("ERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<")
        XCTAssertEqual(result.lastName, "ERIKSSON")
        XCTAssertEqual(result.firstName, "ANNA MARIA")
    }

    func testParseNameSingleNameOnly() {
        let result = reader.parseName("SMITH<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<")
        XCTAssertEqual(result.lastName, "SMITH")
        XCTAssertEqual(result.firstName, "")
    }

    func testParseNameCompoundLastName() {
        let result = reader.parseName("DE<SOUZA<<MARIA<<<<<<<<<<<<<<<<<<<<<<<<")
        XCTAssertEqual(result.lastName, "DE SOUZA")
        XCTAssertEqual(result.firstName, "MARIA")
    }

    func testParseNameCompoundFirstName() {
        let result = reader.parseName("JOHNSON<<MARY<JANE<ANN<<<<<<<<<<<<<<<<<<")
        XCTAssertEqual(result.lastName, "JOHNSON")
        XCTAssertEqual(result.firstName, "MARY JANE ANN")
    }

    func testParseNameAllFillers() {
        let result = reader.parseName("<<<<<<<<<<<<<<<<<<<<")
        XCTAssertEqual(result.lastName, "")
        XCTAssertEqual(result.firstName, "")
    }

    // MARK: - validateCheckDigit Tests

    func testValidateCheckDigitCorrectForDocNumber() {
        // L898902C3: L=21; 21*7+8*3+9*1+8*7+9*3+0*1+2*7+12*3+3*1 = 316; 316%10 = 6
        XCTAssertTrue(reader.validateCheckDigit("L898902C3", check: "6"))
    }

    func testValidateCheckDigitCorrectForDOB() {
        // 740812: 7*7+4*3+0*1+8*7+1*3+2*1 = 122; 122%10 = 2
        XCTAssertTrue(reader.validateCheckDigit("740812", check: "2"))
    }

    func testValidateCheckDigitCorrectForExpiry() {
        // 120415: 1*7+2*3+0*1+4*7+1*3+5*1 = 49; 49%10 = 9
        XCTAssertTrue(reader.validateCheckDigit("120415", check: "9"))
    }

    func testValidateCheckDigitWrongDigitReturnsFalse() {
        XCTAssertFalse(reader.validateCheckDigit("L898902C3", check: "5"))
    }

    func testValidateCheckDigitFillerTreatedAsZero() {
        // All filler "<" = 0; sum = 0; 0%10 = 0; check "0" and check "<" both map to 0
        XCTAssertTrue(reader.validateCheckDigit("<<<", check: "0"))
        XCTAssertTrue(reader.validateCheckDigit("<<<", check: "<"))
    }

    func testValidateCheckDigitAllDigits() {
        // 520727: 5*7+2*3+0*1+7*7+2*3+7*1 = 103; 103%10 = 3
        XCTAssertTrue(reader.validateCheckDigit("520727", check: "3"))
    }

    func testValidateCheckDigitSingleLetter() {
        // A=10; 10*7 = 70; 70%10 = 0
        XCTAssertTrue(reader.validateCheckDigit("A", check: "0"))
    }

    // MARK: - parseMRZ / parseTD3 Tests

    func testParseTD3FullPassportMRZ() {
        let mrz = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<L898902C36UTO7408122F1204159ZE184226B<<<<<10"
        let result = reader.parseMRZ(mrz)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.format, .td3)
        XCTAssertEqual(result?.documentType, "P")
        XCTAssertEqual(result?.issuingCountry, "UTO")
        XCTAssertEqual(result?.lastName, "ERIKSSON")
        XCTAssertEqual(result?.firstName, "ANNA MARIA")
        XCTAssertEqual(result?.documentNumber, "L898902C3")
        XCTAssertEqual(result?.nationality, "UTO")
        XCTAssertEqual(result?.dateOfBirth, "740812")
        XCTAssertEqual(result?.sex, "F")
        XCTAssertEqual(result?.expirationDate, "120415")
        XCTAssertTrue(result?.isValid ?? false)
        XCTAssertEqual(result?.validationErrors.count, 0)
    }

    func testParseTD3OptionalDataPresent() {
        let mrz = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<L898902C36UTO7408122F1204159ZE184226B<<<<<10"
        let result = reader.parseMRZ(mrz)

        XCTAssertNotNil(result?.optionalData1)
    }

    func testParseTD3StripsSpacesAndNewlines() {
        let line1 = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<< "
        let line2 = "L898902C36UTO7408122F1204159ZE184226B<<<<<10"
        let mrz = line1 + "\n" + line2
        let result = reader.parseMRZ(mrz)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.format, .td3)
        XCTAssertEqual(result?.lastName, "ERIKSSON")
    }

    func testParseMRZReturnsNilForGarbage() {
        XCTAssertNil(reader.parseMRZ("HELLO WORLD"))
    }

    func testParseMRZReturnsNilForEmptyString() {
        XCTAssertNil(reader.parseMRZ(""))
    }

    // MARK: - parseMRZ / parseTD1 Tests

    func testParseTD1FullIDCardMRZ() {
        // TD1: 3 lines x 30 = 90 chars, padded to 91 for detectFormat
        // docNum D23145890, check 7:
        //   D=13; 13*7+2*3+3*1+1*7+4*3+5*1+8*7+9*3+0*1 = 207; 207%10 = 7
        // DOB 740812, check 2; Expiry 120415, check 9
        let mrz = "I<UTOD231458907<<<<<<<<<<<<<<<7408122F1204159UTO<<<<<<<<<<<<ERIKSSON<<ANNA<MARIA<<<<<<<<<<<"
        let result = reader.parseMRZ(mrz)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.format, .td1)
        XCTAssertEqual(result?.documentType, "I")
        XCTAssertEqual(result?.issuingCountry, "UTO")
        XCTAssertEqual(result?.lastName, "ERIKSSON")
        XCTAssertEqual(result?.firstName, "ANNA MARIA")
        XCTAssertEqual(result?.documentNumber, "D23145890")
        XCTAssertEqual(result?.nationality, "UTO")
        XCTAssertEqual(result?.dateOfBirth, "740812")
        XCTAssertEqual(result?.sex, "F")
        XCTAssertEqual(result?.expirationDate, "120415")
        XCTAssertTrue(result?.isValid ?? false)
    }

    func testParseTD1OptionalDataNilWhenAllFillers() {
        let mrz = "I<UTOD231458907<<<<<<<<<<<<<<<7408122F1204159UTO<<<<<<<<<<<<ERIKSSON<<ANNA<MARIA<<<<<<<<<<<"
        let result = reader.parseMRZ(mrz)

        XCTAssertNil(result?.optionalData1)
        XCTAssertNil(result?.optionalData2)
    }

    func testParseTD1InvalidCheckDigitReportsError() {
        // Corrupt doc number check digit: 7 -> 3 at position 14
        let mrz = "I<UTOD231458903<<<<<<<<<<<<<<<7408122F1204159UTO<<<<<<<<<<<<ERIKSSON<<ANNA<MARIA<<<<<<<<<<<"
        let result = reader.parseMRZ(mrz)

        XCTAssertNotNil(result)
        XCTAssertFalse(result?.isValid ?? true)
        XCTAssertTrue(result?.validationErrors.contains("Invalid document number check digit") ?? false)
    }

    // MARK: - formatDate Tests

    func testFormatDateCenturyDetectionTwoThousands() {
        // yy <= 30 -> 2000 + yy
        XCTAssertEqual(MRZReader.formatDate("250115"), "2025-01-15")
        XCTAssertEqual(MRZReader.formatDate("000315"), "2000-03-15")
        XCTAssertEqual(MRZReader.formatDate("300601"), "2030-06-01")
    }

    func testFormatDateCenturyDetectionNineteenHundreds() {
        // yy > 30 -> 1900 + yy
        XCTAssertEqual(MRZReader.formatDate("740812"), "1974-08-12")
        XCTAssertEqual(MRZReader.formatDate("990101"), "1999-01-01")
    }

    func testFormatDateReturnsNilForTooShort() {
        XCTAssertNil(MRZReader.formatDate("7408"))
    }

    func testFormatDateReturnsNilForTooLong() {
        XCTAssertNil(MRZReader.formatDate("7408121"))
    }

    func testFormatDateReturnsNilForEmptyString() {
        XCTAssertNil(MRZReader.formatDate(""))
    }

    // MARK: - MRZFormat rawValue Tests

    func testMRZFormatRawValues() {
        XCTAssertEqual(MRZFormat.td1.rawValue, "TD1")
        XCTAssertEqual(MRZFormat.td2.rawValue, "TD2")
        XCTAssertEqual(MRZFormat.td3.rawValue, "TD3")
    }
}
