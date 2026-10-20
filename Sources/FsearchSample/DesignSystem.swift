import AppKit
import SwiftUI

/// Shared visual language for every FsearchDesktop surface.
///
/// The palette is deliberately quiet: warm paper and ink, plus a small set of
/// desaturated earth accents. Fills are flat and matte; borders, spacing and
/// type carry the hierarchy instead of gradients, glows or heavy shadows.
enum FDTheme {
    static let canvas = adaptive("canvas", light: 0xF2EFE8, dark: 0x1B1A17)
    static let surfaceFill = adaptive("surface", light: 0xFAF7EF, dark: 0x23221F)
    static let headerFill = adaptive("header", light: 0xECE7DC, dark: 0x201F1C)
    static let hairlineColor = adaptive("hairline", light: 0xD6D0C3, dark: 0x3A3731)
    static let softFillColor = adaptive("soft-fill", light: 0xE9E4D9, dark: 0x2C2A26)
    static let ink = adaptive("ink", light: 0x25231F, dark: 0xEAE5DB)
    static let onAccent = adaptive("on-accent", light: 0xF7F3EA, dark: 0x1B1A17)

    static let primary = adaptive("primary", light: 0x9A4B3A, dark: 0xC07E68)
    static let slate = adaptive("slate", light: 0x4B5F69, dark: 0x8DA6B1)
    static let ochre = adaptive("ochre", light: 0x8A6428, dark: 0xC9A15E)
    static let olive = adaptive("olive", light: 0x5C6B4A, dark: 0x9AAE83)
    static let clay = adaptive("clay", light: 0x8E4638, dark: 0xC47C69)
    static let plum = adaptive("plum", light: 0x6B4F5C, dark: 0xB08E9E)
    static let sage = adaptive("sage", light: 0x4F6B5A, dark: 0x8FAF9C)
    static let stone = adaptive("stone", light: 0x6B665D, dark: 0xA9A297)
    static let rose = adaptive("rose", light: 0x8A5A5F, dark: 0xC09499)

    static let cardRadius: CGFloat = 6
    static let controlRadius: CGFloat = 4

    static let selectionNSColor = nsAdaptive("selection-ns", light: 0xD9C9AB, dark: 0x4D4538)
    static let highlightNSColor = nsAdaptive("highlight-ns", light: 0xDCC27A, dark: 0xAA8240, alpha: 0.50)
    static let headerNSColor = nsAdaptive("header-ns", light: 0xECE7DC, dark: 0x201F1C)
    static let surfaceNSColor = nsAdaptive("surface-ns", light: 0xFAF7EF, dark: 0x23221F)
    static let hairlineNSColor = nsAdaptive("hairline-ns", light: 0xD6D0C3, dark: 0x3A3731)
    static let primaryNSColor = nsAdaptive("primary-ns", light: 0x9A4B3A, dark: 0xC07E68)


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

struct FDAuroraBackground: View {
    var body: some View {
        FDTheme.canvas
            .ignoresSafeArea()
    }
}

struct FDHeaderBackground: View {
    var accent: Color = FDTheme.primary
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        FDTheme.headerFill
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(accent)
                    .frame(height: 2)
                    .opacity(scheme == .dark ? 0.72 : 0.62)
            }
    }
}

struct FDCard<Content: View>: View {
    var padding: CGFloat = 14
    var tint: Color?
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: FDTheme.cardRadius, style: .continuous)
                    .fill(FDTheme.surfaceFill)
            }
            .overlay(alignment: .leading) {
                if let tint {
                    Rectangle()
                        .fill(tint)
                        .frame(width: 2)
                        .padding(.vertical, 8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: FDTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FDTheme.cardRadius, style: .continuous)
                    .strokeBorder(FDTheme.hairlineColor, lineWidth: 1)
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
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(tint.opacity(scheme == .dark ? 0.22 : 0.12))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(tint)
                    .symbolRenderingMode(.hierarchical)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(tint.opacity(scheme == .dark ? 0.34 : 0.22), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

struct FDBrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(FDTheme.ink)
            Image(systemName: "magnifyingglass")
                .font(.system(size: size * 0.44, weight: .bold))
                .foregroundStyle(FDTheme.canvas)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle()
                .fill(FDTheme.primary)
                .frame(width: size * 0.18, height: size * 0.18)
                .padding(size * 0.09)
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
            .foregroundStyle(FDTheme.onAccent)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 2, style: .continuous).fill(tint))
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
                Rectangle()
                    .fill(tint)
                    .frame(width: 5, height: 5)
            }
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(tint.opacity(scheme == .dark ? 0.13 : 0.08)))
        .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
            .strokeBorder(tint.opacity(scheme == .dark ? 0.24 : 0.16), lineWidth: 1))
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
                            .foregroundStyle(isSelected ? FDTheme.onAccent : option.tint)
                            .symbolRenderingMode(.hierarchical)
                        Text(option.title)
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? FDTheme.onAccent : Color.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(FDTheme.primary)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: FDTheme.controlRadius, style: .continuous)
            .fill(FDTheme.softFillColor))
        .overlay(RoundedRectangle(cornerRadius: FDTheme.controlRadius, style: .continuous)
            .strokeBorder(FDTheme.hairlineColor, lineWidth: 1))
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
                .frame(width: 25, height: 22)
                .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
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
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(tint.opacity(scheme == .dark ? 0.14 : 0.07)))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(tint)
                .frame(width: 2)
                .padding(.vertical, 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(tint.opacity(0.18), lineWidth: 1))
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
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.42)
    }
}

struct FDSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(FDTheme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: FDTheme.controlRadius, style: .continuous)
                .fill(FDTheme.surfaceFill))
            .overlay(RoundedRectangle(cornerRadius: FDTheme.controlRadius, style: .continuous)
                .strokeBorder(FDTheme.hairlineColor, lineWidth: 1))
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
        VStack(spacing: 10) {
            FDIconTile(symbol: symbol, tint: tint, size: 52)
                .padding(.bottom, 2)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 11.5))
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
