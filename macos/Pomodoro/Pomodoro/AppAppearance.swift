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

enum OrchestranaButtonVariant {
    case primary
    case secondary
    case subtle
    case quiet
    case icon
    case destructive
}

struct OrchestranaButtonStyle: ButtonStyle {
    let variant: OrchestranaButtonVariant
    let minWidth: CGFloat?
    let minHeight: CGFloat

    init(
        _ variant: OrchestranaButtonVariant = .secondary,
        minWidth: CGFloat? = nil,
        minHeight: CGFloat = 30
    ) {
        self.variant = variant
        self.minWidth = minWidth
        self.minHeight = minHeight
    }

    func makeBody(configuration: Configuration) -> some View {
        OrchestranaButtonBody(
            configuration: configuration,
            variant: variant,
            minWidth: minWidth,
            minHeight: minHeight
        )
    }
}

private struct OrchestranaButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let variant: OrchestranaButtonVariant
    let minWidth: CGFloat?
    let minHeight: CGFloat

    @AppStorage(AppearanceMode.appStorageKey) private var appearanceModeRawValue = AppearanceMode.standard.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    private var appearanceMode: AppearanceMode {
        AppearanceMode.resolved(from: appearanceModeRawValue)
    }

    var body: some View {
        let shape = buttonShape

        configuration.label
            .font(labelFont)
            .lineLimit(1)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .frame(minWidth: minWidth, minHeight: minHeight)
            .contentShape(shape)
            .background {
                backgroundFill(shape)
            }
            .overlay {
                shape.stroke(borderColor, lineWidth: borderWidth)
            }
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowYOffset)
            .scaleEffect(pressScale)
            .opacity(isEnabled ? 1.0 : 0.48)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
            .onHover { isHovering = $0 }
    }

    private var buttonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var cornerRadius: CGFloat {
        variant == .icon ? 7 : 8
    }

    private var horizontalPadding: CGFloat {
        switch variant {
        case .icon:
            return 7
        case .subtle, .quiet:
            return 10
        default:
            return 12
        }
    }

    private var labelFont: Font {
        switch variant {
        case .icon:
            return .system(.body).weight(.medium)
        default:
            return .system(.subheadline).weight(.medium)
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary:
            return .white
        case .destructive:
            return isEnabled ? .red : .secondary
        case .subtle, .quiet, .icon:
            return .primary
        case .secondary:
            return appearanceMode.primaryTextColor(for: colorScheme)
        }
    }

    @ViewBuilder
    private func backgroundFill(_ shape: RoundedRectangle) -> some View {
        switch variant {
        case .primary:
            shape.fill(Color.accentColor.opacity(isEnabled ? (configuration.isPressed ? 0.78 : 0.88) : 0.3))
        case .destructive:
            shape.fill(Color.red.opacity(backgroundOpacity(primary: 0.08, hover: 0.12, pressed: 0.16)))
        case .subtle, .quiet:
            shape.fill(Color.primary.opacity(backgroundOpacity(primary: 0.00, hover: 0.045, pressed: 0.075)))
        case .icon:
            if appearanceMode == .glass {
                shape.fill(isHovering || configuration.isPressed ? .thinMaterial : .ultraThinMaterial)
            } else {
                shape.fill(Color.primary.opacity(backgroundOpacity(primary: 0.035, hover: 0.065, pressed: 0.095)))
            }
        case .secondary:
            if appearanceMode == .glass {
                shape.fill(.thinMaterial)
            } else {
                shape.fill(appearanceMode.surfaceColor(for: .inset, colorScheme: colorScheme))
            }
        }
    }

    private func backgroundOpacity(primary: Double, hover: Double, pressed: Double) -> Double {
        if configuration.isPressed { return pressed }
        if isHovering { return hover }
        return primary
    }

    private var borderColor: Color {
        switch variant {
        case .primary:
            return Color.white.opacity(isHovering ? 0.28 : 0.18)
        case .destructive:
            return Color.red.opacity(isHovering ? 0.3 : 0.18)
        case .subtle, .quiet:
            return isHovering ? appearanceMode.borderColor(for: colorScheme, isEmphasized: true) : .clear
        case .icon, .secondary:
            return appearanceMode.borderColor(for: colorScheme, isEmphasized: isHovering || configuration.isPressed)
        }
    }

    private var borderWidth: CGFloat {
        (variant == .subtle || variant == .quiet) && !isHovering ? 0 : 1
    }

    private var shadowColor: Color {
        guard isEnabled else { return .clear }
        switch variant {
        case .primary:
            return Color.black.opacity(colorScheme == .dark ? 0.16 : 0.08)
        case .secondary:
            return isHovering ? appearanceMode.shadowColor(for: colorScheme, isEmphasized: false) : .clear
        default:
            return .clear
        }
    }

    private var shadowRadius: CGFloat {
        switch variant {
        case .primary:
            return isHovering ? 4 : 2
        case .secondary:
            return isHovering ? 3 : 0
        default:
            return 0
        }
    }

    private var shadowYOffset: CGFloat {
        variant == .primary ? 1 : 1
    }

    private var pressScale: CGFloat {
        guard isEnabled, !reduceMotion else { return 1.0 }
        return configuration.isPressed ? 0.99 : 1.0
    }
}

