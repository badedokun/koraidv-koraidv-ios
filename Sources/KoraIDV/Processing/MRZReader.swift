import Vision
import UIKit

/// Parsed MRZ data
public struct MRZData {
    /// Document format (TD1, TD2, TD3)
    public let format: MRZFormat
    /// Document type (P=Passport, I=ID, etc.)
    public let documentType: String
    /// Issuing country code (3-letter)
    public let issuingCountry: String
    /// Last name (surname)
    public let lastName: String
    /// First name(s)
    public let firstName: String
    /// Document number
    public let documentNumber: String
    /// Nationality (3-letter country code)
    public let nationality: String
    /// Date of birth (YYMMDD)
    public let dateOfBirth: String
    /// Sex (M/F/<)
    public let sex: String
    /// Expiration date (YYMMDD)
    public let expirationDate: String
    /// Optional data field 1
    public let optionalData1: String?
    /// Optional data field 2
    public let optionalData2: String?
    /// Whether all check digits are valid
    public let isValid: Bool
    /// Validation errors
    public let validationErrors: [String]
}

/// MRZ format type
public enum MRZFormat: String {
    case td1 = "TD1"  // ID cards - 3 lines × 30 chars
    case td2 = "TD2"  // Some IDs - 2 lines × 36 chars
    case td3 = "TD3"  // Passports - 2 lines × 44 chars
}

/// MRZ Reader using Vision framework
final class MRZReader {

    // MARK: - Properties

    private let textRecognitionLevel: VNRequestTextRecognitionLevel = .accurate

    // MARK: - Public Methods

    /// Read MRZ from image
    func readMRZ(from image: UIImage, completion: @escaping (MRZData?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(nil)
            return
        }

        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else { return }

            if let error = error {
                print("[KoraIDV] MRZ read error: \(error)")
                completion(nil)
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(nil)
                return
            }

            // Extract text from observations
            let recognizedText = self.extractMRZText(from: observations)

            // Parse MRZ
            if let mrzData = self.parseMRZ(recognizedText) {
                completion(mrzData)
            } else {
                completion(nil)
            }
        }

