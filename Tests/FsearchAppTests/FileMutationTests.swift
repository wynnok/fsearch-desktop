import AppKit
import XCTest
@testable import FsearchSample

@MainActor
final class FileMutationTests: XCTestCase {
    func testRenamePreservesContentAndDoesNotOverwriteAnExistingFile() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("report.txt")
        let renamed = directory.appendingPathComponent("新笔记😀.md")
        try Data("original content".utf8).write(to: original)
        let actions = FileActionState()
        await actions.rename(path: original.path, to: renamed.lastPathComponent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(try String(contentsOf: renamed, encoding: .utf8), "original content")

        let occupied = directory.appendingPathComponent("occupied.txt")
        try Data("other content".utf8).write(to: occupied)
        await actions.rename(path: renamed.path, to: occupied.lastPathComponent)
        XCTAssertEqual(try String(contentsOf: occupied, encoding: .utf8), "other content")
        XCTAssertEqual(try String(contentsOf: renamed, encoding: .utf8), "original content")
        XCTAssertTrue(actions.message?.hasPrefix("重命名失败") == true)
    }

    func testCancellingPermanentDeletionPreservesTheFile() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("report.txt")
        try Data("keep me".utf8).write(to: original)
        var confirmationTarget: URL?
        let actions = FileActionState(confirmDeletion: { url, _, decision in
            confirmationTarget = url
            decision(false)
        })
        await actions.permanentlyDelete(path: original.path, in: nil)
        XCTAssertEqual(confirmationTarget, original)
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "keep me")
        XCTAssertFalse(actions.isMutating)
    }

    func testConfirmedDeletionOnlyRemovesRequestedFile() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("report.txt")
        let other = directory.appendingPathComponent("other.txt")
        try Data("delete me".utf8).write(to: original)
        try Data("keep me".utf8).write(to: other)
        let actions = FileActionState(confirmDeletion: { _, _, decision in decision(true) })
        await actions.permanentlyDelete(path: original.path, in: nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(try String(contentsOf: other, encoding: .utf8), "keep me")
    }

    func testConfirmationCannotDeleteAReplacementAtTheSamePath() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("report.txt")
        let moved = directory.appendingPathComponent("moved.txt")
        try Data("original".utf8).write(to: original)
        let actions = FileActionState(confirmDeletion: { _, _, decision in
            do {
                try FileManager.default.moveItem(at: original, to: moved)
                try Data("replacement".utf8).write(to: original)
                decision(true)
            } catch {
                XCTFail(error.localizedDescription)
                decision(false)
            }
        })
        await actions.permanentlyDelete(path: original.path, in: nil)
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "replacement")
        XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), "original")
        XCTAssertTrue(actions.message?.contains("已改变") == true)
    }

    func testDeletionDialogDefaultsToCancelAndNamesTheTarget() {
        _ = NSApplication.shared
        let url = URL(fileURLWithPath: "/fixture/report.txt")
        let alert = FileActionState.deletionAlert(for: url)
        XCTAssertEqual(alert.buttons.map(\.title), ["取消", "永久删除"])
        XCTAssertTrue(alert.window.defaultButtonCell === alert.buttons.first?.cell)
        XCTAssertTrue(alert.informativeText.contains(url.path))
        XCTAssertTrue(alert.informativeText.contains("无法撤销"))
    }

    func testTrashUsesTheSystemRecyclerForOnlyTheRequestedItem() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("report.txt")
        try Data("content".utf8).write(to: original)
        var recycled: [URL] = []
        let actions = FileActionState(recycle: { url, completion in
            recycled.append(url)
            completion(nil)
        })
        await actions.moveToTrash(path: original.path)
        XCTAssertEqual(recycled, [original])
        XCTAssertEqual(actions.message, "已移到废纸篓“report.txt”")
    }

    func testFailedTrashDoesNotReportAMutation() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("report.txt")
        try Data("keep me".utf8).write(to: original)
        let actions = FileActionState(recycle: { _, completion in completion(CocoaError(.fileWriteNoPermission)) })
        var changed = false
        actions.onFileMutation = { _, _ in changed = true }
        await actions.moveToTrash(path: original.path)
        XCTAssertFalse(changed)
        XCTAssertTrue(actions.message?.hasPrefix("移到废纸篓失败") == true)
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "keep me")
    }

    func testInfoPresenterReceivesLiteralUnicodeAndQuotedPath() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("引号\"与换行\n😀.txt")
        try Data("content".utf8).write(to: original)
        var infoTarget: URL?
        let actions = FileActionState(information: { infoTarget = $0 })
        actions.showInfo(path: original.path)
        XCTAssertEqual(infoTarget, original)
    }

    func testRenameRefreshKeepsSelectionAndLoadedResultWindow() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["report1.txt", "report2.txt", "report3.txt", "report4.txt"] {
            try Data("content".utf8).write(to: directory.appendingPathComponent(name))
        }
        let model = SearchModel(arguments: ["FsearchSample", directory.path, "--smoke"])
        model.query = "report"
        await model.search()
        model.loadMore()
        let old = directory.appendingPathComponent("report4.txt")
        let new = directory.appendingPathComponent("report5.txt")
        model.selection = old.path
        let actions = FileActionState()
        actions.onFileMutation = model.fileDidChange
        await actions.rename(path: old.path, to: new.lastPathComponent)
        for _ in 0..<100 where model.selection != new.path { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(model.selection, new.path)
        XCTAssertEqual(model.results.count, 4)
        XCTAssertFalse(model.results.contains { $0.path == old.path })
    }

    private func fixtureDirectory() throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = root
            .appendingPathComponent(".build/file-mutation-tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
