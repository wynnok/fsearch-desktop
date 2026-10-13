import Foundation
import XCTest
@testable import FsearchSample

@MainActor
final class FileInspectorTests: XCTestCase {
    func testCurrentSizeAndDirectoryAreHonest() async throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/inspector-tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("report.txt")
        try Data("hello".utf8).write(to: file)
        let state = FileInspectorState()
        await state.select(path: file.path)
        XCTAssertEqual(state.details?.size, 5)
        await state.select(path: directory.path)
        XCTAssertNil(state.details?.size)
        XCTAssertEqual(state.details?.kind, "文件夹（大小未递归计算）")
    }
    func testLateDetailsCannotReplaceCurrentSelection() async {
        let state = FileInspectorState(reader: { path in
            if path == "/old" { try await Task.sleep(for: .milliseconds(80)) }
            return FileDetails(kind: path, size: path == "/old" ? 100 : 5)
        })
        let old = Task { await state.select(path: "/old") }
        await Task.yield()
        await state.select(path: "/new")
        await old.value
        XCTAssertEqual(state.path, "/new")
        XCTAssertEqual(state.details?.kind, "/new")
        XCTAssertEqual(state.details?.size, 5)
        await state.select(path: nil)
        XCTAssertNil(state.details)
    }

    func testDeletedFileReportsReadableFailure() async {
        let state = FileInspectorState()
        await state.select(path: "/nonexistent-fsearch-fixture")
        XCTAssertNil(state.details)
        XCTAssertTrue(state.message.contains("移动、删除"))
        let actions = FileActionState()
        XCTAssertNil(actions.accessibleURL(path: "/nonexistent-fsearch-fixture"))
        XCTAssertTrue(actions.message?.contains("移动、删除") == true)
    }
    func testMultiSelectionShowsCountAndSharedLocationWithoutInventingAttributes() async {
        let selection = SearchSelectionState()
        selection.select(paths: ["/fixtures/a/one.txt", "/fixtures/b/two.txt"], primary: "/fixtures/b/two.txt")
        let inspector = FileInspectorState()
        await inspector.select(paths: selection.selectedPaths, primary: selection.selectedPath)
        XCTAssertEqual(inspector.selectionCount, 2)
        XCTAssertEqual(inspector.commonLocation, "/fixtures")
        XCTAssertNil(inspector.details)
        selection.selectedPath = "/fixtures/a/one.txt"
        XCTAssertEqual(selection.selectedPaths, ["/fixtures/a/one.txt"])
    }
}
