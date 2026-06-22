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

    /// **v1.9.0-rc6.4** — count of liveness challenge submissions
    /// currently in flight to the backend. Incremented in
    /// `handleChallengeComplete` when the POST starts; decremented in
    /// the completion handler. `completeVerification()` is gated on
    /// this reaching zero so we don't fire `/complete` while the
    /// final challenge's image upload is still in flight. Stratum
    /// Remit 2026-06-06 rc6.3 server log showed the race: challenge
    /// #3 POST landed 2.2s AFTER /complete had already fired, so the
    /// backend ignored the late submission and the verification was
    /// scored on only 2 of 3 challenges.
    private var pendingChallengeSubmissions: Int = 0

    /// **v1.9.0-rc6.4** — set when LivenessView fires `onAllComplete`
    /// while there are still in-flight challenge POSTs. Once
    /// `pendingChallengeSubmissions` drains to zero, the deferred
    /// `completeVerification()` call fires.
    private var awaitingChallengesBeforeComplete: Bool = false

    /// **v1.9.0-rc6.4** — minimum dwell time on the ProcessingScreen
    /// after `completeVerification()` is called. The backend's
    /// `/complete` endpoint typically returns in ~100ms, which means
    /// the ProcessingScreen is replaced by the SuccessScreen before
    /// the user can perceive it. Android has a similar minimum-dwell
    /// pattern so the verification-in-progress animation always
    /// registers. 1.5s is long enough to be visible without feeling
    /// like artificial latency.
    private let processingMinDwell: TimeInterval = 1.5

    /// Timestamp when the ProcessingScreen was pushed; used to
    /// compute the remaining dwell time before showing the result.
    private var processingShownAt: Date?

    /// **v1.9.0-rc6.5** — guard so `pushProcessingScreenIfNeeded()` only
    /// pushes once even when called from both `onAllChallengesReported`
    /// (liveness path) and `completeVerification` (no-liveness selfie
    /// path). Without the guard the no-liveness path would push twice
    /// in some scenarios.
    private var processingScreenPushed = false

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
            },
            showVisualGuides: configuration.showVisualGuides
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
                    if response.isSuccess {
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
            },
            showVisualGuides: configuration.showVisualGuides
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
            },
            showVisualGuides: configuration.showVisualGuides
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
                    if response.isSuccess {
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
                // rc6.4: route through onAllChallengesReported so the
                // /complete POST waits for any in-flight final-challenge
                // submission to land first.
                self?.onAllChallengesReported()
            },
            onCancel: { [weak self] in
                self?.cancel()
            },
            showVisualGuides: configuration.showVisualGuides
        )

        pushView(livenessView)
    }

    private func handleChallengeComplete(challenge: LivenessChallenge, imageData: Data) {
        // **v1.9.0-rc6.4** — track in-flight challenge submission so
        // completeVerification() can wait for it before firing /complete.
        // Without this, LivenessView fires onAllComplete (which calls
        // completeVerification) the moment the LivenessManager records
        // the last challenge result — *before* the host has actually
        // POSTed the image to the backend. Server gets /complete
        // before the last challenge image, ignores the late upload,
        // verification scored on N-1 challenges. Stratum Remit
        // 2026-06-06 rc6.3 server log proved the race.
        pendingChallengeSubmissions += 1

        sessionManager.submitLivenessChallenge(
            verificationId: verification.id,
            challenge: challenge,
            imageData: imageData
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.pendingChallengeSubmissions = max(0, self.pendingChallengeSubmissions - 1)

                switch result {
                case .success(let response):
                    // `challengePassed` is optional now (1.6.1) — server
                    // actually returns `completed` under a different name;
                    // wire format rename is tracked for next minor. For
                    // now, treat missing-or-true as passed so decode
                    // never blocks progress.
                    if response.challengePassed ?? true {
                        self.completedChallenges.insert(challenge.id)
                    }
                case .failure(let error):
                    self.showError(error)
                    return
                }

                // rc6.4: if LivenessView's onAllComplete fired while we
                // were waiting for this POST, fire the deferred
                // completeVerification now that all challenges are in.
                if self.awaitingChallengesBeforeComplete && self.pendingChallengeSubmissions == 0 {
                    self.awaitingChallengesBeforeComplete = false
                    self.completeVerification()
                }
            }
        }
    }

    /// **v1.9.0-rc6.4** — called by LivenessView's onAllComplete
    /// callback. Either fires `completeVerification()` immediately
    /// (all challenge POSTs already settled) or defers via the
    /// `awaitingChallengesBeforeComplete` flag (last challenge POST
    /// still in flight; the per-POST completion handler will fire
    /// completeVerification when it lands).
    ///
    /// **v1.9.0-rc6.5** — also pushes the ProcessingScreen IMMEDIATELY
    /// here, before any waiting on challenge POSTs or /complete.
    /// Stratum Remit 2026-06-06 rc6.4 feedback: "the last challenge
    /// still lags for several seconds after the completion before
    /// showing the processing page." Root cause: rc6.4 only pushed
    /// the screen inside `completeVerification()`, which the deferred
    /// path could delay by 2+ seconds while the final challenge POST
    /// roundtripped. User stared at the liveness UI through that
    /// window. Now the transition is immediate at gesture-end; the
    /// /complete latency overlaps with the 1.5s min-dwell timer.
    private func onAllChallengesReported() {
        pushProcessingScreenIfNeeded()

        if pendingChallengeSubmissions == 0 {
            completeVerification()
        } else {
            KoraIDV.log("VFC: onAllComplete fired with \(pendingChallengeSubmissions) challenge POST(s) still in flight; deferring /complete")
            awaitingChallengesBeforeComplete = true
        }
    }

    /// **v1.9.0-rc6.5** — push the ProcessingScreen onto the nav stack
    /// the first time we need it, then record `processingShownAt` so
    /// the min-dwell timer can fire from this moment. Idempotent —
    /// subsequent calls are no-ops because `processingScreenPushed`
    /// stays true for the remainder of the flow.
    private func pushProcessingScreenIfNeeded() {
        guard !processingScreenPushed else { return }
        processingScreenPushed = true
        currentStep = .completing

        let processingView = ProcessingScreen(steps: [
            ProcessingStepItem(label: "Document analyzed", status: .done),
            ProcessingStepItem(label: "Checking face match", status: .active),
            ProcessingStepItem(label: "Finalizing results", status: .pending),
        ])
        pushView(processingView)
        processingShownAt = Date()
    }

    private func completeVerification() {
        // **v1.9.0-rc6.5** — ProcessingScreen push moved to
        // `pushProcessingScreenIfNeeded()`, which is also called from
        // `onAllChallengesReported()` earlier in the flow so the
        // liveness-to-processing transition is immediate at gesture-
        // end (Stratum 2026-06-06 rc6.4 fix). For the no-liveness
        // selfie path, this is the first call and the screen is
        // pushed here. For the liveness path, it's a no-op because
        // the screen was already pushed seconds earlier.
        pushProcessingScreenIfNeeded()

        sessionManager.completeVerification(verificationId: verification.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let verification):
                    // **v1.9.0-rc6.4 — minimum dwell.** Backend's
                    // /complete typically returns in ~100ms (rc6.3
                    // measured 113ms). Without a minimum dwell, the
                    // ProcessingScreen pushed above flashes for one
                    // animation frame before being replaced by the
                    // SuccessScreen — Stratum Remit 2026-06-06 rc6.3
                    // feedback: "we got the result page but did not
                    // see the processing page." Hold the result push
                    // until at least `processingMinDwell` has elapsed
                    // since ProcessingScreen appeared, so the user
                    // always sees the verification-in-progress
                    // animation register.
                    let elapsed = self.processingShownAt.map { Date().timeIntervalSince($0) } ?? .infinity
                    let remaining = max(0, self.processingMinDwell - elapsed)
                    if remaining > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
                            self?.showResult(verification: verification)
                        }
                    } else {
                        self.showResult(verification: verification)
                    }

                case .failure(let error):
                    self.showError(error)
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
        //
        // **v1.9.0-rc6.3** — `.verified` is the koraidv-identity wire
        // string for auto-approve; `.approved` is the legacy alias. Both
        // route to SuccessScreen (or SimplifiedSuccessScreen). Without
        // the `.verified` case here, an auto-approved verification fell
        // into the `default` branch below, which pushes the generic
        // ResultView — whose body switch ALSO lacked `.verified` and
        // rendered an infinite ProcessingScreen. User stuck.
        switch verification.status {
        case .verified, .approved:
            if simplified {
                pushView(SimplifiedSuccessScreen(messages: messages) { [weak self] in
                    self?.finish(with: .success(verification))
                })
            } else {
                pushView(SuccessScreen(verification: verification) { [weak self] in
                    self?.finish(with: .success(verification))
                })
            }

        case .rejected, .failed:
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

        case .reviewRequired, .manualReview:
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
        dismiss { [completion] in completion(.cancelled) }
    }

    private func finish(with result: VerificationResult) {
        dismiss { [completion] in completion(result) }
    }

    /// Dismiss the SDK's presented navigation stack and fire `onDismissed`
    /// only AFTER the dismissal animation has finished.
    ///
    /// **Session-continuity fix (BanffPay, iOS, 2026-06-16):** the host's
    /// completion handler is a natural place to kick off the *next* KYC
    /// session (`startVerification` again). Previously we called
    /// `completion(...)` synchronously right after `dismiss(animated: true)`,
    /// i.e. while the old nav controller was still mid-dismissal. If the host
    /// re-presented from the same presenter inside that callback, UIKit
    /// dropped the presentation ("present while a presentation is in
    /// progress") because the presenter's `presentedViewController` was still
    /// the dismissing stack — so a new verification flow could not be
    /// initiated after a previous one. Routing `completion` through the
    /// dismissal completion block guarantees the presenter is free before the
    /// host re-presents.
    private func dismiss(then onDismissed: @escaping () -> Void) {
        guard let nav = navigationController else {
            onDismissed()
            return
        }
        navigationController = nil
        nav.dismiss(animated: true, completion: onDismissed)
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
        // rc6.2: `verified` is the backend's wire string for auto-approve;
        // `approved` is the legacy alias retained for backwards compat.
        // Both map to the same terminal `result` step here.
        case .processing, .verified, .approved, .rejected, .reviewRequired,
             .failed, .manualReview, .unknown:
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
                onCancel: { [weak self] in self?.cancel() },
                showVisualGuides: configuration.showVisualGuides
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
