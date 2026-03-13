import Foundation
import CommonCrypto

/// HTTP methods
enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// API endpoints
enum APIEndpoint {
    case createVerification
    case getVerification(id: String)
    case uploadDocument(id: String)
    case uploadDocumentBack(id: String)
    case uploadSelfie(id: String)
    case createLivenessSession(id: String)
    case submitLivenessChallenge(id: String)
    case completeVerification(id: String)
    case checkDocumentQuality
    case uploadNFCData(id: String)
    case getDocumentTypes(country: String?)

    var path: String {
        switch self {
        case .createVerification:
            return "/verifications"
        case .getVerification(let id):
            return "/verifications/\(id)"
        case .uploadDocument(let id):
            return "/verifications/\(id)/document"
        case .uploadDocumentBack(let id):
            return "/verifications/\(id)/document/back"
        case .uploadSelfie(let id):
            return "/verifications/\(id)/selfie"
        case .createLivenessSession(let id):
            return "/verifications/\(id)/liveness/session"
        case .submitLivenessChallenge(let id):
            return "/verifications/\(id)/liveness/challenge"
        case .completeVerification(let id):
            return "/verifications/\(id)/complete"
        case .checkDocumentQuality:
            return "/kyc/document-quality"
        case .uploadNFCData(let id):
            return "/verifications/\(id)/nfc"
        case .getDocumentTypes(let country):
            if let country = country, !country.isEmpty {
                return "/document-types?country=\(country)"
            }
            return "/document-types"
        }
    }
}

/// API Client for Kora IDV
final class APIClient {

    // MARK: - Properties

    private let configuration: Configuration
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// Weak-reference proxy to break URLSession → delegate → APIClient retain cycle
    private let delegateProxy: SessionDelegateProxy?

    /// Maximum retry attempts
    private let maxRetries = 3

    /// Base delay for exponential backoff (seconds)
    private let baseDelay: TimeInterval = 1.0

    /// SHA-256 hashes of pinned certificate public keys (ISRG Root X1 and X2)
    fileprivate static let pinnedKeyHashes: Set<String> = [
        "jQJTbIh0grw0/1TkHSumWb+Fs0Ggogr621gT3PvPKG0=", // ISRG Root X1
        "C5+lpZ7tcVwmwQIMcRtPbsQtWLABXhQzejna0wHFr8M="  // ISRG Root X2
    ]

    /// Hosts that require certificate pinning
    fileprivate static let pinnedHosts: Set<String> = [
        "api.koraidv.com",
        "sandbox-api.koraidv.com"
    ]

    // MARK: - Initialization

    init(configuration: Configuration) {
        self.configuration = configuration

        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder.dateEncodingStrategy = .iso8601

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30
        sessionConfig.timeoutIntervalForResource = 60

        // Enable certificate pinning for production with default base URL.
        // Use a proxy delegate so URLSession does not strongly retain APIClient.
        if configuration.environment == .production && configuration.baseURL == nil {
            let proxy = SessionDelegateProxy()
            self.delegateProxy = proxy
            self.session = URLSession(configuration: sessionConfig, delegate: proxy, delegateQueue: nil)
        } else {
            self.delegateProxy = nil
            self.session = URLSession(configuration: sessionConfig)
        }
    }

    /// Internal initializer that accepts a custom URLSessionConfiguration (for testing).
    init(configuration: Configuration, sessionConfiguration: URLSessionConfiguration) {
        self.configuration = configuration

        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder.dateEncodingStrategy = .iso8601

        self.delegateProxy = nil
        self.session = URLSession(configuration: sessionConfiguration)
    }

    deinit {
        session.invalidateAndCancel()
    }

    // MARK: - Request Methods

    /// Make a JSON API request
    func request<T: Decodable, B: Encodable>(
        endpoint: APIEndpoint,
        method: HTTPMethod,
        body: B? = nil as EmptyBody?,
        completion: @escaping (Result<T, KoraError>) -> Void
    ) {
        do {
            var request = try buildRequest(endpoint: endpoint, method: method)

            if let body = body {
                request.httpBody = try encoder.encode(body)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }

            executeWithRetry(request: request, attempt: 0, completion: completion)

        } catch {
            completion(.failure(.encodingError(error)))
        }
    }

