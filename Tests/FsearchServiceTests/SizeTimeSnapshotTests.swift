import Foundation
import FsearchService
import XCTest

final class SizeTimeSnapshotTests: XCTestCase {
    private func withSample(
        _ files: [(String, UInt64, TimeInterval)],
        body: (URL) async throws -> Void
    ) async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/size-time-fixtures/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (path, size, modifiedAt) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            // Sparse samples cross the encoding boundary without allocating GiB of data.
            try handle.truncate(atOffset: size)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: modifiedAt)],
                                                 ofItemAtPath: url.path)
        }
        try await body(root)
    }

    private func pathsAcrossPages(_ snapshot: NameSnapshot) throws -> [String] {
        var paths: [String] = []
        var cursor: SnapshotCursor?
        repeat {
            let page = try snapshot.page(after: cursor, pageSize: 2)
            XCTAssertEqual(page.snapshotID, snapshot.id)
            XCTAssertTrue(page.isComplete)
            XCTAssertEqual(page.totalCount, snapshot.totalCount)
            paths.append(contentsOf: page.results.map(\.path))
            cursor = page.nextCursor
        } while cursor != nil
        return paths
    }

    func testIndexedSizeOrdersEntireSnapshotWithStablePathTiesAcrossPages() async throws {
        try await withSample([
            ("z.bin", 1, 1_700_000_000), ("a/same.bin", 5, 1_700_000_000),
            ("b/same.bin", 5, 1_700_000_000), ("a.bin", 8, 1_700_000_000),
            ("m.bin", 13, 1_700_000_000)
        ]) { root in
            let service = try FsearchService(sampleDirectory: root)
            let ascending = try await service.snapshot(SearchRequest(query: ".bin"), sort: .sizeAscending)
            let descending = try await service.snapshot(SearchRequest(query: ".bin"), sort: .sizeDescending)
            let expected = ["z.bin", "a/same.bin", "b/same.bin", "a.bin", "m.bin"]
            XCTAssertEqual(try self.pathsAcrossPages(ascending), expected.map { root.appendingPathComponent($0).path })
            XCTAssertEqual(try self.pathsAcrossPages(descending), expected.reversed().map { root.appendingPathComponent($0).path })
            XCTAssertEqual(ascending.totalCount, 5)
            XCTAssertEqual(ascending.sort, .sizeAscending)
        }
    }

    func testModificationTimeOrdersEntireSnapshotWithStablePathTiesAcrossPages() async throws {
        try await withSample([
            ("z.bin", 10, 1_600_000_000), ("a/same.bin", 10, 1_650_000_000),
            ("b/same.bin", 10, 1_650_000_000), ("a.bin", 10, 1_700_000_000),
            ("m.bin", 10, 1_750_000_000)
        ]) { root in
            let service = try FsearchService(sampleDirectory: root)
            let ascending = try await service.snapshot(SearchRequest(query: ".bin"), sort: .modifiedAscending)
            let descending = try await service.snapshot(SearchRequest(query: ".bin"), sort: .modifiedDescending)
            let expected = ["z.bin", "a/same.bin", "b/same.bin", "a.bin", "m.bin"]
            XCTAssertEqual(try self.pathsAcrossPages(ascending), expected.map { root.appendingPathComponent($0).path })
            XCTAssertEqual(try self.pathsAcrossPages(descending), expected.reversed().map { root.appendingPathComponent($0).path })
            XCTAssertEqual(try ascending.page(pageSize: 10).results.map(\.modifiedAt),
                           [1_600_000_000, 1_650_000_000, 1_650_000_000, 1_700_000_000, 1_750_000_000])
            XCTAssertEqual(ascending.totalCount, 5)
            XCTAssertEqual(ascending.sort, .modifiedAscending)
        }
    }

    func testTwoGiBBoundaryUsesIndexedPrecisionForOrderingAndUpstreamFilters() async throws {
        try await withSample([
            ("below.bin", 2_147_483_647, 1_700_000_000),
            ("z-exact.bin", 2_147_483_648, 1_700_000_000),
            ("a-plus-one.bin", 2_147_483_649, 1_700_000_000),
            ("next-bucket.bin", 2_149_580_800, 1_700_000_000)
        ]) { root in
            let service = try FsearchService(sampleDirectory: root)
            let ascending = try await service.snapshot(SearchRequest(query: ".bin"), sort: .sizeAscending)
            let descending = try await service.snapshot(SearchRequest(query: ".bin"), sort: .sizeDescending)
            // a-plus-one precedes z-exact: their indexed sizes are equal despite their actual lengths.
            let expected = ["below.bin", "a-plus-one.bin", "z-exact.bin", "next-bucket.bin"]
            XCTAssertEqual(try self.pathsAcrossPages(ascending), expected.map { root.appendingPathComponent($0).path })
            XCTAssertEqual(try self.pathsAcrossPages(descending), expected.reversed().map { root.appendingPathComponent($0).path })
            XCTAssertEqual(try ascending.page(pageSize: 10).results.map(\.indexedSize),
                           [2_147_483_647, 2_147_483_648, 2_147_483_648, 2_149_580_800])
            let indexedMatch = try await service.snapshot(
                SearchRequest(query: "size:2147483648 ext:bin", mode: .advanced), sort: .sizeAscending
            )
            XCTAssertEqual(try self.pathsAcrossPages(indexedMatch),
                           ["a-plus-one.bin", "z-exact.bin"].map { root.appendingPathComponent($0).path })
            let actualMatch = try await service.snapshot(
                SearchRequest(query: "size:2147483649 ext:bin", mode: .advanced), sort: .sizeAscending
            )
            XCTAssertEqual(actualMatch.totalCount, 0)
        }
    }
}
