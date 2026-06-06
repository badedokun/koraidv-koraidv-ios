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

    /// Backend verification scores (0-100 scale)
    public let scores: VerificationScores?

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

/// Backend verification scores (0-100 scale).
///
/// **v1.9.0-rc4 fix.** rc3 declared `screening: Double` as required, but
/// the backend `/complete` response never returns a field by that name —
/// the wire field is `complianceScore` (and it's `omitempty`, so it's
/// often absent entirely). Net result: every rc3 `/complete` response
/// that contained a non-nil `scores` object failed to decode with
/// `keyNotFound("screening")`, which surfaces to the host as
/// "Failed to parse response: The data couldn't be read because it is
/// missing" — the symptom Stratum Remit reported on 2026-06-06 after
/// the rc3 device test.
///
/// Two changes here:
///
/// 1. `screening` → `Double?`. Allows decode to succeed when the
///    backend omits `complianceScore` (the most common case — most
///    verifications don't go through compliance screening).
///
/// 2. `CodingKeys` maps `screening` ← `complianceScore`. Matches the
///    Android SDK's wire-DTO/domain projection at
///    `koraidv-android/.../SessionManager.kt:547`
///    (`screening = it.complianceScore ?: 0.0`). Same consumer-facing
///    field name across platforms; same wire contract; no API break.
///
/// The other fields stay required because the backend always returns
/// them (documentQuality, documentAuth, faceMatch, liveness, nameMatch,
/// dataConsistency, overall are all non-omitempty `float64` in
/// `models.VerificationScores`). Defensive optional-everywhere would
/// be safer but is a public-API change — defer to v1.10.
public struct VerificationScores: Codable {
    public let documentQuality: Double
    public let documentAuth: Double
    public let faceMatch: Double
    public let liveness: Double
    public let nameMatch: Double
    public let dataConsistency: Double
    public let screening: Double?
    public let overall: Double

    enum CodingKeys: String, CodingKey {
        case documentQuality
        case documentAuth
        case faceMatch
        case liveness
        case nameMatch
        case dataConsistency
        case screening = "complianceScore"
        case overall
    }
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
    let expectedFirstName: String?
    let expectedLastName: String?
}

/// Document upload response.
///
/// The backend's `ProcessDocumentResult` does NOT include a top-level
/// `success` field — a 2xx HTTP status IS the success signal. iOS
/// previously declared `success: Bool` as required which caused
/// `JSONDecoder` to throw `keyNotFound` ("data couldn't be read because
/// it is missing") as soon as the SDK actually started getting 2xx
/// responses in v1.6.0 (the multipart→JSON cutover unmasked it —
/// pre-1.6.0 uploads always got HTTP 400 and never reached this path).
/// Android tolerates the missing field because all its DTO fields are
/// nullable. Surfaced by BanffPay 2026-05-26.
struct DocumentUploadResponse: Decodable {
    let success: Bool?
    let documentId: String?
    let qualityScore: Double?
    let qualityIssues: [APIQualityIssue]?
    let extractedData: DocumentVerification?
    let imagePersisted: Bool?

    /// Convenience: HTTP 2xx + decode succeeded ⇒ upload succeeded.
    /// Treats absent `success` as `true` so a server that omits the
    /// field is interpreted as success rather than failure.
    var isSuccess: Bool { success ?? true }
}

/// API Quality issue (from server responses)
struct APIQualityIssue: Decodable {
    let type: String
    let message: String
    let severity: String
}

/// Selfie upload response. Same backend-omits-`success` story as
/// `DocumentUploadResponse` above. `faceDetected` IS returned by the
/// backend so we keep it required.
struct SelfieUploadResponse: Decodable {
    let success: Bool?
    let selfieId: String?
    let faceDetected: Bool
    let qualityScore: Double?
    let qualityIssues: [APIQualityIssue]?
    let imagePersisted: Bool?

    var isSuccess: Bool { success ?? true }
}

/// Document upload metadata (legacy multipart form — DEPRECATED).
///
/// The backend handler only parses `application/json` on /document; the
/// multipart path returned HTTP 400 for every iOS upload (silent bug from
/// the day the iOS SDK shipped, surfaced 2026-05-25 by BanffPay's
/// Olabode). Front uploads now use `UploadDocumentRequest` (the same
/// JSON-with-base64 contract as Android + the existing back-side path).
/// Kept here only so the multipart helper in APIClient.uploadImage still
/// type-checks for unrelated callers (NFC, etc.).
struct DocumentUploadMetadata: Encodable {
    let documentType: String
    let side: String
}

/// Front-side document upload request (JSON path — matches the server's
/// /v1/verifications/{id}/document handler and the Android SDK's wire
/// format). Replaces the broken multipart path above.
///
/// `country` is the ISO-3166 alpha-2 issuing country the SDK user picked
/// in the country picker. Sent here rather than at create-time because
/// createVerification fires at consent-accept, before the picker. Backend
/// backfills the verification's selectedCountry so the selected-vs-detected
/// mismatch gate can fire. Optional for backwards compat.
struct UploadDocumentRequest: Encodable {
    let documentType: String
    let imageBase64: String
    let country: String?
}

