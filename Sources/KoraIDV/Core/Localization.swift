import Foundation

private class BundleToken {}

enum L10n {
    /// Resolve the correct bundle for localization.
    /// SPM defines `Bundle.module`; for CocoaPods we fall back to the bundle
    /// containing this source file.
    private static let bundle: Bundle = {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle(for: BundleToken.self)
        #endif
    }()

    static func tr(_ key: String) -> String {
        // Host-app copy override — parity with Android's string-resource override.
        // Integrators put overrides in their OWN `KoraIDVOverrides.strings` table
        // (a distinct filename), so they never collide with the SDK's bundled
        // `Localizable.strings` — which CocoaPods copies into the app's en.lproj.
        // Using the default `Localizable` table would let the pod's copy win, so we
        // read a dedicated table. If the key is present there, the integrator's copy
        // wins; otherwise fall back to the SDK's bundled default. The sentinel keeps
        // a genuinely-present empty override honoured.
        let sentinel = "\u{1}KORA_UNSET"
        let override = Bundle.main.localizedString(forKey: key, value: sentinel, table: "KoraIDVOverrides")
        if override != sentinel { return override }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        String(format: tr(key), arguments: args)
    }
}
