import Foundation
import UIKit

/// Main entry point for the Kora IDV SDK
public final class KoraIDV {

    // MARK: - Singleton

    /// Shared instance of the SDK
    public static let shared = KoraIDV()

    // MARK: - Properties

    /// Immutable snapshot of SDK state for atomic reads
    private struct SdkState {
        let configuration: Configuration
        let sessionManager: SessionManager
    }

    /// Serial queue protecting mutable state
    private let stateQueue = DispatchQueue(label: "com.koraidv.state")

    /// Atomic state — always read/written under stateQueue
    private var _state: SdkState?

    /// Strong reference to the active flow controller to prevent ARC deallocation
    private var _activeFlowController: VerificationFlowController?

    private init() {}

    // MARK: - Thread-Safe State Access

    /// Read the current SDK state atomically
    private var state: SdkState? {
        stateQueue.sync { _state }
    }

    // MARK: - Configuration

    /// Configure the SDK with the provided configuration
    /// - Parameter configuration: The SDK configuration
    public static func configure(with configuration: Configuration) {
        shared.stateQueue.sync {
            shared._state = SdkState(
                configuration: configuration,
                sessionManager: SessionManager(configuration: configuration)
            )
        }
    }

    /// Check if the SDK is configured
    public static var isConfigured: Bool {
        shared.state != nil
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
        expectedFirstName: String? = nil,
        expectedLastName: String? = nil,
        from presenter: UIViewController,
        completion: @escaping (VerificationResult) -> Void
    ) {
        guard let currentState = shared.state else {
            completion(.failure(KoraError.notConfigured))
            return
        }

        let request = CreateVerificationRequest(
            externalId: externalId,
            tier: tier.rawValue,
            expectedFirstName: expectedFirstName,
            expectedLastName: expectedLastName
        )

        currentState.sessionManager.createVerification(request: request) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let verification):
                    let flowController = VerificationFlowController(
                        verification: verification,
                        configuration: currentState.configuration,
                        sessionManager: currentState.sessionManager,
                        completion: { [weak shared] verificationResult in
                            shared?.stateQueue.sync { shared?._activeFlowController = nil }
                            completion(verificationResult)
                        }
                    )
                    shared.stateQueue.sync { shared._activeFlowController = flowController }
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
        guard let currentState = shared.state else {
            completion(.failure(KoraError.notConfigured))
            return
        }

        currentState.sessionManager.getVerification(id: verificationId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let verification):
                    let flowController = VerificationFlowController(
                        verification: verification,
                        configuration: currentState.configuration,
                        sessionManager: currentState.sessionManager,
                        completion: { [weak shared] verificationResult in
                            shared?.stateQueue.sync { shared?._activeFlowController = nil }
                            completion(verificationResult)
                        }
                    )
                    shared.stateQueue.sync { shared._activeFlowController = flowController }
                    flowController.resume(from: presenter)

                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Document Quality Check

    /// Check document image quality before uploading (no active verification required)
    /// - Parameters:
    ///   - imageData: Raw JPEG image data
    ///   - documentType: The type of document being checked
    ///   - completion: Completion handler with the quality result
    public static func checkDocumentQuality(
        imageData: Data,
        documentType: DocumentType,
        completion: @escaping (Result<DocumentQualityResponse, KoraError>) -> Void
    ) {
        guard let currentState = shared.state else {
            completion(.failure(KoraError.notConfigured))
            return
        }

        currentState.sessionManager.checkDocumentQuality(
            imageData: imageData,
            documentType: documentType,
            completion: completion
        )
    }

    // MARK: - Utilities

    /// SDK version
    public static var version: String {
        "1.7.3"
    }

    /// Reset the SDK configuration
    public static func reset() {
        shared.stateQueue.sync {
            shared._state = nil
        }
    }

    // MARK: - Internal Logging

    /// Whether debug logging is enabled. Safe to call before configuration.
    internal static var debugLogging: Bool {
        shared.state?.configuration.debugLogging ?? false
    }

    /// Log a debug message. Only prints when debugLogging is enabled.
    internal static func log(_ message: @autoclosure () -> String) {
        if debugLogging {
            print("[KoraIDV] \(message())")
        }
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