        request.recognitionLevel = textRecognitionLevel
        request.usesLanguageCorrection = false
        request.customWords = ["<", "<<"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            print("[KoraIDV] Vision request failed: \(error)")
            completion(nil)
        }
    }

    /// Read MRZ from pixel buffer
    func readMRZ(from pixelBuffer: CVPixelBuffer, completion: @escaping (MRZData?) -> Void) {
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else { return }

            if let error = error {
                print("[KoraIDV] MRZ read error: \(error)")
                completion(nil)
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(nil)
                return
            }

            let recognizedText = self.extractMRZText(from: observations)

            if let mrzData = self.parseMRZ(recognizedText) {
                completion(mrzData)
            } else {
                completion(nil)
            }
        }

        request.recognitionLevel = textRecognitionLevel
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            print("[KoraIDV] Vision request failed: \(error)")
            completion(nil)
        }
    }

    // MARK: - Private Methods

    private func extractMRZText(from observations: [VNRecognizedTextObservation]) -> String {
        // Filter observations that look like MRZ (contain < characters)
        var mrzLines: [(text: String, y: CGFloat)] = []

        for observation in observations {
            guard let topCandidate = observation.topCandidates(1).first else { continue }
            let text = topCandidate.string.uppercased()

            // MRZ lines contain < characters and are mostly alphanumeric
            if text.contains("<") || self.looksLikeMRZ(text) {
                mrzLines.append((text: text, y: observation.boundingBox.midY))
            }
        }

        // Sort by Y position (top to bottom in image coordinates)
        mrzLines.sort { $0.y > $1.y }

        // Combine lines
        return mrzLines.map { $0.text }.joined()
    }

    private func looksLikeMRZ(_ text: String) -> Bool {
        // MRZ text is mostly uppercase letters, digits, and <
        let mrzCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<")
        let textCharacters = CharacterSet(charactersIn: text)
        return textCharacters.isSubset(of: mrzCharacters) && text.count >= 20
    }

    private func parseMRZ(_ text: String) -> MRZData? {
        // Clean the text
        let cleaned = text
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .filter { $0.isLetter || $0.isNumber || $0 == "<" }

        // Detect format
        guard let format = detectFormat(cleaned) else {
            return nil
        }

        switch format {
        case .td1:
            return parseTD1(cleaned)
        case .td2:
            return parseTD2(cleaned)
        case .td3:
            return parseTD3(cleaned)
        }
    }

    private func detectFormat(_ text: String) -> MRZFormat? {
        let length = text.count

        // TD1: 3 lines × 30 chars = 90
        if length >= 88 && length <= 92 { return .td1 }

        // TD2: 2 lines × 36 chars = 72
        if length >= 70 && length <= 74 { return .td2 }

        // TD3: 2 lines × 44 chars = 88
        if length >= 86 && length <= 90 { return .td3 }

        return nil
    }

    private func parseTD1(_ text: String) -> MRZData? {
        guard text.count >= 90 else { return nil }

        var validationErrors: [String] = []

        // Line 1 (chars 0-29)
        let documentType = String(text.prefix(2)).replacingOccurrences(of: "<", with: "")
        let issuingCountry = String(text.dropFirst(2).prefix(3))
        let documentNumber = String(text.dropFirst(5).prefix(9)).replacingOccurrences(of: "<", with: "")
        let docNumCheck = String(text.dropFirst(14).prefix(1))
        let optionalData1 = String(text.dropFirst(15).prefix(15)).replacingOccurrences(of: "<", with: "")

        // Line 2 (chars 30-59)
        let line2Start = text.index(text.startIndex, offsetBy: 30)
        let line2 = String(text[line2Start...])

        let dateOfBirth = String(line2.prefix(6))
        let dobCheck = String(line2.dropFirst(6).prefix(1))
        let sex = String(line2.dropFirst(7).prefix(1))
        let expirationDate = String(line2.dropFirst(8).prefix(6))
        let expCheck = String(line2.dropFirst(14).prefix(1))
        let nationality = String(line2.dropFirst(15).prefix(3))
        let optionalData2 = String(line2.dropFirst(18).prefix(11)).replacingOccurrences(of: "<", with: "")

        // Line 3 (chars 60-89) - Name
        let line3Start = text.index(text.startIndex, offsetBy: 60)
        let line3 = String(text[line3Start...])
        let nameParts = parseName(line3)

        // Validate check digits
        if !validateCheckDigit(documentNumber, check: docNumCheck) {
            validationErrors.append("Invalid document number check digit")
        }
        if !validateCheckDigit(dateOfBirth, check: dobCheck) {
            validationErrors.append("Invalid date of birth check digit")
        }
        if !validateCheckDigit(expirationDate, check: expCheck) {
            validationErrors.append("Invalid expiration date check digit")
        }

        return MRZData(
            format: .td1,
            documentType: documentType,
            issuingCountry: issuingCountry,
            lastName: nameParts.lastName,
            firstName: nameParts.firstName,
            documentNumber: documentNumber,
            nationality: nationality,
            dateOfBirth: dateOfBirth,
            sex: sex,
            expirationDate: expirationDate,
            optionalData1: optionalData1.isEmpty ? nil : optionalData1,
            optionalData2: optionalData2.isEmpty ? nil : optionalData2,
            isValid: validationErrors.isEmpty,
            validationErrors: validationErrors
        )
    }

    private func parseTD2(_ text: String) -> MRZData? {
        guard text.count >= 72 else { return nil }

        var validationErrors: [String] = []

        // Line 1 (chars 0-35)
        let documentType = String(text.prefix(2)).replacingOccurrences(of: "<", with: "")
        let issuingCountry = String(text.dropFirst(2).prefix(3))
        let nameParts = parseName(String(text.dropFirst(5).prefix(31)))

        // Line 2 (chars 36-71)
        let line2Start = text.index(text.startIndex, offsetBy: 36)
        let line2 = String(text[line2Start...])

        let documentNumber = String(line2.prefix(9)).replacingOccurrences(of: "<", with: "")
        let docNumCheck = String(line2.dropFirst(9).prefix(1))
        let nationality = String(line2.dropFirst(10).prefix(3))
        let dateOfBirth = String(line2.dropFirst(13).prefix(6))
        let dobCheck = String(line2.dropFirst(19).prefix(1))
        let sex = String(line2.dropFirst(20).prefix(1))
        let expirationDate = String(line2.dropFirst(21).prefix(6))
        let expCheck = String(line2.dropFirst(27).prefix(1))
        let optionalData1 = String(line2.dropFirst(28).prefix(7)).replacingOccurrences(of: "<", with: "")

        // Validate check digits
        if !validateCheckDigit(documentNumber, check: docNumCheck) {
            validationErrors.append("Invalid document number check digit")
        }
        if !validateCheckDigit(dateOfBirth, check: dobCheck) {
            validationErrors.append("Invalid date of birth check digit")
        }
        if !validateCheckDigit(expirationDate, check: expCheck) {
            validationErrors.append("Invalid expiration date check digit")
        }

        return MRZData(
            format: .td2,
            documentType: documentType,
            issuingCountry: issuingCountry,
            lastName: nameParts.lastName,
            firstName: nameParts.firstName,
            documentNumber: documentNumber,
            nationality: nationality,
            dateOfBirth: dateOfBirth,
            sex: sex,
            expirationDate: expirationDate,
            optionalData1: optionalData1.isEmpty ? nil : optionalData1,
            optionalData2: nil,
            isValid: validationErrors.isEmpty,
            validationErrors: validationErrors
        )
    }

    private func parseTD3(_ text: String) -> MRZData? {
        guard text.count >= 88 else { return nil }

        var validationErrors: [String] = []

        // Line 1 (chars 0-43)
        let documentType = String(text.prefix(2)).replacingOccurrences(of: "<", with: "")
        let issuingCountry = String(text.dropFirst(2).prefix(3))
        let nameParts = parseName(String(text.dropFirst(5).prefix(39)))

        // Line 2 (chars 44-87)
        let line2Start = text.index(text.startIndex, offsetBy: 44)
        let line2 = String(text[line2Start...])

        let documentNumber = String(line2.prefix(9)).replacingOccurrences(of: "<", with: "")
        let docNumCheck = String(line2.dropFirst(9).prefix(1))
        let nationality = String(line2.dropFirst(10).prefix(3))
        let dateOfBirth = String(line2.dropFirst(13).prefix(6))
        let dobCheck = String(line2.dropFirst(19).prefix(1))
        let sex = String(line2.dropFirst(20).prefix(1))
        let expirationDate = String(line2.dropFirst(21).prefix(6))
        let expCheck = String(line2.dropFirst(27).prefix(1))
        let optionalData1 = String(line2.dropFirst(28).prefix(14)).replacingOccurrences(of: "<", with: "")

        // Validate check digits
        if !validateCheckDigit(documentNumber, check: docNumCheck) {
            validationErrors.append("Invalid document number check digit")
        }
        if !validateCheckDigit(dateOfBirth, check: dobCheck) {
            validationErrors.append("Invalid date of birth check digit")
        }
        if !validateCheckDigit(expirationDate, check: expCheck) {
            validationErrors.append("Invalid expiration date check digit")
        }

        return MRZData(
            format: .td3,
            documentType: documentType,
            issuingCountry: issuingCountry,
            lastName: nameParts.lastName,
            firstName: nameParts.firstName,
            documentNumber: documentNumber,
            nationality: nationality,
            dateOfBirth: dateOfBirth,
            sex: sex,
            expirationDate: expirationDate,
            optionalData1: optionalData1.isEmpty ? nil : optionalData1,
            optionalData2: nil,
            isValid: validationErrors.isEmpty,
            validationErrors: validationErrors
        )
    }

    private func parseName(_ nameField: String) -> (lastName: String, firstName: String) {
        let parts = nameField.components(separatedBy: "<<")
        let lastName = parts.first?.replacingOccurrences(of: "<", with: " ").trimmingCharacters(in: .whitespaces) ?? ""
        let firstName = parts.dropFirst().first?.replacingOccurrences(of: "<", with: " ").trimmingCharacters(in: .whitespaces) ?? ""
        return (lastName, firstName)
    }

    private func validateCheckDigit(_ data: String, check: String) -> Bool {
        let weights = [7, 3, 1]
        var sum = 0

        for (index, char) in data.enumerated() {
            let value: Int
            if char.isNumber {
                value = Int(String(char)) ?? 0
            } else if char.isLetter {
                value = Int(char.asciiValue ?? 0) - 55 // A=10, B=11, etc.
            } else if char == "<" {
                value = 0
            } else {
                return false
            }

            sum += value * weights[index % 3]
        }

        let expected = sum % 10
        let actual = check == "<" ? 0 : (Int(check) ?? -1)

        return expected == actual
    }

    /// Format date from YYMMDD to human readable
    static func formatDate(_ yymmdd: String) -> String? {
        guard yymmdd.count == 6 else { return nil }

        let yy = Int(yymmdd.prefix(2)) ?? 0
        let mm = String(yymmdd.dropFirst(2).prefix(2))
        let dd = String(yymmdd.dropFirst(4).prefix(2))

        // Determine century
        let year = yy <= 30 ? 2000 + yy : 1900 + yy

        return "\(year)-\(mm)-\(dd)"
    }
}
