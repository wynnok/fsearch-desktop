import FsearchService
import XCTest

final class ContentPaginationTests: XCTestCase {
    func testUTF8ByteRangesBecomeSafeNativeRanges() {
        let text = "a😀e\u{301}b"
        let emoji = ContentLine.nativeRanges(for: [[1, 5]], in: text)
        let combining = ContentLine.nativeRanges(for: [[5, 8]], in: text)
        let truncatedMidScalar = ContentLine.nativeRanges(for: [[2, 4]], in: text)
        let truncatedEnd = ContentLine.nativeRanges(for: [[8, 100]], in: text)

        XCTAssertEqual(emoji.map { String(text[$0]) }, ["😀"])
        XCTAssertEqual(combining.map { String(text[$0]) }, ["e\u{301}"])
        XCTAssertEqual(truncatedMidScalar.map { String(text[$0]) }, ["😀"])
        XCTAssertEqual(truncatedEnd.map { String(text[$0]) }, ["b"])
    }

    @MainActor
    func testControllerContinuesWithSeparateContentCursor() async {
        var requestedCursors: [Int?] = []
        let controller = ContentSearchController { request in
            requestedCursors.append(request.cursor)
            if requestedCursors.count == 1 {
                return Self.response(path: "/tmp/a.txt", next: 7, complete: false)
            }
            return Self.response(path: "/tmp/b.txt", next: nil, complete: true)
        }

        await controller.search(ContentSearchRequest(pattern: "match"))
        await controller.loadMore()

        XCTAssertEqual(requestedCursors, [nil, 7])
        XCTAssertEqual(controller.files.map(\.path), ["/tmp/a.txt", "/tmp/b.txt"])
        XCTAssertEqual(controller.phase, .complete)
    }

    @MainActor
    func testLateContinuationCannotReplaceANewQuery() async {
        var continuation: CheckedContinuation<ContentSearchResponse, Never>?
        let controller = ContentSearchController { request in
            if request.cursor == 4 {
                return await withCheckedContinuation { continuation = $0 }
            }
            return Self.response(path: "/tmp/\(request.pattern).txt", next: request.pattern == "old" ? 4 : nil,
                                 complete: request.pattern != "old")
        }

        await controller.search(ContentSearchRequest(pattern: "old"))
        let late = Task { await controller.loadMore() }
        while continuation == nil { await Task.yield() }
        await controller.search(ContentSearchRequest(pattern: "new"))
        continuation?.resume(returning: Self.response(path: "/tmp/late.txt", next: nil, complete: true))
        await late.value

        XCTAssertEqual(controller.files.map(\.path), ["/tmp/new.txt"])
        XCTAssertEqual(controller.phase, .complete)
    }

    @MainActor
    func testDeletionRestartsAnInFlightContinuationAndFiltersStaleMatches() async {
        let deleted = "/tmp/\(UUID().uuidString)/deleted.txt"
        let old = "/tmp/old-match.txt"
        var late: CheckedContinuation<ContentSearchResponse, Never>?
        var cursors: [Int?] = []
        let controller = ContentSearchController { request in
            cursors.append(request.cursor)
            if request.cursor == 7 {
                return await withCheckedContinuation { late = $0 }
            }
            if cursors.count == 1 { return Self.response(paths: [deleted, old], next: 7, complete: false) }
            if request.cursor == nil { return Self.response(paths: [deleted], next: 4, complete: false) }
            return Self.response(path: "/tmp/survivor.txt", next: nil, complete: true)
        }

        await controller.search(ContentSearchRequest(pattern: "match"))
        let pending = Task { await controller.loadMore() }
        while late == nil { await Task.yield() }
        controller.removeResults(at: deleted)
        XCTAssertEqual(controller.files.map(\.path), [old])
        XCTAssertTrue(controller.canLoadMore)
        XCTAssertEqual(controller.displayedOccurrences, 1)
        late?.resume(returning: Self.response(path: deleted, next: nil, complete: true))
        await pending.value
        XCTAssertEqual(controller.files.map(\.path), [old])
        await controller.loadMore()
        XCTAssertEqual(cursors, [nil, 7, nil, 4])
        XCTAssertEqual(controller.files.map(\.path), ["/tmp/survivor.txt"])
    }

    @MainActor
    func testDeletionOutsideContentScopeKeepsContinuation() async {
        var cursors: [Int?] = []
        let controller = ContentSearchController { request in
            cursors.append(request.cursor)
            if request.cursor == nil { return Self.response(path: "/scope/a.txt", next: 7, complete: false) }
            return Self.response(path: "/scope/b.txt", next: nil, complete: true)
        }
        await controller.search(ContentSearchRequest(pattern: "match", scopePath: "/scope"))
        controller.removeResults(at: "/scope-other/a.txt")
        await controller.loadMore()
        XCTAssertEqual(cursors, [nil, 7])
        XCTAssertEqual(controller.files.map(\.path), ["/scope/a.txt", "/scope/b.txt"])
    }

    @MainActor
    func testIncompleteWithoutCursorIsReportedAsStopped() async {
        let controller = ContentSearchController { _ in
            Self.response(path: "/tmp/a.txt", next: nil, complete: false)
        }

        await controller.search(ContentSearchRequest(pattern: "match"))

        XCTAssertFalse(controller.canLoadMore)
        XCTAssertEqual(controller.phase, .stopped("上游预算停止且没有续查位置；当前结果可能不完整。"))
    }

    private static func response(path: String, next: Int?, complete: Bool) -> ContentSearchResponse {
        response(paths: [path], next: next, complete: complete)
    }

    private static func response(paths: [String], next: Int?, complete: Bool) -> ContentSearchResponse {
        ContentSearchResponse(
            requestID: UUID().uuidString,
            files: paths.map { ContentFile(path: $0, lines: [ContentLine(line: 1, text: "match", ranges: [[0, 5]])]) },
            candidates: paths.count,
            read: paths.count,
            complete: complete,
            next: next,
            indexed: true,
            error: nil
        )
    }
}
