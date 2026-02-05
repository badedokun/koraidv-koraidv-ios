import Foundation

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

    /// Maximum retry attempts
    private let maxRetries = 3

    /// Base delay for exponential backoff (seconds)
    private let baseDelay: TimeInterval = 1.0

    // MARK: - Initialization

    init(configuration: Configuration) {
        self.configuration = configuration

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30
        sessionConfig.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: sessionConfig)

        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder.dateEncodingStrategy = .iso8601
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
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)

            // Add metadata if present
            if let metadata = metadata {
                let metadataData = try encoder.encode(metadata)
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"metadata\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
                body.append(metadataData)
                body.append("\r\n".data(using: .utf8)!)
            }

            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            request.httpBody = body

            executeWithRetry(request: request, attempt: 0, completion: completion)

        } catch {
            completion(.failure(.encodingError(error)))
        }
    }

    // MARK: - Private Methods

    private func buildRequest(endpoint: APIEndpoint, method: HTTPMethod) throws -> URLRequest {
        let url = configuration.environment.baseURL.appendingPathComponent(endpoint.path)

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        // Add auth headers
        request.setValue(configuration.apiKey, forHTTPHeaderField: "Authorization")
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
            print("[KoraIDV] Request: \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?")")
        }

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            // Handle network error
            if let error = error {
                if self.shouldRetry(attempt: attempt, error: error) {
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
                print("[KoraIDV] Response: \(httpResponse.statusCode)")
                if let json = String(data: data, encoding: .utf8) {
                    print("[KoraIDV] Body: \(json.prefix(500))")
                }
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
                if self.shouldRetry(attempt: attempt, error: nil) {
                    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    let delay = Double(retryAfter ?? "") ?? self.calculateDelay(attempt: attempt)
                    self.retryAfterDelay(request: request, attempt: attempt, delay: delay, completion: completion)
                    return
                }
                completion(.failure(.rateLimited))

            case 500...599:
                if self.shouldRetry(attempt: attempt, error: nil) {
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

    private func shouldRetry(attempt: Int, error: Error?) -> Bool {
        guard attempt < maxRetries else { return false }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }

        return true // Retry for server errors and rate limits
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
            print("[KoraIDV] Retrying in \(retryDelay)s (attempt \(attempt + 1)/\(maxRetries))")
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + retryDelay) { [weak self] in
            self?.executeWithRetry(request: request, attempt: attempt + 1, completion: completion)
        }
    }

    private func handleValidationError<T>(
        data: Data,
        completion: @escaping (Result<T, KoraError>) -> Void
    ) {
        do {
            let errorResponse = try decoder.decode(APIErrorResponse.self, from: data)
            completion(.failure(.validationError(errorResponse.errors)))
        } catch {
            completion(.failure(.decodingError(error)))
        }
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
