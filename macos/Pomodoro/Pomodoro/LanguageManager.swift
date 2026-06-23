import Foundation
import SwiftUI
import Combine

final class LanguageManager: ObservableObject {
    enum AppLanguage: String, CaseIterable, Identifiable {
        case auto
        case english
        case chinese

        var id: String { rawValue }

        var localeIdentifier: String? {
            switch self {
            case .auto:
                return nil
            case .english:
                return "en"
            case .chinese:
                return "zh-Hans"
            }
        }

        var resourceCode: String {
            switch self {
            case .auto:
                return LanguageManager.systemPreferredResourceCode()
            case .english:
                return "en"
            case .chinese:
                return "zh"
            }
        }

        // Backward compatibility with existing references.
        static var system: AppLanguage { .auto }
        static var simplifiedChinese: AppLanguage { .chinese }
    }

    static let shared = LanguageManager()

    @Published private(set) var locale: Locale
    @Published var currentLanguage: AppLanguage {
        didSet {
            guard oldValue != currentLanguage else { return }
            applyCurrentLanguage(persistSelection: true)
        }
    }

    private var activeDictionary: [String: String] = [:]

    // Backward compatibility with existing code paths.
    var selectedLanguage: AppLanguage {
        get { currentLanguage }
        set { currentLanguage = newValue }
    }

    private let defaults = UserDefaults.standard
    private let defaultsKey = "app_language"
    private let legacyDefaultsKey = "app.localization.selectedLanguage"
    private var localeObserver: NSObjectProtocol?
    private var englishDictionary: [String: String] = [:]

    private init() {
        let savedLanguage = defaults.string(forKey: defaultsKey)
            ?? defaults.string(forKey: legacyDefaultsKey)
            ?? Locale.current.identifier
        let initialLanguage = Self.appLanguage(for: savedLanguage)
        currentLanguage = initialLanguage
        locale = Self.locale(for: initialLanguage)

        englishDictionary = loadLocalizedDictionary(resourceCode: "en")
        applyCurrentLanguage(persistSelection: false)

        localeObserver = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.currentLanguage == .auto {
                self.applyCurrentLanguage(persistSelection: false)
            }
        }
    }

    deinit {
        if let localeObserver {
            NotificationCenter.default.removeObserver(localeObserver)
        }
    }

    var effectiveLocale: Locale {
        locale
    }

    func setLanguage(_ identifier: String) {
        currentLanguage = Self.appLanguage(for: identifier)
    }

    func setLanguage(_ language: AppLanguage) {
        currentLanguage = language
    }

    func text(_ key: String) -> String {
        activeDictionary[key] ?? englishDictionary[key] ?? key
    }

    func format(_ key: String, _ args: CVarArg...) -> String {
        format(key, arguments: args)
    }

    func format(_ key: String, arguments: [CVarArg]) -> String {
        let formatString = text(key)
        guard !arguments.isEmpty else { return formatString }
        return String(format: formatString, locale: effectiveLocale, arguments: arguments)
    }

    private func applyCurrentLanguage(persistSelection: Bool) {
        locale = Self.locale(for: currentLanguage)
        if persistSelection {
            defaults.set(storedIdentifier(for: currentLanguage), forKey: defaultsKey)
            defaults.set(currentLanguage.rawValue, forKey: legacyDefaultsKey)
        }
        reloadActiveDictionary()
    }

    private func reloadActiveDictionary() {
        let code = currentLanguage.resourceCode
        var dictionary = englishDictionary
        dictionary.merge(loadLocalizedDictionary(resourceCode: code)) { _, localized in localized }
        if dictionary.isEmpty {
            dictionary = englishDictionary
        }
        activeDictionary = dictionary
    }

    private func loadLocalizedDictionary(resourceCode: String) -> [String: String] {
        let stringsDictionary = loadFromStringsFile(localeIdentifier: stringsLocaleIdentifier(for: resourceCode))
        let jsonDictionary = loadDictionary(resourceCode: resourceCode)
        return stringsDictionary.merging(jsonDictionary) { _, jsonValue in jsonValue }
    }

    private func stringsLocaleIdentifier(for resourceCode: String) -> String {
        switch resourceCode {
        case "zh":
            return "zh-Hans"
        default:
            return resourceCode
        }
    }

    private func loadDictionary(resourceCode: String) -> [String: String] {
        let candidateURLs: [URL?] = [
            Bundle.main.url(forResource: resourceCode, withExtension: "json", subdirectory: "Localization"),
            Bundle.main.url(forResource: resourceCode, withExtension: "json")
        ]
        guard let url = candidateURLs.compactMap({ $0 }).first else {
            return [:]
        }
        do {
            let data = try Data(contentsOf: url)
            let parsed = try JSONDecoder().decode([String: String].self, from: data)
            return parsed
        } catch {
            return [:]
        }
    }

    private func loadFromStringsFile(localeIdentifier: String) -> [String: String] {
        guard let languagePath = Bundle.main.path(forResource: localeIdentifier, ofType: "lproj"),
              let bundle = Bundle(path: languagePath),
              let stringsPath = bundle.path(forResource: "Localizable", ofType: "strings"),
              let dict = NSDictionary(contentsOfFile: stringsPath) as? [String: String] else {
            return [:]
        }
        return dict
    }

    private static func systemPreferredResourceCode() -> String {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if preferred.hasPrefix("zh") {
            return "zh"
        }
        return "en"
    }

    private static func appLanguage(for identifier: String) -> AppLanguage {
        switch identifier {
        case "system", "auto":
            return .auto
        case "simplifiedChinese", "zh", "zh-Hans", "zh_CN", "zh-CN":
            return .chinese
        case "en", "en_US", "en-US":
            return .english
        default:
            let normalized = identifier.lowercased()
            if normalized.hasPrefix("zh") {
                return .chinese
            }
            if normalized.hasPrefix("en") {
                return .english
            }
            return .auto
        }
    }

    private static func locale(for language: AppLanguage) -> Locale {
        switch language {
        case .auto:
            return .autoupdatingCurrent
        case .english:
            return Locale(identifier: "en")
        case .chinese:
            return Locale(identifier: "zh-Hans")
        }
    }

    private func storedIdentifier(for language: AppLanguage) -> String {
        switch language {
        case .auto:
            return Locale.current.identifier
        case .english:
            return "en"
        case .chinese:
            return "zh-Hans"
        }
    }
}

typealias LocalizationManager = LanguageManager

@inline(__always)
func L(_ key: String) -> String {
    LanguageManager.shared.text(key)
}

@inline(__always)
func L(_ key: String, _ args: CVarArg...) -> String {
    LanguageManager.shared.format(key, arguments: args)
}

struct LText: View {
    @EnvironmentObject private var languageManager: LanguageManager
    let key: String

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(languageManager.text(key))
    }
}
