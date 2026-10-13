import AppKit
import Combine
#if DEBUG
@_spi(Testing) import FsearchService
#else
import FsearchService
#endif
import Foundation
import Darwin
import SwiftUI

@MainActor
final class SearchModel: ObservableObject {
    @Published var query = "report" { didSet { if query != oldValue { invalidate() } } }
    @Published var mode: SearchMode = .contains { didSet { if mode != oldValue { invalidate() } } }
    @Published var sort: NameSort = .ascending { didSet { if sort != oldValue { invalidate() } } }
    @Published var selection: String?
    @Published private var localMessage = "输入文件名后点击查询，或按 ⌘Return。"
    private(set) var controller: SnapshotQueryController?
    private var observation: AnyCancellable?
    var results: [SearchResult] { controller?.results ?? [] }
    var busy: Bool { controller?.isBusy ?? false }
    var nextCursor: SnapshotCursor? { controller?.nextCursor }
    private var snapshot: NameSnapshot? { controller?.snapshot }
    var message: String {
        guard let controller else { return localMessage }
        switch controller.phase {
        case .idle: return localMessage
        case .loading: return "查询 / 排序中…旧行仅供选择；数量和顺序尚未最终确定。"
        case .cancelled: return "查询已取消，可以重新查询。旧行不代表当前结果。"
        case .failed(let error): return "查询失败：\(error)。可修正后重试；旧行不代表当前结果。"
        case .partial: return "部分结果：已显示 \(results.count) 个 · 仅已载入排序，总数未知"
        case .complete:
            guard let total = controller.totalCount else { return "查询尚未完成" }
            return total == 0 ? "无匹配" : "已显示 \(results.count) / \(total) 个匹配 · \(sortTitle)全局排序 \(sort.ascendingDirection ? "↑" : "↓")"
        }
    }
    private var service: FsearchService?
    private var smokeDirectory: URL?
    private(set) var isEngineMode = false
    private var engineWorkspace: URL?
    private var engineSmokeStarted = false
    private let pageSize = 2

    init() {
        let arguments = CommandLine.arguments
        let bundledSample = Bundle.main.resourceURL?.appendingPathComponent("sample", isDirectory: true)
        guard arguments.count >= 2 || bundledSample.map({ FileManager.default.fileExists(atPath: $0.path) }) == true else {
            localMessage = "请使用 bash scripts/dev.sh run 指定项目内受控样本。"
            return
        }
        do {
            if arguments.count == 3, arguments[1] == "--engine-smoke" {
                let workspace = URL(fileURLWithPath: arguments[2]).resolvingSymlinksInPath()
                engineWorkspace = workspace
                isEngineMode = true
                query = "engine-proof"
                service = try FsearchService(confinedEngineDirectory: workspace.appendingPathComponent("fixtures"),
                                            indexDirectory: workspace.appendingPathComponent("index"))
                connectController()
                return
            }
            var directory = arguments.count >= 2 ? URL(fileURLWithPath: arguments[1]) : bundledSample!
            if arguments.count == 4, arguments[2] == "--smoke" {
                let output = URL(fileURLWithPath: arguments[3], isDirectory: true)
                directory = try NativeSmokeFixtures.create(under: output)
                smokeDirectory = directory
            }
            service = try FsearchService(sampleDirectory: directory)
            connectController()
        } catch {
            localMessage = "样本初始化失败：\(error.localizedDescription)"
        }
    }

    private func connectController() {
        guard let service else { return }
        let controller = SnapshotQueryController(service: service)
        self.controller = controller
        observation = controller.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }

    private func invalidate() {
        controller?.invalidate()
        localMessage = "条件已改变，请重新查询。旧行不代表当前结果。"
    }

    func submit() { Task { await search() } }
    func refresh() { Task { await search(refresh: !isEngineMode) } }

    private func search(refresh: Bool = false, maximumResults: Int? = nil) async {
        guard let controller else { return }
        await controller.query(SearchRequest(query: query, mode: mode), sort: sort,
                               maximumResults: maximumResults, pageSize: pageSize, refresh: refresh)
    }

    func loadMore() {
        do {
            try controller?.loadMore(pageSize: pageSize)
        } catch {
            localMessage = "载入失败：\(error.localizedDescription)"
        }
    }

    var sortTitle: String {
        switch sort {
        case .ascending, .descending: "名称"
        case .sizeAscending, .sizeDescending: "索引大小"
        case .modifiedAscending, .modifiedDescending: "修改时间"
        }
    }

    func sortBy(_ ascending: NameSort, descending: NameSort) {
        sort = sort == ascending ? descending : ascending
        submit()
    }

    func cancel() { controller?.cancel() }

