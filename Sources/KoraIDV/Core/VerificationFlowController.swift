import Foundation
import UIKit
import SwiftUI

/// Controls the verification flow UI and state
final class VerificationFlowController {

    // MARK: - Properties

    private let verification: Verification
    private let configuration: Configuration
    private let sessionManager: SessionManager
    private let completion: (VerificationResult) -> Void

    private var navigationController: UINavigationController?
    private weak var presentingViewController: UIViewController?

    private var currentStep: VerificationStep = .consent
    private var selectedDocumentType: DocumentType?
    private var documentFrontCaptured = false
    private var documentBackCaptured = false
    private var selfieCaptured = false
    private var livenessSession: LivenessSession?
    private var completedChallenges: Set<String> = []

    // MARK: - Initialization

    init(
        verification: Verification,
        configuration: Configuration,
        sessionManager: SessionManager,
        completion: @escaping (VerificationResult) -> Void
    ) {
        self.verification = verification
        self.configuration = configuration
        self.sessionManager = sessionManager
        self.completion = completion
    }

    // MARK: - Flow Control

    /// Start the verification flow from the beginning
    func start(from presenter: UIViewController) {
        presentingViewController = presenter
        currentStep = .consent

        let consentView = ConsentView(
            configuration: configuration,
            onAccept: { [weak self] in
                self?.proceedToDocumentSelection()
            },
            onDecline: { [weak self] in
                self?.cancel()
            }
        )

        let hostingController = UIHostingController(rootView: consentView)
        let navController = UINavigationController(rootViewController: hostingController)
        navController.modalPresentationStyle = .fullScreen
        navController.setNavigationBarHidden(true, animated: false)

        navigationController = navController
        presenter.present(navController, animated: true)
    }

    /// Resume verification from current state
    func resume(from presenter: UIViewController) {
        presentingViewController = presenter

        // Determine where to resume based on verification status
        currentStep = determineCurrentStep(from: verification.status)

        let resumeView = buildViewForStep(currentStep)
        let hostingController = UIHostingController(rootView: AnyView(resumeView))
        let navController = UINavigationController(rootViewController: hostingController)
        navController.modalPresentationStyle = .fullScreen
        navController.setNavigationBarHidden(true, animated: false)

        navigationController = navController
        presenter.present(navController, animated: true)
    }

    // MARK: - Step Navigation

