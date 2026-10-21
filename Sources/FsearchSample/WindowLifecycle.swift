import AppKit
import SwiftUI

@MainActor
final class MainWindowLifecycle: NSObject, NSWindowDelegate {
    static let shared = MainWindowLifecycle()
    private var window: NSWindow?

    func attach(_ window: NSWindow) {
        self.window = window
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = FDTheme.surfaceNSColor
        window.isMovableByWindowBackground = true
        window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    @discardableResult
    func reopen() -> Bool {
        guard let window else { return false }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        return true
    }
}

struct MainWindowAttachment: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowAttachmentView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowAttachmentView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { MainWindowLifecycle.shared.attach(window) }
        }
    }
}

struct ApplicationCommands: Commands {
    let showUpdates: () -> Void

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("关于 FsearchDesktop…", systemImage: "info.circle", action: showUpdates)
            Button("检查更新…", systemImage: "arrow.triangle.2.circlepath", action: showUpdates)
        }
        CommandGroup(after: .windowArrangement) {
            Button("重新打开搜索窗口", systemImage: "macwindow") { MainWindowLifecycle.shared.reopen() }
                .keyboardShortcut("0", modifiers: .command)
        }
    }
}
