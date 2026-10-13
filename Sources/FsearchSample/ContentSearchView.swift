import AppKit
import Combine
import FsearchService
import SwiftUI

@MainActor
final class ContentSearchState: ObservableObject {
    @Published var pattern = "" {
        didSet { if pattern != oldValue { generation += 1; response = nil; busy = false; message = "输入已改变，请重新查询。" } }
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
    @Published private(set) var response: ContentSearchResponse?
    @Published private(set) var busy = false
    @Published private(set) var message = "普通文本按字面匹配；上游 smart case，含大写时区分大小写。"
    @Published private(set) var canLoadMore = false
    private let service: FsearchService?
    private var generation = 0
    private var currentRequest: ContentSearchRequest?

    init(service: FsearchService?) { self.service = service }

    func search() async {
        generation += 1
        let request = generation
        response = nil
        busy = true
        message = "文本查询中…"
        do {
            guard let service else { throw FsearchError.query("引擎尚不可用。") }
            let searchRequest = ContentSearchRequest(
                pattern: pattern,
                mode: mode,
                caseMode: caseMode,
                scopePath: configuration.scope.path,
                showsHidden: configuration.showsHidden,
                filters: configuration.filters
            )
            currentRequest = searchRequest
            let result = try await service.grep(searchRequest)
            guard request == generation else { return }
            response = result
            canLoadMore = result.next != nil
            message = "\(result.files.count) 个文件 · 已显示 \(result.displayedOccurrences) 处匹配 · "
                + (result.indexed ? "内容索引候选" : "直接读取候选")
                + " · 已读取 \(result.read)/\(result.candidates) 候选"
                + (result.next != nil
                    ? " · 未完成：可继续"
                    : result.complete
                        ? " · 本次候选处理完成"
                        : " · 未完成：上游未提供续查位置")
        } catch {
            guard request == generation else { return }
            message = "文本查询失败：\(error.localizedDescription)"
            canLoadMore = false
        }
        busy = false
    }

    func loadMore() async {
        guard let service, let currentRequest, let cursor = response?.next, !busy else { return }
        generation += 1
        let request = generation
        busy = true
        message = "继续文本查询中…"
        do {
            let result = try await service.grep(currentRequest.continuing(at: cursor))
            guard request == generation else { return }
            let existing = Set(response?.files.map(\.path) ?? [])
            let newFiles = result.files.filter { !existing.contains($0.path) }
            response = ContentSearchResponse(
                requestID: result.requestID,
                files: (response?.files ?? []) + newFiles,
                candidates: result.candidates,
                read: result.read,
                complete: result.complete,
                next: result.next,
                indexed: result.indexed,
                error: result.error
            )
            canLoadMore = result.next != nil
            message = "\(response?.files.count ?? 0) 个文件 · 已显示 \(response?.displayedOccurrences ?? 0) 处匹配 · "
                + (result.indexed ? "内容索引候选" : "直接读取候选")
                + (result.next != nil
                    ? " · 未完成：可继续"
                    : result.complete ? " · 本次候选处理完成" : " · 未完成：上游未提供续查位置")
        } catch {
            guard request == generation else { return }
            message = "继续文本查询失败：\(error.localizedDescription)"
        }
        busy = false
    }

    private func invalidateResult(_ message: String) {
        generation += 1
        response = nil
        currentRequest = nil
        canLoadMore = false
        busy = false
        self.message = message
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
                ForEach(state.response?.files ?? []) { file in
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
