import AppKit
import FsearchService
import SwiftUI
import XCTest
@testable import FsearchSample

@MainActor
final class ContentSearchLayoutTests: XCTestCase {
    func testFilesWithOneOrHundredsOfMatchesKeepEqualCompactRows() async throws {
        _ = NSApplication.shared
        let files = [
            ContentFile(path: "/tmp/short.txt", lines: [ContentLine(line: 1, text: "match", ranges: [[0, 5]])]),
            ContentFile(path: "/tmp/many.txt", lines: (1...200).map {
                ContentLine(line: $0, text: "match \($0)", ranges: [[0, 5]])
            }),
            ContentFile(path: "/tmp/very-long-file-name-that-needs-to-be-truncated-in-the-result-list.txt",
                        lines: [ContentLine(line: 1, text: String(repeating: "match ", count: 200), ranges: [[0, 5]])])
        ]
        let host = NSHostingView(rootView: ContentSearchResultsView(files: files, selection: .constant(nil),
                                                                  actions: FileActionState()))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 340),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()

        let table = try XCTUnwrap(firstView(of: NSTableView.self, in: host))
        XCTAssertEqual(table.numberOfRows, 3, "Each file should remain one result")
        let firstHeight = table.rect(ofRow: 0).height
        XCTAssertLessThanOrEqual(firstHeight, 96, "File rows should stay compact enough to scan")
        XCTAssertEqual(table.rect(ofRow: 1).height, firstHeight, accuracy: 1,
                       "Hundreds of matches must not enlarge a file row")
        XCTAssertEqual(table.rect(ofRow: 2).height, firstHeight, accuracy: 1,
                       "Long file names and matching lines must not enlarge a file row")
        XCTAssertTrue(table.visibleRect.contains(table.rect(ofRow: 2)), "Three files should fit without scrolling")
    }

    func testSelectedFileKeepsAllMatchesHighlightingAndIndependentScrolling() async throws {
        _ = NSApplication.shared
        let many = ContentFile(path: "/tmp/many.txt", lines: (1...200).map {
            ContentLine(line: $0, text: "银河😀 match \($0)", ranges: [[0, 10]])
        })
        let short = ContentFile(path: "/tmp/short.txt", lines: [ContentLine(line: 7, text: "only match", ranges: [[5, 10]])])
        let actions = FileActionState()
        let host = NSHostingView(rootView: ContentSearchResultsView(files: [many, short], selection: .constant(many.path),
                                                                  actions: actions))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 340),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()

        let detail = try XCTUnwrap(firstView(of: NSTextView.self, in: host))
        XCTAssertFalse(detail.isEditable)
        XCTAssertTrue(detail.isSelectable, "Matching content should remain copyable")
        XCTAssertEqual(detail.string.components(separatedBy: "银河😀").count - 1, 200,
                       "A compact file row must not discard returned matches")
        let lastRange = try XCTUnwrap(detail.string.range(of: "银河😀 match 200"))
        let lastMatch = NSRange(lastRange, in: detail.string)
        let storage = try XCTUnwrap(detail.textStorage)
        XCTAssertNotNil(storage.attribute(.backgroundColor, at: lastMatch.location, effectiveRange: nil),
                        "Unicode content matches should retain highlighting")
        let table = try XCTUnwrap(firstView(of: NSTableView.self, in: host))
        let listScroll = try XCTUnwrap(table.enclosingScrollView)
        let listOrigin = listScroll.contentView.bounds.origin
        detail.scrollRangeToVisible(lastMatch)
        XCTAssertGreaterThan(try XCTUnwrap(detail.enclosingScrollView).contentView.bounds.minY, 0)
        XCTAssertEqual(listScroll.contentView.bounds.origin, listOrigin,
                       "Browsing a long file must not scroll the file list")

        host.rootView = ContentSearchResultsView(files: [many, short], selection: .constant(short.path), actions: actions)
        try await Task.sleep(for: .milliseconds(100))
        let replacement = try XCTUnwrap(firstView(of: NSTextView.self, in: host))
        XCTAssertTrue(replacement.string.contains("only match"))
        XCTAssertFalse(replacement.string.contains("match 200"), "Details must follow the selected file")
    }

    func testOpeningLoadedContentSearchShowsMatchesAndFitsQueryAndFooter() async throws {
        _ = NSApplication.shared
        let controller = ContentSearchController { request in
            ContentSearchResponse(requestID: request.id,
                                  files: [ContentFile(path: "/tmp/report.txt", lines: [
                                    ContentLine(line: 42, text: "visible match", ranges: [[8, 13]])
                                  ])], candidates: 1, read: 1, complete: true, next: nil, indexed: true, error: nil)
        }
        await controller.search(ContentSearchRequest(pattern: "match"))
        let state = ContentSearchState(controller: controller)
        let host = NSHostingView(rootView: ContentSearchView(state: state))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()

        let detail = try XCTUnwrap(firstView(of: NSTextView.self, in: host),
                                   "Opening existing results should immediately show the first file's matches")
        XCTAssertTrue(detail.string.contains("visible match"))
        let query = try XCTUnwrap(firstView(of: NSTextField.self, in: host))
        let path = try XCTUnwrap(firstView(of: NSPathControl.self, in: host))
        for view in [query, path, try XCTUnwrap(detail.enclosingScrollView)] as [NSView] {
            XCTAssertTrue(window.contentLayoutRect.contains(view.convert(view.bounds, to: nil)))
        }
        XCTAssertEqual(path.url?.path, "/tmp/report.txt", "Path navigation should follow the initial selection")
    }

    private func firstView<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { self.firstView(of: type, in: $0) }.first
    }
}
