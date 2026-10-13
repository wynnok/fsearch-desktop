import AppKit
import FsearchService

// Opt-in acceptance uses the application's existing model and real fixture service.
@MainActor
enum NativeAcceptanceSmoke {
    static func search(model: SearchModel, directory: URL) async throws -> [String: Bool] {
        let scope = directory.appendingPathComponent("journey-scope")
        try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
        for name in ["journey-visible.txt", ".journey-hidden.txt", "journey-note.md"] {
            try Data("journey fixture".utf8).write(to: scope.appendingPathComponent(name))
        }
        try Data("outside scope".utf8).write(to: directory.appendingPathComponent("journey-outside.txt"))
        model.query = "journey"
        model.configuration.scope = .folder(scope.path)
        model.configuration.showsHidden = true
        model.configuration.filters = NameSearchFilters()
        model.sort = .ascending
        // Let automatic condition submission run before the explicit refreshed query.
        await Task.yield()
        await model.search(refresh: true)
        while model.nextCursor != nil { model.loadMore() }
        var checks = ["folderScopeAcrossPages": Set(model.results.map(\.path)) == Set([
            scope.appendingPathComponent("journey-visible.txt").path,
            scope.appendingPathComponent(".journey-hidden.txt").path,
            scope.appendingPathComponent("journey-note.md").path
        ])]
        model.configuration.showsHidden = false
        await Task.yield()
        await model.search()
        checks["hiddenSwitch"] = Set(model.results.map { URL(fileURLWithPath: $0.path).lastPathComponent })
            == ["journey-visible.txt", "journey-note.md"]
        model.query = ""
        model.configuration.filters.extensions = ["md"]
        await Task.yield()
        await model.search()
        checks["filterOnlyQuery"] = model.results.map { URL(fileURLWithPath: $0.path).lastPathComponent } == ["journey-note.md"]
        model.configuration.filters.minimumSize = 20
        model.configuration.filters.maximumSize = 1
        await Task.yield()
        await model.search()
        checks["invalidFilterRecoverable"] = model.statusKind == .error && model.configuration.filters.minimumSize == 20
        model.configuration.filters = NameSearchFilters()
        model.configuration.scope = .allIndexed
        model.configuration.showsHidden = true
        model.query = "journey-outside"
        await Task.yield()
        await model.search()
        checks["clearFiltersAndScope"] = model.results.count == 1 && model.statusKind == .complete
        return checks
    }

    static func files(model: SearchModel, window: NSWindow, directory: URL) async throws -> [String: Bool] {
        let root = directory.appendingPathComponent("file-journey")
        let longParent = root.appendingPathComponent(String(repeating: "长路径", count: 12))
            .appendingPathComponent(String(repeating: "ancestor", count: 15))
        try FileManager.default.createDirectory(at: longParent, withIntermediateDirectories: true)
        let first = root.appendingPathComponent("same.txt")
        let second = longParent.appendingPathComponent("same.txt")
        try Data("first".utf8).write(to: first)
        try Data("second longer".utf8).write(to: second)
        let link = root.appendingPathComponent("linked.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: second)
        let bundle = root.appendingPathComponent("Fixture.app")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let inspector = FileInspectorState()
        await inspector.select(path: first.path)
        var checks = ["firstSameNameSize": inspector.details?.size == 5]
        await inspector.select(path: second.path)
        checks["longPathSameNameSize"] = inspector.path == second.path && inspector.details?.size == 13
        model.query = "same.txt"
        model.configuration.scope = .folder(root.path)
        await Task.yield()
        await model.search(refresh: true)
        while model.nextCursor != nil { model.loadMore() }
        checks["sameNamesInRealResults"] = Set(model.results.map(\.path)) == [first.path, second.path]
        func findTable(_ view: NSView) -> NSTableView? {
            if let table = view as? NSTableView { return table }
            for child in view.subviews { if let table = findTable(child) { return table } }
            return nil
        }
        try await Task.sleep(for: .milliseconds(150))
        if let content = window.contentView, let table = findTable(content),
           let row = model.results.firstIndex(where: { $0.path == second.path }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            try await Task.sleep(for: .milliseconds(150))
            checks["longPathResultSelection"] = model.selection == second.path
        } else { checks["longPathResultSelection"] = false }
        await inspector.select(path: link.path)
        checks["linkIdentity"] = inspector.details?.kind.contains("符号链接") == true
        await inspector.select(path: bundle.path)
        checks["applicationPackageNoRecursiveSize"] = inspector.details?.kind.contains("应用包") == true && inspector.details?.size == nil
        await inspector.select(paths: [first.path, second.path], primary: first.path)
        checks["multiSelectionNoInventedSize"] = inspector.selectionCount == 2 && inspector.details == nil
        let actions = FileActionState()
        let previousClipboard = NSPasteboard.general.string(forType: .string)
        actions.copy(path: second.path)
        checks["longPathCopy"] = NSPasteboard.general.string(forType: .string) == second.path
        if let previousClipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(previousClipboard, forType: .string)
        }
        actions.open(path: longParent.path)
        for _ in 0..<100 where actions.openedURL == nil && actions.message == nil {
            try await Task.sleep(for: .milliseconds(30))
        }
        checks["ancestorFolderOpen"] = actions.openedURL?.path == longParent.path
        try FileManager.default.removeItem(at: second)
        await inspector.select(path: second.path)
        checks["deletedDetailsExplained"] = inspector.details == nil && inspector.message.contains("移动、删除")
        checks["brokenLinkExplained"] = actions.accessibleURL(path: link.path) == nil && actions.message?.contains("链接目标不存在") == true
        let unreadable = root.appendingPathComponent("unreadable.txt")
        try Data("permission fixture".utf8).write(to: unreadable)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadable.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unreadable.path) }
        checks["unreadableActionExplained"] = actions.accessibleURL(path: unreadable.path) == nil && actions.message?.contains("没有读取权限") == true
        model.query = "same.txt"
        await model.search(refresh: true)
        checks["deletedResultRemovedAfterRefresh"] = model.results.map(\.path) == [first.path]
        model.selection = first.path
        return checks
    }
}
