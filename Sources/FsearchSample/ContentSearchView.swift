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
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("文本内容搜索").font(.system(size: 20, weight: .bold))
                    Spacer()
                    Text("Return 查询")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(width: SearchControlsLayout.actionWidth)
                }
                HStack(spacing: 10) {
                    SearchQueryField {
                        TextField("输入文件中的文本…", text: $state.pattern)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 9)
                            .accessibilityLabel("文本内容查询")
                            .accessibilityIdentifier("content-query")
                            .onSubmit { Task { await state.search() } }
                    }
                    SearchSubmitButton(title: "查询正文", width: SearchControlsLayout.actionWidth) {
                        Task { await state.search() }
                    }
                    .disabled(state.busy)
                    .accessibilityIdentifier("submit-content-search")
                }
                Text("搜索已收录的文本文件正文。不解析 PDF、Office、图片或压缩包；云端未下载的正文不可搜索。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Text("匹配方式").fixedSize()
                        Picker("匹配方式", selection: $state.mode) {
                            Text("普通文本").tag(ContentPatternMode.literal)
                            Text("正则表达式").tag(ContentPatternMode.regex)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }
                    .frame(width: SearchControlsLayout.nameOptionsWidth)
                    Spacer(minLength: 12)
                    Text("大小写").fixedSize()
                    Picker("大小写", selection: $state.caseMode) {
                        Text("智能").tag(ContentCaseMode.smart)
                        Text("区分").tag(ContentCaseMode.sensitive)
                        Text("不区分").tag(ContentCaseMode.insensitive)
                    }
                    .labelsHidden()
                    .frame(width: SearchControlsLayout.actionWidth)
                }
                SearchFiltersView(configuration: $state.configuration,
                                  controlsWidth: SearchControlsLayout.nameOptionsWidth,
                                  actionWidth: SearchControlsLayout.actionWidth)
                HStack(spacing: 8) {
                    if state.busy { ProgressView().controlSize(.small) }
                    Text(statusMessage)
                        .font(.system(size: 13)).foregroundStyle(statusColor)
                        .lineLimit(2).textSelection(.enabled)
                        .accessibilityIdentifier("content-query-status")
                    Spacer(minLength: 0)
                }
            }
            .padding(12)
            Divider()
            ContentSearchResultsView(files: state.files, selection: $selection, actions: actions)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    PathNavigationView(path: selection, actions: actions)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("载入更多") { Task { await state.loadMore() } }.disabled(!state.canLoadMore || state.busy)
                        .accessibilityIdentifier("load-more-content")
                    Button("关闭") { actions.updatePreview(path: nil); dismiss() }.keyboardShortcut(.cancelAction)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                if let message = actions.message {
                    Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .padding(12)
        }
        .frame(width: 760, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { selection = state.files.first?.path }
        .onChange(of: selection) { actions.updatePreview(path: $0) }
        .onChange(of: state.response?.requestID) { _ in
            selection = state.files.first?.path
            actions.updatePreview(path: nil)
        }
        .onDisappear { actions.updatePreview(path: nil) }
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
        case .failed: .red
        case .stopped: .orange
        default: .secondary
        }
    }
}
