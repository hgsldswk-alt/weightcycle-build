import Foundation

private final class LocalizationBundle: NSObject {}

enum L {
    static func t(_ key: String) -> String {
        NSLocalizedString(key, bundle: Bundle(for: LocalizationBundle.self), comment: "")
    }

    static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), locale: .current, arguments: args)
    }

    static func number(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(digits)).grouping(.never))
    }
}
