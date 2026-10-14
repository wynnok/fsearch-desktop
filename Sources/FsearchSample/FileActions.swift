import AppKit
import Combine
import Quartz
import SwiftUI

@MainActor
final class FileActionState: NSObject, ObservableObject, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    typealias DeletionConfirmation = @MainActor (URL, NSWindow?, @escaping @MainActor (Bool) -> Void) -> Void
    typealias Recycler = @MainActor (URL, @escaping @Sendable (Error?) -> Void) -> Void
    typealias InformationPresenter = @MainActor (URL) throws -> Void
    private let confirmDeletion: DeletionConfirmation
    private let recycle: Recycler
    private let information: InformationPresenter
    @Published private(set) var message: String?
    @Published private(set) var isMutating = false
    var onFileMutation: ((String, String?) -> Void)?
    private(set) var previewURL: URL?
    private(set) var openedURL: URL?
    private(set) var revealedURL: URL?
    var movePreviewSelection: ((Int) -> Void)?

    init(confirmDeletion: @escaping DeletionConfirmation = FileActionState.presentDeletionConfirmation,
         recycle: @escaping Recycler = FileActionState.recycleItem,
         information: @escaping InformationPresenter = FinderInformation.show) {
        self.confirmDeletion = confirmDeletion
        self.recycle = recycle
        self.information = information
        super.init()
    }

    func requireSingleSelection() { message = "请选择单个结果执行文件动作" }

    func accessibleURL(path: String?) -> URL? {
        guard let path else { if message == nil { message = "请先选择结果" }; return nil }
        // lstat-style attributes preserve a symlink's identity; a broken link cannot be opened.
        guard FileManager.default.fileExists(atPath: path) else {
            message = "文件已移动、删除或链接目标不存在：\(path)"; return nil
        }
        guard FileManager.default.isReadableFile(atPath: path) else {
            message = "没有读取权限：\(path)"; return nil
        }
        message = nil
        return URL(fileURLWithPath: path)
    }

    func open(path: String?) {
        guard let url = accessibleURL(path: path) else { return }
        openedURL = nil
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            Task { @MainActor in
                if let error { self.message = "系统无法打开：\(error.localizedDescription)" }
                else { self.openedURL = url }
            }
        }
    }

    func reveal(path: String?) {
        guard let url = accessibleURL(path: path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        revealedURL = url
    }

    func open(path: String?, with application: URL) {
        guard let url = accessibleURL(path: path) else { return }
        openedURL = nil
        NSWorkspace.shared.open([url], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            Task { @MainActor in
                if let error { self.message = "系统无法打开：\(error.localizedDescription)" }
                else { self.openedURL = url }
            }
        }
    }

    func showInfo(path: String?) {
        guard let url = accessibleURL(path: path) else { return }
        do { try information(url) }
        catch {
            message = (error as NSError).code == -1743
                ? "无法显示 Finder 简介：请在系统设置 → 隐私与安全性 → 自动化中允许本应用控制 Finder。"
                : "Finder 无法显示简介，请确认项目仍可访问后重试。"
        }
    }

    func copy(path: String?) {
        guard let path else { if message == nil { message = "请先选择结果" }; return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        message = "已复制完整路径"
    }

    func rename(path: String?, to name: String) async {
        guard !isMutating, let url = mutationURL(path: path) else { return }
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            message = "重命名失败：请输入有效的文件名，不要包含路径分隔符。"
            return
        }
        let destination = url.deletingLastPathComponent().appendingPathComponent(name)
        guard destination.path != url.path else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.moveItem(at: url, to: destination)
            }.value
            finishMutation(url, newURL: destination, message: "已重命名为“\(name)”")
        } catch {
            message = "重命名失败：\(error.localizedDescription)"
        }
    }

    func requestRename(path: String?, in window: NSWindow?) {
        guard !isMutating, let url = mutationURL(path: path) else { return }
        let alert = NSAlert()
        alert.messageText = "重命名“\(url.lastPathComponent)”"
        alert.informativeText = "请输入新的完整名称（包括扩展名）。"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = url.lastPathComponent
        alert.accessoryView = field
        alert.addButton(withTitle: "重命名")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        Self.presentAlert(alert, in: window) { [self] response in
            guard response == .alertFirstButtonReturn else { return }
            let name = field.stringValue
            Task { await rename(path: url.path, to: name) }
        }
    }

    func permanentlyDelete(path: String?, in window: NSWindow?) async {
        guard !isMutating, let url = mutationURL(path: path) else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            let identity = try Self.entryIdentity(url)
            let confirmed = await withCheckedContinuation { continuation in
                confirmDeletion(url, window) { continuation.resume(returning: $0) }
            }
            guard confirmed else { return }
            let deleted = try await Task.detached(priority: .userInitiated) {
                guard try Self.entryIdentity(url) == identity else { return false }
                try FileManager.default.removeItem(at: url)
                return true
            }.value
            guard deleted else {
                message = "项目在确认期间已改变，请重新选择后操作。"
                return
            }
            finishMutation(url, newURL: nil, message: "已永久删除“\(url.lastPathComponent)”")
        } catch {
            message = "永久删除失败：\(error.localizedDescription)"
        }
    }

    func moveToTrash(path: String?) async {
        guard !isMutating, let url = mutationURL(path: path) else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                recycle(url) { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
            finishMutation(url, newURL: nil, message: "已移到废纸篓“\(url.lastPathComponent)”")
        } catch {
            message = "移到废纸篓失败：\(error.localizedDescription)"
        }
    }

    private static func recycleItem(_ url: URL, _ completion: @escaping @Sendable (Error?) -> Void) {
        NSWorkspace.shared.recycle([url]) { newURLs, error in
            completion(error ?? (newURLs[url] == nil ? CocoaError(.fileWriteUnknown) : nil))
        }
    }

    static func deletionAlert(for url: URL) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "要永久删除“\(url.lastPathComponent)”吗？"
        alert.informativeText = "此操作不会移到废纸篓，无法撤销。文件夹中的所有项目也会被删除。\n\n\(url.path)"
        alert.addButton(withTitle: "取消")
        let delete = alert.addButton(withTitle: "永久删除")
        delete.hasDestructiveAction = true
        delete.keyEquivalent = ""
        alert.window.defaultButtonCell = alert.buttons[0].cell as? NSButtonCell
        return alert
    }

    private static func presentDeletionConfirmation(_ url: URL, _ window: NSWindow?, _ decision: @escaping @MainActor (Bool) -> Void) {
        presentAlert(deletionAlert(for: url), in: window) { decision($0 == .alertSecondButtonReturn) }
    }

    private static func presentAlert(_ alert: NSAlert, in window: NSWindow?, completion: @escaping @MainActor (NSApplication.ModalResponse) -> Void) {
        if let window {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    private nonisolated static func entryIdentity(_ url: URL) throws -> (device: UInt64, inode: UInt64) {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else {
            throw CocoaError(.fileReadUnknown)
        }
        return (device.uint64Value, inode.uint64Value)
    }

    private func mutationURL(path: String?) -> URL? {
        guard let path else { message = "请先选择结果"; return nil }
        let url = URL(fileURLWithPath: path)
        guard url.path != "/" else { message = "不能修改或删除根目录"; return nil }
        do {
            _ = try FileManager.default.attributesOfItem(atPath: url.path)
            message = nil
            return url
        } catch {
            message = "项目已移动、删除或无法访问，请重新选择后操作。"
            return nil
        }
    }

    private func finishMutation(_ url: URL, newURL: URL?, message: String) {
        if previewURL == url { updatePreview(path: nil) }
        self.message = message
        onFileMutation?(url.path, newURL?.path)
    }

    func togglePreview(path: String?) {
        guard let panel = QLPreviewPanel.shared() else { message = "系统 Quick Look 不可用"; return }
        if panel.isVisible { panel.orderOut(nil); previewURL = nil; return }
        guard let url = previewableURL(path: path) else { return }
        previewURL = url
        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    func updatePreview(path: String?) {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
        guard let url = previewableURL(path: path) else {
            previewURL = nil
            panel.orderOut(nil)
            return
        }
        previewURL = url
        panel.reloadData()
    }

    private func previewableURL(path: String?) -> URL? {
        guard let url = accessibleURL(path: path) else { return nil }
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if values?.isUbiquitousItem == true && values?.ubiquitousItemDownloadingStatus != .current {
            message = "文件内容仍在云端；请先在 Finder 下载后预览"
            return nil
        }
        return url
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURL == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewURL as NSURL?
    }
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        if event.type == .keyDown && (event.keyCode == 53 || event.keyCode == 49) {
            panel.orderOut(nil)
            previewURL = nil
            return true
        }
        if event.type == .keyDown && (event.keyCode == 125 || event.keyCode == 126) {
            // Return arrows to the result table, whose selection updates this panel.
            movePreviewSelection?(event.keyCode == 125 ? 1 : -1)
            return true
        }
        return false
    }
}

struct PathNavigationView: View {
    let path: String?
    @ObservedObject var actions: FileActionState

    var body: some View {
        PathBreadcrumbs(path: path, actions: actions)
            .padding(.horizontal, 10).frame(height: 30)
    }
}

private struct PathBreadcrumbs: NSViewRepresentable {
    let path: String?
    let actions: FileActionState

    func makeCoordinator() -> Coordinator { Coordinator(actions: actions) }

    func makeNSView(context: Context) -> NSPathControl {
        let control = NSPathControl()
        control.pathStyle = .standard
        control.isEditable = false
        control.backgroundColor = .clear
        control.controlSize = .small
        control.placeholderString = "选择结果以查看路径"
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setAccessibilityLabel("所选文件路径")
        control.setAccessibilityIdentifier("path-navigation")
        control.target = context.coordinator
        control.action = #selector(Coordinator.openFolder(_:))
        return control
    }

    func updateNSView(_ control: NSPathControl, context: Context) {
        context.coordinator.actions = actions
        let url = path.map { URL(fileURLWithPath: $0) }
        if control.url != url { control.url = url }
        control.toolTip = path
    }

    @MainActor
    final class Coordinator: NSObject {
        var actions: FileActionState

        init(actions: FileActionState) { self.actions = actions }

        @objc func openFolder(_ sender: NSPathControl) {
            guard let url = sender.clickedPathItem?.url else { return }
            if url == sender.url {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { return }
            }
            actions.open(path: url.path)
        }
    }
}
