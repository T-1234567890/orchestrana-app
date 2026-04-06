import Combine
import SwiftUI

@MainActor
final class AppTypography: ObservableObject {
    enum Style: String, CaseIterable, Identifiable {
        case classic
        case editorial

        var id: String { rawValue }

        func title(using localizationManager: LocalizationManager) -> String {
            switch self {
            case .classic:
                return localizationManager.text("settings.appearance.font.classic")
            case .editorial:
                return localizationManager.text("settings.appearance.font.editorial")
            }
        }
    }

    static let shared = AppTypography()

    @Published var style: Style {
        didSet {
            defaults.set(style.rawValue, forKey: Self.defaultsKey)
        }
    }

    private static let defaultsKey = "app.typography.style"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.style = Style(rawValue: defaults.string(forKey: Self.defaultsKey) ?? "") ?? .classic
    }

    func sectionHeaderFont() -> Font {
        switch style {
        case .classic:
            return .title3.weight(.semibold)
        case .editorial:
            return .system(size: 24, weight: .semibold, design: .serif)
        }
    }

    func cardTitleFont() -> Font {
        switch style {
        case .classic:
            return .system(.title3, design: .rounded).weight(.semibold)
        case .editorial:
            return .system(size: 22, weight: .semibold, design: .serif)
        }
    }
}
