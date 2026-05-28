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
        countryCode: String? = nil,
        completion: @escaping (Result<DocumentUploadResponse, KoraError>) -> Void
    ) {
        // Back side: JSON contract matching the server's /document/back
        // handler + the Android SDK's wire format. Carries the optional
        // on-device-decoded barcode payload (Phase 3 fast path).
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

        // Front side: JSON path. Previously this was multipart, which the
        // backend handler rejected with HTTP 400 because /document only
        // parses application/json — that was the iOS-specific failure
        // BanffPay reported 2026-05-25. Aligning with the Android wire
        // format also lets us include `country` so the backend can
        // backfill verification.selectedCountry and fire the
        // selected-vs-detected mismatch gate at /complete.
        let request = UploadDocumentRequest(
            documentType: documentType.rawValue,
            imageBase64: imageData.base64EncodedString(),
            country: countryCode
        )

        apiClient.request(
            endpoint: .uploadDocument(id: verificationId),
            method: .post,
            body: request,
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

    /// Upload selfie image.
    ///
    /// JSON path matching the server's `/v1/verifications/{id}/selfie`
    /// handler and the Android SDK's wire format. Previously this used
    /// `apiClient.uploadImage` (multipart) which the JSON-only handler
    /// rejected with HTTP 400 — sister bug to the v1.6.0 `/document`
    /// fix, missed during that audit and surfaced by BanffPay in v1.6.1
    /// once the upstream blockers cleared.
    func uploadSelfie(
        verificationId: String,
        imageData: Data,
        completion: @escaping (Result<SelfieUploadResponse, KoraError>) -> Void
    ) {
        let request = UploadSelfieRequest(
            imageBase64: imageData.base64EncodedString()
        )
        apiClient.request(
            endpoint: .uploadSelfie(id: verificationId),
            method: .post,
            body: request,
            completion: completion
        )
    }

    /// Create liveness session.
    ///
    /// Decodes the wire DTO (matches backend's `models.LivenessSession`
    /// JSON), then projects it onto the domain `LivenessSession` the UI
    /// expects. The backend doesn't send `sessionId`/`expiresAt`, and
    /// per-challenge `id`/`instruction`/`order` aren't on the wire — the
    /// domain values are synthesized client-side here. Mirrors the
    /// Android pattern at koraidv-android/.../SessionManager.kt:240.
    ///
    /// Before this DTO/domain split, the SDK decoded directly into
    /// `LivenessSession` with non-optional fields the server doesn't
    /// send, so the first liveness call after a successful selfie threw
    /// `keyNotFound` ("data couldn't be read because it is missing").
    /// Surfaced by BanffPay 2026-05-28.
    func createLivenessSession(
        verificationId: String,
        completion: @escaping (Result<LivenessSession, KoraError>) -> Void
    ) {
        apiClient.request(
            endpoint: .createLivenessSession(id: verificationId),
            method: .post,
            body: EmptyBody()
        ) { (result: Result<LivenessSessionDTO, KoraError>) in
            switch result {
            case .success(let dto):
                let session = LivenessSession(
                    sessionId: dto.id,
                    challenges: dto.challenges.enumerated().map { index, challenge in
                        LivenessChallenge(
                            id: "\(dto.id)_\(index)",
                            type: challenge.type,
                            instruction: Self.instructionForChallengeType(challenge.type),
                            order: index
                        )
                    },
                    // Backend doesn't return expiresAt; the SDK enforces a
                    // local 5-minute timeout consistent with the Android peer.
                    expiresAt: Date(timeIntervalSinceNow: 300)
                )
                completion(.success(session))
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    /// Client-side instruction text for a liveness challenge type. Mirrors
    /// the Android peer's `getInstructionForType`. Not localized yet —
    /// matches the Android English defaults for the v1.7.0 cutover; pull
    /// into L10n on the next pass.
    private static func instructionForChallengeType(_ type: ChallengeType) -> String {
        switch type {
        case .blink: return "Blink your eyes slowly"
        case .smile: return "Smile naturally"
        case .turnLeft: return "Slowly turn your head to the left"
        case .turnRight: return "Slowly turn your head to the right"
        case .nodUp: return "Slowly tilt your head up"
        case .nodDown: return "Slowly tilt your head down"
        }
    }

    /// Submit liveness challenge result.
    ///
    /// JSON path matching the server's
    /// `/v1/verifications/{id}/liveness/challenge` handler and the
    /// Android SDK's wire format. Previously used `apiClient.uploadImage`
    /// (multipart) — same multipart-vs-JSON sister bug as `uploadSelfie`
    /// above. Latent since iOS shipped; would have fired the moment
    /// anyone got past the selfie step. Fixed in v1.6.2.
    func submitLivenessChallenge(
        verificationId: String,
        challenge: LivenessChallenge,
        imageData: Data,
        completion: @escaping (Result<LivenessChallengeResponse, KoraError>) -> Void
    ) {
        let request = SubmitLivenessChallengeRequest(
            challengeType: challenge.type.rawValue,
            imageBase64: imageData.base64EncodedString()
        )
        apiClient.request(
            endpoint: .submitLivenessChallenge(id: verificationId),
            method: .post,
            body: request,
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
