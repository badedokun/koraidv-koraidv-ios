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
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        String(format: tr(key), arguments: args)
    }
}
