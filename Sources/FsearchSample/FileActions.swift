import AppKit
import Combine
import Quartz
import SwiftUI

@MainActor
final class FileActionState: NSObject, ObservableObject, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    @Published private(set) var message: String?
    private(set) var previewURL: URL?
    private(set) var openedURL: URL?
    private(set) var revealedURL: URL?
    var movePreviewSelection: ((Int) -> Void)?

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

    func copy(path: String?) {
        guard let path else { if message == nil { message = "请先选择结果" }; return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        message = "已复制完整路径"
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
