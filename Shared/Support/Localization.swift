import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english = "en", spanish = "es"
    static let preferenceKey = "phonedock.language"
    var id: String { rawValue }
    static var selected: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "system") ?? .system
    }
    func resolvedCode(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        guard self == .system else { return rawValue }
        for language in preferredLanguages {
            let code = language.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first
            if code == "es" || code == "en" { return String(code!) }
        }
        return "en"
    }
    var locale: Locale { Locale(identifier: resolvedCode()) }
    var title: String {
        switch self {
        case .system: localized("Follow system")
        case .english: "English"
        case .spanish: "Español"
        }
    }
    func translate(_ key: String, bundle: Bundle = .main) -> String {
        guard let path = bundle.path(forResource: resolvedCode(), ofType: "lproj"),
              let translation = Bundle(path: path) else { return key }
        return translation.localizedString(forKey: key, value: key, table: nil)
    }
}

@inline(__always)
func localized(_ key: String) -> String {
    AppLanguage.selected.translate(key)
}

@inline(__always)
func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: localized(key), locale: AppLanguage.selected.locale, arguments: arguments)
}
