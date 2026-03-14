#if canImport(CoreNFC)
import Foundation
import CoreNFC
import CommonCrypto
import Security

/// Reads ePassport NFC chip data using ICAO 9303 BAC protocol
@available(iOS 13.0, *)
final class NFCPassportReader: NSObject {

    // MARK: - Properties

    private let bacKeyData: BACKeyData
    private var tagSession: NFCTagReaderSession?
    private var passport: NFCTag?

    /// Completion handler for the read operation
    private var completion: ((Result<NFCPassportData, NFCPassportError>) -> Void)?

    /// Secure messaging session keys (established after BAC)
    private var ksEnc: Data?
    private var ksMac: Data?
    private var ssc: Data? // Send Sequence Counter

    // MARK: - Constants

    /// eMRTD application AID
    private static let eMRTDAID: [UInt8] = [0xA0, 0x00, 0x00, 0x02, 0x47, 0x10, 0x01]

    /// Data group file identifiers
    private static let dgFileIDs: [Int: [UInt8]] = [
        1:  [0x01, 0x01], // DG1 - MRZ
        2:  [0x01, 0x02], // DG2 - Face image
        14: [0x01, 0x0E], // SOD (Security Object)
    ]

    /// EF.SOD file identifier
    private static let efSODFileID: [UInt8] = [0x01, 0x1D]

    // MARK: - Initialization

    /// Initialize with BAC key data derived from MRZ
    /// - Parameter bacKeyData: BAC key data containing document number, DOB, and expiry
    init(bacKeyData: BACKeyData) {
        self.bacKeyData = bacKeyData
        super.init()
    }

    // MARK: - Public Methods

    /// Check if NFC passport reading is available on this device
    static var isAvailable: Bool {
        return NFCTagReaderSession.readingAvailable
    }

    /// Start reading the passport chip
    /// - Parameter completion: Called with the passport data or an error
    func startReading(completion: @escaping (Result<NFCPassportData, NFCPassportError>) -> Void) {
        guard NFCPassportReader.isAvailable else {
            completion(.failure(.nfcNotAvailable))
            return
        }

        self.completion = completion

        tagSession = NFCTagReaderSession(
            pollingOption: .iso14443,
            delegate: self,
            queue: .main
        )
        tagSession?.alertMessage = "Hold your iPhone near the passport's data page."
        tagSession?.begin()
    }

    /// Cancel the current reading session
    func cancelReading() {
        tagSession?.invalidate(errorMessage: "Reading cancelled.")
        tagSession = nil
    }

    // MARK: - BAC Protocol

    /// Perform Basic Access Control authentication
    private func performBAC(with tag: NFCISO7816Tag, completion: @escaping (Result<Void, NFCPassportError>) -> Void) {
        // Step 1: Compute K_seed from MRZ info
        let mrzInfoData = Data(bacKeyData.mrzInfoString.utf8)
        let kSeed = sha1(mrzInfoData).prefix(16)

        // Step 2: Derive K_enc and K_mac from K_seed
        let kEnc = deriveKey(kSeed: Data(kSeed), counter: 1) // Encryption key
        let kMac = deriveKey(kSeed: Data(kSeed), counter: 2) // MAC key

        // Step 3: GET CHALLENGE — get random number from chip
        let getChallengeAPDU = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0x84, // GET CHALLENGE
            p1Parameter: 0x00,
            p2Parameter: 0x00,
            data: Data(),
            expectedResponseLength: 8
        )

