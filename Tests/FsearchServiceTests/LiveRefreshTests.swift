import Foundation
import FsearchService
import XCTest

final class LiveRefreshTests: XCTestCase {
    @MainActor
    func testRefreshUsesCurrentQuerySortAndRetainsLoadedWindow() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/live-refresh/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["item1", "item2", "item3", "other"] {
            try Data("fixture".utf8).write(to: root.appendingPathComponent(name))
        }
        let service = try FsearchService(sampleDirectory: root)
        let controller = SnapshotQueryController(service: service)
        await controller.query(SearchRequest(query: "item"), sort: .descending, pageSize: 1)
        try controller.loadMore(pageSize: 1)
        let oldID = controller.snapshot?.id
        try Data("new".utf8).write(to: root.appendingPathComponent("item4"))
        try await service.refreshSample()
        await controller.refreshCurrentQuery()
        XCTAssertNotEqual(controller.snapshot?.id, oldID)
        XCTAssertEqual(controller.totalCount, 4)
        XCTAssertEqual(controller.results.map { URL(fileURLWithPath: $0.path).lastPathComponent }, ["item4", "item3"])
        XCTAssertTrue(try controller.ensureVisible(path: root.appendingPathComponent("item1").path))
        XCTAssertEqual(controller.results.count, 4)
        try FileManager.default.removeItem(at: root.appendingPathComponent("item1"))
        try await service.refreshSample()
        await controller.refreshCurrentQuery()
        XCTAssertEqual(controller.totalCount, 3)
        XCTAssertFalse(try controller.ensureVisible(path: root.appendingPathComponent("item1").path))
        controller.invalidate()
        await controller.refreshCurrentQuery()
        XCTAssertNil(controller.snapshot)
    }
}

private actor RefreshGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var enabled = false
    func enable() { enabled = true }
    func waitIfEnabled() async {
        if enabled { await withCheckedContinuation { continuation = $0 } }
    }
    func isWaiting() -> Bool { continuation != nil }
    func release() { enabled = false; continuation?.resume(); continuation = nil }
}

extension LiveRefreshTests {
    @MainActor
    func testLateRefreshCannotReplaceNewQueryAndItsNextRefreshConfiguration() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/sample")
        let service = try FsearchService(sampleDirectory: root)
        let gate = RefreshGate()
        let controller = SnapshotQueryController { request, sort, maximum, _ in
            let snapshot = try await service.snapshot(request, sort: sort, maximumResults: maximum)
            if request.query == "report" { await gate.waitIfEnabled() }
            return snapshot
        }
        await controller.query(SearchRequest(id: "same-id", query: "report"), pageSize: 1)
        await gate.enable()
        let oldRefresh = Task { await controller.refreshCurrentQuery() }
        while !(await gate.isWaiting()) { await Task.yield() }
        await controller.query(SearchRequest(id: "same-id", query: "other"), sort: .descending)
        let newestID = controller.snapshot?.id
        await gate.release()
        await oldRefresh.value
        XCTAssertEqual(controller.snapshot?.id, newestID)
        await controller.refreshCurrentQuery()
        XCTAssertEqual(controller.snapshot?.sort, .descending)
        XCTAssertEqual(controller.results.map { URL(fileURLWithPath: $0.path).lastPathComponent }, ["other.swift"])
    }
}