    private func proceedToDocumentSelection() {
        currentStep = .documentSelection

        let selectionView = DocumentSelectionView(
            allowedTypes: configuration.documentTypes,
            onSelect: { [weak self] documentType in
                self?.selectedDocumentType = documentType
                self?.proceedToDocumentCapture()
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )

        pushView(selectionView)
    }

    private func proceedToDocumentCapture() {
        guard let documentType = selectedDocumentType else { return }
        currentStep = .documentFront

        let captureView = DocumentCaptureView(
            documentType: documentType,
            side: .front,
            theme: configuration.theme,
            onCapture: { [weak self] imageData in
                self?.handleDocumentCapture(imageData: imageData, side: .front)
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )

        pushView(captureView)
    }

    private func handleDocumentCapture(imageData: Data, side: DocumentSide) {
        guard let documentType = selectedDocumentType else { return }

        showLoading(message: "Processing document...")

        sessionManager.uploadDocument(
            verificationId: verification.id,
            imageData: imageData,
            side: side,
            documentType: documentType
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.hideLoading()

                switch result {
                case .success(let response):
                    if response.success {
                        if side == .front {
                            self?.documentFrontCaptured = true
                            if documentType.requiresBack {
                                self?.proceedToDocumentBack()
                            } else {
                                self?.proceedToSelfieCapture()
                            }
                        } else {
                            self?.documentBackCaptured = true
                            self?.proceedToSelfieCapture()
                        }
                    } else if let issues = response.qualityIssues, !issues.isEmpty {
                        self?.showQualityError(issues: issues, side: side)
                    }

                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
    }

    private func proceedToDocumentBack() {
        guard let documentType = selectedDocumentType else { return }
        currentStep = .documentBack

        let captureView = DocumentCaptureView(
            documentType: documentType,
            side: .back,
            theme: configuration.theme,
            onCapture: { [weak self] imageData in
                self?.handleDocumentCapture(imageData: imageData, side: .back)
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )

        pushView(captureView)
    }

    private func proceedToSelfieCapture() {
        currentStep = .selfie

        let selfieView = SelfieCaptureView(
            theme: configuration.theme,
            onCapture: { [weak self] imageData in
                self?.handleSelfieCapture(imageData: imageData)
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )

        pushView(selfieView)
    }

    private func handleSelfieCapture(imageData: Data) {
        showLoading(message: "Processing selfie...")

        sessionManager.uploadSelfie(
            verificationId: verification.id,
            imageData: imageData
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.hideLoading()

                switch result {
                case .success(let response):
                    if response.success {
                        self?.selfieCaptured = true
                        if self?.configuration.livenessMode == .active {
                            self?.proceedToLiveness()
                        } else {
                            self?.completeVerification()
                        }
                    } else if let issues = response.qualityIssues, !issues.isEmpty {
                        self?.showSelfieQualityError(issues: issues)
                    }

                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
    }

    private func proceedToLiveness() {
        currentStep = .liveness

        showLoading(message: "Setting up liveness check...")

        sessionManager.createLivenessSession(verificationId: verification.id) { [weak self] result in
            DispatchQueue.main.async {
                self?.hideLoading()

                switch result {
                case .success(let session):
                    self?.livenessSession = session
                    self?.showLivenessView(session: session)

                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
    }

    private func showLivenessView(session: LivenessSession) {
        let livenessView = LivenessView(
            session: session,
            theme: configuration.theme,
            onChallengeComplete: { [weak self] challenge, imageData in
                self?.handleChallengeComplete(challenge: challenge, imageData: imageData)
            },
            onAllComplete: { [weak self] in
                self?.completeVerification()
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )

        pushView(livenessView)
    }

    private func handleChallengeComplete(challenge: LivenessChallenge, imageData: Data) {
        sessionManager.submitLivenessChallenge(
            verificationId: verification.id,
            challenge: challenge,
            imageData: imageData
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    if response.challengePassed {
                        self?.completedChallenges.insert(challenge.id)
                    }
                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
    }

    private func completeVerification() {
        currentStep = .completing

        showLoading(message: "Completing verification...")

        sessionManager.completeVerification(verificationId: verification.id) { [weak self] result in
            DispatchQueue.main.async {
                self?.hideLoading()

                switch result {
                case .success(let verification):
                    self?.showResult(verification: verification)

                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
    }

    private func showResult(verification: Verification) {
        currentStep = .result

        let resultView = ResultView(
            verification: verification,
            theme: configuration.theme,
            onDone: { [weak self] in
                self?.finish(with: .success(verification))
            }
        )

        pushView(resultView)
    }

    // MARK: - Utilities

    private func pushView<V: View>(_ view: V) {
        let hostingController = UIHostingController(rootView: view)
        navigationController?.pushViewController(hostingController, animated: true)
    }

    private func showLoading(message: String) {
        // Loading overlay implementation
        let loadingView = LoadingView(message: message)
        let hostingController = UIHostingController(rootView: loadingView)
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.view.backgroundColor = .clear
        navigationController?.present(hostingController, animated: false)
    }

    private func hideLoading() {
        navigationController?.dismiss(animated: false)
    }

    private func showError(_ error: KoraError) {
        let errorView = ErrorView(
            error: error,
            theme: configuration.theme,
            onRetry: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )

        pushView(errorView)
    }

    private func showQualityError(issues: [QualityIssue], side: DocumentSide) {
        let messages = issues.map { $0.message }
        let error = KoraError.qualityValidationFailed(messages)
        showError(error)
    }

    private func showSelfieQualityError(issues: [QualityIssue]) {
        let messages = issues.map { $0.message }
        let error = KoraError.qualityValidationFailed(messages)
        showError(error)
    }

    private func cancel() {
        dismiss()
        completion(.cancelled)
    }

    private func finish(with result: VerificationResult) {
        dismiss()
        completion(result)
    }

    private func dismiss() {
        navigationController?.dismiss(animated: true)
        navigationController = nil
    }

    private func determineCurrentStep(from status: VerificationStatus) -> VerificationStep {
        switch status {
        case .pending:
            return .consent
        case .documentRequired:
            return .documentSelection
        case .selfieRequired:
            return .selfie
        case .livenessRequired:
            return .liveness
        case .processing, .approved, .rejected, .reviewRequired:
            return .result
        case .expired:
            return .result
        }
    }

    @ViewBuilder
    private func buildViewForStep(_ step: VerificationStep) -> some View {
        switch step {
        case .consent:
            ConsentView(
                configuration: configuration,
                onAccept: { [weak self] in self?.proceedToDocumentSelection() },
                onDecline: { [weak self] in self?.cancel() }
            )
        case .documentSelection:
            DocumentSelectionView(
                allowedTypes: configuration.documentTypes,
                onSelect: { [weak self] type in
                    self?.selectedDocumentType = type
                    self?.proceedToDocumentCapture()
                },
                onCancel: { [weak self] in self?.cancel() }
            )
        default:
            EmptyView()
        }
    }
}

// MARK: - Verification Step

private enum VerificationStep {
    case consent
    case documentSelection
    case documentFront
    case documentBack
    case selfie
    case liveness
    case completing
    case result
}
