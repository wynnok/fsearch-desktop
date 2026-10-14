import AppKit
import SwiftUI
import XCTest
@testable import FsearchSample

@MainActor
final class PathNavigationTests: XCTestCase {
    func testBreadcrumbsShowHierarchyAndFollowSelectedResult() async throws {
        _ = NSApplication.shared
        let actions = FileActionState()
        let host = NSHostingView(rootView: PathNavigationView(path: "/Users/example/Documents/report.txt", actions: actions))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 60),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(100))
        let bar = try XCTUnwrap(pathControl(in: host))
        XCTAssertEqual(bar.pathStyle, .standard)
        XCTAssertFalse(bar.isEditable, "The path belongs to the selected result")
        XCTAssertEqual(bar.pathItems.compactMap { $0.url?.path },
                       ["/", "/Users", "/Users/example", "/Users/example/Documents", "/Users/example/Documents/report.txt"])
        XCTAssertTrue(window.contentLayoutRect.contains(bar.convert(bar.bounds, to: nil)))

        host.rootView = PathNavigationView(path: "/tmp/笔记😀.md", actions: actions)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(bar.url?.path, "/tmp/笔记😀.md")
        XCTAssertEqual(bar.pathItems.last?.url?.path, "/tmp/笔记😀.md")

        host.rootView = PathNavigationView(path: nil, actions: actions)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(bar.url)
        XCTAssertTrue(bar.pathItems.isEmpty)
        XCTAssertEqual(bar.placeholderString, "选择结果以查看路径")
    }

    private func pathControl(in view: NSView) -> NSPathControl? {
        if let bar = view as? NSPathControl { return bar }
        return view.subviews.lazy.compactMap { self.pathControl(in: $0) }.first
    }
}