    // Opt-in smoke uses the same actions and real window, with project-local files.
    func runSmokeIfRequested() async {
        if isEngineMode {
            guard !engineSmokeStarted else { return }
            engineSmokeStarted = true
            // Keep validation alive when closing the view cancels its .task.
            Task { await runEngineSmoke() }
            return
        }
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

            for requestedSort in [NameSort.sizeAscending, .sizeDescending, .modifiedAscending, .modifiedDescending] {
                sort = requestedSort
                await search()
                loadMore()
                loadMore()
                let expected: [String]
                switch requestedSort {
                case .sizeAscending: expected = ["demo30.txt", "demo1.txt", "demo2.txt", "demo3.txt", "demo10.txt", "demo20.txt"]
                case .sizeDescending: expected = ["demo20.txt", "demo10.txt", "demo3.txt", "demo2.txt", "demo1.txt", "demo30.txt"]
                case .modifiedAscending: expected = ["demo1.txt", "demo2.txt", "demo3.txt", "demo10.txt", "demo20.txt", "demo30.txt"]
                default: expected = ["demo30.txt", "demo20.txt", "demo10.txt", "demo3.txt", "demo2.txt", "demo1.txt"]
                }
                try require(filenames == expected, "Native attribute sort order failed")
                try require(snapshot?.isComplete == true && message.contains("全局排序"), "Native attribute sort did not complete")
                try await capture(requestedSort.rawValue, under: output)
            }
            try await runResponsivenessSmoke(under: output)

            #if DEBUG
            guard let service else { throw FsearchError.bridge("Smoke service is unavailable") }
            do {
                try await service.injectQueryPanic()
                throw FsearchError.bridge("Injected panic did not fail")
            } catch FsearchError.bridge(let message) {
                try require(message != "Injected panic did not fail", "Injected panic escaped validation")
                invalidate()
                self.localMessage = "查询失败：\(message)"
            }
            try await capture("panic-contained", under: output)
            await search()
            try require(snapshot?.isComplete == true, "Query after panic did not recover")
            try await capture("recovered", under: output)
            #endif
            try cleanupSmokeFixtures()
            NSApplication.shared.terminate(nil)
        } catch {
            try? cleanupSmokeFixtures()
            fputs("Native smoke failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private func runEngineSmoke() async {
        do {
            guard let service, let workspace = engineWorkspace else { throw FsearchError.bridge("Engine unavailable") }
            for _ in 0..<200 {
                if try await service.status().ready { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            query = "engine-proof"
            await search()
            try require(filenames == ["engine-proof.txt"], "Native Engine query failed")
            let output = workspace.appendingPathComponent("index")
            try await capture("engine-query", under: output)
            guard let window = NSApplication.shared.windows.first(where: { $0.isVisible }) else {
                throw FsearchError.bridge("Engine window unavailable")
            }
            _ = try await service.changes()
            window.close()
            let fixture = workspace.appendingPathComponent("fixtures/engine-window.txt")
            try Data("change while closed".utf8).write(to: fixture)
            var changedWhileClosed = false
            for _ in 0..<200 {
                let response = try await service.search(SearchRequest(query: "engine-window", collectAll: true))
                if response.results.count == 1 { changedWhileClosed = true; break }
                try await Task.sleep(for: .milliseconds(100))
            }
            try require(changedWhileClosed, "Index did not follow changes with window closed")
            let changes = try await service.changes()
            try require(!changes.isEmpty, "No Engine change notification while closed")
            window.makeKeyAndOrderFront(nil)
            query = "engine-window"
            await search()
            try require(filenames == ["engine-window.txt"], "Reopened window did not query live Engine")
            try await capture("engine-reopened", under: output)
            try await service.saveIndex()
            try await Task.sleep(for: .seconds(2))
            print("Native Engine query, close, background update, notification, reopen, save and application exit: passed")
            NSApplication.shared.terminate(nil)
        } catch {
            fputs("Native Engine smoke failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private func cleanupSmokeFixtures() throws {
        if let smokeDirectory {
            try FileManager.default.removeItem(at: smokeDirectory)
            self.smokeDirectory = nil
        }
    }

    private func runResponsivenessSmoke(under output: URL) async throws {
        guard let directory = smokeDirectory, let service, let controller,
              let window = NSApplication.shared.windows.first(where: { $0.isVisible }),
              let view = window.contentView else { throw FsearchError.bridge("Responsive smoke window unavailable") }
        let count = max(25_001, Int(ProcessInfo.processInfo.environment["FSEARCH_SNAPSHOT_COUNT"] ?? "") ?? 25_001)
        try await Task.detached {
            for number in 1...count {
                try Data("resource fixture".utf8).write(to: directory.appendingPathComponent("entry\(number).txt"))
            }
        }.value
        try await service.refreshSample()
        sort = .ascending
        query = "demo"
        await search()
        selection = results.first?.id
        let selected = selection
        query = "entry"
        let started = Date()
        let old = Task { await search() }
        while !busy { await Task.yield() }
        try require(selection == selected && !results.isEmpty && controller.totalCount == nil && nextCursor == nil,
                    "Busy state lost selection or exposed stale count/pagination")
        var pulses = 0
        var largestGap = 0.0
        var previous = Date()
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
                let now = Date()
                largestGap = max(largestGap, now.timeIntervalSince(previous))
                previous = now
                pulses += 1
                // Real native window event delivery remains possible during query/sort.
                window.displayIfNeeded()
            }
        }
        defer { heartbeat.cancel() }
        func textEditor(in view: NSView) -> NSTextView? {
            if let text = view as? NSTextView, text.isEditable { return text }
            return view.subviews.lazy.compactMap { textEditor(in: $0) }.first
        }
        guard let editor = textEditor(in: view) else { throw FsearchError.bridge("Native text editor unavailable") }
        window.makeFirstResponder(editor)
        editor.insertText("entry2", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        try await Task.sleep(for: .milliseconds(10))
        try require(query == "entry2" && editor.string == "entry2", "Native input did not update while query was running")
        let originalFrame = window.frame
        window.setFrame(originalFrame.insetBy(dx: -4, dy: -4), display: true)
        window.setFrame(originalFrame, display: true)
        selection = selected
        await search()
        await old.value
        let expected = (1...count).filter { String($0).hasPrefix("2") }.count
        try require(snapshot?.totalCount == expected && filenames.allSatisfy { $0.hasPrefix("entry2") },
                    "Native late query overwrote latest results or count")
        try require(pulses > 0 && largestGap < 0.5, "Main thread was unresponsive during large query/sort")
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let metrics = "NATIVE_RESPONSIVENESS count=\(count) total_s=\(Date().timeIntervalSince(started)) main_pulses=\(pulses) max_gap_s=\(largestGap) peak_rss_bytes=\(usage.ru_maxrss)\n"
        try Data(metrics.utf8).write(to: output.appendingPathComponent("responsiveness.txt"))
        print(metrics, terminator: "")
        try await capture("responsive-latest", under: output)
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
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

struct SearchView: View {
    @ObservedObject var model: SearchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.isEngineMode ? "真实 Engine · 受限验证模式" : "样本验证模式 · 未启动真实 Engine")
                .font(.headline)
            Text(model.isEngineMode ? "Fsearch 0.2.1 · 独立索引 · 默认名称与内容索引 · 就绪不代表全盘覆盖" : "Fsearch 0.2.1 · 仅查询指定样本目录及其子目录")
                .foregroundStyle(.secondary)
            HStack {
                Picker("输入方式", selection: $model.mode) {
                    Text("名称包含").tag(SearchMode.contains)
                    Text("高级查询").tag(SearchMode.advanced)
                }
                .frame(width: 230)
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
                Button(model.isEngineMode ? "刷新查询" : "刷新样本") { model.refresh() }.disabled(model.busy)
                if model.busy { Button("取消") { model.cancel() } }
            }
            Text(model.mode == .contains ? "普通输入按文件名包含匹配，标点、空格和换行保持原义；⌘Return 查询。" : "高级输入使用 Fsearch 查询语法；输入错误可修正后重试。")
                .font(.caption).foregroundStyle(.secondary)
            Text(model.message)
                .textSelection(.enabled)
                .accessibilityIdentifier("query-status")
            HStack {
                Button("名称\(model.sortTitle == "名称" ? (model.sort.ascendingDirection ? " ↑" : " ↓") : "")") {
                    model.sortBy(.ascending, descending: .descending)
                }
                Button("索引大小\(model.sortTitle == "索引大小" ? (model.sort.ascendingDirection ? " ↑" : " ↓") : "")") {
                    model.sortBy(.sizeAscending, descending: .sizeDescending)
                }
                Button("修改时间\(model.sortTitle == "修改时间" ? (model.sort.ascendingDirection ? " ↑" : " ↓") : "")") {
                    model.sortBy(.modifiedAscending, descending: .modifiedDescending)
                }
            }
            Text("索引大小是索引记录值，可能存在取整或变化滞后；不是实际大小、目录汇总或磁盘占用。")
                .font(.caption).foregroundStyle(.secondary)
            List(model.results, selection: $model.selection) { result in
                VStack(alignment: .leading) {
                    Text(URL(fileURLWithPath: result.path).lastPathComponent)
                        .font(.headline)
                    Text(result.path).font(.caption).foregroundStyle(.secondary)
                    Text("索引大小：\(result.indexedSize) 字节 · 类型：\(result.kind) · 分数：\(result.score)")
                        .font(.caption)
                    Text("修改时间：\(Date(timeIntervalSince1970: TimeInterval(result.modifiedAt)).formatted())")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .tag(result.id)
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
