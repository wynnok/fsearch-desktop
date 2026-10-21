import AppKit
import Combine
#if DEBUG
@_spi(Testing) import FsearchService
#else
import FsearchService
#endif
import Foundation
import Darwin
import Quartz
import SwiftUI

@MainActor
final class SearchModel: ObservableObject {
    let updates = ManualUpdateState()
    @Published var showsUpdates = false
    @Published var showsContentSearch = false
    lazy var contentSearch = ContentSearchState(service: service)
    @Published private(set) var engineVersion = "尚未读取"
    @Published private(set) var selectionMessage: String?
    @Published private(set) var applicationMessage: String?
    private(set) var observedChangeCount = 0
    lazy var permissionStatus = PermissionStatusModel(
        onboardingDismissed: preferencesStore?.onboardingDismissed ?? false,
        onDismiss: { [weak self] in self?.persistPreferences(onboardingDismissed: true) }
    )
    private var preferencesStore: LocalPreferences?
    private var restoringPreferences = false
    private var preferenceObservation: AnyCancellable?
    private var pollingTask: Task<Void, Never>?
    private var isPollingService = false
    private var changesPending = false
    private var pendingRenames: [String: String] = [:]
    private var validationMessage: String?
    private var lastServiceError: Error?
    @Published var configuration = SearchConfiguration() {
        didSet {
            guard configuration != oldValue, !restoringPreferences else { return }
            invalidate()
            persistPreferences()
            if (configuration.scope != oldValue.scope || configuration.showsHidden != oldValue.showsHidden
                || configuration.filters != oldValue.filters)
                && (configuration.hasQueryInput || configuration.filters.isEffective) { submit() }
        }
    }
    let selectionState = SearchSelectionState()
    @Published private(set) var activity: SearchActivity = .idle
    @Published private(set) var focusRequest = 0
    @Published private var localMessage = "输入文件名后点击查询文件名，或按 Return。"
    private(set) var controller: SnapshotQueryController?
    private var observation: AnyCancellable?
    private var searchGeneration = 0
    var results: [SearchResult] { controller?.results ?? [] }
    var busy: Bool { controller?.isBusy ?? false }
    var nextCursor: SnapshotCursor? { controller?.nextCursor }
    private var snapshot: NameSnapshot? { controller?.snapshot }
    var inspectorRefreshID: UUID? { controller?.snapshot?.id }
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
        if let validationMessage { return validationMessage }
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
        if validationMessage != nil { return .error }
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
    var canSearchContent: Bool { isEngineMode && service != nil }
    private var smokeDirectory: URL?
    private(set) var isEngineMode = false
    private var engineWorkspace: URL?
    private var engineSmokeStarted = false
    private var contentWorkspace = false
    private var contentSmokeRequested = false
    private var desktopSmokeWorkspace: URL?
    private(set) var isPermissionProbeMode = false
    private var permissionProbeArguments: PermissionProbeArguments?
    private var permissionProbeStarted = false
    private let pageSize: Int

