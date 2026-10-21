import AppKit
import XCTest
@testable import FsearchSample

@MainActor
final class WindowLifecycleTests: XCTestCase {
    func testCloseAndReopenRetainsWindowContentAndSelection() {
        _ = NSApplication.shared
        let lifecycle = MainWindowLifecycle()
        let selection = SearchSelectionState()
        selection.selectedPath = "/fixture/report.txt"
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let content = NSView()
        window.contentView = content
        window.toolbar = NSToolbar(identifier: "compact-window-check")
        window.toolbarStyle = .unified
        let previousChromeHeight = window.frame.height - window.contentLayoutRect.height
        lifecycle.attach(window)
        XCTAssertEqual(window.toolbarStyle, .unifiedCompact)
        XCTAssertLessThan(window.frame.height - window.contentLayoutRect.height, previousChromeHeight,
                          "The title bar should shrink without moving search into the window chrome")
        window.orderFront(nil)
        window.performClose(nil)
        XCTAssertFalse(window.isVisible)
        XCTAssertTrue(lifecycle.reopen())
        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(window.contentView === content)
        XCTAssertEqual(selection.selectedPath, "/fixture/report.txt")
        window.orderOut(nil)
    }
}
