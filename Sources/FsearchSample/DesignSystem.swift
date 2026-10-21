import AppKit
import SwiftUI

/// Shared visual language for every FsearchDesktop surface.
///
/// Neutral content surfaces keep files legible; system glass belongs to controls.
/// Ocean, teal, amber and coral provide small, purposeful accents.
enum FDTheme {
    static let canvas = adaptive("canvas", light: 0xF3F5F7, dark: 0x191C20)
    static let surfaceFill = adaptive("surface", light: 0xFFFFFF, dark: 0x22262B)
    static let headerFill = adaptive("header", light: 0xF4F6F8, dark: 0x20252B)
    static let hairlineColor = Color(nsColor: .separatorColor).opacity(0.55)
    static let softFillColor = adaptive("soft-fill", light: 0xEBEFF3, dark: 0x30363E)
    static let ink = Color(nsColor: .labelColor)
    static let onAccent = Color.white

    static let primary = adaptive("primary", light: 0x0867B5, dark: 0x1479C9)
    static let slate = adaptive("slate", light: 0x176FA6, dark: 0x75BFF0)
    static let ochre = adaptive("ochre", light: 0x966116, dark: 0xEDB75D)
    static let olive = adaptive("olive", light: 0x31744C, dark: 0x86CCA0)
    static let clay = adaptive("clay", light: 0xB64438, dark: 0xF19C8D)
    static let teal = adaptive("teal", light: 0x087C83, dark: 0x74CCD0)
    static let sage = adaptive("sage", light: 0x337667, dark: 0x82C8B6)
    static let stone = adaptive("stone", light: 0x626D79, dark: 0xA6B0BE)
    static let rose = adaptive("rose", light: 0xAF4F63, dark: 0xEEA1B0)

    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 12

    static let selectionNSColor = nsAdaptive("selection-ns", light: 0xD9EBFA, dark: 0x254B6A)
    static let highlightNSColor = nsAdaptive("highlight-ns", light: 0xF1CB75, dark: 0x9A7126, alpha: 0.50)
    static let headerNSColor = nsAdaptive("header-ns", light: 0xF4F6F8, dark: 0x20252B)
    static let surfaceNSColor = nsAdaptive("surface-ns", light: 0xFFFFFF, dark: 0x22262B)
    static let hairlineNSColor = NSColor.separatorColor
    static let primaryNSColor = nsAdaptive("primary-ns", light: 0x0867B5, dark: 0x75BFF0)


    private static func adaptive(_ name: String, light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: nsAdaptive(name, light: light, dark: dark))
    }

    private static func nsAdaptive(_ name: String, light: UInt32, dark: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(name: NSColor.Name("FDTheme.\(name)")) { appearance in
            NSColor(rgb: isDark(appearance) ? dark : light).withAlphaComponent(alpha)
        }
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

private extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Surfaces

/// Use native Liquid Glass when available, with an accessible material fallback.
struct FDGlassSurface: ViewModifier {
    var radius: CGFloat = FDTheme.controlRadius
    var tint: Color? = nil
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if reduceTransparency || contrast == .increased {
            content
                .background(FDTheme.surfaceFill, in: shape)
                .overlay(shape.strokeBorder(FDTheme.hairlineColor, lineWidth: 1))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(FDTheme.hairlineColor, lineWidth: 0.5))
        }
    }
}

struct FDAuroraBackground: View {
    var body: some View {
        FDTheme.canvas
            .ignoresSafeArea()
    }
}

struct FDHeaderBackground: View {
    var accent: Color = FDTheme.primary
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            if reduceTransparency || contrast == .increased {
                FDTheme.headerFill
            } else {
                Rectangle().fill(.regularMaterial)
                accent.opacity(0.025)
            }
        }
    }
}

struct FDCard<Content: View>: View {
    var padding: CGFloat = 14
    var tint: Color?
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: FDTheme.cardRadius, style: .continuous)
                    .fill(FDTheme.surfaceFill)
            }
            .clipShape(RoundedRectangle(cornerRadius: FDTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FDTheme.cardRadius, style: .continuous)
                    .strokeBorder(tint?.opacity(0.16) ?? FDTheme.hairlineColor, lineWidth: 0.5)
            }
    }
}

// MARK: - Badges & pills

