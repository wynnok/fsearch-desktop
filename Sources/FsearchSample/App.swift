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
    @Published var configuration = SearchConfiguration() {
        didSet { if configuration != oldValue { invalidate() } }
    }
    let selectionState = SearchSelectionState()
    @Published private(set) var activity: SearchActivity = .idle
    @Published private(set) var focusRequest = 0
    @Published private var localMessage = "输入文件名后点击查询，或按 Command-Return。"
    private(set) var controller: SnapshotQueryController?
    private var observation: AnyCancellable?
    private var searchGeneration = 0
    var results: [SearchResult] { controller?.results ?? [] }
    var busy: Bool { controller?.isBusy ?? false }
    var nextCursor: SnapshotCursor? { controller?.nextCursor }
    private var snapshot: NameSnapshot? { controller?.snapshot }
    var query: String {
        get { configuration.query }
        set { configuration.query = newValue }
    }
    var nameMode: NameMatchMode {
        get { configuration.nameMode }
        set { configuration.nameMode = newValue }
    }
    private(set) var sortPreference: NameSort? {
        get { configuration.sortPreference }
        set { configuration.sortPreference = newValue }
    }
    var sort: NameSort {
        get { configuration.sort }
        set { configuration.sort = newValue }
    }
    var selection: String? {
        get { selectionState.selectedPath }
        set { selectionState.selectedPath = newValue }
    }
    var isInspectorVisible: Bool { selectionState.isInspectorVisible }
    var selectedResult: SearchResult? {
        guard let selection else { return nil }
        return results.first { $0.id == selection }
    }
    var message: String {
        guard let controller else { return localMessage }
        switch controller.phase {
        case .idle: return localMessage
        case .loading:
            return activity == .sorting
                ? "排序中…旧行仅供选择；数量和顺序尚未最终确定。"
                : "查询中…旧行仅供选择；数量和顺序尚未最终确定。"
        case .cancelled: return "查询已取消，可以重新查询。旧行不代表当前结果。"
        case .failed(let error): return "查询失败：\(error)。可修正后重试；旧行不代表当前结果。"
        case .partial:
            return "部分结果：已显示 \(results.count) 个 · 仅已载入排序，总数未知"
        case .complete:
            guard let total = controller.totalCount else { return "查询尚未完成" }
            if total == 0 { return "无匹配" }
            return "已显示 \(results.count) / \(total) 个匹配 · \(sortDescription)"
        }
    }
    var paginationMessage: String? {
        guard let controller else { return nil }
        switch controller.phase {
        case .partial:
            return "部分结果"
        case .complete:
            guard let total = controller.totalCount, total > 0 else { return nil }
            return nextCursor == nil ? "已载入全部 \(total) 个结果" : "还可继续载入同一快照"
        default:
            return nil
        }
    }
    var statusKind: SearchStatusKind {
        guard let controller else { return .prompt }
        switch controller.phase {
        case .idle: return .prompt
        case .loading: return activity == .sorting ? .sorting : .querying
        case .cancelled: return .cancelled
        case .failed: return .error
        case .partial: return .partial
        case .complete:
            return controller.totalCount == 0 ? .noMatch : .complete
        }
    }
    private var service: FsearchService?
    private var smokeDirectory: URL?
    private(set) var isEngineMode = false
    private var engineWorkspace: URL?
    private var engineSmokeStarted = false
    private(set) var isPermissionProbeMode = false
    private var permissionProbeArguments: PermissionProbeArguments?
    private var permissionProbeStarted = false
    private let pageSize = 2

    init() {
        let arguments = CommandLine.arguments
        let bundledSample = Bundle.main.resourceURL?.appendingPathComponent("sample", isDirectory: true)
        guard arguments.count >= 2 || bundledSample.map({ FileManager.default.fileExists(atPath: $0.path) }) == true else {
            localMessage = "请使用 bash scripts/dev.sh run 指定项目内受控样本。"
            return
        }
        do {
            if arguments.count == 5, arguments[1] == "--permission-probe" {
                permissionProbeArguments = PermissionProbeArguments(
                    phase: arguments[2],
                    config: URL(fileURLWithPath: arguments[3]),
                    output: URL(fileURLWithPath: arguments[4])
                )
                isPermissionProbeMode = true
                localMessage = "权限验证专用模式：等待真实 Engine 与受保护位置证据。"
                return
            }
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
        searchGeneration += 1
        activity = .idle
        controller?.invalidate()
        localMessage = "条件已改变，请重新查询。旧行不代表当前结果。"
    }

    func submit() { Task { await search() } }
    func refresh() { Task { await search(refresh: !isEngineMode) } }

    private func search(
        refresh: Bool = false,
        maximumResults: Int? = nil,
        activity requestedActivity: SearchActivity = .querying
    ) async {
        guard let controller else { return }
        searchGeneration += 1
        let generation = searchGeneration
        guard hasQueryInput else {
            activity = .idle
            controller.invalidate()
            localMessage = "请输入文件名后查询；空输入不会列出全部文件。"
            return
        }
        activity = requestedActivity
        await controller.query(
            NameSearchRequest(query: query, mode: nameMode),
            sort: sortPreference,
            maximumResults: maximumResults,
            pageSize: pageSize,
            refresh: refresh
        )
        if generation == searchGeneration {
            activity = .idle
        }
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
        case .relevance: "关联性"
        case .ascending, .descending: "名称"
        case .sizeAscending, .sizeDescending: "索引大小"
        case .modifiedAscending, .modifiedDescending: "修改时间"
        }
    }

    private var sortDescription: String {
        if sort == .relevance {
            return "关联性排序"
        }
        return "\(sortTitle)全局排序 \(sort.ascendingDirection ? "↑" : "↓")"
    }

    private var hasQueryInput: Bool {
        configuration.hasQueryInput
    }

    @discardableResult
    func sortBy(_ ascending: NameSort, descending: NameSort) -> Task<Void, Never> {
        sort = sort == ascending ? descending : ascending
        return Task { await search(activity: .sorting) }
    }

    func sortBy(_ column: SearchSortColumn) {
        switch column {
        case .name:
            sortBy(.ascending, descending: .descending)
        case .size:
            sortBy(.sizeAscending, descending: .sizeDescending)
        case .modified:
            sortBy(.modifiedAscending, descending: .modifiedDescending)
        }
    }

    func cancel() {
        searchGeneration += 1
        activity = .idle
        controller?.cancel()
    }

    func requestSearchFocus() { focusRequest += 1 }
    func toggleInspector() { selectionState.toggleInspector() }

    // Opt-in smoke uses the same actions and real window, with project-local files.
    func runSmokeIfRequested() async {
        if isPermissionProbeMode {
            guard !permissionProbeStarted else { return }
            permissionProbeStarted = true
            Task { await runPermissionProbe() }
            return
        }
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
            let cases: [(String, String, NameMatchMode, [String])] = [
                ("punctuation", "type:", .contains, ["type:doc.txt"]),
                ("spaces", "draft notes", .contains, ["draft notes.txt"]),
                ("quotes", "\"draft\"", .contains, ["quote \"draft\".txt"]),
                ("newline", "line\nbreak", .contains, ["line\nbreak.txt"]),
                ("unicode", "笔记😀", .contains, ["笔记😀.md"]),
                ("normalization", "café", .contains, ["cafe\u{301}.txt"]),
                ("case-insensitive", "DEMO", .contains, ["demo1.txt", "demo2.txt"]),
                ("fuzzy", "dmeo10.txt", .fuzzy, ["demo10.txt"]),
                ("prefix", "demo1", .prefix, ["demo1.txt", "demo10.txt"]),
                ("suffix", "0.txt", .suffix, ["demo10.txt", "demo20.txt"]),
                ("whole-name", "demo10.txt", .wholeName, ["demo10.txt"]),
                ("no-match", "absent-fixture-name", .contains, [])
            ]
            for (name, input, searchMode, expected) in cases {
                query = input
                nameMode = searchMode
                sortPreference = nil
                await search()
                try require(filenames == expected, "Native query state failed: \(name)")
                try require(snapshot?.isComplete == true, "Native query completeness failed")
                try await capture(name, under: output)
            }

            query = ""
            nameMode = .contains
            await search()
            try require(snapshot == nil && message.contains("空输入不会列出全部文件"),
                        "Empty input queried all files")
            try await capture("empty", under: output)

            query = "demo"
            await search(maximumResults: 0)
            try require(snapshot == nil && message.hasPrefix("查询失败"), "Service error was not shown")
            try await capture("failure", under: output)

            query = "demo"
            nameMode = .contains
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
            try await runWindowInteractionSmoke(under: output)

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

    private func runPermissionProbe() async {
        guard let request = permissionProbeArguments else {
            fputs("Permission probe arguments are unavailable\n", stderr)
            exit(1)
        }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        do {
            guard let phase = PermissionValidationPhase(rawValue: request.phase) else {
                throw FsearchError.bridge("Usage: --permission-probe <skip|grant|recheck|restart|revoke> <config.json> <output.json>")
            }
            let config = try loadPermissionProbeConfig(request.config)
            let indexDirectory = try validatePermissionProbeConfig(config)
            let iCloudPath = config.iCloudPlaceholder.map {
                URL(fileURLWithPath: $0, isDirectory: false)
            }
            let iCloudBefore = iCloudStat(iCloudPath)

            // The Rust gate rejects this before creating the index unless the
            // process is marked as a dedicated permission-validation run.
            let service = try FsearchService(realEngineIndexDirectory: indexDirectory)
            let readyStatus = try await waitForPermissionEngine(service)
            let settle = try await waitForPermissionContentSettle(service, readyStatus: readyStatus)
            let iCloudAfter = iCloudStat(iCloudPath)
            let iCloud = iCloudEvidence(path: iCloudPath, before: iCloudBefore, after: iCloudAfter)

            var locations: [PermissionProtectedLocationEvidence] = []
            for configured in config.protectedLocations {
                let directory = URL(fileURLWithPath: configured.path, isDirectory: true)
                    .standardizedFileURL
                let sentinel = directory.appendingPathComponent(configured.sentinelName)
                let exists = FileManager.default.fileExists(atPath: sentinel.path)
                let directReadable = exists && canRead(sentinel)
                let response = try await service.search(
                    SearchRequest(query: configured.sentinelName, collectAll: true)
                )
                let sentinelPath = sentinel.standardizedFileURL.path
                let searchMatched = response.results.contains {
                    URL(fileURLWithPath: $0.path).standardizedFileURL.path == sentinelPath
                }
                locations.append(PermissionProtectedLocationEvidence(
                    name: configured.name,
                    path: configured.path,
                    exists: exists,
                    directReadable: directReadable,
                    searchMatched: searchMatched,
                    searchComplete: response.isComplete
                ))
            }
            let evidence = PermissionProbeEvidence(
                phase: phase,
                timestamp: timestamp,
                status: settle.status,
                locations: locations,
                iCloud: iCloud,
                contentSettled: settle.settled,
                contentSettleReason: settle.reason
            )
            try writePermissionEvidence(evidence, to: request.output)
            print("Permission probe \(phase.rawValue) completed: \(request.output.path)")
            NSApplication.shared.terminate(nil)
        } catch {
            let failure = PermissionProbeFailure(
                phase: request.phase,
                timestamp: timestamp,
                error: error.localizedDescription,
                assessment: PermissionPhaseAssessment(
                    passed: false,
                    reasons: [error.localizedDescription]
                )
            )
            try? writePermissionEvidence(failure, to: request.output)
            fputs("Permission probe failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private func loadPermissionProbeConfig(_ url: URL) throws -> PermissionProbeConfig {
        guard url.path.hasPrefix("/"), FileManager.default.fileExists(atPath: url.path) else {
            throw FsearchError.bridge("Permission probe config must be an existing absolute file")
        }
        return try JSONDecoder().decode(PermissionProbeConfig.self, from: Data(contentsOf: url))
    }

    private func validatePermissionProbeConfig(_ config: PermissionProbeConfig) throws -> URL {
        guard config.indexDirectory.hasPrefix("/") else {
            throw FsearchError.bridge("Permission probe indexDirectory must be absolute")
        }
        guard !config.protectedLocations.isEmpty else {
            throw FsearchError.bridge("Permission probe requires at least one protected location")
        }
        for location in config.protectedLocations {
            let sentinel = URL(fileURLWithPath: location.sentinelName)
            guard location.path.hasPrefix("/"), !location.name.isEmpty,
                  !location.sentinelName.isEmpty, location.sentinelName != ".",
                  location.sentinelName != "..", sentinel.lastPathComponent == location.sentinelName else {
                throw FsearchError.bridge("Each protected location needs an absolute path and simple sentinelName")
            }
        }
        return URL(fileURLWithPath: config.indexDirectory, isDirectory: true)
    }

    private func waitForPermissionEngine(_ service: FsearchService) async throws -> ServiceStatus {
        let configured = TimeInterval(ProcessInfo.processInfo.environment["FSEARCH_PERMISSION_READY_TIMEOUT_SECONDS"] ?? "")
        let timeout = max(1, configured ?? 1800)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let status = try await service.status()
            if status.ready { return status }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw FsearchError.bridge("Permission Engine did not become ready before timeout")
    }

    private func waitForPermissionContentSettle(
        _ service: FsearchService,
        readyStatus: ServiceStatus
    ) async throws -> PermissionContentSettleResult {
        let configured = TimeInterval(
            ProcessInfo.processInfo.environment["FSEARCH_PERMISSION_CONTENT_SETTLE_SECONDS"] ?? ""
        )
        let timeout = max(0, configured ?? 300)
        let deadline = Date().addingTimeInterval(timeout)
        var latest = readyStatus
        while true {
            if let contentDocs = latest.contentDocs, contentDocs > 0,
               latest.contentPending == 0 {
                return PermissionContentSettleResult(status: latest, settled: true, reason: nil)
            }
            let docs = latest.contentDocs.map(String.init) ?? "unknown"
            let pending = latest.contentPending.map(String.init) ?? "unknown"
            if Date() >= deadline {
                return PermissionContentSettleResult(
                    status: latest,
                    settled: false,
                    reason: "content index did not establish activity and settle before timeout; contentDocs=\(docs), contentPending=\(pending)"
                )
            }
            try await Task.sleep(for: .milliseconds(500))
            latest = try await service.status()
        }
    }

    private func canRead(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        do {
            _ = try handle.read(upToCount: 1)
            return true
        } catch {
            return false
        }
    }

    private func iCloudStat(_ url: URL?) -> PermissionICloudStat? {
        guard let url else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return PermissionICloudStat(
                exists: false, size: nil, isUbiquitous: nil,
                downloadingStatus: nil, error: "placeholder path does not exist"
            )
        }
        do {
            let values = try url.resourceValues(forKeys: [
                .fileSizeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
            ])
            return PermissionICloudStat(
                exists: true,
                size: values.fileSize.map(Int64.init),
                isUbiquitous: values.isUbiquitousItem,
                downloadingStatus: values.ubiquitousItemDownloadingStatus?.rawValue,
                error: nil
            )
        } catch {
            return PermissionICloudStat(
                exists: true, size: nil, isUbiquitous: nil,
                downloadingStatus: nil, error: error.localizedDescription
            )
        }
    }

    private func iCloudEvidence(
        path: URL?,
        before: PermissionICloudStat?,
        after: PermissionICloudStat?
    ) -> PermissionICloudEvidence {
        guard let path else {
            return PermissionICloudEvidence(
                configured: false, path: nil, materialization: .unverified,
                before: nil, after: nil, reason: "iCloud placeholder was not configured"
            )
        }
        guard let before, let after, before.exists, after.exists,
              before.isUbiquitous == true, after.isUbiquitous == true else {
            return PermissionICloudEvidence(
                configured: true, path: path.path, materialization: .unverified,
                before: before, after: after, reason: "configured path is not a verifiable iCloud placeholder"
            )
        }
        if after.downloadingStatus == "downloaded" || after.downloadingStatus == "current" {
            return PermissionICloudEvidence(
                configured: true, path: path.path, materialization: .materialized,
                before: before, after: after, reason: "placeholder became materialized"
            )
        }
        if before.downloadingStatus == "notDownloaded", after.downloadingStatus == "notDownloaded" {
            return PermissionICloudEvidence(
                configured: true, path: path.path, materialization: .notMaterialized,
                before: before, after: after, reason: nil
            )
        }
        return PermissionICloudEvidence(
            configured: true, path: path.path, materialization: .unverified,
            before: before, after: after, reason: "ubiquitous downloading status was inconclusive"
        )
    }

    private func writePermissionEvidence<T: Encodable>(_ evidence: T, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(evidence).write(to: url, options: .atomic)
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
        query = "entry"
        let sortStart = Task { await search(activity: .sorting) }
        while activity != .sorting { await Task.yield() }
        try require(message.contains("排序中"), "Sorting state was not visible")
        await sortStart.value
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

    private func runWindowInteractionSmoke(under output: URL) async throws {
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible }),
              let root = window.contentView,
              let table = firstView(of: NSTableView.self, in: root),
              let editor = firstView(of: NSTextView.self, in: root), editor.isEditable else {
            throw FsearchError.bridge("Native interaction window is unavailable")
        }

        guard let searchMenu = NSApplication.shared.mainMenu?.items.first(where: { $0.title == "搜索" }),
              let submenu = searchMenu.submenu else {
            throw FsearchError.bridge("Native search menu is unavailable")
        }
        let menuTitles = Set(submenu.items.map(\.title))
        try require(
            menuTitles.isSuperset(of: ["聚焦搜索", "查询", "刷新", "取消"]) == true,
            "Native search menu is incomplete"
        )

        requestSearchFocus()
        for _ in 0..<50 where window.firstResponder !== editor {
            try await Task.sleep(for: .milliseconds(20))
        }
        try require(window.firstResponder === editor, "Search focus action did not focus the name editor")
        try require(editor.accessibilityLabel() == "文件名", "Name editor has no VoiceOver label")

        try require(table.accessibilityLabel() == "搜索结果", "Results table has no VoiceOver label")
        window.makeFirstResponder(table)
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        try await Task.sleep(for: .milliseconds(20))
        try require(selection == results.first?.id, "Mouse-equivalent selection did not update the model")
        guard let downArrow = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{F701}",
            charactersIgnoringModifiers: "\u{F701}",
            isARepeat: false,
            keyCode: 125
        ) else {
            throw FsearchError.bridge("Cannot synthesize keyboard navigation")
        }
        table.keyDown(with: downArrow)
        try await Task.sleep(for: .milliseconds(20))
        try require(table.selectedRow == 1 && selection == results[1].id,
                    "Keyboard selection did not move to the next result")

        let selectedID = selection
        let selectedSnapshotID = snapshot?.id
        try require(isInspectorVisible, "Inspector was not visible by default")
        try await capture("inspector-visible", under: output)
        toggleInspector()
        try await Task.sleep(for: .milliseconds(50))
        try require(
            !isInspectorVisible
                && snapshot?.id == selectedSnapshotID
                && !busy
                && selection == selectedID,
            "Inspector toggle changed search or selection state"
        )
        try await capture("inspector-hidden", under: output)
        toggleInspector()
        try await Task.sleep(for: .milliseconds(50))
        try require(selection == selectedID, "Inspector toggle lost selection")

        let sortTask = sortBy(.ascending, descending: .descending)
        await sortTask.value
        try require(selection == selectedID && snapshot?.sort == .descending,
                    "Sorting did not retain selection")

        let previousAppearance = NSApplication.shared.appearance
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        try await capture("dark-mode", under: output)
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
        try await capture("light-mode", under: output)
        NSApplication.shared.appearance = previousAppearance
    }

    private func firstView<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for child in view.subviews {
            if let match = firstView(of: type, in: child) { return match }
        }
        return nil
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

private struct PermissionProbeArguments {
    let phase: String
    let config: URL
    let output: URL
}

private struct PermissionProbeConfig: Decodable {
    let indexDirectory: String
    let protectedLocations: [PermissionProbeLocationConfig]
    let iCloudPlaceholder: String?
}

private struct PermissionProbeLocationConfig: Decodable {
    let name: String
    let path: String
    let sentinelName: String
}

private struct PermissionProbeFailure: Codable {
    let phase: String
    let timestamp: String
    let error: String
    let assessment: PermissionPhaseAssessment
}

private struct PermissionContentSettleResult {
    let status: ServiceStatus
    let settled: Bool
    let reason: String?
}

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@main
struct FsearchSampleApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate
    @StateObject private var model = SearchModel()

    var body: some Scene {
        WindowGroup("Fsearch") {
            SearchView(model: model, selectionState: model.selectionState)
        }
        .commands {
            SearchCommands(model: model, selectionState: model.selectionState)
        }
    }
}