    init(arguments: [String] = CommandLine.arguments, preferences: LocalPreferences? = nil) {
        pageSize = arguments.contains("--smoke") || arguments.contains("--engine-smoke") ? 2 : 200
        let isValidation = arguments.contains("--smoke") || arguments.contains("--engine-smoke")
            || arguments.contains("--permission-probe") || arguments.contains("--content-smoke")
            || arguments.contains("--content-workspace")
            || arguments.contains("--desktop-smoke")
        preferencesStore = isValidation ? nil : (preferences ?? LocalPreferences.applicationStore)
        restoringPreferences = true
        preferencesStore?.restore(configuration: &configuration, selection: selectionState)
        restoringPreferences = false
        preferenceObservation = selectionState.$isInspectorVisible.dropFirst().sink { [weak self] visible in
            self?.persistPreferences(inspectorVisible: visible)
        }
        do {
            if arguments.count == 3, ["--content-smoke", "--content-workspace"].contains(arguments[1]) {
                let workspace = URL(fileURLWithPath: arguments[2]).resolvingSymlinksInPath()
                engineWorkspace = workspace
                isEngineMode = true
                contentWorkspace = true
                contentSmokeRequested = arguments[1] == "--content-smoke"
                service = try FsearchService(confinedEngineDirectory: workspace.appendingPathComponent("fixtures"),
                                            indexDirectory: workspace.appendingPathComponent("index"))
                connectController()
                return
            }
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
            if arguments.count == 3, arguments[1] == "--desktop-smoke" {
                desktopSmokeWorkspace = URL(fileURLWithPath: arguments[2]).resolvingSymlinksInPath()
            }
            let startup = ApplicationStartup(
                arguments: desktopSmokeWorkspace == nil ? arguments : Array(arguments.prefix(1)),
                applicationSupport: desktopSmokeWorkspace ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
                home: FileManager.default.homeDirectoryForCurrentUser
            )
            if case .desktop(let index, let home) = startup {
                isEngineMode = true
                configuration.query = ""
                service = try FsearchService(desktopIndexDirectory: index, homeDirectory: home)
                connectController()
                return
            }
            guard case .sample(var directory) = startup else { return }
            if arguments.count == 4, arguments[2] == "--smoke" {
                let output = URL(fileURLWithPath: arguments[3], isDirectory: true)
                directory = try NativeSmokeFixtures.create(under: output)
                smokeDirectory = directory
            }
            service = try FsearchService(sampleDirectory: directory)
            connectController()
        } catch {
            localMessage = "搜索服务初始化失败：\(error.localizedDescription)"
            lastServiceError = error
            permissionStatus.recordFailure(error)
        }
    }

