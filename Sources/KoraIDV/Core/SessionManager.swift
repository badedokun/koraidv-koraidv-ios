import Foundation

/// Manages verification sessions and state
public final class SessionManager {

    // MARK: - Properties

    private let apiClient: APIClient
    private let configuration: Configuration

    /// Current active verification
    public private(set) var currentVerification: Verification?

    /// Session start time
    private var sessionStartTime: Date?

    // MARK: - Initialization

    init(configuration: Configuration) {
        self.configuration = configuration
        self.apiClient = APIClient(configuration: configuration)
    }

    // MARK: - Verification Lifecycle

    /// Create a new verification
    func createVerification(
        request: CreateVerificationRequest,
        completion: @escaping (Result<Verification, KoraError>) -> Void
    ) {
        sessionStartTime = Date()

        apiClient.request(
            endpoint: .createVerification,
            method: .post,
            body: request
        ) { [weak self] (result: Result<Verification, KoraError>) in
            if case .success(let verification) = result {
                self?.currentVerification = verification
            }
            completion(result)
        }
    }

    /// Get an existing verification
    func getVerification(
        id: String,
        completion: @escaping (Result<Verification, KoraError>) -> Void
    ) {
        apiClient.request(
            endpoint: .getVerification(id: id),
            method: .get
        ) { [weak self] (result: Result<Verification, KoraError>) in
            if case .success(let verification) = result {
                self?.currentVerification = verification
                self?.sessionStartTime = Date()
            }
            completion(result)
        }
    }

    /// Upload document image.
    ///
    /// `decodedBarcodePayload` is optional and only meaningful for back
    /// captures on documents that carry a barcode (US/CA DLs, voter's
    /// cards). When present (Vision decoded the PDF417 successfully on
    /// device — see `BarcodeScanner`), the server skips its own image
    /// decoding and parses the AAMVA payload directly. Empty/`nil` =
    /// server falls back to its zxing-cpp + pdf417decoder cascade.
    /// Phase 3 of the multi-channel decode roadmap.
    func uploadDocument(
        verificationId: String,
        imageData: Data,
        side: DocumentSide,
        documentType: DocumentType,
        decodedBarcodePayload: String? = nil,
        completion: @escaping (Result<DocumentUploadResponse, KoraError>) -> Void
    ) {
        // Back side: use the JSON contract that matches the server's
        // /document/back handler (and the Android SDK's wire format).
        // This is the path that carries `decodedBarcodePayload`.
        if side == .back {
            let request = UploadDocumentBackRequest(
                imageBase64: imageData.base64EncodedString(),
                decodedBarcodePayload: decodedBarcodePayload
            )
            apiClient.request(
                endpoint: .uploadDocumentBack(id: verificationId),
                method: .post,
                body: request,
                completion: completion
            )
            return
        }

        // Front side: existing multipart path (kept for compatibility).
        let metadata = DocumentUploadMetadata(
            documentType: documentType.rawValue,
            side: side.rawValue
        )

        apiClient.uploadImage(
            endpoint: .uploadDocument(id: verificationId),
            imageData: imageData,
            metadata: metadata,
            completion: completion
        )
    }

    /// Check document quality before uploading (no active verification required)
    func checkDocumentQuality(
        imageData: Data,
        documentType: DocumentType,
        completion: @escaping (Result<DocumentQualityResponse, KoraError>) -> Void
    ) {
        let base64 = imageData.base64EncodedString()
        let request = CheckDocumentQualityRequest(
            documentFrontBase64: base64,
            documentType: documentType.rawValue
        )

        apiClient.request(
            endpoint: .checkDocumentQuality,
            method: .post,
            body: request,
            completion: completion
        )
    }

    /// Upload selfie image
    func uploadSelfie(
        verificationId: String,
        imageData: Data,
        completion: @escaping (Result<SelfieUploadResponse, KoraError>) -> Void
    ) {
        apiClient.uploadImage(
            endpoint: .uploadSelfie(id: verificationId),
            imageData: imageData,
            metadata: nil as EmptyBody?,
            completion: completion
        )
    }

