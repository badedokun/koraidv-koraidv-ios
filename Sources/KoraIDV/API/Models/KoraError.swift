import Foundation

/// Kora SDK Error types
public enum KoraError: LocalizedError {

    // MARK: - Configuration Errors

    /// SDK not configured
    case notConfigured

    /// Invalid API key
    case invalidAPIKey

    /// Invalid tenant ID
    case invalidTenantId

    // MARK: - Network Errors

    /// Network connection error
    case networkError(Error)

    /// Request timed out
    case timeout

    /// No internet connection
    case noInternet

    // MARK: - HTTP Errors

    /// Unauthorized (401)
    case unauthorized

    /// Forbidden (403)
    case forbidden

    /// Resource not found (404)
    case notFound

    /// Validation error (422)
    case validationError([ValidationError]?)

    /// Rate limited (429)
    case rateLimited

    /// Server error (5xx)
    case serverError(Int)

    /// Other HTTP error
    case httpError(Int)

    // MARK: - Response Errors

    /// Invalid response
    case invalidResponse

    /// No data in response
    case noData

    /// Decoding error
    case decodingError(Error)

    /// Encoding error
    case encodingError(Error)

    // MARK: - Capture Errors

    /// Camera access denied
    case cameraAccessDenied

    /// Camera not available
    case cameraNotAvailable

    /// Capture failed
    case captureFailed(String)

    /// Quality validation failed
    case qualityValidationFailed([String])

    // MARK: - Document Errors

    /// Document not detected
    case documentNotDetected

    /// Document type not supported
    case documentTypeNotSupported

    /// MRZ could not be read
    case mrzReadFailed

    // MARK: - Face Errors

    /// Face not detected
    case faceNotDetected

    /// Multiple faces detected
    case multipleFacesDetected

    /// Face match failed
    case faceMatchFailed

    // MARK: - Liveness Errors

    /// Liveness check failed
    case livenessCheckFailed

    /// Challenge not completed
    case challengeNotCompleted(String)

    /// Session expired
    case sessionExpired

    // MARK: - Verification Errors

    /// Verification expired
    case verificationExpired

    /// Verification already completed
    case verificationAlreadyCompleted

    /// Invalid verification state
    case invalidVerificationState(String)

    // MARK: - Generic Errors

    /// Unknown error
    case unknown(String)

