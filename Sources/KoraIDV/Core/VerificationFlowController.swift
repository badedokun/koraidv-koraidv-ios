import Foundation
import UIKit
import SwiftUI
#if canImport(CoreNFC)
import CoreNFC
#endif

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
    private var selectedCountry: CountryInfo?
    private var selectedDocumentType: DocumentType?
    private var documentFrontCaptured = false
    private var documentBackCaptured = false
    private var selfieCaptured = false
    private var livenessSession: LivenessSession?
    private var completedChallenges: Set<String> = []
    private var isLoadingPresented = false
    private var capturedMRZData: MRZData?
    private var nfcPassportData: NFCPassportData?

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
                self?.proceedToCountrySelection()
            },
            onDecline: { [weak self] in
                self?.cancel()
            }
        )

        let hostingController = UIHostingController(rootView: consentView)
        let navController = UINavigationController(rootViewController: hostingController)
        navController.modalPresentationStyle = UIModalPresentationStyle.fullScreen
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
        navController.modalPresentationStyle = UIModalPresentationStyle.fullScreen
        navController.setNavigationBarHidden(true, animated: false)

        navigationController = navController
        presenter.present(navController, animated: true)

        // For country selection, the buildViewForStep returns a loading
        // placeholder. Trigger the actual async fetch now that the nav
        // controller is presented.
        if currentStep == .countrySelection {
            proceedToCountrySelection()
        }
    }

    // MARK: - Step Navigation

    private func proceedToCountrySelection() {
        currentStep = .countrySelection

        showLoading(message: "Loading countries...")

        sessionManager.fetchSupportedCountries { [weak self] result in
            DispatchQueue.main.async {
                self?.hideLoading()

                switch result {
                case .success(let countries):
                    self?.showCountrySelection(countries: countries)
                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
    }

    private func showCountrySelection(countries: [CountryInfo]) {
        let countryView = CountrySelectionView(
            countries: countries,
            onSelect: { [weak self] (country: CountryInfo) in
                self?.selectedCountry = country
                self?.proceedToDocumentSelection(country: country)
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )

        pushView(countryView)
    }

    private func proceedToDocumentSelection(country: CountryInfo) {
        currentStep = .documentSelection

        let allowedTypes = country.documentTypes.filter { type in
            configuration.documentTypes.contains(type)
        }

        let selectionView = DocumentSelectionView(
            allowedTypes: allowedTypes.isEmpty ? configuration.documentTypes : allowedTypes,
            selectedCountry: country,
            onSelect: { [weak self] (documentType: DocumentType) in
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
            documentType: documentType,
            // Backend backfills verification.selectedCountry from this so
            // the selected-vs-detected mismatch gate at /complete can fire.
            // Only meaningful on FRONT uploads (backfill is conditional on
            // the field being currently empty), but harmless on back.
            countryCode: selectedCountry?.id
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
                                self?.proceedAfterDocumentCapture()
                            }
                        } else {
                            self?.documentBackCaptured = true
                            self?.proceedAfterDocumentCapture()
                        }
                    } else if let issues = response.qualityIssues, !issues.isEmpty {
                        self?.showQualityError(issues: issues, side: side)
                    } else {
                        self?.showError(.unknown("Document processing failed. Please try again."))
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

        // Show flip instruction before back capture
        let flipView = FlipDocumentView(
            onContinue: { [weak self] in
                self?.showDocumentBackCapture(documentType: documentType)
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )

        pushView(flipView)
    }

    private func showDocumentBackCapture(documentType: DocumentType) {
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

    /// Determine whether to show NFC step or proceed to selfie after document capture
    private func proceedAfterDocumentCapture() {
        if shouldOfferNFC() {
            proceedToNFCChip()
        } else {
            proceedToSelfieCapture()
        }
    }

    /// Check if NFC chip reading should be offered
    private func shouldOfferNFC() -> Bool {
        // Only for enhanced tier
        guard verification.tier == VerificationTier.enhanced.rawValue else { return false }

        // Only for documents with MRZ (passports and EU IDs)
        guard let docType = selectedDocumentType, docType.hasMRZ else { return false }

        // Check device supports NFC ISO 7816 tag reading
        #if canImport(CoreNFC)
        if #available(iOS 13.0, *) {
            return NFCTagReaderSession.readingAvailable
        }
        #endif

        return false
    }

    private func proceedToNFCChip() {
        #if canImport(CoreNFC)
        currentStep = .nfcChip

        // We need MRZ data for BAC — attempt to get it from the captured document
        // If we don't have MRZ data yet, try to read it from the front image
        if let mrzData = capturedMRZData {
            showNFCView(mrzData: mrzData)
        } else {
            // Skip NFC if no MRZ data available — cannot perform BAC without it
            KoraIDV.log("No MRZ data available for NFC — skipping")
            proceedToSelfieCapture()
        }
        #else
        proceedToSelfieCapture()
        #endif
    }

    #if canImport(CoreNFC)
    private func showNFCView(mrzData: MRZData) {
        let bacKeyData = BACKeyData(
            documentNumber: mrzData.documentNumber,
            dateOfBirth: mrzData.dateOfBirth,
            expirationDate: mrzData.expirationDate
        )

        let nfcView = NFCPassportView(
            bacKeyData: bacKeyData,
            theme: configuration.theme,
            onSuccess: { [weak self] nfcData in
                self?.handleNFCSuccess(nfcData: nfcData)
            },
            onSkip: { [weak self] in
                self?.proceedToSelfieCapture()
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )

        pushView(nfcView)
    }

    private func handleNFCSuccess(nfcData: NFCPassportData) {
        self.nfcPassportData = nfcData

        showLoading(message: "Uploading chip data...")

        sessionManager.uploadNFCData(
            verificationId: verification.id,
            nfcData: nfcData
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.hideLoading()

                switch result {
                case .success:
                    self?.proceedToSelfieCapture()
                case .failure(let error):
                    KoraIDV.log("NFC upload failed (non-fatal): \(error.localizedDescription)")
                    // NFC is optional — proceed to selfie even if upload fails
                    self?.proceedToSelfieCapture()
                }
            }
        }
    }
    #endif

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
                    } else {
                        self?.showError(.unknown("Selfie processing failed. Please try again."))
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

        // Show processing screen
        let processingView = ProcessingScreen(steps: [
            ProcessingStepItem(label: "Document analyzed", status: .done),
            ProcessingStepItem(label: "Checking face match", status: .active),
            ProcessingStepItem(label: "Finalizing results", status: .pending),
        ])
        pushView(processingView)

        sessionManager.completeVerification(verificationId: verification.id) { [weak self] result in
            DispatchQueue.main.async {
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

        let simplified = configuration.resultPageMode == .simplified
        let messages = configuration.customMessages

        // Route to appropriate result screen based on status. In simplified
        // mode (REQ-005) we show only Success / Failed / Review without any
        // scores or technical metrics.
        switch verification.status {
        case .approved:
            if simplified {
                pushView(SimplifiedSuccessScreen(messages: messages) { [weak self] in
                    self?.finish(with: .success(verification))
                })
            } else {
                pushView(SuccessScreen(verification: verification) { [weak self] in
                    self?.finish(with: .success(verification))
                })
            }

        case .rejected:
            if simplified {
                pushView(SimplifiedFailedScreen(messages: messages) { [weak self] in
                    self?.finish(with: .failure(.unknown("Verification rejected")))
                })
            } else {
                pushView(RejectedScreen(verification: verification) { [weak self] in
                    self?.finish(with: .failure(.unknown("Verification rejected")))
                })
            }

        case .expired:
            if simplified {
                // Expired is a failure flavour in simplified mode.
                let overrideMessages = ResultPageMessages(
                    failedTitle: messages?.failedTitle ?? "Document Expired",
                    failedMessage: messages?.failedMessage ?? "The document you submitted has expired. Please use a valid document."
                )
                pushView(SimplifiedFailedScreen(messages: overrideMessages) { [weak self] in
                    self?.finish(with: .failure(.verificationExpired))
                })
            } else {
                pushView(ExpiredDocumentScreen(verification: verification) { [weak self] in
                    self?.finish(with: .failure(.verificationExpired))
                })
            }

        case .reviewRequired:
            if simplified {
                pushView(SimplifiedReviewScreen(verification: verification, messages: messages) { [weak self] in
                    self?.finish(with: .success(verification))
                })
            } else {
                pushView(ManualReviewScreen(verification: verification) { [weak self] in
                    self?.finish(with: .success(verification))
                })
            }

        default:
            pushView(ResultView(
                verification: verification,
                theme: self.configuration.theme,
                onDone: { [weak self] in
                    self?.finish(with: .success(verification))
                }
            ))
        }
    }

    // MARK: - Utilities

    private func pushView<V: View>(_ view: V) {
        let hostingController = UIHostingController(rootView: view)
        navigationController?.pushViewController(hostingController, animated: true)
    }

    private func showLoading(message: String) {
        guard !isLoadingPresented else { return }
        isLoadingPresented = true
        let loadingView = LoadingView(message: message)
        let hostingController = UIHostingController(rootView: loadingView)
        hostingController.modalPresentationStyle = UIModalPresentationStyle.overFullScreen
        hostingController.view.backgroundColor = UIColor.clear
        navigationController?.present(hostingController, animated: false)
    }

    private func hideLoading() {
        guard isLoadingPresented else { return }
        isLoadingPresented = false
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

    private func showQualityError(issues: [APIQualityIssue], side: DocumentSide) {
        let messages = issues.map { $0.message }
        let error = KoraError.qualityValidationFailed(messages)
        showError(error)
    }

    private func showSelfieQualityError(issues: [APIQualityIssue]) {
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
            return .countrySelection
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
                onAccept: { [weak self] in self?.proceedToCountrySelection() },
                onDecline: { [weak self] in self?.cancel() }
            )
        case .countrySelection:
            // Show a loading screen; the actual country list is fetched
            // asynchronously via proceedToCountrySelection().
            LoadingView(message: "Loading countries...")
        case .selfie:
            SelfieCaptureView(
                theme: configuration.theme,
                onCapture: { [weak self] imageData in
                    self?.handleSelfieCapture(imageData: imageData)
                },
                onCancel: { [weak self] in self?.cancel() }
            )
        case .liveness:
            // Liveness requires a session; start by creating one
            ProcessingScreen(steps: [
                ProcessingStepItem(label: "Setting up liveness check", status: .active),
            ])
        case .result:
            ResultView(
                verification: verification,
                theme: configuration.theme,
                onDone: { [weak self] in
                    guard let self = self else { return }
                    self.finish(with: .success(self.verification))
                }
            )
        default:
            // For document steps, restart from country selection since we need
            // the user to re-select document type for the capture flow
            ConsentView(
                configuration: configuration,
                onAccept: { [weak self] in self?.proceedToCountrySelection() },
                onDecline: { [weak self] in self?.cancel() }
            )
        }
    }
}

// MARK: - Verification Step

private enum VerificationStep {
    case consent
    case countrySelection
    case documentSelection
    case documentFront
    case documentBack
    case nfcChip
    case selfie
    case liveness
    case completing
    case result
}