/// Selfie upload request (JSON path — matches the server's
/// `/v1/verifications/{id}/selfie` handler and the Android SDK's wire
/// format).
///
/// iOS previously used the multipart `apiClient.uploadImage` helper for
/// this endpoint, but the backend handler only parses JSON
/// (`UploadSelfieRequest { ImageBase64 string }` + `ShouldBindJSON`).
/// Result: every iOS selfie upload returned HTTP 400 since the SDK
/// shipped — invisible until v1.6.1 cleared the upstream blockers
/// (multipart→JSON on `/document`, then optional `success` on the
/// decoder). Sister bug to the v1.6.0 doc-front fix; missed during
/// that audit. Fixed in v1.6.2 (2026-05-27).
struct UploadSelfieRequest: Encodable {
    let imageBase64: String
}

/// Liveness-challenge submission request (JSON path — matches the
/// server's `/v1/verifications/{id}/liveness/challenge` handler and
/// the Android SDK's wire format).
///
/// Same multipart-vs-JSON sister bug as `UploadSelfieRequest` above —
/// iOS used `apiClient.uploadImage` (multipart) while the backend
/// `SubmitLivenessChallengeRequest { ChallengeType, ImageBase64 }`
/// strictly requires JSON. Latent since iOS shipped; would have
/// fired the moment anyone got past the selfie step. Fixed in v1.6.2.
struct SubmitLivenessChallengeRequest: Encodable {
    let challengeType: String
    let imageBase64: String
}

/// Back-side document upload request (JSON path — matches the
/// /v1/verifications/{id}/document/back server contract and the wire
/// format used by the Android SDK).
///
/// `decodedBarcodePayload` is the optional Phase 3 fast-path: when the
/// client decoded the PDF417 / QR / DataMatrix on-device using
/// `BarcodeScanner` (which wraps Apple Vision's `VNDetectBarcodesRequest`),
/// the AAMVA payload travels here so the server can skip image-based
/// barcode decoding. Empty/`nil` when on-device decode failed — server
/// falls back to its zxing-cpp + pdf417decoder cascade.
/// See `docs/architecture/idv-decode-roadmap.md` Phase 3.
struct UploadDocumentBackRequest: Encodable {
    let imageBase64: String
    let decodedBarcodePayload: String?
}

/// Liveness session (domain model — consumed by UI).
///
/// Constructed by mapping `LivenessSessionDTO` (the wire shape) — see
/// SessionManager.createLivenessSession for the DTO→domain projection.
/// Fields here include client-derived values (`id`-synthesized challenge
/// ids, locale-derived instructions, position-derived order, default
/// `expiresAt`) because the backend response does not carry them.
struct LivenessSession {
    let sessionId: String
    let challenges: [LivenessChallenge]
    let expiresAt: Date
}

/// Liveness challenge (domain model — consumed by UI).
public struct LivenessChallenge {
    public let id: String
    public let type: ChallengeType
    public let instruction: String
    public let order: Int
}

/// Wire-format DTO for the backend's `/v1/verifications/{id}/liveness/session`
/// response (matches `models.LivenessSession` in the Go identity-service).
/// The backend sends `id` (not `sessionId`), omits `expiresAt`, and the
/// nested challenge entries carry only `type` (no `id`, `instruction`,
/// or `order`). Domain-shaping happens in SessionManager — see the
/// android sibling at `koraidv-android/.../SessionManager.kt:240` for
/// the equivalent mapper.
struct LivenessSessionDTO: Decodable {
    let id: String
    let challenges: [LivenessChallengeDTO]
}

/// Wire-format DTO for a single challenge entry inside the liveness
/// session response. Only `type` is populated by the backend.
struct LivenessChallengeDTO: Decodable {
    let type: ChallengeType
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

/// Document quality check request.
///
/// The `/kyc/document-quality` endpoint is the one outlier in
/// identity-service still using snake_case JSON tags
/// (`document_front_base64`, `document_type`). Explicit CodingKeys
/// ensure the encoder produces snake_case on the wire regardless of
/// any keyEncodingStrategy default. Latent bug found via the Web SDK
/// in 2026-05-29; iOS hadn't surfaced it because no production iOS
/// flow currently calls `checkDocumentQuality`.
struct CheckDocumentQualityRequest: Encodable {
    let documentFrontBase64: String
    let documentType: String

    enum CodingKeys: String, CodingKey {
        case documentFrontBase64 = "document_front_base64"
        case documentType = "document_type"
    }
}

/// Document quality check response
public struct DocumentQualityResponse: Decodable {
    public let success: Bool
    public let qualityScore: Double
    public let qualityIssues: [String]
    public let details: DocumentQualityDetails?
}

/// Document quality details
public struct DocumentQualityDetails: Decodable {
    public let textReadability: Double
    public let faceQuality: Double
    public let imageClarity: Double
}

/// Liveness challenge response.
///
/// Defensive: backend doesn't return `success`, and the field names
/// for the other fields are a known mismatch with `SubmitLivenessChallengeResult`
/// (server returns `completed`/`score`/`allCompleted`, not
/// `challengePassed`/`confidence`/`remainingChallenges`). The full
/// rename is tracked for the next minor; making everything optional
/// here at least lets decode succeed instead of throwing.
struct LivenessChallengeResponse: Decodable {
    let success: Bool?
    let challengePassed: Bool?
    let confidence: Double?
    let remainingChallenges: Int?
    let imagePersisted: Bool?

    var isSuccess: Bool { success ?? true }
}
