import AppKit
import Combine
import Quartz
import SwiftUI

@MainActor
final class FileActionState: NSObject, ObservableObject, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    typealias DeletionConfirmation = @MainActor (URL, NSWindow?, @escaping @MainActor (Bool) -> Void) -> Void
    typealias Recycler = @MainActor (URL, @escaping @Sendable (Error?) -> Void) -> Void
    typealias InformationPresenter = @MainActor (URL) throws -> Void
    typealias BatchDeletionConfirmation = @MainActor ([URL], NSWindow?, @escaping @MainActor (Bool) -> Void) -> Void
    private let confirmBatchDeletion: BatchDeletionConfirmation
    private let confirmDeletion: DeletionConfirmation
    private let recycle: Recycler
    private let information: InformationPresenter
    @Published private(set) var message: String?
    @Published private(set) var isMutating = false
    var onFileMutation: ((String, String?) -> Void)?
    private(set) var previewURL: URL?
    private(set) var previewURLs: [URL] = []
    private(set) var openedURL: URL?
    private(set) var revealedURL: URL?
    var movePreviewSelection: ((Int) -> Void)?

    init(confirmDeletion: @escaping DeletionConfirmation = FileActionState.presentDeletionConfirmation,
         confirmBatchDeletion: @escaping BatchDeletionConfirmation = FileActionState.presentBatchDeletionConfirmation,
         recycle: @escaping Recycler = FileActionState.recycleItem,
         information: @escaping InformationPresenter = FinderInformation.show) {
        self.confirmDeletion = confirmDeletion
        self.confirmBatchDeletion = confirmBatchDeletion
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
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { @Sendable _, error in
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
        NSWorkspace.shared.open([url], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration()) { @Sendable _, error in
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

    private func accessibleURLs(paths: [String]) -> [URL]? {
        guard !paths.isEmpty else { message = "请先选择结果"; return nil }
        var urls: [URL] = []
        for path in paths {
            guard let url = accessibleURL(path: path) else { return nil }
            urls.append(url)
        }
        return urls
    }

    func open(paths: [String], with application: URL? = nil) {
        guard let urls = accessibleURLs(paths: paths) else { return }
        if let application {
            NSWorkspace.shared.open(urls, withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration()) { @Sendable _, error in
                Task { @MainActor in
                    if let error { self.message = "系统无法打开：\(error.localizedDescription)" }
                    else { self.openedURL = urls.first }
                }
            }
        } else {
            for url in urls { open(path: url.path) }
        }
    }

    func reveal(paths: [String]) {
        guard let urls = accessibleURLs(paths: paths) else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        revealedURL = urls.first
    }

    func showInfo(paths: [String]) {
        var errors: [String] = []
        for path in paths {
            showInfo(path: path)
            if let message { errors.append(message) }
        }
        if !errors.isEmpty { message = errors.joined(separator: "\n") }
    }

    func copy(paths: [String]) {
        guard !paths.isEmpty else { message = "请先选择结果"; return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
        message = "已复制 \(paths.count) 个完整路径"
    }

    func copyFiles(paths: [String]) {
        guard !paths.isEmpty else { message = "请先选择结果"; return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(paths.map { NSURL(fileURLWithPath: $0) })
        message = "已复制 \(paths.count) 个项目"
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

    func permanentlyDelete(paths: [String], in window: NSWindow?) async {
        if paths.count == 1 { await permanentlyDelete(path: paths[0], in: window); return }
        await mutate(paths: paths, permanently: true, in: window)
    }

    func moveToTrash(paths: [String]) async {
        if paths.count == 1 { await moveToTrash(path: paths[0]); return }
        await mutate(paths: paths, permanently: false, in: nil)
    }

    private func mutate(paths: [String], permanently: Bool, in window: NSWindow?) async {
        guard !isMutating, !paths.isEmpty else { return }
        isMutating = true
        defer { isMutating = false }
        var errors: [String] = []
        let urls = paths.compactMap { path -> URL? in
            guard let url = mutationURL(path: path) else {
                errors.append("\(path)：\(message ?? "无法访问")")
                return nil
            }
            return url
        }
        // A selected directory already includes its selected descendants; do not delete twice.
        let targets = urls.filter { url in
            !urls.contains { parent in
                parent != url && url.path.hasPrefix(parent.path + "/") &&
                    (try? FileManager.default.attributesOfItem(atPath: parent.path)[.type] as? FileAttributeType) == .typeDirectory
            }
        }
        var identities: [URL: (device: UInt64, inode: UInt64)] = [:]
        if permanently {
            for url in targets {
                do { identities[url] = try Self.entryIdentity(url) }
                catch { errors.append("\(url.path)：\(error.localizedDescription)") }
            }
            guard !identities.isEmpty else { message = errors.joined(separator: "\n"); return }
            let confirmed = await withCheckedContinuation { continuation in
                confirmBatchDeletion(targets, window) { continuation.resume(returning: $0) }
            }
            guard confirmed else { return }
        }
        var succeeded = 0
        for url in targets {
            do {
                if permanently {
                    guard let identity = identities[url] else { continue }
                    let deleted = try await Task.detached(priority: .userInitiated) {
                        guard try Self.entryIdentity(url) == identity else { return false }
                        try FileManager.default.removeItem(at: url)
                        return true
                    }.value
                    guard deleted else { errors.append("\(url.path)：项目在确认期间已改变"); continue }
                } else {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        recycle(url) { error in
                            if let error { continuation.resume(throwing: error) }
                            else { continuation.resume() }
                        }
                    }
                }
                succeeded += 1
                for affected in urls where affected == url || affected.path.hasPrefix(url.path + "/") {
                    finishMutation(affected, newURL: nil, message: "")
                }
            } catch { errors.append("\(url.path)：\(error.localizedDescription)") }
        }
        message = "\(permanently ? "永久删除" : "移到废纸篓")：成功 \(succeeded) 项，失败 \(errors.count) 项"
            + (errors.isEmpty ? "" : "\n" + errors.joined(separator: "\n"))
    }

    static func deletionAlert(for urls: [URL]) -> NSAlert {
        if urls.count == 1 { return deletionAlert(for: urls[0]) }
        let alert = deletionAlert(for: urls.first ?? URL(fileURLWithPath: "/"))
        alert.messageText = "要永久删除 \(urls.count) 个项目吗？"
        alert.informativeText = "此操作不会移到废纸篓，无法撤销。文件夹中的所有项目也会被删除。\n\n"
            + urls.map(\.path).joined(separator: "\n")
        return alert
    }

    private static func presentBatchDeletionConfirmation(_ urls: [URL], _ window: NSWindow?, _ decision: @escaping @MainActor (Bool) -> Void) {
        presentAlert(deletionAlert(for: urls), in: window) { decision($0 == .alertSecondButtonReturn) }
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
        if previewURLs.contains(url) { updatePreview(paths: previewURLs.filter { $0 != url }.map(\.path)) }
        self.message = message
        onFileMutation?(url.path, newURL?.path)
    }

    func togglePreview(path: String?) { togglePreview(paths: path.map { [$0] } ?? []) }

    func togglePreview(paths: [String]) {
        guard let panel = QLPreviewPanel.shared() else { message = "系统快速查看不可用"; return }
        if panel.isVisible {
            previewURL = nil
            previewURLs = []
            panel.orderOut(nil)
            return
        }
        guard setPreview(paths: paths) else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.currentPreviewItemIndex = 0
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    func updatePreview(path: String?) { updatePreview(paths: path.map { [$0] } ?? []) }

    func updatePreview(paths: [String]) {
        guard previewURL != nil, QLPreviewPanel.sharedPreviewPanelExists(),
              let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
        guard setPreview(paths: paths) else {
            previewURL = nil
            previewURLs = []
            panel.orderOut(nil)
            return
        }
        panel.reloadData()
    }

    private func setPreview(paths: [String]) -> Bool {
        guard !paths.isEmpty else { return false }
        var urls: [URL] = []
        for path in paths {
            guard let url = previewableURL(path: path) else { return false }
            urls.append(url)
        }
        previewURLs = urls
        previewURL = urls.first
        return true
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

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard previewURLs.indices.contains(index) else { return nil }
        return previewURLs[index] as NSURL
    }
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        if event.type == .keyDown && (event.keyCode == 53 || event.keyCode == 49) {
            previewURL = nil
            previewURLs = []
            panel.order(.out, relativeTo: 0)
            return true
        }
        if event.type == .keyDown && (event.keyCode == 125 || event.keyCode == 126) {
            if previewURLs.count > 1 { return false }
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
            .opacity(path == nil ? 0 : 1)
            .overlay(alignment: .leading) {
                if path == nil {
                    Text("选择结果以查看路径")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: 24)
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
