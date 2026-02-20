import Foundation

enum L10n {
    static func tr(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        String(format: tr(key), arguments: args)
    }
}
