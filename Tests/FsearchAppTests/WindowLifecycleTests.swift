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
        lifecycle.attach(window)
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
