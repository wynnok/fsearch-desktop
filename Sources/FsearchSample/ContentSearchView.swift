import AppKit
import Combine
import FsearchService
import SwiftUI

@MainActor
final class ContentSearchState: ObservableObject {
    @Published var pattern = "" {
        didSet { if pattern != oldValue { generation += 1; response = nil; busy = false; message = "输入已改变，请重新查询。" } }
    }
    @Published private(set) var response: ContentSearchResponse?
    @Published private(set) var busy = false
    @Published private(set) var message = "普通文本按字面匹配；上游 smart case，含大写时区分大小写。"
    private let service: FsearchService?
    private var generation = 0

    init(service: FsearchService?) { self.service = service }

    func search() async {
        generation += 1
        let request = generation
        response = nil
        busy = true
        message = "文本查询中…"
        do {
            guard let service else { throw FsearchError.query("引擎尚不可用。") }
            let result = try await service.grep(ContentSearchRequest(pattern: pattern))
            guard request == generation else { return }
            response = result
            message = "\(result.files.count) 个文件 · 已显示 \(result.displayedOccurrences) 处匹配 · "
                + (result.indexed ? "内容索引候选" : "直接读取候选")
                + " · 已读取 \(result.read)/\(result.candidates) 候选"
                + (result.hasMore ? " · 未完成：预算或文件数量限制；当前入口尚不支持续查。" : " · 本次候选处理完成")
        } catch {
            guard request == generation else { return }
            message = "文本查询失败：\(error.localizedDescription)"
        }
        busy = false
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
            Text("正文使用当前引擎范围；名称窗口的范围与属性筛选尚不应用于正文。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("输入普通文本", text: $state.pattern).accessibilityLabel("正文查询")
                    .onSubmit { Task { await state.search() } }
                Button("查询正文") { Task { await state.search() } }.disabled(state.busy)
            }
            Text(state.message).font(.caption).textSelection(.enabled)
            Text("最多 100 个文件、每文件最多 5 条匹配行；片段约 400 UTF-8 字节，上游预算 250ms。匹配数仅为已显示部分。")
                .font(.caption).foregroundStyle(.secondary)
            List(selection: $selection) {
                ForEach(state.response?.files ?? []) { file in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(file.path).font(.headline).textSelection(.enabled)
                        ForEach(Array(file.lines.enumerated()), id: \.offset) { _, line in
                            Text("\(line.line): \(line.text)").font(.system(.body, design: .monospaced)).textSelection(.enabled)
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
}
