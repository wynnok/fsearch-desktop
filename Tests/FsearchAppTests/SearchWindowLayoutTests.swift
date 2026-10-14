import AppKit
import SwiftUI
import XCTest
@testable import FsearchSample

@MainActor
final class SearchWindowLayoutTests: XCTestCase {
    func testSearchControlsAndResultsFitWithoutResizingAfterSearch() async throws {
        _ = NSApplication.shared
        let model = SearchModel(arguments: ["FsearchSample", "fixtures/sample", "--smoke"])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: SearchView(model: model, selectionState: model.selectionState))
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        model.query = ".md"
        await model.search()

        for size in [NSSize(width: 960, height: 620), NSSize(width: 1100, height: 720)] {
            window.setContentSize(size)
            try await Task.sleep(for: .milliseconds(200))
            host.layoutSubtreeIfNeeded()
            let editor = try XCTUnwrap(firstView(of: NSTextView.self, in: host))
            let table = try XCTUnwrap(firstView(of: NSTableView.self, in: host))
            let input = try XCTUnwrap(editor.enclosingScrollView)
            let results = try XCTUnwrap(table.enclosingScrollView)
            let visible = window.contentLayoutRect
            XCTAssertTrue(visible.contains(input.convert(input.bounds, to: nil)), "Search input is clipped at \(size)")
            XCTAssertTrue(visible.contains(results.convert(results.bounds, to: nil)), "Results are clipped at \(size)")
            XCTAssertGreaterThan(results.bounds.height, 250, "Results should remain the main workspace")
            XCTAssertLessThanOrEqual(table.tableColumns.reduce(0) { $0 + $1.width }, results.contentSize.width + 1,
                                     "Result columns should fit without horizontal scrolling at \(size)")
            XCTAssertLessThanOrEqual(table.bounds.width, results.contentSize.width + 1,
                                     "The table viewport should fit at \(size)")
            let resultFrame = results.convert(results.bounds, to: nil)
            XCTAssertGreaterThanOrEqual(resultFrame.minY - visible.minY, 60,
                                        "Path navigation and bottom actions need visible space at \(size)")
        }
    }

    private func firstView<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { self.firstView(of: type, in: $0) }.first
    }
}
