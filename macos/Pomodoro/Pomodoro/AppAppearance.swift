import AppKit
import SwiftUI

private extension Color {
    init(hexRGB: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hexRGB >> 16) & 0xFF) / 255.0,
            green: Double((hexRGB >> 8) & 0xFF) / 255.0,
            blue: Double(hexRGB & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    static let appStorageKey = "appearanceMode"

    case glass
    case standard

    var id: String { rawValue }

    static func resolved(from rawValue: String) -> AppearanceMode {
        AppearanceMode(rawValue: rawValue) ?? .standard
    }

    func secondaryTextColor(for colorScheme: ColorScheme) -> Color {
        switch self {
        case .glass:
            return .secondary
        case .standard:
            return colorScheme == .dark ? Color(hexRGB: 0xA1A1AA) : Color(hexRGB: 0x6B7280)
        }
    }

    func surfaceColor(for level: AppearanceSurfaceLevel, colorScheme: ColorScheme) -> Color {
        switch self {
        case .glass:
            return .clear
        case .standard:
            if colorScheme == .dark {
                switch level {
                case .panel:
                    return Color(hexRGB: 0x1C1F26)
                case .inset:
                    return Color(hexRGB: 0x22262F)
                case .overlay:
                    return Color(hexRGB: 0x1C1F26)
                }
            } else {
                switch level {
                case .panel:
                    return Color(hexRGB: 0xFFFFFF)
                case .inset:
                    return Color(hexRGB: 0xFCFBF9)
                case .overlay:
                    return Color(hexRGB: 0xFFFFFF)
                }
            }
        }
    }

    func mainBackgroundColor(for colorScheme: ColorScheme) -> Color {
        switch self {
        case .glass:
            return .clear
        case .standard:
            return colorScheme == .dark ? Color(hexRGB: 0x0F1115) : Color(hexRGB: 0xF3F2EF)
        }
    }

    func borderColor(for colorScheme: ColorScheme, isEmphasized: Bool = false) -> Color {
        switch self {
        case .glass:
            return Color.white.opacity(isEmphasized ? 0.18 : 0.12)
        case .standard:
            if colorScheme == .dark {
                return Color.white.opacity(isEmphasized ? 0.07 : 0.05)
            } else {
                return Color.black.opacity(isEmphasized ? 0.08 : 0.06)
            }
        }
    }

    func shadowColor(for colorScheme: ColorScheme, isEmphasized: Bool = false) -> Color {
        switch self {
        case .glass:
            return Color.black.opacity(isEmphasized ? 0.07 : 0.05)
        case .standard:
            if colorScheme == .dark {
                return Color.black.opacity(isEmphasized ? 0.28 : 0.22)
            } else {
                return Color.black.opacity(isEmphasized ? 0.06 : 0.04)
            }
        }
    }

    func shadowRadius(for colorScheme: ColorScheme, isEmphasized: Bool = false) -> CGFloat {
        switch self {
        case .glass:
            return isEmphasized ? 18 : 14
        case .standard:
            return colorScheme == .dark ? (isEmphasized ? 10 : 8) : (isEmphasized ? 6 : 4)
        }
    }

    func shadowYOffset(for colorScheme: ColorScheme, isEmphasized: Bool = false) -> CGFloat {
        switch self {
        case .glass:
            return isEmphasized ? 10 : 8
        case .standard:
            return colorScheme == .dark ? (isEmphasized ? 5 : 4) : (isEmphasized ? 3 : 2)
        }
    }

    func primaryTextColor(for colorScheme: ColorScheme) -> Color {
        switch self {
        case .glass:
            return .primary
        case .standard:
            return colorScheme == .dark ? Color(hexRGB: 0xF5F7FA) : Color(hexRGB: 0x111111)
        }
    }
}

enum AppearanceSurfaceLevel {
    case panel
    case inset
    case overlay
}

private struct AppRoundedSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let mode: AppearanceMode
    let cornerRadius: CGFloat
    let glassMaterial: Material
    let standardLevel: AppearanceSurfaceLevel
    let isEmphasized: Bool
    let showsShadow: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                if mode == .glass {
                    shape.fill(glassMaterial)
                } else {
                    shape.fill(mode.surfaceColor(for: standardLevel, colorScheme: colorScheme))
                }
            }
            .clipShape(shape)
            .overlay {
                shape.stroke(mode.borderColor(for: colorScheme, isEmphasized: isEmphasized), lineWidth: 1)
            }
            .shadow(
                color: showsShadow ? mode.shadowColor(for: colorScheme, isEmphasized: isEmphasized) : .clear,
                radius: showsShadow ? mode.shadowRadius(for: colorScheme, isEmphasized: isEmphasized) : 0,
                x: 0,
                y: showsShadow ? mode.shadowYOffset(for: colorScheme, isEmphasized: isEmphasized) : 0
            )
    }
}

extension View {
    func appRoundedSurface(
        mode: AppearanceMode,
        cornerRadius: CGFloat,
        glassMaterial: Material = .regularMaterial,
        standardLevel: AppearanceSurfaceLevel = .panel,
        isEmphasized: Bool = false,
        showsShadow: Bool = true
    ) -> some View {
        modifier(
            AppRoundedSurfaceModifier(
                mode: mode,
                cornerRadius: cornerRadius,
                glassMaterial: glassMaterial,
                standardLevel: standardLevel,
                isEmphasized: isEmphasized,
                showsShadow: showsShadow
            )
        )
    }
}

struct MainInterfaceBackground: View {
    @AppStorage(AppearanceMode.appStorageKey) private var appearanceModeRawValue = AppearanceMode.standard.rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var appearanceMode: AppearanceMode {
        AppearanceMode.resolved(from: appearanceModeRawValue)
    }

    var body: some View {
        ZStack {
            if appearanceMode == .glass {
                AppBackground()
                    .transition(.opacity)
            } else {
                appearanceMode.mainBackgroundColor(for: colorScheme)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appearanceMode)
    }
}