struct OrchestranaTextFieldStyle: TextFieldStyle {
    @AppStorage(AppearanceMode.appStorageKey) private var appearanceModeRawValue = AppearanceMode.standard.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func _body(configuration: TextField<Self._Label>) -> some View {
        let appearanceMode = AppearanceMode.resolved(from: appearanceModeRawValue)
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)

        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                if appearanceMode == .glass {
                    shape.fill(.thinMaterial)
                } else {
                    shape.fill(appearanceMode.surfaceColor(for: .inset, colorScheme: colorScheme))
                }
            }
            .overlay {
                shape.stroke(appearanceMode.borderColor(for: colorScheme), lineWidth: 1)
            }
            .opacity(isEnabled ? 1.0 : 0.55)
    }
}

struct OrchestranaSelectorOption<Value: Hashable>: Identifiable {
    let id: String
    let value: Value
    let title: String
    let subtitle: String?
    let systemImage: String?

    init(
        _ title: String,
        value: Value,
        subtitle: String? = nil,
        systemImage: String? = nil,
        id: String? = nil
    ) {
        self.id = id ?? title
        self.value = value
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
    }
}

enum OrchestranaSelectorLayout {
    case inline
    case grid
}

struct OrchestranaSelector<Value: Hashable>: View {
    let options: [OrchestranaSelectorOption<Value>]
    @Binding var selection: Value
    let layout: OrchestranaSelectorLayout
    let minOptionWidth: CGFloat
    let accessibilityLabel: String?

    @AppStorage(AppearanceMode.appStorageKey) private var appearanceModeRawValue = AppearanceMode.standard.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    init(
        selection: Binding<Value>,
        options: [OrchestranaSelectorOption<Value>],
        layout: OrchestranaSelectorLayout = .inline,
        minOptionWidth: CGFloat = 74,
        accessibilityLabel: String? = nil
    ) {
        self._selection = selection
        self.options = options
        self.layout = layout
        self.minOptionWidth = minOptionWidth
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        let appearanceMode = AppearanceMode.resolved(from: appearanceModeRawValue)
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)

        Group {
            switch layout {
            case .inline:
                HStack(spacing: 4) {
                    optionButtons
                }
            case .grid:
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: minOptionWidth), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    optionButtons
                }
            }
        }
            .padding(3)
            .background {
                if appearanceMode == .glass {
                    shape.fill(.ultraThinMaterial)
                } else {
                    shape.fill(appearanceMode.surfaceColor(for: .inset, colorScheme: colorScheme))
                }
            }
            .overlay {
                shape.stroke(appearanceMode.borderColor(for: colorScheme), lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel ?? "")
    }

    @ViewBuilder
    private var optionButtons: some View {
        ForEach(options) { option in
            selectorButton(for: option)
        }
    }

    private func selectorButton(for option: OrchestranaSelectorOption<Value>) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                selection = option.value
            }
        } label: {
            OrchestranaSelectorOptionLabel(
                option: option,
                isSelected: selection == option.value,
                minWidth: minOptionWidth
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(selection == option.value ? .isSelected : [])
    }
}