    /// Make a request without body
    func request<T: Decodable>(
        endpoint: APIEndpoint,
        method: HTTPMethod,
        completion: @escaping (Result<T, KoraError>) -> Void
    ) {
        do {
            let request = try buildRequest(endpoint: endpoint, method: method)
            executeWithRetry(request: request, attempt: 0, completion: completion)
        } catch {
            completion(.failure(.encodingError(error)))
        }
    }

    /// Upload image with metadata
    func uploadImage<T: Decodable, M: Encodable>(
        endpoint: APIEndpoint,
        imageData: Data,
        metadata: M?,
        completion: @escaping (Result<T, KoraError>) -> Void
    ) {
        do {
            var request = try buildRequest(endpoint: endpoint, method: .post)

            let boundary = UUID().uuidString
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            var body = Data()

            // Add image
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"image\"; filename=\"image.jpg\"\r\n".utf8))
            body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
            body.append(imageData)
            body.append(Data("\r\n".utf8))

            // Add metadata if present
            if let metadata = metadata {
                let metadataData = try encoder.encode(metadata)
                body.append(Data("--\(boundary)\r\n".utf8))
                body.append(Data("Content-Disposition: form-data; name=\"metadata\"\r\n".utf8))
                body.append(Data("Content-Type: application/json\r\n\r\n".utf8))
                body.append(metadataData)
                body.append(Data("\r\n".utf8))
            }

            body.append(Data("--\(boundary)--\r\n".utf8))
            request.httpBody = body