        tag.sendCommand(apdu: getChallengeAPDU) { [weak self] responseData, sw1, sw2, error in
            guard let self = self else { return }

            if let error = error {
                completion(.failure(.bacAuthenticationFailed("GET CHALLENGE failed: \(error.localizedDescription)")))
                return
            }

            guard sw1 == 0x90, sw2 == 0x00, responseData.count == 8 else {
                completion(.failure(.bacAuthenticationFailed("GET CHALLENGE unexpected response")))
                return
            }

            let rndICC = responseData // 8-byte random from chip

            // Step 4: Generate our own randoms
            let rndIFD = self.generateRandom(count: 8)
            let kIFD = self.generateRandom(count: 16)

            // Step 5: Build S = rndIFD || rndICC || kIFD
            var s = Data()
            s.append(rndIFD)
            s.append(rndICC)
            s.append(kIFD)

            // Step 6: Encrypt S with K_enc (3DES-CBC, IV=0)
            let eIFD = self.tripleDESEncrypt(data: s, key: kEnc)

            // Step 7: Compute MAC over eIFD with K_mac
            let mIFD = self.retailMAC(data: eIFD, key: kMac)

            // Step 8: Build EXTERNAL AUTHENTICATE command data = eIFD || mIFD
            var cmdData = Data()
            cmdData.append(eIFD)
            cmdData.append(mIFD)

            let extAuthAPDU = NFCISO7816APDU(
                instructionClass: 0x00,
                instructionCode: 0x82, // EXTERNAL AUTHENTICATE
                p1Parameter: 0x00,
                p2Parameter: 0x00,
                data: cmdData,
                expectedResponseLength: 40
            )

            tag.sendCommand(apdu: extAuthAPDU) { responseData, sw1, sw2, error in
                if let error = error {
                    completion(.failure(.bacAuthenticationFailed("EXTERNAL AUTHENTICATE failed: \(error.localizedDescription)")))
                    return
                }

                guard sw1 == 0x90, sw2 == 0x00, responseData.count == 40 else {
                    completion(.failure(.bacAuthenticationFailed("EXTERNAL AUTHENTICATE rejected by chip")))
                    return
                }

                // Step 9: Decrypt response
                let eICC = responseData.prefix(32)
                let mICC = responseData.suffix(8)

                // Verify MAC
                let expectedMAC = self.retailMAC(data: Data(eICC), key: kMac)
                guard mICC == expectedMAC else {
                    completion(.failure(.bacAuthenticationFailed("MAC verification failed")))
                    return
                }

                // Decrypt eICC
                let decrypted = self.tripleDESDecrypt(data: Data(eICC), key: kEnc)

                guard decrypted.count >= 32 else {
                    completion(.failure(.bacAuthenticationFailed("Invalid response length")))
                    return
                }

                // Extract kICC (last 16 bytes of decrypted data)
                let kICC = decrypted.suffix(16)

                // Step 10: Compute session keys
                // K_seed_session = kIFD XOR kICC
                var kSeedSession = Data(count: 16)
                for i in 0..<16 {
                    kSeedSession[i] = kIFD[i] ^ kICC[i]
                }

                self.ksEnc = self.deriveKey(kSeed: kSeedSession, counter: 1)
                self.ksMac = self.deriveKey(kSeed: kSeedSession, counter: 2)

                // Compute initial SSC = rndICC[4..7] || rndIFD[4..7]
                var ssc = Data()
                ssc.append(rndICC.suffix(4))
                ssc.append(rndIFD.suffix(4))
                self.ssc = ssc

                KoraIDV.log("BAC authentication successful")
                completion(.success(()))
            }
        }
    }

    // MARK: - Data Group Reading

    /// Select the eMRTD application on the chip
    private func selectApplication(tag: NFCISO7816Tag, completion: @escaping (Result<Void, NFCPassportError>) -> Void) {
        let selectAPDU = NFCISO7816APDU(
            instructionClass: 0x00,
            instructionCode: 0xA4, // SELECT
            p1Parameter: 0x04,     // Select by DF name
            p2Parameter: 0x0C,     // No response data
            data: Data(NFCPassportReader.eMRTDAID),
            expectedResponseLength: -1
        )

        tag.sendCommand(apdu: selectAPDU) { _, sw1, sw2, error in
            if let error = error {
                completion(.failure(.applicationSelectionFailed))
                KoraIDV.log("SELECT eMRTD failed: \(error.localizedDescription)")
                return
            }

            guard sw1 == 0x90, sw2 == 0x00 else {
                completion(.failure(.applicationSelectionFailed))
                return
            }

            completion(.success(()))
        }
    }

    /// Select a specific file (EF) by its short file ID
    private func selectFile(tag: NFCISO7816Tag, fileID: [UInt8], completion: @escaping (Result<Void, NFCPassportError>) -> Void) {
        let data: Data
        let apdu: NFCISO7816APDU

        if let ksEnc = self.ksEnc, let ksMac = self.ksMac {
            // Use secure messaging
            let plainAPDU = NFCISO7816APDU(
                instructionClass: 0x00,
                instructionCode: 0xA4,
                p1Parameter: 0x02,     // Select by EF identifier
                p2Parameter: 0x0C,
                data: Data(fileID),
                expectedResponseLength: -1
            )
            guard let secureAPDU = buildSecureAPDU(plainAPDU, ksEnc: ksEnc, ksMac: ksMac) else {
                completion(.failure(.secureMessagingError("Failed to build secure SELECT")))
                return
            }
            apdu = secureAPDU
        } else {
            apdu = NFCISO7816APDU(
                instructionClass: 0x00,
                instructionCode: 0xA4,
                p1Parameter: 0x02,
                p2Parameter: 0x0C,
                data: Data(fileID),
                expectedResponseLength: -1
            )
        }

        tag.sendCommand(apdu: apdu) { [weak self] responseData, sw1, sw2, error in
            if let error = error {
                completion(.failure(.dataGroupReadFailed("SELECT file failed: \(error.localizedDescription)")))
                return
            }

            // With secure messaging, verify response MAC if applicable
            if self?.ksEnc != nil {
                // Increment SSC for response
                self?.incrementSSC()
            }

            guard sw1 == 0x90, sw2 == 0x00 else {
                completion(.failure(.dataGroupReadFailed("SELECT file returned \(String(format: "%02X%02X", sw1, sw2))")))
                return
            }

            completion(.success(()))
        }
    }

    /// Read binary data from the currently selected file
    private func readBinary(tag: NFCISO7816Tag, offset: Int, length: Int, completion: @escaping (Result<Data, NFCPassportError>) -> Void) {
        let p1 = UInt8((offset >> 8) & 0xFF)
        let p2 = UInt8(offset & 0xFF)
        let le = min(length, 0xDF) // Max read size per command (accounting for secure messaging overhead)

        if let ksEnc = self.ksEnc, let ksMac = self.ksMac {
            let plainAPDU = NFCISO7816APDU(
                instructionClass: 0x00,
                instructionCode: 0xB0,
                p1Parameter: p1,
                p2Parameter: p2,
                data: Data(),
                expectedResponseLength: le
            )
            guard let secureAPDU = buildSecureAPDU(plainAPDU, ksEnc: ksEnc, ksMac: ksMac) else {
                completion(.failure(.secureMessagingError("Failed to build secure READ BINARY")))
                return
            }

            tag.sendCommand(apdu: secureAPDU) { [weak self] responseData, sw1, sw2, error in
                if let error = error {
                    completion(.failure(.dataGroupReadFailed("READ BINARY failed: \(error.localizedDescription)")))
                    return
                }

                // Increment SSC for response
                self?.incrementSSC()

                guard sw1 == 0x90, sw2 == 0x00 else {
                    if sw1 == 0x6C {
                        // Wrong Le — retry with correct length
                        self?.readBinary(tag: tag, offset: offset, length: Int(sw2), completion: completion)
                        return
                    }
                    completion(.failure(.dataGroupReadFailed("READ BINARY returned \(String(format: "%02X%02X", sw1, sw2))")))
                    return
                }

                // Unwrap secure messaging response
                if let plainData = self?.unwrapSecureResponse(responseData) {
                    completion(.success(plainData))
                } else {
                    // If unwrapping fails, return raw data (may work for some implementations)
                    completion(.success(responseData))
                }
            }
        } else {
            let apdu = NFCISO7816APDU(
                instructionClass: 0x00,
                instructionCode: 0xB0,
                p1Parameter: p1,
                p2Parameter: p2,
                data: Data(),
                expectedResponseLength: le
            )

            tag.sendCommand(apdu: apdu) { responseData, sw1, sw2, error in
                if let error = error {
                    completion(.failure(.dataGroupReadFailed("READ BINARY failed: \(error.localizedDescription)")))
                    return
                }

                guard sw1 == 0x90, sw2 == 0x00 else {
                    completion(.failure(.dataGroupReadFailed("READ BINARY returned \(String(format: "%02X%02X", sw1, sw2))")))
                    return
                }

                completion(.success(responseData))
            }
        }
    }

    /// Read an entire data group file
    private func readDataGroup(tag: NFCISO7816Tag, fileID: [UInt8], name: String, completion: @escaping (Result<Data, NFCPassportError>) -> Void) {
        // Select the file first
        selectFile(tag: tag, fileID: fileID) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success:
                // Read the first 4 bytes to get the TLV header and determine total length
                self.readBinary(tag: tag, offset: 0, length: 4) { result in
                    switch result {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success(let headerData):
                        guard headerData.count >= 2 else {
                            completion(.failure(.invalidData("Header too short for \(name)")))
                            return
                        }

                        // Parse TLV length
                        let (totalLength, headerLength) = TLVParser.parseLength(Data(headerData.dropFirst(1)))

                        guard totalLength > 0 else {
                            completion(.failure(.invalidData("Zero length for \(name)")))
                            return
                        }

                        let fullLength = Int(totalLength) + 1 + headerLength // tag byte + length bytes + value

                        // Read the entire file in chunks
                        self.readFullFile(tag: tag, totalLength: fullLength, name: name, completion: completion)
                    }
                }
            }
        }
    }

    /// Read a complete file by chunking READ BINARY commands
    private func readFullFile(tag: NFCISO7816Tag, totalLength: Int, name: String, completion: @escaping (Result<Data, NFCPassportError>) -> Void) {
        var allData = Data()
        let chunkSize = 0xDF // Conservative chunk size for secure messaging

        func readNextChunk() {
            let offset = allData.count
            let remaining = totalLength - offset
            let toRead = min(remaining, chunkSize)

            if toRead <= 0 {
                completion(.success(allData))
                return
            }

            self.readBinary(tag: tag, offset: offset, length: toRead) { result in
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let chunkData):
                    allData.append(chunkData)

                    // Update NFC alert with progress
                    let progress = Double(allData.count) / Double(totalLength)
                    self.tagSession?.alertMessage = "Reading \(name)... \(Int(progress * 100))%"

                    if allData.count >= totalLength {
                        completion(.success(allData))
                    } else {
                        readNextChunk()
                    }
                }
            }
        }

        readNextChunk()
    }

    /// Orchestrate the full passport reading flow
    private func readPassport(tag: NFCISO7816Tag) {
        tagSession?.alertMessage = "Connecting to passport..."

        // Step 1: Select eMRTD application
        selectApplication(tag: tag) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                self.finishWithError(error)
                return
            case .success:
                break
            }

            self.tagSession?.alertMessage = "Authenticating..."

            // Step 2: Perform BAC
            self.performBAC(with: tag) { result in
                switch result {
                case .failure(let error):
                    self.finishWithError(error)
                    return
                case .success:
                    break
                }

                self.tagSession?.alertMessage = "Reading MRZ data..."

                // Step 3: Read DG1 (MRZ)
                self.readDataGroup(tag: tag, fileID: [0x01, 0x01], name: "DG1") { result in
                    let dg1Data: Data
                    switch result {
                    case .failure(let error):
                        self.finishWithError(error)
                        return
                    case .success(let data):
                        dg1Data = data
                    }

                    self.tagSession?.alertMessage = "Reading face image..."

                    // Step 4: Read DG2 (Face)
                    self.readDataGroup(tag: tag, fileID: [0x01, 0x02], name: "DG2") { result in
                        let dg2Data: Data
                        switch result {
                        case .failure(let error):
                            // DG2 failure is not fatal — continue without face image
                            KoraIDV.log("DG2 read failed (non-fatal): \(error.localizedDescription)")
                            dg2Data = Data()
                        case .success(let data):
                            dg2Data = data
                        }

                        self.tagSession?.alertMessage = "Reading security data..."

                        // Step 5: Read EF.SOD (Security Object)
                        self.readDataGroup(tag: tag, fileID: [0x01, 0x1D], name: "SOD") { result in
                            let sodData: Data
                            switch result {
                            case .failure(let error):
                                KoraIDV.log("SOD read failed (non-fatal): \(error.localizedDescription)")
                                sodData = Data()
                            case .success(let data):
                                sodData = data
                            }

                            self.tagSession?.alertMessage = "Verifying passport data..."

                            // Step 6: Parse and verify
                            self.processReadData(dg1: dg1Data, dg2: dg2Data, sod: sodData)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data Processing

    /// Process all read data groups and build the passport data result
    private func processReadData(dg1: Data, dg2: Data, sod: Data) {
        // Parse DG1 to extract MRZ
        let mrzData = parseDG1(dg1)

        // Parse DG2 to extract face image
        let faceImageData = parseDG2(dg2)

        // Perform Passive Authentication
        let passiveAuthPassed = performPassiveAuthentication(dg1: dg1, dg2: dg2, sod: sod)

        let firstName = mrzData?.firstName ?? bacKeyData.documentNumber
        let lastName = mrzData?.lastName ?? ""
        let documentNumber = mrzData?.documentNumber ?? bacKeyData.documentNumber
        let dateOfBirth = mrzData?.dateOfBirth ?? bacKeyData.dateOfBirth
        let expirationDate = mrzData?.expirationDate ?? bacKeyData.expirationDate
        let nationality = mrzData?.nationality ?? ""
        let sex = mrzData?.sex ?? ""
        let issuingCountry = mrzData?.issuingCountry ?? ""

        let passportData = NFCPassportData(
            documentNumber: documentNumber,
            firstName: firstName,
            lastName: lastName,
            dateOfBirth: dateOfBirth,
            expirationDate: expirationDate,
            nationality: nationality,
            sex: sex,
            issuingCountry: issuingCountry,
            faceImageData: faceImageData,
            passiveAuthPassed: passiveAuthPassed,
            activeAuthPassed: nil,
            chipAuthPassed: nil,
            dg1Data: dg1,
            dg2Data: dg2,
            sodData: sod.isEmpty ? nil : sod
        )

        tagSession?.alertMessage = "Passport read successfully!"
        tagSession?.invalidate()
        tagSession = nil
        completion?(.success(passportData))
        completion = nil
    }

    // MARK: - DG1 Parsing

    /// Parse DG1 to extract MRZ data
    private func parseDG1(_ data: Data) -> MRZData? {
        guard data.count > 5 else { return nil }

        // DG1 structure: tag 61 -> tag 5F1F -> MRZ string
        let parsed = TLVParser.parse(data)
        guard let dg1Content = parsed.first(where: { $0.tag == 0x61 }) else {
            // Try direct parsing if outer tag is different
            return parseMRZFromRawDG1(data)
        }

        // Look for MRZ data tag (5F1F)
        let innerTLVs = TLVParser.parse(dg1Content.value)
        if let mrzTLV = innerTLVs.first(where: { $0.tag == 0x5F1F }) {
            if let mrzString = String(data: mrzTLV.value, encoding: .utf8) {
                let reader = MRZReader()
                return reader.parseMRZ(mrzString)
            }
        }

        return parseMRZFromRawDG1(data)
    }

    /// Attempt to parse MRZ from raw DG1 bytes by scanning for text content
    private func parseMRZFromRawDG1(_ data: Data) -> MRZData? {
        // Try to find MRZ text within the data by looking for P< or I< patterns
        if let text = String(data: data, encoding: .utf8) {
            let reader = MRZReader()
            // Try to find MRZ-like content
            let candidates = text.components(separatedBy: CharacterSet.controlCharacters)
                .filter { $0.count >= 30 && $0.contains("<") }
                .joined()
            if !candidates.isEmpty {
                return reader.parseMRZ(candidates)
            }
        }
        return nil
    }

    // MARK: - DG2 Parsing

    /// Parse DG2 to extract face image data (JPEG or JPEG2000)
    private func parseDG2(_ data: Data) -> Data? {
        guard data.count > 10 else { return nil }

        // JPEG magic bytes: FF D8 FF
        if let jpegRange = data.range(of: Data([0xFF, 0xD8, 0xFF])) {
            // Find JPEG end marker (FF D9)
            if let endRange = data.range(of: Data([0xFF, 0xD9]), in: jpegRange.lowerBound..<data.endIndex) {
                return data[jpegRange.lowerBound..<endRange.upperBound]
            }
            // No end marker found — return from start to end
            return Data(data[jpegRange.lowerBound...])
        }

        // JPEG2000 magic bytes: 00 00 00 0C 6A 50
        let jp2Magic: [UInt8] = [0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50]
        if let jp2Range = data.range(of: Data(jp2Magic)) {
            return Data(data[jp2Range.lowerBound...])
        }

        return nil
    }

    // MARK: - Passive Authentication

    /// Perform Passive Authentication by verifying DG hashes against SOD
    private func performPassiveAuthentication(dg1: Data, dg2: Data, sod: Data) -> Bool {
        guard !sod.isEmpty else {
            KoraIDV.log("No SOD data — skipping Passive Authentication")
            return false
        }

        // Parse SOD to extract hash algorithm and data group hashes
        guard let sodInfo = parseSOD(sod) else {
            KoraIDV.log("Failed to parse SOD")
            return false
        }

        // Hash DG1 and DG2 with the algorithm specified in SOD
        let dg1Hash: Data
        let dg2Hash: Data

        switch sodInfo.hashAlgorithm {
        case .sha1:
            dg1Hash = sha1(dg1)
            dg2Hash = sha1(dg2)
        case .sha256:
            dg1Hash = sha256(dg1)
            dg2Hash = sha256(dg2)
        }

        // Compare hashes
        var passed = true

        if let expectedDG1Hash = sodInfo.dataGroupHashes[1] {
            if dg1Hash != expectedDG1Hash {
                KoraIDV.log("DG1 hash mismatch — Passive Authentication failed")
                passed = false
            }
        }

        if !dg2.isEmpty, let expectedDG2Hash = sodInfo.dataGroupHashes[2] {
            if dg2Hash != expectedDG2Hash {
                KoraIDV.log("DG2 hash mismatch — Passive Authentication failed")
                passed = false
            }
        }

        if passed {
            KoraIDV.log("Passive Authentication passed")
        }

        return passed
    }

    // MARK: - SOD Parsing

    /// Information extracted from the Security Object Document
    private struct SODInfo {
        let hashAlgorithm: HashAlgorithm
        let dataGroupHashes: [Int: Data] // DG number -> hash
    }

    private enum HashAlgorithm {
        case sha1
        case sha256
    }

    /// Parse the Security Object Document (EF.SOD)
    private func parseSOD(_ data: Data) -> SODInfo? {
        // SOD is a CMS SignedData structure (ASN.1 DER encoded)
        // We need to dig through the ASN.1 to find:
        // 1. The hash algorithm OID
        // 2. The encapContentInfo containing LDS Security Object
        // 3. Data group hash values

        // SHA-1 OID: 1.3.14.3.2.26 = 06 05 2B 0E 03 02 1A
        let sha1OID: [UInt8] = [0x06, 0x05, 0x2B, 0x0E, 0x03, 0x02, 0x1A]
        // SHA-256 OID: 2.16.840.1.101.3.4.2.1 = 06 09 60 86 48 01 65 03 04 02 01
        let sha256OID: [UInt8] = [0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01]

        // Determine hash algorithm
        let hashAlgorithm: HashAlgorithm
        if data.range(of: Data(sha256OID)) != nil {
            hashAlgorithm = .sha256
        } else if data.range(of: Data(sha1OID)) != nil {
            hashAlgorithm = .sha1
        } else {
            KoraIDV.log("Unknown hash algorithm in SOD")
            return nil
        }

        // Find data group hashes in the LDS Security Object
        // The hashes are in SEQUENCE { INTEGER dgNumber, OCTET STRING hash } entries
        let hashes = extractDataGroupHashes(from: data, algorithm: hashAlgorithm)

        guard !hashes.isEmpty else {
            KoraIDV.log("No data group hashes found in SOD")
            return nil
        }

        return SODInfo(hashAlgorithm: hashAlgorithm, dataGroupHashes: hashes)
    }

    /// Extract data group hashes from the SOD ASN.1 structure
    private func extractDataGroupHashes(from data: Data, algorithm: HashAlgorithm) -> [Int: Data] {
        var hashes: [Int: Data] = [:]
        let hashLength = algorithm == .sha256 ? 32 : 20

        // Scan for SEQUENCE { INTEGER, OCTET STRING } patterns
        // Tag 0x30 = SEQUENCE, 0x02 = INTEGER, 0x04 = OCTET STRING
        var index = 0
        let bytes = [UInt8](data)

        while index < bytes.count - 4 {
            // Look for SEQUENCE tag
            if bytes[index] == 0x30 {
                let seqStart = index
                index += 1

                // Parse sequence length
                let (seqLen, seqLenBytes) = parseBERLength(bytes, offset: index)
                index += seqLenBytes

                guard seqLen > 0, index + Int(seqLen) <= bytes.count else {
                    index = seqStart + 1
                    continue
                }

                let seqEnd = index + Int(seqLen)

                // Check for INTEGER tag
                if index < seqEnd, bytes[index] == 0x02 {
                    index += 1
                    let (intLen, intLenBytes) = parseBERLength(bytes, offset: index)
                    index += intLenBytes

                    guard intLen > 0, intLen <= 4, index + Int(intLen) <= seqEnd else {
                        index = seqStart + 1
                        continue
                    }

                    // Read DG number
                    var dgNumber = 0
                    for i in 0..<Int(intLen) {
                        dgNumber = (dgNumber << 8) | Int(bytes[index + i])
                    }
                    index += Int(intLen)

                    // Check for OCTET STRING tag
                    if index < seqEnd, bytes[index] == 0x04 {
                        index += 1
                        let (octetLen, octetLenBytes) = parseBERLength(bytes, offset: index)
                        index += octetLenBytes

                        if Int(octetLen) == hashLength, index + hashLength <= bytes.count {
                            let hashData = Data(bytes[index..<(index + hashLength)])
                            hashes[dgNumber] = hashData
                            index += hashLength
                            continue
                        }
                    }
                }

                index = seqStart + 1
            } else {
                index += 1
            }
        }

        return hashes
    }

    /// Parse a BER-encoded length field
    private func parseBERLength(_ bytes: [UInt8], offset: Int) -> (UInt64, Int) {
        guard offset < bytes.count else { return (0, 0) }

        let firstByte = bytes[offset]

        if firstByte < 0x80 {
            // Short form
            return (UInt64(firstByte), 1)
        }

        let numLengthBytes = Int(firstByte & 0x7F)
        guard numLengthBytes > 0, numLengthBytes <= 4, offset + 1 + numLengthBytes <= bytes.count else {
            return (0, 1)
        }

        var length: UInt64 = 0
        for i in 0..<numLengthBytes {
            length = (length << 8) | UInt64(bytes[offset + 1 + i])
        }

        return (length, 1 + numLengthBytes)
    }

    // MARK: - Secure Messaging

    /// Build a secure messaging APDU (wraps plaintext APDU with encryption and MAC)
    private func buildSecureAPDU(_ apdu: NFCISO7816APDU, ksEnc: Data, ksMac: Data) -> NFCISO7816APDU? {
        // Increment SSC
        incrementSSC()
        guard let ssc = self.ssc else { return nil }

        var do87 = Data() // Encrypted data
        var do97 = Data() // Expected length

        // Build DO'87 (encrypted command data) if there is data
        let cmdData = apdu.data ?? Data()
        if !cmdData.isEmpty {
            // Pad and encrypt the data
            let paddedData = iso9797Pad(cmdData)
            let encrypted = tripleDESEncrypt(data: paddedData, key: ksEnc)

            do87.append(0x87)
            let encDataWithIndicator = Data([0x01]) + encrypted
            do87.append(contentsOf: encodeBERLength(encDataWithIndicator.count))
            do87.append(0x01) // Padding indicator
            do87.append(encrypted)
        }

        // Build DO'97 (expected response length)
        let le = apdu.expectedResponseLength
        if le > 0 {
            do97.append(0x97)
            do97.append(0x01)
            do97.append(UInt8(min(le, 0xFF)))
        }

        // Build MAC input: SSC || padded(CLA|INS|P1|P2) || DO'87 || DO'97
        var macInput = Data()
        macInput.append(ssc)

        // Padded command header (CLA with secure messaging bit set)
        let maskedCLA = apdu.instructionClass | 0x0C
        var cmdHeader = Data([maskedCLA, apdu.instructionCode, apdu.p1Parameter, apdu.p2Parameter])
        cmdHeader = iso9797Pad(cmdHeader)
        macInput.append(cmdHeader)

        if !do87.isEmpty {
            macInput.append(do87)
        }
        if !do97.isEmpty {
            macInput.append(do97)
        }
        macInput = iso9797Pad(macInput)

        // Compute MAC
        let mac = retailMAC(data: macInput, key: ksMac)

        // Build DO'8E (MAC)
        var do8E = Data()
        do8E.append(0x8E)
        do8E.append(0x08)
        do8E.append(mac)

        // Construct protected APDU data
        var protectedData = Data()
        if !do87.isEmpty { protectedData.append(do87) }
        if !do97.isEmpty { protectedData.append(do97) }
        protectedData.append(do8E)

        return NFCISO7816APDU(
            instructionClass: apdu.instructionClass | 0x0C,
            instructionCode: apdu.instructionCode,
            p1Parameter: apdu.p1Parameter,
            p2Parameter: apdu.p2Parameter,
            data: protectedData,
            expectedResponseLength: 256
        )
    }

    /// Unwrap a secure messaging response to extract plaintext data
    private func unwrapSecureResponse(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }

        var plainData = Data()
        var index = 0
        let bytes = [UInt8](data)

        while index < bytes.count {
            let tag = bytes[index]
            index += 1

            guard index < bytes.count else { break }

            let (length, lenBytes) = parseBERLength(bytes, offset: index)
            index += lenBytes

            let valueEnd = index + Int(length)
            guard valueEnd <= bytes.count else { break }

            switch tag {
            case 0x87:
                // Encrypted data — skip padding indicator byte, then decrypt
                if index < valueEnd, bytes[index] == 0x01 {
                    let encrypted = Data(bytes[(index + 1)..<valueEnd])
                    if let ksEnc = self.ksEnc {
                        let decrypted = tripleDESDecrypt(data: encrypted, key: ksEnc)
                        plainData.append(removePadding(decrypted))
                    }
                }
            case 0x99:
                // Status word — ignore for data extraction
                break
            case 0x8E:
                // MAC — ignore (should verify in production)
                break
            default:
                break
            }

            index = valueEnd
        }

        return plainData
    }

    /// Increment the Send Sequence Counter
    private func incrementSSC() {
        guard var ssc = self.ssc else { return }
        // Increment the 8-byte counter as a big-endian integer
        var carry: UInt16 = 1
        for i in stride(from: ssc.count - 1, through: 0, by: -1) {
            let sum = UInt16(ssc[i]) + carry
            ssc[i] = UInt8(sum & 0xFF)
            carry = sum >> 8
            if carry == 0 { break }
        }
        self.ssc = ssc
    }

    // MARK: - Cryptographic Operations

    /// Derive a 3DES key from K_seed using ICAO 9303 key derivation
    private func deriveKey(kSeed: Data, counter: UInt8) -> Data {
        // D = K_seed || 00 00 00 counter
        var d = Data(kSeed)
        d.append(contentsOf: [0x00, 0x00, 0x00, counter])

        // Hash with SHA-1
        let hash = sha1(d)

        // Ka = first 8 bytes, Kb = next 8 bytes
        let ka = adjustParity(Data(hash.prefix(8)))
        let kb = adjustParity(Data(hash.dropFirst(8).prefix(8)))

        // 3DES key = Ka || Kb || Ka (2-key 3DES as 24-byte key)
        var key = Data()
        key.append(ka)
        key.append(kb)
        key.append(ka)
        return key
    }

    /// Adjust DES key parity bits (odd parity for each byte)
    private func adjustParity(_ key: Data) -> Data {
        var adjusted = Data(count: key.count)
        for i in 0..<key.count {
            var b = key[i] & 0xFE
            // Count bits
            var bits = b
            bits = (bits ^ (bits >> 4))
            bits = (bits ^ (bits >> 2))
            bits = (bits ^ (bits >> 1))
            // Set parity bit
            if (bits & 1) == 0 {
                b |= 1
            }
            adjusted[i] = b
        }
        return adjusted
    }

    /// 3DES-CBC encrypt (IV = 0)
    private func tripleDESEncrypt(data: Data, key: Data) -> Data {
        let keyBytes = [UInt8](key)
        let dataBytes = [UInt8](data)
        var outBytes = [UInt8](repeating: 0, count: data.count + kCCBlockSize3DES)
        var outLength: size_t = 0

        let status = CCCrypt(
            CCOperation(kCCEncrypt),
            CCAlgorithm(kCCAlgorithm3DES),
            0, // No padding — we handle padding ourselves
            keyBytes, keyBytes.count,
            nil, // IV = 0
            dataBytes, dataBytes.count,
            &outBytes, outBytes.count,
            &outLength
        )

        guard status == kCCSuccess else { return Data() }
        return Data(outBytes.prefix(outLength))
    }

    /// 3DES-CBC decrypt (IV = 0)
    private func tripleDESDecrypt(data: Data, key: Data) -> Data {
        let keyBytes = [UInt8](key)
        let dataBytes = [UInt8](data)
        var outBytes = [UInt8](repeating: 0, count: data.count + kCCBlockSize3DES)
        var outLength: size_t = 0

        let status = CCCrypt(
            CCOperation(kCCDecrypt),
            CCAlgorithm(kCCAlgorithm3DES),
            0, // No padding
            keyBytes, keyBytes.count,
            nil, // IV = 0
            dataBytes, dataBytes.count,
            &outBytes, outBytes.count,
            &outLength
        )

        guard status == kCCSuccess else { return Data() }
        return Data(outBytes.prefix(outLength))
    }

    /// Single DES-CBC encrypt (for retail MAC intermediate steps)
    private func desEncrypt(data: Data, key: Data, iv: Data? = nil) -> Data {
        let keyBytes = [UInt8](key)
        let dataBytes = [UInt8](data)
        let ivBytes: [UInt8]? = iv.map { [UInt8]($0) }
        var outBytes = [UInt8](repeating: 0, count: data.count + kCCBlockSizeDES)
        var outLength: size_t = 0

        let status = CCCrypt(
            CCOperation(kCCEncrypt),
            CCAlgorithm(kCCAlgorithmDES),
            0, // No padding
            keyBytes, min(keyBytes.count, kCCKeySizeDES),
            ivBytes, // IV
            dataBytes, dataBytes.count,
            &outBytes, outBytes.count,
            &outLength
        )

        guard status == kCCSuccess else { return Data() }
        return Data(outBytes.prefix(outLength))
    }

    /// ISO 9797-1 MAC Algorithm 3 (Retail MAC) using DES/3DES
    /// Uses single DES for all blocks except the last, which uses 3DES
    private func retailMAC(data: Data, key: Data) -> Data {
        // Split the 24-byte 3DES key into Ka (first 8) and Kb (second 8)
        let ka = Data(key.prefix(8))
        let kb = Data(key.dropFirst(8).prefix(8))

        let padded = iso9797Pad(data)
        let blocks = stride(from: 0, to: padded.count, by: 8).map {
            Data(padded[$0..<min($0 + 8, padded.count)])
        }

        guard !blocks.isEmpty else { return Data(count: 8) }

        // Process all blocks with DES(Ka) in CBC mode
        var intermediate = Data(count: 8) // IV = 0
        for block in blocks {
            // XOR with previous result
            var xored = Data(count: 8)
            for i in 0..<8 {
                xored[i] = intermediate[i] ^ block[i]
            }
            intermediate = desEncrypt(data: xored, key: ka)
        }

        // Final block: decrypt with Kb, then encrypt with Ka
        let decrypted = desDecrypt(data: intermediate, key: kb)
        let mac = desEncrypt(data: decrypted, key: ka)

        return Data(mac.prefix(8))
    }

    /// Single DES-CBC decrypt
    private func desDecrypt(data: Data, key: Data, iv: Data? = nil) -> Data {
        let keyBytes = [UInt8](key)
        let dataBytes = [UInt8](data)
        let ivBytes: [UInt8]? = iv.map { [UInt8]($0) }
        var outBytes = [UInt8](repeating: 0, count: data.count + kCCBlockSizeDES)
        var outLength: size_t = 0

        let status = CCCrypt(
            CCOperation(kCCDecrypt),
            CCAlgorithm(kCCAlgorithmDES),
            0,
            keyBytes, min(keyBytes.count, kCCKeySizeDES),
            ivBytes,
            dataBytes, dataBytes.count,
            &outBytes, outBytes.count,
            &outLength
        )

        guard status == kCCSuccess else { return Data() }
        return Data(outBytes.prefix(outLength))
    }

    /// ISO 9797-1 padding (add 0x80 then 0x00 bytes to reach block boundary)
    private func iso9797Pad(_ data: Data) -> Data {
        var padded = Data(data)
        padded.append(0x80)
        while padded.count % 8 != 0 {
            padded.append(0x00)
        }
        return padded
    }

    /// Remove ISO 9797-1 padding
    private func removePadding(_ data: Data) -> Data {
        guard !data.isEmpty else { return data }
        // Find 0x80 marker from the end
        for i in stride(from: data.count - 1, through: 0, by: -1) {
            if data[i] == 0x80 {
                return Data(data.prefix(i))
            } else if data[i] != 0x00 {
                // No padding found — return as-is
                return data
            }
        }
        return data
    }

    /// SHA-1 hash
    private func sha1(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA1(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }

    /// SHA-256 hash
    private func sha256(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }

    /// Generate cryptographically random bytes
    private func generateRandom(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    // MARK: - BER Length Encoding

    /// Encode a length value in BER format
    private func encodeBERLength(_ length: Int) -> [UInt8] {
        if length < 0x80 {
            return [UInt8(length)]
        } else if length <= 0xFF {
            return [0x81, UInt8(length)]
        } else if length <= 0xFFFF {
            return [0x82, UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)]
        } else {
            return [0x83, UInt8((length >> 16) & 0xFF), UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)]
        }
    }

    // MARK: - Error Handling

    private func finishWithError(_ error: NFCPassportError) {
        tagSession?.invalidate(errorMessage: error.localizedDescription)
        tagSession = nil
        completion?(.failure(error))
        completion = nil
    }
}

// MARK: - NFCTagReaderSessionDelegate

@available(iOS 13.0, *)
extension NFCPassportReader: NFCTagReaderSessionDelegate {

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        KoraIDV.log("NFC session became active")
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        let nfcError = error as NSError

        // Check for user cancellation
        if nfcError.code == NFCReaderError.readerSessionInvalidationErrorUserCanceled.rawValue {
            completion?(.failure(.userCancelled))
        } else if nfcError.code == NFCReaderError.readerSessionInvalidationErrorSessionTimeout.rawValue {
            completion?(.failure(.sessionTimeout))
        } else if nfcError.code != NFCReaderError.readerSessionInvalidationErrorFirstNDEFTagRead.rawValue {
            // Don't report error for normal invalidation
            KoraIDV.log("NFC session invalidated: \(error.localizedDescription)")
        }

        tagSession = nil
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "No passport detected.")
            return
        }

        // We need an ISO 7816 tag
        guard case .iso7816(let iso7816Tag) = tag else {
            session.invalidate(errorMessage: "This is not a supported passport.")
            return
        }

        session.connect(to: tag) { [weak self] error in
            if let error = error {
                session.invalidate(errorMessage: "Connection failed: \(error.localizedDescription)")
                return
            }

            self?.readPassport(tag: iso7816Tag)
        }
    }
}

