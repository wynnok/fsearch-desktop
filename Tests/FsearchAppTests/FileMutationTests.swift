import AppKit
import FsearchService
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

    func testConfirmedDeletionImmediatelyUpdatesBothSearchListsAndTheirSelection() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = ["report1.txt", "report2.txt", "report3.txt"].map { directory.appendingPathComponent($0) }
        for file in files { try Data("match".utf8).write(to: file) }
        let model = SearchModel(arguments: ["FsearchSample", directory.path, "--smoke"])
        let content = ContentSearchState(controller: ContentSearchController { request in
            ContentSearchResponse(requestID: request.id, files: files.map {
                ContentFile(path: $0.path, lines: [ContentLine(line: 1, text: "match", ranges: [[0, 5]])])
            }, candidates: 3, read: 3, complete: true, next: nil, indexed: true, error: nil)
        })
        model.contentSearch = content
        content.pattern = "match"
        await content.search()
        await model.search()
        let deleted = files[0]
        model.selectionState.select(paths: [deleted.path, files[1].path], primary: deleted.path)

        let actions = FileActionState(confirmDeletion: { _, _, decision in decision(true) })
        actions.onFileMutation = model.fileDidChange
        await actions.permanentlyDelete(path: deleted.path, in: nil)

        XCTAssertEqual(model.results.map(\.path), Array(files.dropFirst()).map(\.path))
        XCTAssertEqual(model.controller?.totalCount, 2)
        XCTAssertEqual(model.selectionState.selectedPaths, [files[1].path])
        XCTAssertEqual(content.files.map(\.path), Array(files.dropFirst()).map(\.path))
        XCTAssertEqual(content.controller.displayedOccurrences, 2)
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

    func testCancellingNativeDeletionSheetPreservesTheFile() async throws {
        _ = NSApplication.shared
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("report.txt")
        try Data("keep me".utf8).write(to: file)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        let actions = FileActionState()
        let deletion = Task { await actions.permanentlyDelete(path: file.path, in: window) }
        defer {
            if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .abort) }
            deletion.cancel()
        }
        for _ in 0..<250 where window.attachedSheet?.isVisible != true {
            try await Task.sleep(for: .milliseconds(20))
        }
        let sheet = try XCTUnwrap(window.attachedSheet)
        XCTAssertTrue(sheet.isVisible)
        let cancel = try XCTUnwrap(sheet.defaultButtonCell?.controlView as? NSButton)
        XCTAssertEqual(cancel.title, "取消")
        XCTAssertTrue(cancel.isEnabled)
        cancel.performClick(nil)
        for _ in 0..<250 where actions.isMutating {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(actions.isMutating)
        guard !actions.isMutating else { return }
        await deletion.value
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "keep me")
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
        XCTAssertTrue(actions.message?.contains("请检查文件及所在文件夹的权限") == true)
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "keep me")
    }

    func testPendingTrashBlocksRepeatedRequestsUntilItReportsFailure() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("report.txt")
        try Data().write(to: file)
        let requested = expectation(description: "已请求移到废纸篓")
        var complete: (@Sendable (Error?) -> Void)?
        let actions = FileActionState(recycle: { _, completion in
            guard complete == nil else {
                XCTFail("重复提交了移到废纸篓请求")
                completion(CocoaError(.fileWriteUnknown))
                return
            }
            complete = completion
            requested.fulfill()
        })
        let trash = Task { await actions.moveToTrash(path: file.path) }
        await fulfillment(of: [requested], timeout: 2)
        XCTAssertEqual(actions.deletionProgress, "正在移到废纸篓…")
        XCTAssertTrue(actions.isMutating)
        await actions.moveToTrash(path: file.path)
        complete?(CocoaError(.fileWriteNoPermission))
        await trash.value
        XCTAssertNil(actions.deletionProgress)
        XCTAssertFalse(actions.isMutating)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testFileRemovedDuringConfirmationDisappearsWithAnExplanation() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("report.txt")
        try Data().write(to: file)
        let model = SearchModel(arguments: ["FsearchSample", directory.path, "--smoke"])
        await model.search()
        XCTAssertEqual(model.results.map(\.path), [file.path])
        let actions = FileActionState(confirmDeletion: { _, _, decision in
            do {
                try FileManager.default.removeItem(at: file)
                decision(true)
            } catch { XCTFail(error.localizedDescription); decision(false) }
        })
        actions.onFileMutation = model.fileDidChange
        await actions.permanentlyDelete(path: file.path, in: nil)
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertTrue(actions.message?.contains("已不存在，已从结果中移除") == true)
        XCTAssertNil(actions.deletionProgress)
    }

    func testPartialDirectoryDeletionClearsOnlyMissingDescendantsFromBothLists() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = directory.appendingPathComponent("report-folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let removed = folder.appendingPathComponent("report1.txt")
        let kept = folder.appendingPathComponent("report2.txt")
        for file in [removed, kept] { try Data("match".utf8).write(to: file) }
        let model = SearchModel(arguments: ["FsearchSample", directory.path, "--smoke"])
        model.contentSearch = ContentSearchState(controller: ContentSearchController { request in
            ContentSearchResponse(requestID: request.id, files: [removed, kept].map {
                ContentFile(path: $0.path, lines: [])
            }, candidates: 2, read: 2, complete: true, next: nil, indexed: false, error: nil)
        })
        model.contentSearch.pattern = "match"
        await model.contentSearch.search()
        await model.search()
        model.selection = removed.path

        let actions = FileActionState(confirmDeletion: { _, _, decision in decision(true) }, remove: { _ in
            try FileManager.default.removeItem(at: removed)
            throw CocoaError(.fileWriteNoPermission)
        })
        actions.onFileMutation = model.fileDidChange
        actions.onDirectoryDeletionFailure = model.reconcileFailedDirectoryRemoval
        await actions.permanentlyDelete(path: folder.path, in: nil)

        XCTAssertEqual(Set(model.results.map(\.path)), [folder.path, kept.path])
        XCTAssertEqual(model.controller?.totalCount, 2)
        XCTAssertNil(model.selection)
        XCTAssertEqual(model.contentSearch.files.map(\.path), [kept.path])
        XCTAssertTrue(actions.message?.contains("没有权限删除") == true)
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
