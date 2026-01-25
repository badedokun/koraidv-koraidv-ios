import Foundation

/// Verification model
public struct Verification: Codable {
    /// Unique verification ID
    public let id: String

    /// External ID provided by the client
    public let externalId: String

    /// Tenant ID
    public let tenantId: String

    /// Verification tier
    public let tier: String

    /// Current status
    public let status: VerificationStatus

    /// Document verification result
    public let documentVerification: DocumentVerification?

    /// Face verification result
    public let faceVerification: FaceVerification?

    /// Liveness verification result
    public let livenessVerification: LivenessVerification?

    /// Risk signals
    public let riskSignals: [RiskSignal]?

    /// Overall risk score (0-100)
    public let riskScore: Int?

    /// Creation timestamp
    public let createdAt: Date

    /// Last update timestamp
    public let updatedAt: Date

    /// Completion timestamp
    public let completedAt: Date?
}

/// Verification status
public enum VerificationStatus: String, Codable {
    case pending = "pending"
    case documentRequired = "document_required"
    case selfieRequired = "selfie_required"
    case livenessRequired = "liveness_required"
    case processing = "processing"
    case approved = "approved"
    case rejected = "rejected"
    case reviewRequired = "review_required"
    case expired = "expired"
}

/// Document verification result
public struct DocumentVerification: Codable {
    public let documentType: String
    public let documentNumber: String?
    public let firstName: String?
    public let lastName: String?
    public let dateOfBirth: String?
    public let expirationDate: String?
    public let issuingCountry: String?
    public let mrzValid: Bool?
    public let authenticityScore: Double?
    public let extractedFields: [String: String]?
}

/// Face verification result
public struct FaceVerification: Codable {
    public let matchScore: Double
    public let matchResult: String
    public let confidence: Double
}

/// Liveness verification result
public struct LivenessVerification: Codable {
    public let livenessScore: Double
    public let isLive: Bool
    public let challengeResults: [ChallengeResult]?
}

/// Individual challenge result
public struct ChallengeResult: Codable {
    public let type: String
    public let passed: Bool
    public let confidence: Double
}

/// Risk signal
public struct RiskSignal: Codable {
    public let code: String
    public let severity: String
    public let message: String
}

// MARK: - Request/Response Models

/// Create verification request
struct CreateVerificationRequest: Encodable {
    let externalId: String
    let tier: String
}

/// Document upload response
struct DocumentUploadResponse: Decodable {
    let success: Bool
    let documentId: String?
    let qualityScore: Double?
    let qualityIssues: [QualityIssue]?
    let extractedData: DocumentVerification?
}

/// Quality issue
struct QualityIssue: Decodable {
    let type: String
    let message: String
    let severity: String
}

/// Selfie upload response
struct SelfieUploadResponse: Decodable {
    let success: Bool
    let selfieId: String?
    let faceDetected: Bool
    let qualityScore: Double?
    let qualityIssues: [QualityIssue]?
}

/// Document upload metadata
struct DocumentUploadMetadata: Encodable {
    let documentType: String
    let side: String
}

/// Liveness session
struct LivenessSession: Decodable {
    let sessionId: String
    let challenges: [LivenessChallenge]
    let expiresAt: Date
}

/// Liveness challenge
public struct LivenessChallenge: Decodable {
    public let id: String
    public let type: ChallengeType
    public let instruction: String
    public let order: Int
}

/// Challenge type
public enum ChallengeType: String, Codable {
    case blink = "blink"
    case smile = "smile"
    case turnLeft = "turn_left"
    case turnRight = "turn_right"
    case nodUp = "nod_up"
    case nodDown = "nod_down"
}

/// Liveness challenge metadata
struct LivenessChallengeMetadata: Encodable {
    let challengeType: String
    let challengeId: String
}

/// Liveness challenge response
struct LivenessChallengeResponse: Decodable {
    let success: Bool
    let challengePassed: Bool
    let confidence: Double
    let remainingChallenges: Int
}
