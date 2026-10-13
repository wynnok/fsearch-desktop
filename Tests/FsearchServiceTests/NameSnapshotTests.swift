import Foundation
import FsearchService
import XCTest
import Darwin

final class NameSnapshotTests: XCTestCase {
    private func withSample(
        _ paths: [String],
        body: (URL) async throws -> Void
    ) async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/snapshot-fixtures/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for path in paths {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("sample".utf8).write(to: url)
        }
        try await body(root)
    }

    func testNaturalNameOrderAndExactCompleteCount() async throws {
        try await withSample(["file10.txt", "file2.txt", "file1.txt"]) { root in
            let service = try FsearchService(sampleDirectory: root)
            let snapshot = try await service.snapshot(SearchRequest(id: "numbers", query: "file"))
            let page = try snapshot.page(pageSize: 10)
            XCTAssertEqual(page.results.map { URL(fileURLWithPath: $0.path).lastPathComponent },
                           ["file1.txt", "file2.txt", "file10.txt"])
            XCTAssertEqual(snapshot.requestID, "numbers")
            XCTAssertEqual(snapshot.totalCount, 3)
            XCTAssertEqual(snapshot.loadedCount, 3)
            XCTAssertTrue(snapshot.isComplete)
            XCTAssertEqual(page.snapshotID, snapshot.id)
            XCTAssertNil(page.nextCursor)
        }
    }

    func testCompleteLargeSnapshotHasIndependentNaturalOrderAcrossPages() async throws {
        let count = max(25_001, Int(ProcessInfo.processInfo.environment["FSEARCH_SNAPSHOT_COUNT"] ?? "") ?? 25_001)
        let filenames = (1...count).reversed().map { "entry\($0).txt" }
        try await withSample(filenames) { root in
            let openedAt = Date()
            let service = try FsearchService(sampleDirectory: root)
            let openSeconds = Date().timeIntervalSince(openedAt)
            let firstAt = Date()
            let snapshot = try await service.snapshot(SearchRequest(query: "entry"))
            let firstSeconds = Date().timeIntervalSince(firstAt)
            var paths: [String] = []
            var cursor: SnapshotCursor?
            repeat {
                let page = try snapshot.page(after: cursor, pageSize: 317)
                XCTAssertEqual(page.snapshotID, snapshot.id)
                paths.append(contentsOf: page.results.map(\.path))
                cursor = page.nextCursor
            } while cursor != nil
            // Integer order is an independent oracle; no production comparator is reused.
            XCTAssertEqual(paths, (1...count).map { root.appendingPathComponent("entry\($0).txt").path })
            XCTAssertEqual(Set(paths).count, count)
            XCTAssertEqual(snapshot.totalCount, count)
            XCTAssertTrue(snapshot.isComplete)
            var warmSeconds: [Double] = []
            for _ in 0..<5 {
                let start = Date()
                let warm = try await service.snapshot(SearchRequest(query: "entry"))
                warmSeconds.append(Date().timeIntervalSince(start))
                XCTAssertEqual(warm.totalCount, count)
            }
            warmSeconds.sort()
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            print("SNAPSHOT_MEASURE count=\(count) open_s=\(openSeconds) first_snapshot_s=\(firstSeconds) warm_n=5 p50_s=\(warmSeconds[2]) p95_s=\(warmSeconds[4]) process_peak_rss_bytes=\(usage.ru_maxrss)")
        }
    }

    func testNativeNaturalOrderForCaseAccentsChineseEmojiAndPathTies() async throws {
        let files = ["file10.txt", "fíle4.txt", "FILE3.txt", "file2.txt", "笔记10.md", "笔记2.md",
                     "😀10.log", "😀2.log", "b/same.bin", "a/same.bin", "b/cafe\u{301}.pdf", "a/café.pdf"]
        try await withSample(files) { root in
            let service = try FsearchService(sampleDirectory: root)
            let cases: [(String, [String])] = [
                (".txt", ["file2.txt", "FILE3.txt", "fíle4.txt", "file10.txt"]),
                (".md", ["笔记2.md", "笔记10.md"]),
                (".log", ["😀2.log", "😀10.log"]),
                (".bin", ["a/same.bin", "b/same.bin"]),
                (".pdf", ["a/café.pdf", "b/cafe\u{301}.pdf"])
            ]
            for (query, expected) in cases {
                let ascending = try await service.snapshot(SearchRequest(query: query))
                let descending = try await service.snapshot(SearchRequest(query: query), sort: .descending)
                XCTAssertEqual(try ascending.page(pageSize: 20).results.map(\.path),
                               expected.map { root.appendingPathComponent($0).path }, query)
                XCTAssertEqual(try descending.page(pageSize: 20).results.map(\.path),
                               expected.reversed().map { root.appendingPathComponent($0).path }, query)
            }
        }
    }

    func testRefreshQueryAndSortChangesCannotMixSnapshotPages() async throws {
        try await withSample(["entry1.txt", "entry2.txt", "entry3.txt"]) { root in
            let service = try FsearchService(sampleDirectory: root)
            let original = try await service.snapshot(SearchRequest(id: "original", query: "entry"))
            let cursor = try XCTUnwrap(original.page(pageSize: 1).nextCursor)
            try Data("new".utf8).write(to: root.appendingPathComponent("entry0.txt"))
            try FileManager.default.removeItem(at: root.appendingPathComponent("entry2.txt"))
            try await service.refreshSample()
            let refreshed = try await service.snapshot(SearchRequest(id: "refreshed", query: "entry"))
            XCTAssertNotEqual(original.id, refreshed.id)
            XCTAssertEqual(try refreshed.page(pageSize: 10).results.map { URL(fileURLWithPath: $0.path).lastPathComponent },
                           ["entry0.txt", "entry1.txt", "entry3.txt"])
            XCTAssertEqual(try original.page(after: cursor, pageSize: 10).results.map { URL(fileURLWithPath: $0.path).lastPathComponent },
                           ["entry2.txt", "entry3.txt"])
            let changedQuery = try await service.snapshot(SearchRequest(query: "entry3"))
            let changedSort = try await service.snapshot(SearchRequest(query: "entry"), sort: .descending)
            for snapshot in [refreshed, changedQuery, changedSort] {
                XCTAssertThrowsError(try snapshot.page(after: cursor)) { error in
                    XCTAssertEqual(error as? SnapshotError, .foreignCursor)
                }
            }
        }
    }

    func testLimitedLoadedOrderHasNoCompleteCountEvenWhenLastPageIsShort() async throws {
        try await withSample(["file1.txt", "file2.txt", "file3.txt", "file4.txt"]) { root in
            let service = try FsearchService(sampleDirectory: root)
            let limited = try await service.snapshot(SearchRequest(query: "file"), maximumResults: 2)
            let lastPage = try limited.page(pageSize: 50)
            XCTAssertEqual(limited.loadedCount, 2)
            XCTAssertFalse(limited.isComplete)
            XCTAssertNil(limited.totalCount)
            XCTAssertNil(lastPage.nextCursor)
            XCTAssertFalse(lastPage.isComplete)
            XCTAssertNil(lastPage.totalCount)
            let complete = try await service.snapshot(SearchRequest(query: "file"))
            XCTAssertEqual(complete.totalCount, 4)
            XCTAssertTrue(complete.isComplete)
        }
    }

    func testEmptySnapshotAndInvalidPagingOrLimits() async throws {
        try await withSample(["file1.txt"]) { root in
            let service = try FsearchService(sampleDirectory: root)
            let empty = try await service.snapshot(SearchRequest(query: "absent"))
            let page = try empty.page(pageSize: Int.max)
            XCTAssertTrue(page.results.isEmpty)
            XCTAssertEqual(page.totalCount, 0)
            XCTAssertTrue(page.isComplete)
            XCTAssertNil(page.nextCursor)
            for size in [0, -1] {
                XCTAssertThrowsError(try empty.page(pageSize: size)) { error in
                    XCTAssertEqual(error as? SnapshotError, .invalidPageSize)
                }
            }
            for limit in [0, -1] {
                do {
                    _ = try await service.snapshot(SearchRequest(query: "file"), maximumResults: limit)
                    XCTFail("Invalid snapshot limit must fail")
                } catch {
                    XCTAssertEqual(error as? SnapshotError, .invalidMaximumResults)
                }
            }
        }
    }
}
