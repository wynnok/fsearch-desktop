import AppKit
#if DEBUG
@_spi(Testing) import FsearchService
#else
import FsearchService
#endif
import Foundation
import SwiftUI

@MainActor
final class SearchModel: ObservableObject {
    @Published var query = "report" { didSet { if query != oldValue { invalidate() } } }
    @Published var mode: SearchMode = .contains { didSet { if mode != oldValue { invalidate() } } }
    @Published var sort: NameSort = .ascending { didSet { if sort != oldValue { invalidate() } } }
    @Published var results: [SearchResult] = []
    @Published var message = "输入文件名后点击查询，或按 ⌘Return。"
    @Published var busy = false
    @Published private(set) var nextCursor: SnapshotCursor?
    private var service: FsearchService?
    private var snapshot: NameSnapshot?
    private var generation = 0
    private var smokeDirectory: URL?
    private let pageSize = 2

    init() {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else {
            message = "请使用 bash scripts/dev.sh run 指定项目内受控样本。"
            return
        }
        do {
            var directory = URL(fileURLWithPath: arguments[1])
            if arguments.count == 4, arguments[2] == "--smoke" {
                let output = URL(fileURLWithPath: arguments[3], isDirectory: true)
                directory = try NativeSmokeFixtures.create(under: output)
                smokeDirectory = directory
            }
            service = try FsearchService(sampleDirectory: directory)
        } catch {
            message = "样本初始化失败：\(error.localizedDescription)"
        }
    }

    private func invalidate() {
        generation += 1
        snapshot = nil
        nextCursor = nil
        results = []
        busy = false
        message = "条件已改变，请重新查询。"
    }

    func submit() { Task { await search() } }
    func refresh() { Task { await search(refresh: true) } }

    private func search(refresh: Bool = false, maximumResults: Int? = nil) async {
        guard let service, !busy else { return }
        invalidate()
        let currentGeneration = generation
        let request = SearchRequest(query: query, mode: mode)
        let requestedSort = sort
        busy = true
        message = refresh ? "刷新样本中…" : "查询中…"
        defer { if generation == currentGeneration { busy = false } }
        do {
            if refresh { try await service.refreshSample() }
            let newSnapshot = try await service.snapshot(request, sort: requestedSort, maximumResults: maximumResults)
            guard generation == currentGeneration else { return }
            let page = try newSnapshot.page(pageSize: pageSize)
            snapshot = newSnapshot
            results = page.results
            nextCursor = page.nextCursor
            updateMessage()
        } catch {
            guard generation == currentGeneration else { return }
            message = "查询失败：\(error.localizedDescription)"
        }
    }

    func loadMore() {
        guard let snapshot, let nextCursor, !busy else { return }
        do {
            let page = try snapshot.page(after: nextCursor, pageSize: pageSize)
            guard page.snapshotID == self.snapshot?.id else { return }
            results.append(contentsOf: page.results)
            self.nextCursor = page.nextCursor
            updateMessage()
        } catch {
            message = "载入失败：\(error.localizedDescription)"
        }
    }

    private func updateMessage() {
        guard let snapshot else { return }
        if let total = snapshot.totalCount, snapshot.isComplete {
            message = total == 0 ? "无匹配" : "已显示 \(results.count) / \(total) 个匹配 · 名称全局排序"
        } else {
            message = "部分结果：已显示 \(results.count) 个 · 仅已载入排序，总数未知"
        }
    }

