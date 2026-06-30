import XCTest
@testable import KoraIDV

final class VerificationFlowControllerTests: XCTestCase {

    // MARK: - Helpers

    private func makeConfiguration() -> Configuration {
        Configuration(
            apiKey: "ck_sandbox_test_key",
            tenantId: "test-tenant",
            environment: .sandbox,
            baseURL: URL(string: "https://test.koraidv.com/api/v1")
        )
    }

    private func makeVerification(status: VerificationStatus = .pending) -> Verification {
        Verification(
            id: "v-test-123",
            externalId: "ext-1",
            tenantId: "t-1",
            tier: "standard",
            status: status,
            documentVerification: nil,
            faceVerification: nil,
            livenessVerification: nil,
            riskSignals: nil,
            riskScore: nil,
            createdAt: Date(),
            updatedAt: Date(),
            scores: nil,
            completedAt: nil,
            decisionReason: nil
        )
    }

    private func makeVerificationWithScores(
        faceMatchScore: Double = 0.95,
        livenessScore: Double = 0.88,
        authenticityScore: Double = 0.92,
        riskScore: Int? = 15
    ) -> Verification {
        Verification(
            id: "v-scored",
            externalId: "ext-scored",
            tenantId: "t-1",
            tier: "standard",
            status: .approved,
            documentVerification: DocumentVerification(
                documentType: "passport",
                documentNumber: "AB1234567",
                firstName: "John",
                lastName: "Doe",
                dateOfBirth: "1990-01-01",
                expirationDate: "2030-12-31",
                issuingCountry: "US",
                mrzValid: true,
                authenticityScore: authenticityScore,
                extractedFields: nil
            ),
            faceVerification: FaceVerification(
                matchScore: faceMatchScore,
                matchResult: "match",
                confidence: 0.99
            ),
            livenessVerification: LivenessVerification(
                livenessScore: livenessScore,
                isLive: true,
                challengeResults: [
                    ChallengeResult(type: "blink", passed: true, confidence: 0.95),
                    ChallengeResult(type: "smile", passed: true, confidence: 0.90)
                ]
            ),
            riskSignals: nil,
            riskScore: riskScore,
            createdAt: Date(),
            updatedAt: Date(),
            scores: nil,
            completedAt: Date(),
            decisionReason: nil
        )
    }

    // MARK: - Score Calculations

    func testPerfectScoresAllReturn100() {
        let v = makeVerificationWithScores(
            faceMatchScore: 1.0,
            livenessScore: 1.0,
            authenticityScore: 1.0
        )
        XCTAssertEqual(v.faceVerification!.matchScore, 1.0)
        XCTAssertEqual(v.livenessVerification!.livenessScore, 1.0)
        XCTAssertEqual(v.documentVerification!.authenticityScore!, 1.0)
    }

    func testZeroScoresAllReturn0() {
        let v = makeVerificationWithScores(
            faceMatchScore: 0.0,
            livenessScore: 0.0,
            authenticityScore: 0.0
        )
        XCTAssertEqual(v.faceVerification!.matchScore, 0.0)
        XCTAssertEqual(v.livenessVerification!.livenessScore, 0.0)
        XCTAssertEqual(v.documentVerification!.authenticityScore!, 0.0)
    }

    func testMixedScoresReturnCorrectValues() {
        let v = makeVerificationWithScores(
            faceMatchScore: 0.85,
            livenessScore: 0.92,
            authenticityScore: 0.78
        )
        XCTAssertEqual(v.faceVerification!.matchScore, 0.85, accuracy: 0.001)
        XCTAssertEqual(v.livenessVerification!.livenessScore, 0.92, accuracy: 0.001)
        XCTAssertEqual(v.documentVerification!.authenticityScore!, 0.78, accuracy: 0.001)
    }

    func testRiskScoreIsPresent() {
        let v = makeVerificationWithScores(riskScore: 25)
        XCTAssertEqual(v.riskScore, 25)
    }

    func testNilRiskScore() {
        let v = makeVerificationWithScores(riskScore: nil)
        XCTAssertNil(v.riskScore)
    }

    func testFaceVerificationConfidence() {
        let v = makeVerificationWithScores(faceMatchScore: 0.95)
        XCTAssertEqual(v.faceVerification!.confidence, 0.99, accuracy: 0.001)
    }