// MARK: - TLV Parser

/// Simple TLV (Tag-Length-Value) parser for ASN.1/BER encoded data
struct TLVParser {

    struct TLV {
        let tag: UInt64
        let value: Data
    }

    /// Parse TLV-encoded data
    static func parse(_ data: Data) -> [TLV] {
        var results: [TLV] = []
        var index = 0
        let bytes = [UInt8](data)

        while index < bytes.count {
            // Parse tag
            let (tag, tagLength) = parseTag(bytes, offset: index)
            index += tagLength

            guard index < bytes.count else { break }

            // Parse length
            let (length, lengthBytes) = parseLength(Data(bytes[index...]))
            index += lengthBytes

            guard length > 0, index + Int(length) <= bytes.count else { break }

            // Extract value
            let value = Data(bytes[index..<(index + Int(length))])
            results.append(TLV(tag: tag, value: value))

            index += Int(length)
        }

        return results
    }

    /// Parse a TLV tag (handles multi-byte tags)
    static func parseTag(_ bytes: [UInt8], offset: Int) -> (UInt64, Int) {
        guard offset < bytes.count else { return (0, 0) }

        var tag = UInt64(bytes[offset])
        var length = 1

        // Check if this is a multi-byte tag
        if (bytes[offset] & 0x1F) == 0x1F {
            // Multi-byte tag
            while offset + length < bytes.count {
                tag = (tag << 8) | UInt64(bytes[offset + length])
                length += 1
                if (bytes[offset + length - 1] & 0x80) == 0 {
                    break
                }
            }
        }

        return (tag, length)
    }

    /// Parse a BER length field
    static func parseLength(_ data: Data) -> (UInt64, Int) {
        guard !data.isEmpty else { return (0, 0) }

        let firstByte = data[data.startIndex]

        if firstByte < 0x80 {
            return (UInt64(firstByte), 1)
        }

        if firstByte == 0x80 {
            // Indefinite length — not supported, return 0
            return (0, 1)
        }

        let numBytes = Int(firstByte & 0x7F)
        guard numBytes > 0, numBytes <= 4, data.count >= 1 + numBytes else {
            return (0, 1)
        }

        var length: UInt64 = 0
        for i in 0..<numBytes {
            length = (length << 8) | UInt64(data[data.startIndex + 1 + i])
        }

        return (length, 1 + numBytes)
    }
}

#endif // canImport(CoreNFC)