    /// Create liveness session
    func createLivenessSession(
        verificationId: String,
        completion: @escaping (Result<LivenessSession, KoraError>) -> Void
    ) {
        apiClient.request(
            endpoint: .createLivenessSession(id: verificationId),
            method: .post,
            body: EmptyBody()
        ) { (result: Result<LivenessSession, KoraError>) in
            completion(result)
        }
    }

    /// Submit liveness challenge result
    func submitLivenessChallenge(
        verificationId: String,
        challenge: LivenessChallenge,
        imageData: Data,
        completion: @escaping (Result<LivenessChallengeResponse, KoraError>) -> Void
    ) {
        let metadata = LivenessChallengeMetadata(
            challengeType: challenge.type.rawValue,
            challengeId: challenge.id
        )

        apiClient.uploadImage(
            endpoint: .submitLivenessChallenge(id: verificationId),
            imageData: imageData,
            metadata: metadata,
            completion: completion
        )
    }

    /// Upload NFC chip data
    func uploadNFCData(
        verificationId: String,
        nfcData: NFCPassportData,
        completion: @escaping (Result<NFCUploadResponse, KoraError>) -> Void
    ) {
        var dg1Hash: String?
        var dg2Hash: String?

        if let dg1Data = nfcData.dg1Data {
            dg1Hash = dg1Data.map { String(format: "%02x", $0) }.joined()
        }
        if let dg2Data = nfcData.dg2Data {
            dg2Hash = dg2Data.prefix(32).map { String(format: "%02x", $0) }.joined()
        }

        let request = NFCUploadRequest(
            documentNumber: nfcData.documentNumber,
            firstName: nfcData.firstName,
            lastName: nfcData.lastName,
            dateOfBirth: nfcData.dateOfBirth,
            expirationDate: nfcData.expirationDate,
            nationality: nfcData.nationality,
            sex: nfcData.sex,
            issuingCountry: nfcData.issuingCountry,
            passiveAuthPassed: nfcData.passiveAuthPassed,
            activeAuthPassed: nfcData.activeAuthPassed,
            chipAuthPassed: nfcData.chipAuthPassed,
            hasFaceImage: nfcData.faceImageData != nil,
            dg1Hash: dg1Hash,
            dg2Hash: dg2Hash
        )

        apiClient.request(
            endpoint: .uploadNFCData(id: verificationId),
            method: .post,
            body: request,
            completion: completion
        )
    }

    /// Complete the verification
    func completeVerification(
        verificationId: String,
        completion: @escaping (Result<Verification, KoraError>) -> Void
    ) {
        apiClient.request(
            endpoint: .completeVerification(id: verificationId),
            method: .post,
            body: EmptyBody()
        ) { [weak self] (result: Result<Verification, KoraError>) in
            if case .success(let verification) = result {
                self?.currentVerification = verification
            }
            completion(result)
        }
    }

    // MARK: - Document Types & Countries

    /// Fetch supported countries and document types from the API.
    /// Returns an array of `CountryInfo` populated with the document types
    /// that are both supported by the API and allowed by the SDK configuration.
    func fetchSupportedCountries(
        completion: @escaping (Result<[CountryInfo], KoraError>) -> Void
    ) {
        apiClient.request(
            endpoint: .getDocumentTypes(country: nil),
            method: .get
        ) { [weak self] (result: Result<DocumentTypesResponse, KoraError>) in
            switch result {
            case .success(let response):
                let configuredTypes = self?.configuration.documentTypes ?? DocumentType.allCases
                let countries = response.countries
                    .map { $0.toCountryInfo(documentTypes: response.documentTypes, configuredTypes: configuredTypes) }
                    .filter { !$0.documentTypes.isEmpty } // Only show countries that have at least one usable doc type
                completion(.success(countries))

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Session Management

    /// Check if the session has timed out
    var isSessionTimedOut: Bool {
        guard let startTime = sessionStartTime else { return false }
        return Date().timeIntervalSince(startTime) > configuration.timeout
    }

    /// Reset the session
    func resetSession() {
        currentVerification = nil
        sessionStartTime = nil
    }

    /// Refresh session timeout
    func refreshSession() {
        sessionStartTime = Date()
    }
}

// MARK: - Document Side

public enum DocumentSide: String {
    case front = "front"
    case back = "back"
}

// MARK: - Empty Body

private struct EmptyBody: Encodable {}