            executeWithRetry(request: request, attempt: 0, completion: completion)

        } catch {
            completion(.failure(.encodingError(error)))
        }
    }

    // MARK: - Private Methods

    private func buildRequest(endpoint: APIEndpoint, method: HTTPMethod) throws -> URLRequest {
        let url = configuration.resolvedBaseURL.appendingPathComponent(endpoint.path)

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        // Add auth headers
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.tenantId, forHTTPHeaderField: "X-Tenant-ID")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("KoraIDV-iOS/\(KoraIDV.version)", forHTTPHeaderField: "User-Agent")

        return request
    }

    private func executeWithRetry<T: Decodable>(
        request: URLRequest,
        attempt: Int,
        completion: @escaping (Result<T, KoraError>) -> Void
    ) {
        if configuration.debugLogging {
            KoraIDV.log("Request: \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?")")
        }

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else {
                completion(.failure(.unknown("Request cancelled")))
                return
            }

            // Handle network error
            if let error = error {
                if self.shouldRetry(attempt: attempt, method: request.httpMethod, error: error) {
                    self.retryAfterDelay(request: request, attempt: attempt, completion: completion)
                    return
                }
                completion(.failure(.networkError(error)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }

            guard let data = data else {
                completion(.failure(.noData))
                return
            }

            if self.configuration.debugLogging {
                KoraIDV.log("Response: \(httpResponse.statusCode) (\(data.count) bytes)")
            }

            // Handle HTTP status codes
            switch httpResponse.statusCode {
            case 200...299:
                do {
                    let result = try self.decoder.decode(T.self, from: data)
                    completion(.success(result))
                } catch {
                    completion(.failure(.decodingError(error)))
                }

            case 401:
                completion(.failure(.unauthorized))

            case 403:
                completion(.failure(.forbidden))

            case 404:
                completion(.failure(.notFound))

            case 422:
                self.handleValidationError(data: data, completion: completion)

            case 429:
                if self.shouldRetry(attempt: attempt, method: request.httpMethod, error: nil) {
                    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    let delay = Double(retryAfter ?? "") ?? self.calculateDelay(attempt: attempt)
                    self.retryAfterDelay(request: request, attempt: attempt, delay: delay, completion: completion)
                    return
                }
                completion(.failure(.rateLimited))

            case 500...599:
                if self.shouldRetry(attempt: attempt, method: request.httpMethod, error: nil) {
                    self.retryAfterDelay(request: request, attempt: attempt, completion: completion)
                    return
                }
                completion(.failure(.serverError(httpResponse.statusCode)))

            default:
                completion(.failure(.httpError(httpResponse.statusCode)))
            }
        }

        task.resume()
    }

    private func shouldRetry(attempt: Int, method: String?, error: Error?) -> Bool {
        guard attempt < maxRetries else { return false }

        // Only retry idempotent methods (GET, PUT, DELETE) for server errors.
        // POST is not idempotent — retrying could create duplicate resources.
        let isIdempotent = method != "POST"

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet:
                return true // Network errors are safe to retry for all methods
            default:
                return false
            }
        }

        return isIdempotent // Only retry server errors for idempotent methods
    }

    private func calculateDelay(attempt: Int) -> TimeInterval {
        let delay = baseDelay * pow(2.0, Double(attempt))
        let jitter = Double.random(in: 0...0.5)
        return delay + jitter
    }

    private func retryAfterDelay<T: Decodable>(
        request: URLRequest,
        attempt: Int,
        delay: TimeInterval? = nil,
        completion: @escaping (Result<T, KoraError>) -> Void
    ) {
        let retryDelay = delay ?? calculateDelay(attempt: attempt)

        if configuration.debugLogging {
            KoraIDV.log("Retrying in \(retryDelay)s (attempt \(attempt + 1)/\(maxRetries))")
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + retryDelay) { [weak self] in
            self?.executeWithRetry(request: request, attempt: attempt + 1, completion: completion)
        }
    }

    private func handleValidationError<T>(
        data: Data,
        completion: @escaping (Result<T, KoraError>) -> Void
    ) {
        // Try format 1: { "errors": [{ "field": "...", "message": "..." }] }
        if let response = try? decoder.decode(APIErrorResponse.self, from: data),
           let errors = response.errors, !errors.isEmpty {
            completion(.failure(.validationError(errors)))
            return
        }
        // Try format 2: { "details": { "field": "message" } }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let details = json["details"] as? [String: String] {
            let errors = details.map { ValidationError(field: $0.key, message: $0.value) }
            completion(.failure(.validationError(errors)))
            return
        }
        // Try format 3: { "error": "..." }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? String {
            completion(.failure(.validationError([ValidationError(field: "unknown", message: error)])))
            return
        }
        completion(.failure(.invalidResponse))
    }
}

// MARK: - Empty Body

private struct EmptyBody: Encodable {}

// MARK: - API Error Response

struct APIErrorResponse: Decodable {
    let message: String
    let errors: [ValidationError]?
}

public struct ValidationError: Decodable {
    public let field: String
    public let message: String
}

// MARK: - Session Delegate Proxy

/// Weak-reference proxy that breaks the URLSession → APIClient retain cycle.
/// URLSession retains its delegate strongly; this proxy holds no strong
/// references back, allowing APIClient to be deallocated normally.
private final class SessionDelegateProxy: NSObject, URLSessionDelegate {

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust,
              APIClient.pinnedHosts.contains(challenge.protectionSpace.host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Evaluate the server trust
        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Extract certificates using the appropriate API for the OS version
        var certificates: [SecCertificate] = []
        if #available(iOS 15.0, *) {
            if let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] {
                certificates = chain
            }
        } else {
            let count = SecTrustGetCertificateCount(serverTrust)
            for index in 0..<count {
                if let cert = SecTrustGetCertificateAtIndex(serverTrust, index) {
                    certificates.append(cert)
                }
            }
        }

        // Check each certificate in the chain for a pinned public key
        var pinMatched = false
        for certificate in certificates {
            if let publicKey = SecCertificateCopyKey(certificate),
               let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? {
                let hash = sha256Base64(data: publicKeyData)
                if APIClient.pinnedKeyHashes.contains(hash) {
                    pinMatched = true
                    break
                }
            }
        }

        if pinMatched {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private func sha256Base64(data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash).base64EncodedString()
    }
}
