import AppKit
import SwiftUI
import XCTest
@testable import FsearchSample

@MainActor
final class SearchWindowLayoutTests: XCTestCase {
    func testReturnQueriesFileNamesWithoutInsertingNewline() async throws {
        _ = NSApplication.shared
        let model = SearchModel(arguments: ["FsearchSample", "fixtures/sample", "--smoke"])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: SearchView(model: model, selectionState: model.selectionState))
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        model.query = "report"
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        let editor = try XCTUnwrap(firstView(of: NSTextView.self, in: host))
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                 timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                 characters: "\r", charactersIgnoringModifiers: "\r",
                                                 isARepeat: false, keyCode: 36))
        editor.keyDown(with: event)
        for _ in 0..<100 where model.results.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(editor.string, "report")
        XCTAssertEqual(model.query, "report")
        XCTAssertEqual(Set(model.results.map { URL(fileURLWithPath: $0.path).lastPathComponent }),
                       ["report2.txt", "report10.txt"])
    }

    func testShiftReturnPreservesNewlineAsFileNameDataWithoutQuerying() async throws {
        _ = NSApplication.shared
        let model = SearchModel(arguments: ["FsearchSample", "fixtures/sample", "--smoke"])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: SearchView(model: model, selectionState: model.selectionState))
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        model.query = "report"
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        let editor = try XCTUnwrap(firstView(of: NSTextView.self, in: host))
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift,
                                                 timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                 characters: "\r", charactersIgnoringModifiers: "\r",
                                                 isARepeat: false, keyCode: 36))
        editor.keyDown(with: event)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(editor.string, "report\n")
        XCTAssertEqual(model.query, "report\n")
        XCTAssertTrue(model.results.isEmpty)
    }

    func testFileNameTextIsVerticallyCenteredInSearchField() async throws {
        _ = NSApplication.shared
        let model = SearchModel(arguments: ["FsearchSample", "fixtures/sample", "--smoke"])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: SearchView(model: model, selectionState: model.selectionState))
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        model.query = "report"
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        let editor = try XCTUnwrap(firstView(of: NSTextView.self, in: host))
        let layoutManager = try XCTUnwrap(editor.layoutManager)
        let container = try XCTUnwrap(editor.textContainer)
        let glyphRange = layoutManager.glyphRange(for: container)
        let origin = editor.textContainerOrigin
        let textBounds = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            .offsetBy(dx: origin.x, dy: origin.y)
        XCTAssertEqual(textBounds.midY, editor.bounds.midY, accuracy: 1.0,
                       "File name text should be vertically centered; text=\(textBounds.midY) field=\(editor.bounds.midY)")
    }

    func testSampleModeCannotOpenContentSearchFromMainWindow() async throws {
        _ = NSApplication.shared
        let model = SearchModel(arguments: ["FsearchSample", "fixtures/sample", "--smoke"])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: SearchView(model: model, selectionState: model.selectionState))
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(model.canSearchContent)
        let point = host.convert(NSPoint(x: host.bounds.maxX - 80,
                                        y: host.isFlipped ? 25 : host.bounds.maxY - 25), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                       timestamp: 0, windowNumber: window.windowNumber,
                                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(model.showsContentSearch)
    }

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
