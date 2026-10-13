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
        VStack(alignment: .leading, spacing: 12) {
            Text("文本内容搜索").font(.headline)
            Text("仅上游合规文本；不解析 PDF/Office/OCR 或压缩包，云端缺失正文不可搜。样本名称模式不支持正文。")
                .font(.caption)
            HStack {
                Picker("匹配方式", selection: $state.mode) {
                    Text("普通文本").tag(ContentPatternMode.literal)
                    Text("正则表达式").tag(ContentPatternMode.regex)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                Picker("大小写", selection: $state.caseMode) {
                    Text("智能").tag(ContentCaseMode.smart)
                    Text("区分").tag(ContentCaseMode.sensitive)
                    Text("不区分").tag(ContentCaseMode.insensitive)
                }
                .frame(maxWidth: 260)
            }
            SearchFiltersView(configuration: $state.configuration)
            HStack {
                TextField("输入正文查询", text: $state.pattern).accessibilityLabel("正文查询")
                    .onSubmit { Task { await state.search() } }
                Button("查询正文") { Task { await state.search() } }.disabled(state.busy)
            }
            Text(state.message).font(.caption).textSelection(.enabled)
            List(selection: $selection) {
                ForEach(state.files) { file in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(file.path).font(.headline).textSelection(.enabled)
                        ForEach(Array(file.lines.enumerated()), id: \.offset) { _, line in
                            Text(highlighted(line)).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                    .tag(file.path)
                    .contextMenu {
                        Button("打开") { actions.open(path: file.path) }
                        Button("Quick Look") { actions.togglePreview(path: file.path) }
                        Button("在 Finder 显示") { actions.reveal(path: file.path) }
                        Button("复制完整路径") { actions.copy(path: file.path) }
                    }
                }
            }
            .accessibilityLabel("按文件分组的内容结果")
            HStack {
                Button("打开") { actions.open(path: selection) }.disabled(selection == nil)
                Button("Quick Look") { actions.togglePreview(path: selection) }.disabled(selection == nil)
                Button("在 Finder 显示") { actions.reveal(path: selection) }.disabled(selection == nil)
                Button("继续") { Task { await state.loadMore() } }.disabled(!state.canLoadMore)
                Spacer()
                Button("关闭") { actions.updatePreview(path: nil); dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let message = actions.message { Text(message).font(.caption) }
        }
        .padding(20).frame(width: 760, height: 520)
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
