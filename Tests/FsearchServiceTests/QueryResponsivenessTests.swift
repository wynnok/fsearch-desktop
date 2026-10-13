import Foundation
import FsearchService
import XCTest

private actor RequestGate {
    private var pending: [String: CheckedContinuation<Void, Never>] = [:]

    func wait(_ id: String) async {
        await withCheckedContinuation { pending[id] = $0 }
    }

    func release(_ id: String) { pending.removeValue(forKey: id)?.resume() }
    func contains(_ id: String) -> Bool { pending[id] != nil }
}

final class QueryResponsivenessTests: XCTestCase {
    @MainActor
    func testLoadingPartialFailureAndCancellationAllowAnotherQuery() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/responsiveness-fixtures/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["item1.txt", "item2.txt", "item3.txt"] {
            try Data("fixture".utf8).write(to: root.appendingPathComponent(name))
        }
        let service = try FsearchService(sampleDirectory: root)
        let gate = RequestGate()
        let controller = SnapshotQueryController { request, sort, maximumResults, refresh in
            if request.id == "slow" { await gate.wait(request.id) }
            if refresh { try await service.refreshSample() }
            return try await service.snapshot(request, sort: sort, maximumResults: maximumResults)
        }
        await controller.query(SearchRequest(query: "item"), maximumResults: 1)
        XCTAssertEqual(controller.phase, .partial)
        XCTAssertNil(controller.totalCount)
        let selectedPath = try XCTUnwrap(controller.results.first?.path)
        let slow = Task { await controller.query(SearchRequest(id: "slow", query: "item")) }
        while !(await gate.contains("slow")) { await Task.yield() }
        XCTAssertTrue(controller.isBusy)
        XCTAssertEqual(controller.results.first?.path, selectedPath)
        XCTAssertNil(controller.totalCount)
        XCTAssertNil(controller.nextCursor)
        controller.cancel()
        XCTAssertEqual(controller.phase, .cancelled)
        await controller.query(SearchRequest(query: "re:[", mode: .advanced))
        guard case .failed = controller.phase else { return XCTFail("Invalid query must fail") }
        await controller.query(SearchRequest(query: "item"), pageSize: 1)
        XCTAssertEqual(controller.phase, .complete)
        XCTAssertEqual(controller.totalCount, 3)
        await gate.release("slow")
        await slow.value
        XCTAssertEqual(controller.totalCount, 3)
        XCTAssertEqual(controller.phase, .complete)
    }

    @MainActor
    func testLateOldSnapshotCannotReplaceNewResultsCountOrCursor() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/responsiveness-fixtures/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["old1.txt", "old2.txt", "old3.txt", "new1.txt", "new2.txt"] {
            try Data("fixture".utf8).write(to: root.appendingPathComponent(name))
        }
        let service = try FsearchService(sampleDirectory: root)
        let gate = RequestGate()
        let controller = SnapshotQueryController { request, sort, maximumResults, refresh in
            if refresh { try await service.refreshSample() }
            let result = try await service.snapshot(request, sort: sort, maximumResults: maximumResults)
            if request.id == "old" { await gate.wait(request.id) }
            return result
        }
        let old = Task { await controller.query(SearchRequest(id: "old", query: "old"), pageSize: 1) }
        while !(await gate.contains("old")) { await Task.yield() }
        XCTAssertTrue(controller.isBusy)
        await controller.query(SearchRequest(id: "new", query: "new"), pageSize: 1)
        let newSnapshotID = try XCTUnwrap(controller.snapshot?.id)
        XCTAssertEqual(controller.totalCount, 2)
        XCTAssertEqual(controller.results.map { URL(fileURLWithPath: $0.path).lastPathComponent }, ["new1.txt"])
        await gate.release("old")
        await old.value
        XCTAssertEqual(controller.snapshot?.id, newSnapshotID)
        XCTAssertEqual(controller.totalCount, 2)
        try controller.loadMore(pageSize: 1)
        XCTAssertEqual(controller.results.map { URL(fileURLWithPath: $0.path).lastPathComponent }, ["new1.txt", "new2.txt"])
        XCTAssertNil(controller.nextCursor)
        XCTAssertEqual(controller.phase, .complete)
    }
}
