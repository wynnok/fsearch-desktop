import AppKit
import Quartz
import XCTest
@testable import FsearchSample

@MainActor
final class MultiSelectionFileActionTests: XCTestCase {
    func testCopyPathsPreservesResultOrderAndFileCopyWritesFileURLs() {
        _ = NSApplication.shared
        let actions = FileActionState()
        let paths = ["/fixture/second.txt", "/fixture/first.txt"]
        actions.copy(paths: paths)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "/fixture/second.txt\n/fixture/first.txt")
        actions.copyFiles(paths: paths)
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL]
        XCTAssertEqual(urls?.map(\.path), paths)
    }
    func testQuickLookContainsAllSelectedFilesInOrder() throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let paths = [root.appendingPathComponent("FileOpenTests.swift").path,
                     root.appendingPathComponent("FileMutationTests.swift").path]
        let actions = FileActionState()
        actions.togglePreview(paths: paths)
        let panel = try XCTUnwrap(QLPreviewPanel.shared())
        defer { panel.orderOut(nil) }
        XCTAssertEqual(actions.numberOfPreviewItems(in: panel), 2)
        XCTAssertEqual(actions.previewPanel(panel, previewItemAt: 1)?.previewItemURL, URL(fileURLWithPath: paths[1]))
    }

    func testBatchDeleteCancelsOnceAndProtectsReplacementAfterConfirmation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = [root.appendingPathComponent("one"), root.appendingPathComponent("two")]
        for file in files { try Data("original".utf8).write(to: file) }
        var confirmations = 0
        let cancel = FileActionState(confirmBatchDeletion: { urls, _, decision in
            confirmations += 1
            XCTAssertEqual(urls, files)
            decision(false)
        })
        await cancel.permanentlyDelete(paths: files.map(\.path), in: nil)
        XCTAssertEqual(confirmations, 1)
        XCTAssertTrue(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        let replace = FileActionState(confirmBatchDeletion: { _, _, decision in
            do {
                try FileManager.default.moveItem(at: files[0], to: root.appendingPathComponent("saved"))
                try Data("replacement".utf8).write(to: files[0])
                decision(true)
            } catch { XCTFail("\(error)"); decision(false) }
        })
        await replace.permanentlyDelete(paths: files.map(\.path), in: nil)
        XCTAssertEqual(try String(contentsOf: files[0], encoding: .utf8), "replacement")
        XCTAssertFalse(FileManager.default.fileExists(atPath: files[1].path))
        XCTAssertTrue(replace.message?.contains("失败 1") == true)
    }

    func testBatchTrashContinuesAfterFailureAndReportsOnlySuccessfulMutation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = [root.appendingPathComponent("one"), root.appendingPathComponent("two")]
        for file in files { try Data().write(to: file) }
        let actions = FileActionState(recycle: { url, completion in
            completion(url == files[0] ? CocoaError(.fileWriteNoPermission) : nil)
        })
        var changed: [String] = []
        actions.onFileMutation = { path, _ in changed.append(path) }
        await actions.moveToTrash(paths: files.map(\.path))
        XCTAssertEqual(changed, [files[1].path])
        XCTAssertTrue(actions.message?.contains("失败 1") == true)
        XCTAssertFalse(actions.isMutating)
    }

    func testDeletingSelectedFolderAndChildRefreshesResultsAndSelection() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/multi-selection-tests/\(UUID().uuidString)")
        let folder = root.appendingPathComponent("report-folder")
        let child = folder.appendingPathComponent("report.txt")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: child)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = SearchModel(arguments: ["FsearchSample", root.path, "--smoke"])
        model.query = "report"
        await model.search()
        XCTAssertEqual(model.results.count, 2)
        model.selectionState.select(paths: [folder.path, child.path], primary: child.path)
        let actions = FileActionState(confirmBatchDeletion: { urls, _, decision in
            XCTAssertEqual(urls.map(\.path), [folder.path])
            decision(true)
        })
        actions.onFileMutation = model.fileDidChange
        await actions.permanentlyDelete(paths: [child.path, folder.path], in: nil)
        for _ in 0..<100 where !model.results.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertTrue(model.selectionState.selectedPaths.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertTrue(actions.message?.contains("失败 0") == true)
    }
}
