import AppKit
import FsearchService
import Foundation
import SwiftUI

@MainActor
final class SearchModel: ObservableObject {
    @Published var query = "report"
    @Published var results: [SearchResult] = []
    @Published var message = "输入名称后按 Return 或点击查询。"
    @Published var busy = false
    private var service: FsearchService?

    init() {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else {
            message = "请使用 bash scripts/dev.sh run 指定项目内受控样本。"
            return
        }
        do {
            service = try FsearchService(sampleDirectory: URL(fileURLWithPath: arguments[1]))
        } catch {
            message = "样本初始化失败：\(error.localizedDescription)"
        }
    }

    func submit() {
        Task { await search() }
    }

    private func search() async {
        guard let service, !busy else { return }
        busy = true
        message = "查询中…"
        results = []
        let request = SearchRequest(query: query)
        defer { busy = false }
        do {
            let response = try await service.search(request)
            results = response.results
            message = results.isEmpty ? "无匹配" : "已载入 \(results.count) 个结果（上限 \(request.limit)）"
        } catch {
            message = "查询失败：\(error.localizedDescription)"
        }
    }

    // Opt-in native smoke: exercise the same action and capture the real window.
    func runSmokeIfRequested() async {
        let arguments = CommandLine.arguments
        guard arguments.count == 4, arguments[2] == "--smoke" else { return }
        let output = URL(fileURLWithPath: arguments[3], isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let cases = [
                ("success", "report", 2, "已载入"),
                ("no-match", "^absent-fixture-name$", 0, "无匹配"),
                ("failure", "re:[", 0, "查询失败"),
                ("recovered", "笔记", 1, "已载入")
            ]
            for (name, input, count, expectedMessage) in cases {
                query = input
                await search()
                guard results.count == count, message.hasPrefix(expectedMessage) else {
                    throw FsearchError.bridge("Native smoke state failed: \(name)")
                }
                try await Task.sleep(for: .milliseconds(300))
                guard let view = NSApplication.shared.windows.first(where: { $0.isVisible })?.contentView,
                      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    throw FsearchError.bridge("Native window is unavailable")
                }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw FsearchError.bridge("Cannot capture native window")
                }
                try png.write(to: output.appendingPathComponent("\(name).png"))
                print("Native smoke \(name): passed")
            }
            NSApplication.shared.terminate(nil)
        } catch {
            fputs("Native smoke failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

struct SearchView: View {
    @ObservedObject var model: SearchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("样本验证模式 · 未启动真实 Engine")
                .font(.headline)
            Text("Fsearch 0.2.1 · 仅查询指定样本目录的一层条目")
                .foregroundStyle(.secondary)
            HStack {
                TextField("Fsearch 查询（例如 report、笔记、re:[）", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.submit() }
                    .accessibilityIdentifier("sample-query")
                Button("查询") { model.submit() }
                    .disabled(model.busy)
            }
            Text("此验证入口使用上游查询语法，默认词为模糊匹配，标点会按查询语法解释。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(model.message)
                .textSelection(.enabled)
                .accessibilityIdentifier("query-status")
            List(model.results) { result in
                VStack(alignment: .leading) {
                    Text(URL(fileURLWithPath: result.path).lastPathComponent)
                        .font(.headline)
                    Text(result.path).font(.caption).foregroundStyle(.secondary)
                    Text("索引大小：\(result.indexedSize) 字节 · 类型：\(result.kind) · 分数：\(result.score)")
                        .font(.caption)
                }
                .textSelection(.enabled)
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await model.runSmokeIfRequested() }
    }
}

@main
struct FsearchSampleApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate
    @StateObject private var model = SearchModel()

    var body: some Scene {
        WindowGroup("Fsearch 样本验证") {
            SearchView(model: model)
        }
    }
}