    // Opt-in smoke uses the same actions and real window, with project-local files.
    func runSmokeIfRequested() async {
        let arguments = CommandLine.arguments
        guard arguments.count == 4, arguments[2] == "--smoke" else { return }
        let output = URL(fileURLWithPath: arguments[3], isDirectory: true)
        defer { try? cleanupSmokeFixtures() }
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let cases: [(String, String, SearchMode, [String])] = [
                ("empty", "", .contains, []),
                ("blank", " \n", .contains, []),
                ("punctuation", "type:", .contains, ["type:doc.txt"]),
                ("spaces", "draft notes", .contains, ["draft notes.txt"]),
                ("quotes", "\"draft\"", .contains, ["quote \"draft\".txt"]),
                ("newline", "line\nbreak", .contains, ["line\nbreak.txt"]),
                ("unicode", "笔记😀", .contains, ["笔记😀.md"]),
                ("normalization", "café", .contains, ["cafe\u{301}.txt"]),
                ("no-match", "absent-fixture-name", .contains, [])
            ]
            for (name, input, searchMode, expected) in cases {
                query = input
                mode = searchMode
                await search()
                try require(filenames == expected, "Native query state failed: \(name)")
                try require(snapshot?.isComplete == true, "Native query completeness failed")
                try await capture(name, under: output)
            }
            query = "re:["
            mode = .advanced
            await search()
            try require(snapshot == nil && message.hasPrefix("查询失败"), "Advanced error was not shown")
            try await capture("failure", under: output)

            query = "demo"
            mode = .contains
            sort = .ascending
            await search()
            try require(snapshot?.totalCount == 5, "Native total count failed")
            try require(filenames == ["demo1.txt", "demo2.txt"], "Native first page order failed")
            try await capture("page-one", under: output)
            loadMore()
            try require(filenames == ["demo1.txt", "demo2.txt", "demo3.txt", "demo10.txt"], "Native second page failed")
            try await capture("page-two", under: output)
            loadMore()
            try require(filenames == ["demo1.txt", "demo2.txt", "demo3.txt", "demo10.txt", "demo20.txt"] && nextCursor == nil,
                        "Native final page failed")
            try await capture("page-final", under: output)

            sort = .descending
            await search()
            loadMore()
            loadMore()
            try require(filenames == ["demo20.txt", "demo10.txt", "demo3.txt", "demo2.txt", "demo1.txt"], "Native descending order failed")
            try await capture("descending", under: output)
            await search(maximumResults: 2)
            try require(snapshot?.isComplete == false && snapshot?.totalCount == nil && message.hasPrefix("部分结果"),
                        "Native partial results were shown as complete")
            try await capture("partial", under: output)
            let previousID = snapshot?.id
            if let smokeDirectory {
                try Data("refresh fixture".utf8).write(to: smokeDirectory.appendingPathComponent("demo30.txt"))
            }
            await search(refresh: true)
            try require(snapshot?.id != previousID && snapshot?.totalCount == 6 && filenames == ["demo30.txt", "demo20.txt"],
                        "Native refreshed snapshot failed")
            try await capture("refreshed", under: output)

            #if DEBUG
            guard let service else { throw FsearchError.bridge("Smoke service is unavailable") }
            do {
                try await service.injectQueryPanic()
                throw FsearchError.bridge("Injected panic did not fail")
            } catch FsearchError.bridge(let message) {
                try require(message != "Injected panic did not fail", "Injected panic escaped validation")
                invalidate()
                self.message = "查询失败：\(message)"
            }
            try await capture("panic-contained", under: output)
            await search()
            try require(snapshot?.totalCount == 6, "Query after panic did not recover")
            try await capture("recovered", under: output)
            #endif
            try cleanupSmokeFixtures()
            NSApplication.shared.terminate(nil)
        } catch {
            try? cleanupSmokeFixtures()
            fputs("Native smoke failed\n", stderr)
            exit(1)
        }
    }

    private func cleanupSmokeFixtures() throws {
        if let smokeDirectory {
            try FileManager.default.removeItem(at: smokeDirectory)
            self.smokeDirectory = nil
        }
    }

    private var filenames: [String] { results.map { URL(fileURLWithPath: $0.path).lastPathComponent } }

    private func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw FsearchError.bridge(message) }
    }

    private func capture(_ name: String, under output: URL) async throws {
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
            Text("Fsearch 0.2.1 · 仅查询指定样本目录及其子目录")
                .foregroundStyle(.secondary)
            HStack {
                Picker("输入方式", selection: $model.mode) {
                    Text("名称包含").tag(SearchMode.contains)
                    Text("高级查询").tag(SearchMode.advanced)
                }
                .frame(width: 230)
                Picker("名称顺序", selection: $model.sort) {
                    Text("升序").tag(NameSort.ascending)
                    Text("降序").tag(NameSort.descending)
                }
                .frame(width: 190)
            }
            HStack {
                TextEditor(text: $model.query)
                    .font(.body)
                    .frame(height: 52)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.3)))
                    .accessibilityLabel("文件名")
                    .accessibilityIdentifier("sample-query")
                Button("查询") { model.submit() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.busy)
                Button("刷新样本") { model.refresh() }.disabled(model.busy)
            }
            Text(model.mode == .contains ? "普通输入按文件名包含匹配，标点、空格和换行保持原义；⌘Return 查询。" : "高级输入使用 Fsearch 查询语法；输入错误可修正后重试。")
                .font(.caption).foregroundStyle(.secondary)
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
            Button("继续载入同一快照") { model.loadMore() }
                .disabled(model.nextCursor == nil || model.busy)
        }
        .padding(20)
        .frame(minWidth: 860, minHeight: 600)
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
