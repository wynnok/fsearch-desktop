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

    init(service: FsearchService?) {
        controller = ContentSearchController { request in
            guard let service else { throw FsearchError.query("引擎尚不可用。") }
            return try await service.grep(request)
        }
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
                Text("文本内容搜索").font(.headline)
                HStack(spacing: 10) {
                    SearchQueryField {
                        TextField("输入文件中的文本…", text: $state.pattern)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 9)
                            .accessibilityLabel("文本内容查询")
                            .accessibilityIdentifier("content-query")
                            .onSubmit { Task { await state.search() } }
                    }
                    SearchSubmitButton(title: "查询正文") { Task { await state.search() } }
                        .disabled(state.busy)
                        .accessibilityIdentifier("submit-content-search")
                }
                Text("仅搜索已纳入索引的文本文件；不解析 PDF、Office、图片或压缩包，云端未下载的正文不可搜索。Return 查询。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Text("匹配方式")
                    Picker("匹配方式", selection: $state.mode) {
                        Text("普通文本").tag(ContentPatternMode.literal)
                        Text("正则表达式").tag(ContentPatternMode.regex)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240, alignment: .leading)
                    Picker("大小写", selection: $state.caseMode) {
                        Text("智能").tag(ContentCaseMode.smart)
                        Text("区分").tag(ContentCaseMode.sensitive)
                        Text("不区分").tag(ContentCaseMode.insensitive)
                    }
                    .frame(width: 220)
                    Spacer(minLength: 0)
                }
                SearchFiltersView(configuration: $state.configuration)
                HStack(spacing: 8) {
                    if state.busy { ProgressView().controlSize(.small) }
                    Text(state.message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }
            .padding(12)
            Divider()
            List(selection: $selection) {
                ForEach(state.files) { file in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(URL(fileURLWithPath: file.path).lastPathComponent)
                            .font(.headline).lineLimit(1).truncationMode(.middle)
                        Text((file.path as NSString).deletingLastPathComponent)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        ForEach(Array(file.lines.enumerated()), id: \.offset) { _, line in
                            Text(highlighted(line)).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                    .help(file.path)
                    .tag(file.path)
                    .contextMenu {
                        SearchFileActionButtons(path: file.path, actions: actions)
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .accessibilityLabel("按文件分组的内容结果")
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                PathNavigationView(path: selection, actions: actions)
                HStack(spacing: 8) {
                    SearchFileActionButtons(path: selection, actions: actions)
                    Spacer(minLength: 0)
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
        .onChange(of: selection) { actions.updatePreview(path: $0) }
        .onChange(of: state.response?.requestID) { _ in selection = nil; actions.updatePreview(path: nil) }
        .onDisappear { actions.updatePreview(path: nil) }
    }

    private func highlighted(_ line: ContentLine) -> AttributedString {
        var value = AttributedString("\(line.line): ")
        var text = AttributedString(line.text)
        for range in line.nativeRanges {
            guard let lower = AttributedString.Index(range.lowerBound, within: text),
                  let upper = AttributedString.Index(range.upperBound, within: text) else { continue }
            text[lower..<upper].backgroundColor = .yellow
            text[lower..<upper].foregroundColor = .black
        }
        value.append(text)
        return value
    }
}
