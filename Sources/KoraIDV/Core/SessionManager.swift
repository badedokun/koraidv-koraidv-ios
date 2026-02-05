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

    /// Upload document image
    func uploadDocument(
        verificationId: String,
        imageData: Data,
        side: DocumentSide,
        documentType: DocumentType,
        completion: @escaping (Result<DocumentUploadResponse, KoraError>) -> Void
    ) {
        let endpoint: APIEndpoint = side == .front
            ? .uploadDocument(id: verificationId)
            : .uploadDocumentBack(id: verificationId)

        let metadata = DocumentUploadMetadata(
            documentType: documentType.rawValue,
            side: side.rawValue
        )

        apiClient.uploadImage(
            endpoint: endpoint,
            imageData: imageData,
            metadata: metadata,
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
