import AppKit
import Combine
import FsearchService
import SwiftUI

@MainActor
final class ContentSearchState: ObservableObject {
    @Published var pattern = "" {
        didSet { if pattern != oldValue { invalidateResult("输入已改变，请重新查询。") } }
    }
    @Published var mode: ContentPatternMode = .literal {
        didSet { invalidateResult("匹配方式已改变，请重新查询。") }
    }
    @Published var caseMode: ContentCaseMode = .smart {
        didSet { invalidateResult("大小写方式已改变，请重新查询。") }
    }
    @Published var configuration = SearchConfiguration(query: "") {
        didSet { invalidateResult("范围或属性筛选已改变，请重新查询。") }
    }
    let controller: ContentSearchController
    var resultLimit = 100
    private var observation: AnyCancellable?

    var response: ContentSearchResponse? { controller.response }
    var files: [ContentFile] { controller.files }
    var busy: Bool { controller.busy }
    var message: String { controller.message }
    var canLoadMore: Bool { controller.canLoadMore }

    convenience init(service: FsearchService?) {
        self.init(controller: ContentSearchController { request in
            guard let service else { throw FsearchError.query("引擎尚不可用。") }
            return try await service.grep(request)
        })
    }

    init(controller: ContentSearchController) {
        self.controller = controller
        observation = controller.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func search() async {
        await controller.search(ContentSearchRequest(
            pattern: pattern,
            mode: mode,
            caseMode: caseMode,
            limit: resultLimit,
            scopePath: configuration.scope.path,
            showsHidden: configuration.showsHidden,
            filters: configuration.filters
        ))
    }

    func loadMore() async { await controller.loadMore() }

    private func invalidateResult(_ message: String) {
        controller.invalidate(message: message)
    }
}

struct ContentSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state: ContentSearchState
    @StateObject private var actions = FileActionState()
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(FDTheme.hairlineColor)
            ContentSearchResultsView(files: state.files, selection: $selection, actions: actions)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
            Divider().overlay(FDTheme.hairlineColor)
            footer
        }
        .frame(width: 760, height: 520)
        .background(FDTheme.canvas)
        .tint(FDTheme.primary)
        .onAppear { selection = state.files.first?.path }
        .onChange(of: selection) { actions.updatePreview(path: $0) }
        .onChange(of: state.response?.requestID) { _ in
            selection = state.files.first?.path
            actions.updatePreview(path: nil)
        }
        .onDisappear { actions.updatePreview(path: nil) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                FDIconTile(symbol: "text.magnifyingglass", tint: FDTheme.teal, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("文本内容搜索")
                        .font(.system(size: 17, weight: .bold))
                    Text("在已收录的文本文件中查找内容")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    FDKeyCap(text: "Return")
                    Text("查询")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                FDActionIconButton(symbol: "xmark",
                                   label: "关闭",
                                   tint: .secondary,
                                   action: close)
            }

            HStack(spacing: 10) {
                SearchQueryField(
                    symbol: "text.magnifyingglass",
                    tint: FDTheme.teal,
                    onClear: state.pattern.isEmpty ? nil : { state.pattern = "" }
                ) {
                    TextField("输入文件中的文本…", text: $state.pattern)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 2)
                        .accessibilityLabel("文本内容查询")
                        .accessibilityIdentifier("content-query")
                        .onSubmit { Task { await state.search() } }
                }

                SearchSubmitButton(title: "查询正文",
                                   width: SearchControlsLayout.actionWidth,
                                   action: { Task { await state.search() } })
                    .disabled(state.busy)
                    .accessibilityIdentifier("submit-content-search")
            }

            HStack(spacing: 5) {
                Image(systemName: "info.circle")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text("搜索已收录的文本文件正文；不解析 PDF、Office、图片或压缩包，云端未下载的正文不可搜索。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 9) {
                FDSegmentedPicker(
                    options: [
                        .init(value: .literal, title: "普通文本", symbol: "text.alignleft", tint: FDTheme.teal),
                        .init(value: .regex, title: "正则表达式", symbol: "curlybraces", tint: FDTheme.teal)
                    ],
                    selection: $state.mode,
                    accessibilityLabel: "匹配方式"
                )
                .accessibilityIdentifier("content-mode")

                controlDivider

                Text("大小写")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)

                FDSegmentedPicker(
                    options: [
                        .init(value: .smart, title: "自动", symbol: "a.square", tint: FDTheme.ochre),
                        .init(value: .sensitive, title: "区分", symbol: "a.square.fill", tint: FDTheme.ochre),
                        .init(value: .insensitive, title: "不区分", symbol: "abc", tint: FDTheme.ochre)
                    ],
                    selection: $state.caseMode,
                    accessibilityLabel: "大小写"
                )
                .accessibilityIdentifier("content-case")

                Spacer(minLength: 8)
            }

            HStack(spacing: 9) {
                SearchScopeMenu(configuration: $state.configuration)
                controlDivider
                SearchHiddenToggle(configuration: $state.configuration)
                Spacer(minLength: 8)
                SearchFiltersView(configuration: $state.configuration)
            }

            HStack(alignment: .top, spacing: 6) {
                if state.busy {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(statusColor)
                        .padding(.top, 1)
                } else {
                    Image(systemName: statusSymbol)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .symbolRenderingMode(.hierarchical)
                        .padding(.top, 1)
                }
                Text(statusMessage)
                    .font(.system(size: 10.5))
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("content-query-status")
                Spacer(minLength: 0)
            }

            if let message = actions.message {
                FDNoticeBanner(text: message,
                               symbol: "info.circle.fill",
                               tint: FDTheme.ochre)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(FDHeaderBackground(accent: FDTheme.teal))
    }

    private var controlDivider: some View {
        Rectangle()
            .fill(FDTheme.hairlineColor)
            .frame(width: 1, height: 17)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            PathNavigationView(path: selection, actions: actions)
                .frame(maxWidth: .infinity, alignment: .leading)

            SearchFileActionIconRow(path: selection, actions: actions, size: 24)

            Rectangle()
                .fill(FDTheme.hairlineColor)
                .frame(width: 1, height: 16)

            Button {
                Task { await state.loadMore() }
            } label: {
                Label("载入更多", systemImage: "arrow.down.circle")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .disabled(!state.canLoadMore || state.busy)
            .accessibilityIdentifier("load-more-content")
            .buttonStyle(FDSecondaryButtonStyle())

            Button(action: close) {
                Label("关闭", systemImage: "xmark")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(FDSecondaryButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(FDHeaderBackground(accent: FDTheme.teal))
    }

    private func close() {
        actions.updatePreview(path: nil)
        dismiss()
    }

    private var statusMessage: String {
        let counts = "已载入 \(state.files.count) 个文件 · \(state.controller.displayedOccurrences) 处匹配"
        switch state.controller.phase {
        case .idle, .failed:
            return state.message
        case .loading:
            return state.files.isEmpty ? "正在搜索文本…" : "正在载入更多匹配文件…"
        case .partial:
            return "\(counts) · 仍可能有更多结果，可继续载入"
        case .complete:
            return "\(counts) · 本次查询已完成"
        case .stopped:
            return "\(counts) · 结果可能不完整，可缩小范围后重试"
        }
    }

    private var statusColor: Color {
        switch state.controller.phase {
        case .failed: FDTheme.clay
        case .stopped: FDTheme.ochre
        case .loading: FDTheme.teal
        case .complete: FDTheme.olive
        default: .secondary
        }
    }

    private var statusSymbol: String {
        switch state.controller.phase {
        case .failed: "exclamationmark.triangle.fill"
        case .stopped: "pause.circle.fill"
        case .loading: "magnifyingglass"
        case .complete: "checkmark.circle.fill"
        default: "info.circle"
        }
    }
}
