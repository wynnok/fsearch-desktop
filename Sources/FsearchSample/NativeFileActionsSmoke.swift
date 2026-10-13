import AppKit
import FsearchService
import Quartz

@MainActor
enum NativeFileActionsSmoke {
    static func run(window: NSWindow, selectionState: SearchSelectionState) async throws -> [String: Bool] {
        func findTable(_ view: NSView) -> NonAnimatingTableView? {
            if let table = view as? NonAnimatingTableView { return table }
            for child in view.subviews { if let table = findTable(child) { return table } }
            return nil
        }
        guard let root = window.contentView, let table = findTable(root), table.numberOfRows >= 2,
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
        if let doubleAction = table.doubleAction {
            NSApplication.shared.sendAction(doubleAction, to: table.target, from: table)
            for _ in 0..<100 where actions.openedURL == nil && actions.message == nil {
                try await Task.sleep(for: .milliseconds(30))
            }
        }
        checks["doubleClickNativeTarget"] = actions.openedURL == first
        if let copyItem = table.menu?.items.first(where: { $0.title == "复制完整路径" }), let action = copyItem.action {
            NSApplication.shared.sendAction(action, to: copyItem.target, from: copyItem)
        }
        checks["contextCopyFullPath"] = NSPasteboard.general.string(forType: .string) == firstPath
        if let revealItem = table.menu?.items.first(where: { $0.title == "在 Finder 显示所选项目" }), let action = revealItem.action {
            NSApplication.shared.sendAction(action, to: revealItem.target, from: revealItem)
        }
        // Confirms the native request; Finder's visible selection needs separate UI observation.
        checks["finderNativeRequestTarget"] = actions.revealedURL == first
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(table)
        table.keyDown(with: try event(49, " "))
        checks["spacePreviewTarget"] = QLPreviewPanel.shared()?.isVisible == true && actions.previewURL == first
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        try await Task.sleep(for: .milliseconds(150))
        checks["selectionUpdatesPreview"] = actions.previewURL?.path == selectionState.selectedPath
        if let panel = QLPreviewPanel.shared() {
            _ = actions.previewPanel(panel, handle: try event(53, "\u{1b}"))
            for _ in 0..<50 where panel.isVisible { try await Task.sleep(for: .milliseconds(20)) }
            checks["escapeClosesPreview"] = !panel.isVisible && actions.previewURL == nil
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