private struct OrchestranaSelectorOptionLabel<Value: Hashable>: View {
    let option: OrchestranaSelectorOption<Value>
    let isSelected: Bool
    let minWidth: CGFloat

    @AppStorage(AppearanceMode.appStorageKey) private var appearanceModeRawValue = AppearanceMode.standard.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let appearanceMode = AppearanceMode.resolved(from: appearanceModeRawValue)
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        VStack(alignment: .center, spacing: option.subtitle == nil ? 0 : 2) {
            HStack(spacing: 6) {
                if let systemImage = option.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(.caption, weight: .semibold))
                }
                Text(option.title)
                    .font(.system(.subheadline, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if let subtitle = option.subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.82) : appearanceMode.secondaryTextColor(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .foregroundStyle(isSelected ? .white : .primary)
        .padding(.horizontal, 10)
        .padding(.vertical, option.subtitle == nil ? 6 : 7)
        .frame(minWidth: minWidth, minHeight: option.subtitle == nil ? 28 : 42)
        .background {
            if isSelected {
                shape.fill(Color.accentColor.opacity(0.86))
            } else {
                shape.fill(Color.primary.opacity(0.001))
            }
        }
        .overlay {
            shape.stroke(
                isSelected ? Color.white.opacity(0.16) : Color.clear,
                lineWidth: 1
            )
        }
    }
}

struct OrchestranaStepControl: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let valueText: (Int) -> String
    let onChange: (() -> Void)?

    @Environment(\.isEnabled) private var isEnabled

    init(
        value: Binding<Int>,
        in range: ClosedRange<Int>,
        step: Int = 1,
        valueText: @escaping (Int) -> String,
        onChange: (() -> Void)? = nil
    ) {
        self._value = value
        self.range = range
        self.step = step
        self.valueText = valueText
        self.onChange = onChange
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                adjust(by: -step)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 14, height: 14)
            }
            .orchestranaButton(.icon, minWidth: 28, minHeight: 28)
            .disabled(value <= range.lowerBound)
            .help("Decrease")

            Text(valueText(value))
                .font(.system(.subheadline).monospacedDigit())
                .foregroundStyle(isEnabled ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: 92)

            Button {
                adjust(by: step)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 14, height: 14)
            }
            .orchestranaButton(.icon, minWidth: 28, minHeight: 28)
            .disabled(value >= range.upperBound)
            .help("Increase")
        }
        .onChange(of: value) { _, _ in
            onChange?()
        }
    }

    private func adjust(by delta: Int) {
        value = min(max(value + delta, range.lowerBound), range.upperBound)
    }
}

struct OrchestranaControlGroup<Content: View>: View {
    let content: Content

    @AppStorage(AppearanceMode.appStorageKey) private var appearanceModeRawValue = AppearanceMode.standard.rawValue

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let appearanceMode = AppearanceMode.resolved(from: appearanceModeRawValue)

        HStack(spacing: 8) {
            content
        }
        .padding(4)
        .appRoundedSurface(
            mode: appearanceMode,
            cornerRadius: 12,
            glassMaterial: .ultraThinMaterial,
            standardLevel: .inset,
            isEmphasized: false,
            showsShadow: false
        )
    }
}

struct OrchestranaFormRow<Control: View>: View {
    let title: String
    let detail: String?
    let control: Control

    init(
        title: String,
        detail: String? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.body, weight: .medium))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 16)
            control
        }
    }
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

    func orchestranaButton(
        _ variant: OrchestranaButtonVariant = .secondary,
        minWidth: CGFloat? = nil,
        minHeight: CGFloat = 30
    ) -> some View {
        buttonStyle(OrchestranaButtonStyle(variant, minWidth: minWidth, minHeight: minHeight))
    }

    func orchestranaTextField() -> some View {
        textFieldStyle(OrchestranaTextFieldStyle())
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
