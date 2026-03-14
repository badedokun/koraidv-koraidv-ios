import Foundation

// MARK: - NFC Passport Data

/// Data read from an ePassport NFC chip
public struct NFCPassportData {

    // MARK: - Personal Information

    /// Document number from DG1
    public let documentNumber: String

    /// First name(s) from DG1
    public let firstName: String

    /// Last name (surname) from DG1
    public let lastName: String

    /// Date of birth (YYMMDD) from DG1
    public let dateOfBirth: String

    /// Expiration date (YYMMDD) from DG1
    public let expirationDate: String

    /// Nationality (3-letter country code) from DG1
    public let nationality: String

    /// Sex (M/F/<) from DG1
    public let sex: String

    /// Issuing country (3-letter country code) from DG1
    public let issuingCountry: String

    // MARK: - Biometric Data

    /// Face image data (JPEG or JPEG2000) extracted from DG2
    public let faceImageData: Data?

    // MARK: - Authentication Status

    /// Whether Passive Authentication passed (SOD hash verification)
    public let passiveAuthPassed: Bool

    /// Whether Active Authentication passed (optional, nil if not attempted)
    public let activeAuthPassed: Bool?

    /// Whether Chip Authentication passed (optional, nil if not attempted)
    public let chipAuthPassed: Bool?

    // MARK: - Raw Data

    /// Raw DG1 data
    public let dg1Data: Data?

    /// Raw DG2 data
    public let dg2Data: Data?

    /// Raw SOD (Security Object Document) data
    public let sodData: Data?
}

// MARK: - BAC Key Data

/// Key data derived from MRZ for Basic Access Control
struct BACKeyData {

    /// Document number (up to 9 characters, padded with <)
    let documentNumber: String

    /// Document number check digit
    let documentNumberCheckDigit: String

    /// Date of birth (YYMMDD)
    let dateOfBirth: String

    /// Date of birth check digit
    let dateOfBirthCheckDigit: String

    /// Expiration date (YYMMDD)
    let expirationDate: String

    /// Expiration date check digit
    let expirationDateCheckDigit: String

    // MARK: - Initialization

    /// Create BAC key data from MRZ fields
    /// - Parameters:
    ///   - documentNumber: Document number from MRZ
    ///   - dateOfBirth: Date of birth in YYMMDD format
    ///   - expirationDate: Expiration date in YYMMDD format
    init(documentNumber: String, dateOfBirth: String, expirationDate: String) {
        // Pad document number to 9 characters with <
        let paddedDocNum = documentNumber.padding(toLength: 9, withPad: "<", startingAt: 0)
        self.documentNumber = paddedDocNum
        self.documentNumberCheckDigit = BACKeyData.computeCheckDigit(paddedDocNum)
        self.dateOfBirth = dateOfBirth
        self.dateOfBirthCheckDigit = BACKeyData.computeCheckDigit(dateOfBirth)
        self.expirationDate = expirationDate
        self.expirationDateCheckDigit = BACKeyData.computeCheckDigit(expirationDate)
    }

    /// The MRZ information string used to derive K_seed
    /// Format: documentNumber + checkDigit + dateOfBirth + checkDigit + expirationDate + checkDigit
    var mrzInfoString: String {
        return documentNumber + documentNumberCheckDigit +
               dateOfBirth + dateOfBirthCheckDigit +
               expirationDate + expirationDateCheckDigit
    }

    // MARK: - Check Digit Computation

    /// Compute ICAO 9303 check digit for a data string
    static func computeCheckDigit(_ data: String) -> String {
        let weights = [7, 3, 1]
        var sum = 0

        for (index, char) in data.enumerated() {
            let value: Int
            if char.isNumber {
                value = Int(String(char)) ?? 0
            } else if char.isUppercase {
                value = Int(char.asciiValue ?? 0) - 55 // A=10, B=11, ...
            } else if char == "<" {
                value = 0
            } else {
                value = 0
            }
            sum += value * weights[index % 3]
        }

        return String(sum % 10)
    }
}

// MARK: - NFC Reading State

/// State of the NFC passport reading process
enum NFCReadingState: Equatable {
    /// Waiting for user to present passport
    case waiting
    /// Authenticating with the chip (BAC)
    case authenticating
    /// Reading data groups from the chip
    case reading(progress: Double)
    /// Verifying data integrity (Passive Authentication)
    case verifying
    /// Reading completed successfully
    case success
    /// Reading failed with an error
    case error(String)

    static func == (lhs: NFCReadingState, rhs: NFCReadingState) -> Bool {
        switch (lhs, rhs) {
        case (.waiting, .waiting): return true
        case (.authenticating, .authenticating): return true
        case (.reading(let a), .reading(let b)): return a == b
        case (.verifying, .verifying): return true
        case (.success, .success): return true
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - NFC Error

/// Errors specific to NFC passport reading
enum NFCPassportError: LocalizedError {
    /// NFC not available on this device
    case nfcNotAvailable
    /// BAC authentication failed
    case bacAuthenticationFailed(String)
    /// Failed to select eMRTD application
    case applicationSelectionFailed
    /// Failed to read a data group
    case dataGroupReadFailed(String)
    /// Passive authentication failed — data may have been tampered with
    case passiveAuthenticationFailed(String)
    /// Invalid or corrupted data
    case invalidData(String)
    /// NFC session timed out
    case sessionTimeout
    /// User cancelled NFC session
    case userCancelled
    /// Unexpected APDU response
    case unexpectedResponse(sw1: UInt8, sw2: UInt8)
    /// Secure messaging error
    case secureMessagingError(String)

    var errorDescription: String? {
        switch self {
        case .nfcNotAvailable:
            return "NFC is not available on this device."
        case .bacAuthenticationFailed(let detail):
            return "Passport authentication failed: \(detail)"
        case .applicationSelectionFailed:
            return "Could not connect to the passport chip."
        case .dataGroupReadFailed(let group):
            return "Failed to read passport data (\(group))."
        case .passiveAuthenticationFailed(let detail):
            return "Passport data verification failed: \(detail)"
        case .invalidData(let detail):
            return "Invalid passport data: \(detail)"
        case .sessionTimeout:
            return "NFC session timed out. Please try again."
        case .userCancelled:
            return "NFC reading was cancelled."
        case .unexpectedResponse(let sw1, let sw2):
            return "Unexpected chip response: \(String(format: "%02X%02X", sw1, sw2))"
        case .secureMessagingError(let detail):
            return "Secure communication error: \(detail)"
        }
    }
}

// MARK: - NFC Upload Request

/// Request body for uploading NFC chip data to the server
struct NFCUploadRequest: Encodable {
    let documentNumber: String
    let firstName: String
    let lastName: String
    let dateOfBirth: String
    let expirationDate: String
    let nationality: String
    let sex: String
    let issuingCountry: String
    let passiveAuthPassed: Bool
    let activeAuthPassed: Bool?
    let chipAuthPassed: Bool?
    let hasFaceImage: Bool
    let dg1Hash: String?
    let dg2Hash: String?
}

// MARK: - NFC Upload Response

/// Response from the server after uploading NFC chip data
struct NFCUploadResponse: Decodable {
    let success: Bool
    let chipVerified: Bool?
    let message: String?
}