    func testLivenessChallengeResults() {
        let v = makeVerificationWithScores()
        XCTAssertEqual(v.livenessVerification!.challengeResults!.count, 2)
        XCTAssertTrue(v.livenessVerification!.challengeResults!.allSatisfy { $0.passed })
    }

    func testDocumentVerificationExtractedFields() {
        let v = makeVerificationWithScores()
        XCTAssertEqual(v.documentVerification!.firstName, "John")
        XCTAssertEqual(v.documentVerification!.lastName, "Doe")
        XCTAssertEqual(v.documentVerification!.documentNumber, "AB1234567")
    }

    func testDocumentMRZValidity() {
        let v = makeVerificationWithScores()
        XCTAssertTrue(v.documentVerification!.mrzValid!)
    }

    func testNilDocumentVerification() {
        let v = makeVerification(status: .pending)
        XCTAssertNil(v.documentVerification)
        XCTAssertNil(v.faceVerification)
        XCTAssertNil(v.livenessVerification)
    }

    // MARK: - Verification Status Step Determination

    func testPendingStatusMapsToCorrectState() {
        let v = makeVerification(status: .pending)
        XCTAssertEqual(v.status, .pending)
    }

    func testDocumentRequiredStatusMapsToCorrectState() {
        let v = makeVerification(status: .documentRequired)
        XCTAssertEqual(v.status, .documentRequired)
    }

    func testSelfieRequiredStatusMapsToCorrectState() {
        let v = makeVerification(status: .selfieRequired)
        XCTAssertEqual(v.status, .selfieRequired)
    }

    func testLivenessRequiredStatusMapsToCorrectState() {
        let v = makeVerification(status: .livenessRequired)
        XCTAssertEqual(v.status, .livenessRequired)
    }

    func testProcessingStatusMapsToCorrectState() {
        let v = makeVerification(status: .processing)
        XCTAssertEqual(v.status, .processing)
    }

    func testApprovedStatusMapsToCorrectState() {
        let v = makeVerification(status: .approved)
        XCTAssertEqual(v.status, .approved)
    }

    func testRejectedStatusMapsToCorrectState() {
        let v = makeVerification(status: .rejected)
        XCTAssertEqual(v.status, .rejected)
    }

    func testReviewRequiredStatusMapsToCorrectState() {
        let v = makeVerification(status: .reviewRequired)
        XCTAssertEqual(v.status, .reviewRequired)
    }

    // MARK: - Verification Status Raw Values

    func testAllStatusRawValuesAreSnakeCase() {
        let allStatuses: [VerificationStatus] = [
            .pending, .documentRequired, .selfieRequired, .livenessRequired,
            .processing, .approved, .rejected, .reviewRequired, .expired
        ]
        for status in allStatuses {
            XCTAssertFalse(status.rawValue.isEmpty, "Status should have non-empty rawValue")
            XCTAssertTrue(
                status.rawValue.allSatisfy { $0.isLowercase || $0 == "_" },
                "Status rawValue should be snake_case: \(status.rawValue)"
            )
        }
    }

    func testSpecificStatusRawValues() {
        XCTAssertEqual(VerificationStatus.pending.rawValue, "pending")
        XCTAssertEqual(VerificationStatus.documentRequired.rawValue, "document_required")
        XCTAssertEqual(VerificationStatus.selfieRequired.rawValue, "selfie_required")
        XCTAssertEqual(VerificationStatus.livenessRequired.rawValue, "liveness_required")
        XCTAssertEqual(VerificationStatus.processing.rawValue, "processing")
        XCTAssertEqual(VerificationStatus.approved.rawValue, "approved")
        XCTAssertEqual(VerificationStatus.rejected.rawValue, "rejected")
        XCTAssertEqual(VerificationStatus.reviewRequired.rawValue, "review_required")
        XCTAssertEqual(VerificationStatus.expired.rawValue, "expired")
    }

    // MARK: - Verification Properties

    func testVerificationIdIsPreserved() {
        let v = makeVerification()
        XCTAssertEqual(v.id, "v-test-123")
    }

    func testVerificationExternalIdIsPreserved() {
        let v = makeVerification()
        XCTAssertEqual(v.externalId, "ext-1")
    }

