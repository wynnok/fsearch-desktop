import SwiftUI

enum SearchControlsLayout {
    static let actionWidth: CGFloat = 132
}

struct SearchQueryField<Content: View>: View {
    var symbol = "magnifyingglass"
    var tint: Color = FDTheme.primary
    var onClear: (() -> Void)?
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 19)

            content

            if let onClear {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.tertiary)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .help("清除输入")
                .accessibilityLabel("清除输入")
            }
        }
        .padding(.horizontal, 11)
        .frame(minWidth: 240, minHeight: 40, maxHeight: 40)
        .background {
            RoundedRectangle(cornerRadius: FDTheme.controlRadius, style: .continuous)
                .fill(FDTheme.surfaceFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: FDTheme.controlRadius, style: .continuous)
                .strokeBorder(tint.opacity(scheme == .dark ? 0.52 : 0.34), lineWidth: 1)
        }
    }
}

struct SearchSubmitButton: View {
    let title: String
    var width: CGFloat? = nil
    var tint: Color = FDTheme.primary
    var symbol = "magnifyingglass"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12.5, weight: .semibold))
                .frame(minWidth: 92, maxWidth: width == nil ? nil : .infinity, minHeight: 26)
        }
        .buttonStyle(FDPrimaryButtonStyle(tint: tint))
        .frame(width: width)
        .keyboardShortcut(.return, modifiers: .command)
    }
}

enum SearchFileAction: String, CaseIterable {
    case open, preview, reveal, copy

    var title: String {
        switch self {
        case .open: "打开"
        case .preview: "快速查看"
        case .reveal: "在 Finder 中显示"
        case .copy: "复制路径"
        }
    }

    var symbol: String {
        switch self {
        case .open: "arrow.up.forward.square"
        case .preview: "eye"
        case .reveal: "folder"
        case .copy: "doc.on.doc"
        }
    }

    var tint: Color {
        switch self {
        case .open: FDTheme.slate
        case .preview: FDTheme.plum
        case .reveal: FDTheme.ochre
        case .copy: FDTheme.sage
        }
    }

    @MainActor
    func perform(path: String?, actions: FileActionState) {
        switch self {
        case .open: actions.open(path: path)
        case .preview: actions.togglePreview(path: path)
        case .reveal: actions.reveal(path: path)
        case .copy: actions.copy(path: path)
        }
    }
}

struct SearchFileActionButtons: View {
    let path: String?
    @ObservedObject var actions: FileActionState

    var body: some View {
        ForEach(SearchFileAction.allCases, id: \.self) { action in
            Button { action.perform(path: path, actions: actions) } label: {
                Label(action.title, systemImage: action.symbol)
            }
            .accessibilityIdentifier("file-action-\(action.rawValue)")
            .disabled(path == nil || actions.isMutating)
        }
    }
}

/// Compact icon-only action strip used by the footer and inspector.
struct SearchFileActionIconRow: View {
    let path: String?
    @ObservedObject var actions: FileActionState
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: 1) {
            ForEach(SearchFileAction.allCases, id: \.self) { action in
                Button {
                    action.perform(path: path, actions: actions)
                } label: {
                    Image(systemName: action.symbol)
                        .font(.system(size: size * 0.55, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(path == nil || actions.isMutating
                                         ? Color.secondary.opacity(0.45) : action.tint)
                        .frame(width: size, height: size)
                        .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(path == nil || actions.isMutating)
                .help(action.title)
                .accessibilityLabel(action.title)
                .accessibilityIdentifier("file-action-\(action.rawValue)")
            }
        }
    }
}