    private func connectController() {
        guard let service else { return }
        let controller = SnapshotQueryController(service: service)
        self.controller = controller
        observation = controller.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollService()
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
        }
    }

    private func persistPreferences(onboardingDismissed: Bool? = nil, inspectorVisible: Bool? = nil) {
        do {
            try preferencesStore?.save(configuration: configuration,
                                       inspectorVisible: inspectorVisible ?? selectionState.isInspectorVisible,
                                       onboardingDismissed: onboardingDismissed)
        } catch {
            applicationMessage = "偏好保存失败；当前搜索仍可使用。"
        }
    }

    deinit { pollingTask?.cancel() }

    private func pollService() async {
        guard !isPollingService, let service else { return }
        isPollingService = true
        defer { isPollingService = false }
        do {
            let status = try await service.status()
            let changes = try await service.changes()
            if permissionStatus.status != status || permissionStatus.failureMessage != nil {
                permissionStatus.apply(status)
            }
            if engineVersion != status.upstreamVersion { engineVersion = status.upstreamVersion }
            lastServiceError = nil
            if !changes.isEmpty {
                observedChangeCount += changes.count
                changesPending = true
            }
            guard changesPending, let controller, !controller.isBusy,
                  controller.phase == .complete || controller.phase == .partial else { return }
            changesPending = false
            let selected = selection
            let selectedPaths = selectionState.selectedPaths
            let generation = searchGeneration
            await controller.refreshCurrentQuery()
            guard generation == searchGeneration, selection == selected,
                  selectionState.selectedPaths == selectedPaths else { return }
            var restoredPaths = selectedPaths
            var restoredPrimary = selected
            for (oldPath, newPath) in pendingRenames {
                guard selectedPaths.contains(oldPath) else { pendingRenames[oldPath] = nil; continue }
                let newVisible = (try? controller.ensureVisible(path: newPath)) == true
                if !newVisible && (controller.phase == .partial || (try? controller.ensureVisible(path: oldPath)) == true) { continue }
                restoredPaths.remove(oldPath)
                restoredPaths.insert(newPath)
                if selected == oldPath { restoredPrimary = newPath }
                pendingRenames[oldPath] = nil
            }
            restoreSelection(restoredPrimary, paths: restoredPaths)
        } catch {
            lastServiceError = error
            permissionStatus.recordFailure(error)
        }
    }

    func recheckPermissions() {
        Task {
            guard let service else { return }
            await permissionStatus.recheck { try await service.status() }
        }
    }

    func exportDiagnostics() {
        let error: Error?
        if case .failed(let message) = controller?.phase { error = FsearchError.query(message) }
        else { error = lastServiceError }
        if let message = DiagnosticExporter.present(status: permissionStatus.status, error: error) {
            applicationMessage = message
        }
    }

    private func restoreSelection(_ path: String?, paths: Set<String>) {
        guard !paths.isEmpty, let controller,
              controller.phase == .complete || controller.phase == .partial else { return }
        let surviving = Set(paths.filter { (try? controller.ensureVisible(path: $0)) == true })
        if surviving != paths && controller.phase == .partial {
            selectionMessage = "当前部分结果尚未包含所有所选文件；未确认它们是否仍符合筛选。"
            return
        }
        selectionState.select(paths: surviving, primary: path.flatMap { surviving.contains($0) ? $0 : nil })
        selectionMessage = surviving == paths ? nil : "所选文件已删除、移动或不再符合当前筛选。"
    }

    private func invalidate() {
        searchGeneration += 1
        activity = .idle
        validationMessage = nil
        controller?.invalidate()
        localMessage = "条件已改变，请重新查询。旧行不代表当前结果。"
    }

    func submit() { Task { await search() } }
    func refresh() { Task { await search(refresh: !isEngineMode) } }

    func fileDidChange(_ oldPath: String, _ newPath: String?) {
        if selectionState.selectedPaths.contains(oldPath) {
            if let newPath { pendingRenames[oldPath] = newPath }
            else {
                var paths = selectionState.selectedPaths
                paths.remove(oldPath)
                selectionState.select(paths: paths, primary: selection == oldPath ? nil : selection)
            }
        }
        if !isEngineMode, let service {
            Task {
                do {
                    try await service.refreshSample()
                    changesPending = true
                    await pollService()
                } catch { applicationMessage = "文件已改变，但结果刷新失败，请重新查询。" }
            }
        }
    }

    func search(
        refresh: Bool = false,
        maximumResults: Int? = nil,
        activity requestedActivity: SearchActivity = .querying
    ) async {
        guard let controller else { return }
        searchGeneration += 1
        let generation = searchGeneration
        guard configuration.hasEffectiveQuery else {
            activity = .idle
            controller.invalidate()
            localMessage = "请输入文件名后查询；空输入不会列出全部文件。"
            return
        }
        let request: NameSearchRequest
        do { request = try configuration.request() }
        catch {
            controller.invalidate()
            validationMessage = "筛选无效：\(error.localizedDescription)。请修正后重试。"
            return
        }
        validationMessage = nil
        let selected = selection
        let selectedPaths = selectionState.selectedPaths
        activity = requestedActivity
        await controller.query(
            request,
            sort: sortPreference,
            maximumResults: maximumResults,
            pageSize: pageSize,
            refresh: refresh
        )
        if generation == searchGeneration {
            activity = .idle
            if selection == selected && selectionState.selectedPaths == selectedPaths {
                restoreSelection(selected, paths: selectedPaths)
            }
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
        if let workspace = desktopSmokeWorkspace {
            guard !engineSmokeStarted else { return }
            engineSmokeStarted = true
            Task { await runDesktopSmoke(workspace: workspace) }
            return
        }
        if contentWorkspace {
            if contentSmokeRequested && !engineSmokeStarted {
                engineSmokeStarted = true
                Task { await runContentSmoke() }
            }
            return
        }
        if isPermissionProbeMode {
            guard !permissionProbeStarted else { return }
            permissionProbeStarted = true
            Task { await runPermissionProbe() }
            return
        }
        if isEngineMode {
            guard engineWorkspace != nil else { return }
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
            if let window = NSApplication.shared.windows.first(where: { $0.isVisible }) {
                let checks = try await NativeFileActionsSmoke.run(window: window, selectionState: selectionState)
                try require(checks.values.allSatisfy { $0 }, "Native file action checks failed: \(checks)")
                try JSONEncoder().encode(checks).write(to: output.appendingPathComponent("file-actions.json"))
                print("Native file actions and Quick Look: passed (Finder visible selection remains unverified)")
            }

            sort = .descending
            await search()
            loadMore()
            loadMore()
            try require(filenames == ["demo20.txt", "demo10.txt", "demo3.txt", "demo2.txt", "demo1.txt"], "Native descending order failed: \(filenames)")
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
            guard let smokeDirectory else { throw FsearchError.bridge("Acceptance fixture unavailable") }
            let searchChecks = try await NativeAcceptanceSmoke.search(model: self, directory: smokeDirectory)
            try require(searchChecks.values.allSatisfy { $0 }, "Search acceptance failed: \(searchChecks)")
            try JSONEncoder().encode(searchChecks).write(to: output.appendingPathComponent("search-journey.json"))
            try await capture("search-journey", under: output)
            guard let acceptanceWindow = NSApplication.shared.windows.first(where: { $0.isVisible }) else {
                throw FsearchError.bridge("Acceptance window unavailable")
            }
            let fileChecks = try await NativeAcceptanceSmoke.files(model: self, window: acceptanceWindow, directory: smokeDirectory)
            try require(fileChecks.values.allSatisfy { $0 }, "File acceptance failed: \(fileChecks)")
            try JSONEncoder().encode(fileChecks).write(to: output.appendingPathComponent("file-journey.json"))
            try await capture("file-journey", under: output)
            showsUpdates = true
            for _ in 0..<100 where acceptanceWindow.attachedSheet == nil {
                try await Task.sleep(for: .milliseconds(20))
            }
            guard let updateSheet = acceptanceWindow.attachedSheet else {
                throw FsearchError.bridge("Manual update sheet did not open")
            }
            try await capture("manual-update-entry", under: output, window: updateSheet)
            showsUpdates = false
            for _ in 0..<100 where acceptanceWindow.attachedSheet != nil {
                try await Task.sleep(for: .milliseconds(20))
            }
            try require(acceptanceWindow.attachedSheet == nil, "Manual update sheet did not dismiss")
            print("Native search and file acceptance journeys: passed")

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

    private func runDesktopSmoke(workspace: URL) async {
        do {
            guard canSearchContent, let service else { throw FsearchError.bridge("Desktop content search disabled") }
            let fixture = workspace.appendingPathComponent("fixtures")
            let path = fixture.appendingPathComponent("desktop-proof.txt").path
            configuration.scope = .folder(fixture.path)
            query = "desktop-proof"
            for _ in 0..<600 {
                await search()
                if results.contains(where: { $0.path == path }) { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            try require(results.map(\.path) == [path],
                        "Desktop name search did not find fixture: query=\(query), count=\(results.count), phase=\(String(describing: controller?.phase))")
            query = "query-row-proof"
            await search()
            try require(results.count == 157 && nextCursor == nil && message.contains("157 / 157"),
                        "Desktop result list still truncates the first page to two rows")
            let unchangedSnapshot = inspectorRefreshID
            try await Task.sleep(for: .seconds(1))
            try require(!busy && inspectorRefreshID == unchangedSnapshot,
                        "Unrelated background changes restarted or replaced the completed query")
            try await capture("desktop-results-157", under: workspace)
            contentSearch.configuration.scope = .folder(fixture.path)
            contentSearch.pattern = "desktop-content-proof"
            await contentSearch.search()
            try require(contentSearch.files.map(\.path) == [path], "Desktop text content search did not find fixture")
            // Change delivery must work on the unconfined desktop entry, too.
            for _ in 0..<600 {
                if try await service.status().ready { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            try require(try await service.status().ready, "Desktop disk index did not become ready")
            _ = try await service.changes()
            let changesBeforeAddition = observedChangeCount
            let added = fixture.appendingPathComponent("desktop-added.txt")
            try Data("desktop-content-added".utf8).write(to: added)
            var delivered = false
            for _ in 0..<200 {
                let changes = try await service.changes()
                if observedChangeCount > changesBeforeAddition || changes.contains(where: { $0.path.hasPrefix(fixture.path) }) {
                    delivered = true
                    break
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            try require(delivered, "Desktop change notifications missing")
            query = "desktop-added"
            for _ in 0..<200 {
                await search()
                if results.contains(where: { $0.path == added.path }) { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            try require(results.map(\.path) == [added.path], "Desktop live name search did not update")
            await permissionStatus.recheck { try await service.status() }
            try require(permissionStatus.status?.mode == "engine", "Desktop permission status is still sample mode")
            try JSONEncoder().encode(permissionStatus.status).write(to: workspace.appendingPathComponent("desktop-status.json"))
            try await capture("desktop-search", under: workspace)
            print("Desktop startup, name search, text content search, permission probe and live changes: passed")
            NSApplication.shared.terminate(nil)
        } catch {
            fputs("Desktop smoke failed: \(error.localizedDescription)\n", stderr)
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

    private func runContentSmoke() async {
        do {
            guard let service, let workspace = engineWorkspace else { throw FsearchError.bridge("Content Engine unavailable") }
            for _ in 0..<200 {
                if try await service.status().ready { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            contentSearch.pattern = "银河😀"
            for _ in 0..<200 {
                await contentSearch.search()
                if contentSearch.files.count == 1 { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard let response = contentSearch.response, let file = contentSearch.files.first,
                  file.lines.map(\.text) == ["银河😀 first", "银河😀 second"],
                  response.displayedOccurrences == 2 else { throw FsearchError.bridge("Native content grouping failed") }
            let highlighted = file.lines[0].nativeRanges
                .map { String(file.lines[0].text[$0]) }
                .joined()
            try require(highlighted == "银河😀", "Native Unicode highlight range failed")

            let options = workspace.appendingPathComponent("fixtures/options")
            contentSearch.mode = .literal
            contentSearch.configuration.scope = .folder(options.path)
            contentSearch.pattern = "a.b"
            await contentSearch.search()
            try require(contentSearch.files.map(\.path) == [
                options.appendingPathComponent("literal.txt").path
            ], "Native literal content option failed")

            contentSearch.mode = .regex
            contentSearch.pattern = "a[.]b|axb"
            await contentSearch.search()
            try require(Set(contentSearch.files.map(\.path)) == Set([
                options.appendingPathComponent("literal.txt").path,
                options.appendingPathComponent("regex.txt").path
            ]), "Native regex content option failed")

            contentSearch.mode = .literal
            contentSearch.caseMode = .sensitive
            contentSearch.pattern = "ALPHA"
            await contentSearch.search()
            let casePath = options.appendingPathComponent("case.txt").path
            try require(!contentSearch.files.contains { $0.path == casePath },
                        "Native sensitive case failed")

            let pagination = workspace.appendingPathComponent("fixtures/pagination")
            contentSearch.caseMode = .smart
            contentSearch.configuration.scope = .folder(pagination.path)
            contentSearch.resultLimit = 1
            contentSearch.pattern = "cursor-match"
            await contentSearch.search()
            guard let firstPageCount = contentSearch.response?.files.count,
                  firstPageCount == 1, contentSearch.canLoadMore else {
                throw FsearchError.bridge("Native content cursor did not produce a page")
            }
            await contentSearch.loadMore()
            let paginationPaths = contentSearch.files.map(\.path)
            try require(paginationPaths.count == 2 && Set(paginationPaths).count == 2,
                        "Native content cursor repeated or skipped a page")
            contentSearch.resultLimit = 100

            contentSearch.mode = .regex
            contentSearch.pattern = "["
            await contentSearch.search()
            try require(contentSearch.pattern == "[" && contentSearch.message.contains("失败"),
                        "Invalid native regex did not preserve its input")
            contentSearch.mode = .literal
            contentSearch.configuration.scope = .allIndexed
            contentSearch.pattern = "Alpha"
            await contentSearch.search()
            try require(!contentSearch.files.isEmpty, "Invalid native regex did not recover")

            guard let window = NSApplication.shared.windows.first(where: { $0.isVisible }) else {
                throw FsearchError.bridge("Content window unavailable")
            }
            showsContentSearch = true
            for _ in 0..<100 where window.attachedSheet == nil { try await Task.sleep(for: .milliseconds(20)) }
            guard let sheet = window.attachedSheet else { throw FsearchError.bridge("Content sheet unavailable") }
            let output = workspace.appendingPathComponent("index/content-smoke")
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try await capture("content-results", under: output, window: sheet)
            let actions = FileActionState()
            actions.open(path: file.path)
            for _ in 0..<100 where actions.openedURL == nil && actions.message == nil { try await Task.sleep(for: .milliseconds(30)) }
            try require(actions.openedURL?.path == file.path, "Content file did not open")
            actions.togglePreview(path: file.path)
            try require(actions.previewURL?.path == file.path && QLPreviewPanel.shared()?.isVisible == true, "Content file preview failed")
            actions.updatePreview(path: nil)
            let diagnostic = output.appendingPathComponent("diagnostics.json")
            try DiagnosticReport(status: try await service.status()).write(to: diagnostic)
            try require(!String(contentsOf: diagnostic, encoding: .utf8).contains("银河"), "Content leaked into diagnostics")
            contentSearch.pattern = "absent-content-pattern"
            await contentSearch.search()
            try require(contentSearch.files.isEmpty, "Native no-match failed")
            showsContentSearch = false
            for _ in 0..<100 where window.attachedSheet != nil { try await Task.sleep(for: .milliseconds(20)) }
            try require(window.attachedSheet == nil, "Content sheet did not close")
            print("Native content grouping/options/cursor/highlight, CRLF, open, Quick Look, no-match and diagnostic exclusion: passed")
            NSApplication.shared.terminate(nil)
        } catch {
            fputs("Native content smoke failed: \(error.localizedDescription)\n", stderr)
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
            query = "engine-"
            await search()
            selection = results.first?.path
            let retainedQuery = query
            let retainedSelection = selection
            let output = workspace.appendingPathComponent("index")
            try await capture("engine-query", under: output)
            guard let window = NSApplication.shared.windows.first(where: { $0.isVisible }) else {
                throw FsearchError.bridge("Engine window unavailable")
            }
            let changeCount = observedChangeCount
            window.close()
            try require(!window.isVisible, "Close did not hide the main window")
            let fixture = workspace.appendingPathComponent("fixtures/engine-window.txt")
            try Data("change while closed".utf8).write(to: fixture)
            var changedWhileClosed = false
            for _ in 0..<200 {
                if snapshot?.totalCount == 3 { changedWhileClosed = true; break }
                try await Task.sleep(for: .milliseconds(100))
            }
            try require(changedWhileClosed, "Index did not follow changes with window closed")
            try require(observedChangeCount > changeCount, "No Engine change notification while closed")
            try require(MainWindowLifecycle.shared.reopen(), "Menu reopen failed")
            try require(query == retainedQuery && selection == retainedSelection,
                        "Reopened window lost running input or selection")
            loadMore()
            try require(filenames.contains("engine-window.txt"), "Reopened window did not retain refreshed results")
            try await capture("engine-reopened", under: output)
            selection = fixture.path
            try FileManager.default.removeItem(at: fixture)
            for _ in 0..<200 {
                if selection == nil && !filenames.contains("engine-window.txt") { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            try require(selection == nil && selectionMessage != nil,
                        "Deleted selection did not explain its disappearance")
            try await capture("engine-deleted-selection", under: output)
            let original = workspace.appendingPathComponent("fixtures/engine-proof.txt")
            let renamed = workspace.appendingPathComponent("fixtures/engine-renamed.txt")
            selection = original.path
            let fileActions = FileActionState()
            fileActions.onFileMutation = fileDidChange
            await fileActions.rename(path: original.path, to: renamed.lastPathComponent)
            for _ in 0..<200 where selection != renamed.path { try await Task.sleep(for: .milliseconds(50)) }
            try require(selection == renamed.path && filenames.contains("engine-renamed.txt"),
                        "Native Engine rename lost selection before notifications were applied")
            await fileActions.rename(path: renamed.path, to: original.lastPathComponent)
            for _ in 0..<200 where selection != original.path { try await Task.sleep(for: .milliseconds(50)) }
            try require(selection == original.path && filenames.contains("engine-proof.txt"), "Native Engine rename restore failed")
            print("Native Engine file mutation selection: passed")
            try await service.saveIndex()
            try await Task.sleep(for: .seconds(2))
            print("Native Engine query, close, background update, notification, reopen and save: passed")
            guard let quit = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                              timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil,
                                              characters: "q", charactersIgnoringModifiers: "q",
                                              isARepeat: false, keyCode: 12),
                  let menu = NSApplication.shared.mainMenu else {
                throw FsearchError.bridge("Command-Q event or application menu unavailable")
            }
            print("Native Engine Command-Q dispatch")
            try require(menu.performKeyEquivalent(with: quit), "Application menu did not handle Command-Q")
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
        try require(menuTitles.contains("导出诊断报告…"), "Diagnostic export action is unavailable")

        let originalFrame = window.frame
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        for (name, size) in [("layout-minimum", NSSize(width: 960, height: 680)),
                             ("layout-default", NSSize(width: 1100, height: 720))] {
            window.setContentSize(size)
            try await Task.sleep(for: .milliseconds(200))
            root.layoutSubtreeIfNeeded()
            guard let input = editor.enclosingScrollView, let results = table.enclosingScrollView else {
                throw FsearchError.bridge("Native search controls unavailable")
            }
            let visible = window.contentLayoutRect
            let resultFrame = results.convert(results.bounds, to: nil)
            try require(visible.contains(input.convert(input.bounds, to: nil)), "Native search input is clipped")
            try require(visible.contains(resultFrame) && resultFrame.height >= 250,
                        "Native results workspace is clipped or too small")
            try require(resultFrame.minY - visible.minY >= 60, "Native bottom actions are clipped")
            try require(table.tableColumns.reduce(0) { $0 + $1.width } <= results.contentSize.width + 1,
                        "Native result columns require horizontal scrolling")
            try require(table.bounds.width <= results.contentSize.width + 1, "Native table viewport is clipped")
            try await capture(name, under: output)
        }
        window.setFrame(originalFrame, display: true)

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

        let retainedQuery = query
        window.performClose(nil)
        try require(!window.isVisible, "Close did not hide the search window")
        try require(MainWindowLifecycle.shared.reopen(), "Search window did not reopen")
        try require(query == retainedQuery && selection == selectedID && editor.string == retainedQuery,
                    "Reopened search window lost current input or selection")
        try await capture("settings-window-reopened", under: output)

        let diagnosticURL = output.appendingPathComponent("diagnostics.json")
        try DiagnosticReport(status: permissionStatus.status,
                             error: FsearchError.query("/Users/隐私/秘密.txt\nprivate-body-marker"),
                             stderr: "/Users/隐私/逗号,路径.txt\nprivate-body-marker").write(to: diagnosticURL)
        let diagnosticData = try Data(contentsOf: diagnosticURL)
        let diagnosticText = String(decoding: diagnosticData, as: UTF8.self)
        let diagnostic = try JSONSerialization.jsonObject(with: diagnosticData) as? [String: Any]
        try require(diagnostic?["errorCategory"] as? String == "query"
                    && diagnostic?["engineVersion"] as? String == engineVersion,
                    "Diagnostic export lost version or error category")
        try require(!diagnosticText.contains("隐私") && !diagnosticText.contains("private-body-marker")
                    && !diagnosticText.contains(retainedQuery), "Diagnostic export leaked private input")
        print("Native settings window reopen and diagnostic file: passed")

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

    private func capture(_ name: String, under output: URL, window: NSWindow? = nil) async throws {
        try await Task.sleep(for: .milliseconds(300))
        guard let view = (window ?? NSApplication.shared.windows.first(where: { $0.isVisible }))?.contentView,
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
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowLifecycle.shared.reopen()
        return true
    }
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
        Window("FsearchDesktop", id: "main-search") {
            SearchView(model: model, selectionState: model.selectionState)
                .background(MainWindowAttachment())
                .sheet(isPresented: $model.showsUpdates) {
                    UpdateView(state: model.updates, engineVersion: model.engineVersion)
                }
                .sheet(isPresented: $model.showsContentSearch) {
                    ContentSearchView(state: model.contentSearch)
                }
        }
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            SearchCommands(model: model, selectionState: model.selectionState)
            ApplicationCommands(showUpdates: { model.showsUpdates = true })
        }
    }
}
