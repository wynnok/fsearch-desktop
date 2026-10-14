import AppKit
import FsearchService
import Quartz

@MainActor
enum NativeFileActionsSmoke {
    static func run(window: NSWindow, selectionState: SearchSelectionState) async throws -> [String: Bool] {
        func findView<T: NSView>(of type: T.Type, in view: NSView) -> T? {
            if let match = view as? T { return match }
            for child in view.subviews { if let match = findView(of: type, in: child) { return match } }
            return nil
        }
        guard let root = window.contentView, let table = findView(of: NonAnimatingTableView.self, in: root), table.numberOfRows >= 2,
              let pathBar = findView(of: NSPathControl.self, in: root),
              let actions = table.previewController else {
            throw FsearchError.bridge("文件动作冒烟需要真实窗口及至少两个受控结果")
        }
        func event(_ code: UInt16, _ characters: String) throws -> NSEvent {
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil,
                                              characters: characters, charactersIgnoringModifiers: characters,
                                              isARepeat: false, keyCode: code) else {
                throw FsearchError.bridge("无法创建原生按键")
            }
            return event
        }
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        window.makeFirstResponder(table)
        try await Task.sleep(for: .milliseconds(100))
        guard let firstPath = selectionState.selectedPath else { throw FsearchError.bridge("无选中目标") }
        let first = URL(fileURLWithPath: firstPath)
        table.keyDown(with: try event(36, "\r"))
        for _ in 0..<100 where actions.openedURL == nil && actions.message == nil {
            try await Task.sleep(for: .milliseconds(30))
        }
        var checks = ["enterOpenNativeTarget": actions.openedURL == first]
        if let menu = table.menu {
            menu.delegate?.menuNeedsUpdate?(menu)
            let titles = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
            checks["contextMenuRequestedActions"] = titles == ["打开", "快速查看", "在 Finder 中显示", "复制路径",
                "打开方式", "显示简介", "重命名…", "移到废纸篓", "永久删除…"]
            checks["contextMenuIcons"] = menu.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.image != nil }
            checks["openWithListsApplications"] = menu.items.first(where: { $0.title == "打开方式" })?.submenu?.items.isEmpty == false
        }
        if let doubleAction = table.doubleAction {
            NSApplication.shared.sendAction(doubleAction, to: table.target, from: table)
            for _ in 0..<100 where actions.openedURL == nil && actions.message == nil {
                try await Task.sleep(for: .milliseconds(30))
            }
        }
        checks["doubleClickNativeTarget"] = actions.openedURL == first
        if let copyItem = table.menu?.items.first(where: { $0.title == "复制路径" }), let action = copyItem.action {
            NSApplication.shared.sendAction(action, to: copyItem.target, from: copyItem)
        }
        checks["contextCopyFullPath"] = NSPasteboard.general.string(forType: .string) == firstPath
        if let revealItem = table.menu?.items.first(where: { $0.title == "在 Finder 中显示" }), let action = revealItem.action {
            NSApplication.shared.sendAction(action, to: revealItem.target, from: revealItem)
        }
        // Confirms the native request; Finder's visible selection needs separate UI observation.
        checks["finderNativeRequestTarget"] = actions.revealedURL == first
        if ProcessInfo.processInfo.environment["FSEARCH_VERIFY_FINDER_INFO"] == "1" {
            actions.showInfo(path: first.path)
            checks["finderInformationWindowRequest"] = actions.message == nil
        }
        let folder = first.deletingLastPathComponent()
        func folderElement(in element: NSAccessibilityProtocol) -> NSAccessibilityProtocol? {
            if element.accessibilityURL()?.path == folder.path
                || element.accessibilityTitle() == folder.lastPathComponent
                || (element as? NSPathComponentCell)?.url?.path == folder.path { return element }
            for child in (element.accessibilityChildren() ?? []).compactMap({ $0 as? NSAccessibilityProtocol }) {
                if let match = folderElement(in: child) { return match }
            }
            return nil
        }
        guard let folderElement = folderElement(in: pathBar) else {
            throw FsearchError.bridge("路径栏的父文件夹不可访问")
        }
        let folderFrame = folderElement.accessibilityFrame()
        let location = window.convertPoint(fromScreen: NSPoint(x: folderFrame.midX, y: folderFrame.midY))
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [],
                                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [],
                                         timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                         context: nil, eventNumber: 1, clickCount: 1, pressure: 0) else {
            throw FsearchError.bridge("无法创建路径栏单击事件")
        }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.postEvent(up, atStart: true)
        pathBar.mouseDown(with: down)
        for _ in 0..<100 where actions.openedURL != folder {
            try await Task.sleep(for: .milliseconds(30))
        }
        checks["pathFolderSingleClickTarget"] = actions.openedURL == folder
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(table)
        table.keyDown(with: try event(49, " "))
        checks["spacePreviewTarget"] = QLPreviewPanel.shared()?.isVisible == true && actions.previewURL == first
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        try await Task.sleep(for: .milliseconds(150))
        checks["selectionUpdatesPreview"] = actions.previewURL?.path == selectionState.selectedPath
        if let panel = QLPreviewPanel.shared() {
            _ = actions.previewPanel(panel, handle: try event(53, "\u{1b}"))
            actions.updatePreview(path: selectionState.selectedPath)
            // Quick Look's preview service can finish closing asynchronously.
            for _ in 0..<250 where panel.isVisible { try await Task.sleep(for: .milliseconds(20)) }
            checks["escapeClosesPreview"] = !panel.isVisible && actions.previewURL == nil
        }
        if let deleteItem = table.menu?.items.first(where: { $0.title == "永久删除…" }), let action = deleteItem.action {
            // The menu still represents the first item, even though selection moved to the second.
            NSApplication.shared.sendAction(action, to: deleteItem.target, from: deleteItem)
            for _ in 0..<100 where window.attachedSheet == nil { try await Task.sleep(for: .milliseconds(20)) }
            guard let sheet = window.attachedSheet, let cancel = sheet.defaultButtonCell?.controlView as? NSButton else {
                throw FsearchError.bridge("永久删除确认窗口未出现或没有默认取消按钮")
            }
            checks["permanentDeleteDefaultsToCancel"] = cancel.title == "取消"
            func containsTargetName(_ view: NSView) -> Bool {
                if let text = view as? NSTextField, text.stringValue.contains(first.lastPathComponent) { return true }
                return view.subviews.contains { containsTargetName($0) }
            }
            checks["permanentDeleteKeepsOriginalMenuTarget"] = sheet.contentView.map(containsTargetName) == true
            cancel.performClick(nil)
            for _ in 0..<100 where window.attachedSheet != nil || actions.isMutating { try await Task.sleep(for: .milliseconds(20)) }
            checks["permanentDeleteCancelPreservesFile"] = FileManager.default.fileExists(atPath: first.path)
        }
        if let scroll = table.enclosingScrollView {
            // Large native rows make scrolling observable with the small controlled fixture.
            let rowHeight = table.rowHeight
            table.rowHeight = scroll.contentView.bounds.height + 50
            table.reloadData()
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            try await Task.sleep(for: .milliseconds(100))
            let targetY = table.rect(ofRow: 1).minY + 5
            scroll.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scroll.reflectScrolledClipView(scroll.contentView)
            let origin = scroll.contentView.bounds.origin.y
            // The periodic public status update causes a real SwiftUI/AppKit update.
            try await Task.sleep(for: .milliseconds(750))
            checks["statusUpdatePreservesUserScroll"] = origin > 0 && abs(scroll.contentView.bounds.origin.y - origin) < 2
            table.rowHeight = rowHeight
            table.reloadData()
            scroll.contentView.scroll(to: .zero)
        }
        table.selectRowIndexes(IndexSet(integersIn: 0..<2), byExtendingSelection: false)
        try await Task.sleep(for: .milliseconds(100))
        checks["multiSelectionPreserved"] = selectionState.selectedPaths.count == 2
        checks["multiSelectionClearsPath"] = pathBar.url == nil && pathBar.pathItems.isEmpty
        table.keyDown(with: try event(36, "\r"))
        checks["multiActionExplained"] = actions.message?.contains("请选择单个") == true
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        actions.open(path: firstPath + ".does-not-exist")
        checks["missingTargetExplained"] = actions.message?.contains("移动、删除") == true
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(table)
        checks["resultsFocusRestored"] = window.firstResponder === table
        return checks
    }
}
