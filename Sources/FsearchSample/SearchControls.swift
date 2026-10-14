import SwiftUI

struct SearchQueryField<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(minWidth: 280, minHeight: 40, maxHeight: 40)
            .padding(.horizontal, 10)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
    }
}

struct SearchSubmitButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "magnifyingglass")
                .frame(minWidth: 96, minHeight: 28)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle)
        .controlSize(.large)
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