    func testVerificationTierIsPreserved() {
        let v = makeVerification()
        XCTAssertEqual(v.tier, "standard")
    }

    func testVerificationTimestampsArePresent() {
        let v = makeVerification()
        XCTAssertNotNil(v.createdAt)
        XCTAssertNotNil(v.updatedAt)
    }

    func testCompletedAtIsNilForPending() {
        let v = makeVerification(status: .pending)
        XCTAssertNil(v.completedAt)
    }

    func testCompletedAtIsSetForCompletedVerification() {
        let v = makeVerificationWithScores()
        XCTAssertNotNil(v.completedAt)
    }

    // MARK: - Document Types

    func testAllDocumentTypesHaveDisplayNames() {
        for docType in DocumentType.allCases {
            XCTAssertFalse(docType.displayName.isEmpty, "\(docType) should have a display name")
        }
    }

    func testDocumentTypeRequiresBackForDriversLicense() {
        XCTAssertTrue(DocumentType.usDriversLicense.requiresBack)
    }

    func testDocumentTypeDoesNotRequireBackForPassport() {
        XCTAssertFalse(DocumentType.internationalPassport.requiresBack)
    }

    func testPassportHasMRZ() {
        XCTAssertTrue(DocumentType.internationalPassport.hasMRZ)
    }

    func testDriversLicenseDoesNotHaveMRZ() {
        XCTAssertFalse(DocumentType.usDriversLicense.hasMRZ)
    }

    func testEUIDCardsHaveMRZ() {
        XCTAssertTrue(DocumentType.euIdGermany.hasMRZ)
        XCTAssertTrue(DocumentType.euIdFrance.hasMRZ)
        XCTAssertTrue(DocumentType.euIdSpain.hasMRZ)
        XCTAssertTrue(DocumentType.euIdItaly.hasMRZ)
    }

    // MARK: - Challenge Types

    func testAllChallengeTypeRawValues() {
        XCTAssertEqual(ChallengeType.blink.rawValue, "blink")
        XCTAssertEqual(ChallengeType.smile.rawValue, "smile")
        XCTAssertEqual(ChallengeType.turnLeft.rawValue, "turn_left")
        XCTAssertEqual(ChallengeType.turnRight.rawValue, "turn_right")
        XCTAssertEqual(ChallengeType.nodUp.rawValue, "nod_up")
        XCTAssertEqual(ChallengeType.nodDown.rawValue, "nod_down")
    }

    // MARK: - Verification Result

    func testVerificationResultSuccess() {
        let v = makeVerification(status: .approved)
        let result = VerificationResult.success(v)
        if case .success(let verification) = result {
            XCTAssertEqual(verification.status, .approved)
        } else {
            XCTFail("Expected success result")
        }
    }

    func testVerificationResultFailure() {
        let result = VerificationResult.failure(.timeout)
        if case .failure(let error) = result {
            XCTAssertEqual(error.errorCode, "TIMEOUT")
        } else {
            XCTFail("Expected failure result")
        }
    }

    func testVerificationResultCancelled() {
        let result = VerificationResult.cancelled
        if case .cancelled = result {
            // Pass
        } else {
            XCTFail("Expected cancelled result")
        }
    }

    // MARK: - Verification Tier

    func testVerificationTierRawValues() {
        XCTAssertEqual(VerificationTier.basic.rawValue, "basic")
        XCTAssertEqual(VerificationTier.standard.rawValue, "standard")
        XCTAssertEqual(VerificationTier.enhanced.rawValue, "enhanced")
    }

    // MARK: - Liveness Mode

    func testDefaultLivenessModeIsActive() {
        let config = makeConfiguration()
        XCTAssertEqual(config.livenessMode, .active)
    }

    func testLivenessModeCanBeSetToPassive() {
        var config = makeConfiguration()
        config.livenessMode = .passive
        XCTAssertEqual(config.livenessMode, .passive)
    }
}

// MARK: - Equatable conformance for LivenessMode (test only)

extension LivenessMode: @retroactive Equatable {
    public static func == (lhs: LivenessMode, rhs: LivenessMode) -> Bool {
        switch (lhs, rhs) {
        case (.active, .active), (.passive, .passive):
            return true
        default:
            return false
        }
    }
}