struct FDIconTile: View {
    let symbol: String
    var tint: Color = FDTheme.primary
    var size: CGFloat = 30
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(tint.opacity(scheme == .dark ? 0.20 : 0.09))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(tint)
                    .symbolRenderingMode(.hierarchical)
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(tint.opacity(scheme == .dark ? 0.26 : 0.12), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

struct FDBrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(FDTheme.primary)
            Image(systemName: "magnifyingglass")
                .font(.system(size: size * 0.44, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Circle()
                .fill(Color(red: 0.98, green: 0.72, blue: 0.30))
                .frame(width: size * 0.18, height: size * 0.18)
                .padding(size * 0.12)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct FDCountBadge: View {
    let text: String
    var tint: Color = FDTheme.primary

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.12)))
    }
}

struct FDStatusPill: View {
    let text: String
    let symbol: String
    var tint: Color = FDTheme.olive
    var showsProgress = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 5) {
            if showsProgress {
                ProgressView()
                    .controlSize(.mini)
                    .tint(tint)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule()
            .fill(tint.opacity(scheme == .dark ? 0.13 : 0.08)))
        .overlay(Capsule()
            .strokeBorder(tint.opacity(scheme == .dark ? 0.24 : 0.12), lineWidth: 0.5))
    }
}

struct FDSectionLabel: View {
    let title: String
    var symbol: String?
    var tint: Color = FDTheme.primary

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(tint)
            } else {
                Rectangle()
                    .fill(tint)
                    .frame(width: 2, height: 10)
            }
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.2)
                .foregroundStyle(.secondary)
        }
    }
}

struct FDKeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(FDTheme.softFillColor))
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(FDTheme.hairlineColor, lineWidth: 1))
    }
}

// MARK: - Controls

struct FDSegmentedOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    let symbol: String
    var tint: Color = FDTheme.primary

    var id: Value { value }
}

struct FDSegmentedPicker<Value: Hashable>: View {
    let options: [FDSegmentedOption<Value>]
    @Binding var selection: Value
    var accessibilityLabel: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = option.value == selection
                Button {
                    guard !isSelected else { return }
                    selection = option.value
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: option.symbol)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(isSelected ? option.tint : Color.secondary)
                            .symbolRenderingMode(.hierarchical)
                        Text(option.title)
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? FDTheme.ink : Color.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: FDTheme.controlRadius, style: .continuous)
                                .fill(FDTheme.surfaceFill)
                                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: FDTheme.controlRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .modifier(FDGlassSurface(radius: FDTheme.controlRadius + 3))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct FDActionIconButton: View {
    let symbol: String
    let label: String
    var tint: Color = FDTheme.primary
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isEnabled ? tint : Color.secondary.opacity(0.5))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 26, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(FDSecondaryButtonStyle())
        .disabled(!isEnabled)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct FDNoticeBanner: View {
    let text: String
    var symbol: String = "info.circle.fill"
    var tint: Color = FDTheme.ochre
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: FDTheme.controlRadius, style: .continuous)
            .fill(tint.opacity(scheme == .dark ? 0.14 : 0.07)))
        .clipShape(RoundedRectangle(cornerRadius: FDTheme.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FDTheme.controlRadius, style: .continuous)
            .strokeBorder(tint.opacity(0.18), lineWidth: 0.5))
    }
}

// MARK: - Buttons

struct FDPrimaryButtonStyle: ButtonStyle {
    var tint: Color = FDTheme.primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(FDTheme.onAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: FDTheme.controlRadius, style: .continuous)
                .fill(tint))
            .modifier(FDGlassSurface(tint: tint, interactive: isEnabled))
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.42)
    }
}

struct FDSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(FDTheme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .modifier(FDGlassSurface(interactive: isEnabled))
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.42)
    }
}

// MARK: - Empty state

struct FDEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var tint: Color = FDTheme.primary
    var hints: [(key: String, label: String)] = []

    var body: some View {
        VStack(spacing: 12) {
            FDIconTile(symbol: symbol, tint: tint, size: 68)
                .padding(.bottom, 6)
            Text(title)
                .font(.system(size: 19, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
            if !hints.isEmpty {
                HStack(spacing: 10) {
                    ForEach(hints, id: \.key) { hint in
                        HStack(spacing: 4) {
                            FDKeyCap(text: hint.key)
                            Text(hint.label)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(24)
    }
}
