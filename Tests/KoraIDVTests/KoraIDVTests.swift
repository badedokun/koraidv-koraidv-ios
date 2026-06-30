import XCTest
@testable import KoraIDV

final class KoraIDVTests: XCTestCase {

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        // Ensure a clean state before each test
        KoraIDV.reset()
    }

    override func tearDown() {
        KoraIDV.reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeConfiguration(
        apiKey: String = "ck_live_test123",
        tenantId: String = "tenant-test-id"
    ) -> Configuration {
        Configuration(apiKey: apiKey, tenantId: tenantId)
    }

    // MARK: - isConfigured

    func testIsConfiguredFalseBeforeConfigure() {
        XCTAssertFalse(KoraIDV.isConfigured)
    }

    func testIsConfiguredTrueAfterConfigure() {
        KoraIDV.configure(with: makeConfiguration())
        XCTAssertTrue(KoraIDV.isConfigured)
    }

    // MARK: - reset()

    func testResetMakesIsConfiguredFalse() {
        KoraIDV.configure(with: makeConfiguration())
        XCTAssertTrue(KoraIDV.isConfigured)

        KoraIDV.reset()
        XCTAssertFalse(KoraIDV.isConfigured)
    }

    // MARK: - version

    func testVersionMatchesPodspec() {
        // Pinned by `scripts/release-*-sdk.sh` workflow; bumped in lockstep
        // with the podspec + Package.swift. If this fails the SDK was
        // tagged without bumping `KoraIDV.version` — release was incomplete.
        XCTAssertEqual(KoraIDV.version, "1.10.0")
    }

    // MARK: - Double Configure

    func testDoubleConfigureDoesNotCrash() {
        let config1 = makeConfiguration(apiKey: "ck_live_first")
        let config2 = makeConfiguration(apiKey: "ck_live_second")

        KoraIDV.configure(with: config1)
        XCTAssertTrue(KoraIDV.isConfigured)

        KoraIDV.configure(with: config2)
        XCTAssertTrue(KoraIDV.isConfigured)
    }

    // MARK: - Configure, Reset, Configure cycle

    func testConfigureResetConfigureCycle() {
        KoraIDV.configure(with: makeConfiguration())
        XCTAssertTrue(KoraIDV.isConfigured)

        KoraIDV.reset()
        XCTAssertFalse(KoraIDV.isConfigured)

        KoraIDV.configure(with: makeConfiguration(apiKey: "ck_sandbox_new"))
        XCTAssertTrue(KoraIDV.isConfigured)
    }

    // MARK: - Shared Singleton

    func testSharedInstanceIsSameObject() {
        let a = KoraIDV.shared
        let b = KoraIDV.shared
        XCTAssertTrue(a === b, "shared should return the same instance")
    }

    // MARK: - Reset Without Configure

    func testResetWithoutConfigureDoesNotCrash() {
        // Should be safe to call reset even when not configured
        KoraIDV.reset()
        XCTAssertFalse(KoraIDV.isConfigured)
    }

    // MARK: - Multiple Resets

    func testMultipleResetsDoNotCrash() {
        KoraIDV.configure(with: makeConfiguration())
        KoraIDV.reset()
        KoraIDV.reset()
        KoraIDV.reset()
        XCTAssertFalse(KoraIDV.isConfigured)
    }
}
