import Foundation
import UIKit

/// Main entry point for the Kora IDV SDK
public final class KoraIDV {

    // MARK: - Singleton

    /// Shared instance of the SDK
    public static let shared = KoraIDV()

    // MARK: - Properties

    private var configuration: Configuration?
    private var sessionManager: SessionManager?

    private init() {}

    // MARK: - Configuration

    /// Configure the SDK with the provided configuration
    /// - Parameter configuration: The SDK configuration
    public static func configure(with configuration: Configuration) {
        shared.configuration = configuration
        shared.sessionManager = SessionManager(configuration: configuration)
    }

    /// Check if the SDK is configured
    public static var isConfigured: Bool {
        shared.configuration != nil
    }

    // MARK: - Verification

    /// Start a verification flow
    /// - Parameters:
    ///   - externalId: Your unique identifier for this user/verification
    ///   - tier: The verification tier to use
    ///   - presenter: The view controller to present the verification flow from
    ///   - completion: Completion handler with the result
    public static func startVerification(
        externalId: String,
        tier: VerificationTier = .standard,
        from presenter: UIViewController,
        completion: @escaping (VerificationResult) -> Void
    ) {
        guard let config = shared.configuration else {
            completion(.failure(KoraError.notConfigured))
            return
        }

        guard let sessionManager = shared.sessionManager else {
            completion(.failure(KoraError.notConfigured))
            return
        }

        let request = CreateVerificationRequest(
            externalId: externalId,
            tier: tier.rawValue
        )

        sessionManager.createVerification(request: request) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let verification):
                    let flowController = VerificationFlowController(
                        verification: verification,
                        configuration: config,
                        sessionManager: sessionManager,
                        completion: completion
                    )
                    flowController.start(from: presenter)

                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    /// Resume an existing verification
    /// - Parameters:
    ///   - verificationId: The ID of the verification to resume
    ///   - presenter: The view controller to present the verification flow from
    ///   - completion: Completion handler with the result
    public static func resumeVerification(
        verificationId: String,
        from presenter: UIViewController,
        completion: @escaping (VerificationResult) -> Void
    ) {
        guard let config = shared.configuration else {
            completion(.failure(KoraError.notConfigured))
            return
        }

        guard let sessionManager = shared.sessionManager else {
            completion(.failure(KoraError.notConfigured))
            return
        }

        sessionManager.getVerification(id: verificationId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let verification):
                    let flowController = VerificationFlowController(
                        verification: verification,
                        configuration: config,
                        sessionManager: sessionManager,
                        completion: completion
                    )
                    flowController.resume(from: presenter)

                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Utilities

    /// SDK version
    public static var version: String {
        "1.0.0"
    }

    /// Reset the SDK configuration
    public static func reset() {
        shared.configuration = nil
        shared.sessionManager = nil
    }
}

// MARK: - Verification Result

/// Result of a verification flow
public enum VerificationResult {
    /// Verification completed successfully
    case success(Verification)
    /// Verification failed with an error
    case failure(KoraError)
    /// User cancelled the verification
    case cancelled
}

// MARK: - Verification Tier

/// Verification tier levels
public enum VerificationTier: String {
    case basic = "basic"
    case standard = "standard"
    case enhanced = "enhanced"
}