    /// User cancelled
    case userCancelled

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "SDK not configured. Call KoraIDV.configure() first."
        case .invalidAPIKey:
            return "Invalid API key provided."
        case .invalidTenantId:
            return "Invalid tenant ID provided."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .timeout:
            return "Request timed out. Please try again."
        case .noInternet:
            return "No internet connection. Please check your network."
        case .unauthorized:
            return "Authentication failed. Please check your API key."
        case .forbidden:
            return "Access denied."
        case .notFound:
            return "Resource not found."
        case .validationError(let errors):
            if let errors = errors, !errors.isEmpty {
                return errors.map { "\($0.field): \($0.message)" }.joined(separator: ", ")
            }
            return "Validation error."
        case .rateLimited:
            return "Rate limit exceeded. Please try again later."
        case .serverError(let code):
            return "Server error (\(code)). Please try again later."
        case .httpError(let code):
            return "HTTP error (\(code))."
        case .invalidResponse:
            return "Invalid response from server."
        case .noData:
            return "No data received from server."
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .cameraAccessDenied:
            return "Camera access denied. Please enable camera access in Settings."
        case .cameraNotAvailable:
            return "Camera not available on this device."
        case .captureFailed(let reason):
            return "Capture failed: \(reason)"
        case .qualityValidationFailed(let issues):
            return "Quality check failed: \(issues.joined(separator: ", "))"
        case .documentNotDetected:
            return "Document not detected. Please position the document within the frame."
        case .documentTypeNotSupported:
            return "This document type is not supported."
        case .mrzReadFailed:
            return "Could not read document MRZ. Please try again."
        case .faceNotDetected:
            return "Face not detected. Please position your face within the frame."
        case .multipleFacesDetected:
            return "Multiple faces detected. Please ensure only one face is visible."
        case .faceMatchFailed:
            return "Face match failed. Please try again."
        case .livenessCheckFailed:
            return "Liveness check failed. Please try again."
        case .challengeNotCompleted(let challenge):
            return "Challenge '\(challenge)' was not completed successfully."
        case .sessionExpired:
            return "Session expired. Please start a new verification."
        case .verificationExpired:
            return "Verification expired. Please start a new verification."
        case .verificationAlreadyCompleted:
            return "This verification has already been completed."
        case .invalidVerificationState(let state):
            return "Invalid verification state: \(state)"
        case .unknown(let message):
            return message
        case .userCancelled:
            return "Verification cancelled by user."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .cameraAccessDenied:
            return "Go to Settings > Privacy > Camera and enable access for this app."
        case .noInternet:
            return "Check your Wi-Fi or cellular connection and try again."
        case .timeout, .serverError, .rateLimited:
            return "Please wait a moment and try again."
        case .documentNotDetected:
            return "Place the document on a flat, well-lit surface and center it in the frame."
        case .faceNotDetected:
            return "Ensure good lighting and center your face in the oval guide."
        case .qualityValidationFailed:
            return "Hold the device steady and ensure good lighting."
        default:
            return nil
        }
    }

    /// Error code for analytics
    public var errorCode: String {
        switch self {
        case .notConfigured: return "NOT_CONFIGURED"
        case .invalidAPIKey: return "INVALID_API_KEY"
        case .invalidTenantId: return "INVALID_TENANT_ID"
        case .networkError: return "NETWORK_ERROR"
        case .timeout: return "TIMEOUT"
        case .noInternet: return "NO_INTERNET"
        case .unauthorized: return "UNAUTHORIZED"
        case .forbidden: return "FORBIDDEN"
        case .notFound: return "NOT_FOUND"
        case .validationError: return "VALIDATION_ERROR"
        case .rateLimited: return "RATE_LIMITED"
        case .serverError: return "SERVER_ERROR"
        case .httpError: return "HTTP_ERROR"
        case .invalidResponse: return "INVALID_RESPONSE"
        case .noData: return "NO_DATA"
        case .decodingError: return "DECODING_ERROR"
        case .encodingError: return "ENCODING_ERROR"
        case .cameraAccessDenied: return "CAMERA_ACCESS_DENIED"
        case .cameraNotAvailable: return "CAMERA_NOT_AVAILABLE"
        case .captureFailed: return "CAPTURE_FAILED"
        case .qualityValidationFailed: return "QUALITY_VALIDATION_FAILED"
        case .documentNotDetected: return "DOCUMENT_NOT_DETECTED"
        case .documentTypeNotSupported: return "DOCUMENT_TYPE_NOT_SUPPORTED"
        case .mrzReadFailed: return "MRZ_READ_FAILED"
        case .faceNotDetected: return "FACE_NOT_DETECTED"
        case .multipleFacesDetected: return "MULTIPLE_FACES_DETECTED"
        case .faceMatchFailed: return "FACE_MATCH_FAILED"
        case .livenessCheckFailed: return "LIVENESS_CHECK_FAILED"
        case .challengeNotCompleted: return "CHALLENGE_NOT_COMPLETED"
        case .sessionExpired: return "SESSION_EXPIRED"
        case .verificationExpired: return "VERIFICATION_EXPIRED"
        case .verificationAlreadyCompleted: return "VERIFICATION_ALREADY_COMPLETED"
        case .invalidVerificationState: return "INVALID_VERIFICATION_STATE"
        case .unknown: return "UNKNOWN"
        case .userCancelled: return "USER_CANCELLED"
        }
    }

    /// Compatibility property for code access
    public var code: ErrorCode {
        return ErrorCode(rawValue: errorCode)
    }

    /// Compatibility property for message access
    public var message: String {
        return errorDescription ?? "Unknown error"
    }
}

// MARK: - Error Code Wrapper

/// Wrapper for error code to provide rawValue access
public struct ErrorCode: RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
