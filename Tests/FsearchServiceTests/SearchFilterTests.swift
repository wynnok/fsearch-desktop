import Foundation
import FsearchService
import XCTest

final class SearchFilterTests: XCTestCase {
    func testScopeAndHiddenSwitchPreserveIndexAndCompletePages() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/filter-fixtures/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("chosen"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["chosen/item1.txt", "chosen/.item2.txt", "item3.txt"] {
            try Data("fixture".utf8).write(to: root.appendingPathComponent(path))
        }
        let service = try FsearchService(sampleDirectory: root)
        let scoped = try await service.snapshot(NameSearchRequest(query: "item", scopePath: root.appendingPathComponent("chosen").path))
        let first = try scoped.page(pageSize: 1)
        XCTAssertEqual(first.totalCount, 2)
        XCTAssertEqual(try scoped.page(after: first.nextCursor, pageSize: 1).results.count, 1)
        let visible = try await service.snapshot(NameSearchRequest(query: "item", showsHidden: false))
        XCTAssertEqual(try visible.page(pageSize: 10).results.map { URL(fileURLWithPath: $0.path).lastPathComponent }, ["item1.txt", "item3.txt"])
        let restored = try await service.snapshot(NameSearchRequest(query: "item"))
        XCTAssertEqual(restored.totalCount, 3)
    }
func testAdvancedFiltersRemainIntactWithoutStructuredOverrides() async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/sample")
    let service = try FsearchService(sampleDirectory: root)
    let snapshot = try await service.snapshot(SearchRequest(query: "kind:dir", mode: .advanced))
    XCTAssertTrue(try snapshot.page(pageSize: 100).results.allSatisfy { $0.kind == 1 })
}

func testFilterOnlyCombinesKindExtensionSizeAndTimeWithInclusiveBounds() async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/filter-fixtures/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root.appendingPathComponent("folder.txt"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let fixtures: [(String, Int, TimeInterval)] = [
        ("keep1.TXT", 7, 1_700_000_000), ("keep2.txt", 9, 1_700_000_100),
        ("large.txt", 10, 1_700_000_050), ("old.txt", 8, 1_699_999_999),
        ("other.md", 8, 1_700_000_050)
    ]
    for (name, size, modified) in fixtures {
        let url = root.appendingPathComponent(name)
        try Data(repeating: 65, count: size).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: modified)], ofItemAtPath: url.path)
    }
    let service = try FsearchService(sampleDirectory: root)
    let filters = NameSearchFilters(kind: .file, extensions: ["TXT"], minimumSize: 7,
                                    maximumSize: 9, modifiedAfter: 1_700_000_000,
                                    modifiedBefore: 1_700_000_100)
    let snapshot = try await service.snapshot(NameSearchRequest(query: "", filters: filters))
    let first = try snapshot.page(pageSize: 1)
    let second = try snapshot.page(after: first.nextCursor, pageSize: 1)
    XCTAssertEqual((first.results + second.results).map { URL(fileURLWithPath: $0.path).lastPathComponent }, ["keep1.TXT", "keep2.txt"])
    XCTAssertEqual(second.totalCount, 2)
    let noMatches = try await service.snapshot(NameSearchRequest(query: "", filters: NameSearchFilters(extensions: ["unknown"])))
    XCTAssertEqual(noMatches.totalCount, 0)
}

func testInvalidRangesReportErrorsRatherThanBroadeningTheQuery() async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/sample")
    let service = try FsearchService(sampleDirectory: root)
    do {
        _ = try await service.snapshot(NameSearchRequest(query: "report", filters: NameSearchFilters(minimumSize: 10, maximumSize: 1)))
        XCTFail("Inverted range should fail")
    } catch let error as FsearchError {
        XCTAssertEqual(error.localizedDescription, "索引大小的最小值不能大于最大值")
    }
}

func testHiddenLimitedResultDoesNotClaimCompleteCollection() async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/sample")
    let service = try FsearchService(sampleDirectory: root)
    let snapshot = try await service.snapshot(NameSearchRequest(query: "", showsHidden: false, filters: NameSearchFilters(kind: .file)), maximumResults: 1)
    XCTAssertEqual(snapshot.loadedCount, 1)
    XCTAssertFalse(snapshot.isComplete)
}

func testStructuredSizeFilterUsesUpstreamIndexedPrecision() async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/filter-fixtures/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("large.bin")
    XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: nil))
    let handle = try FileHandle(forWritingTo: file)
    try handle.truncate(atOffset: 2_147_483_649)
    try handle.close()
    let service = try FsearchService(sampleDirectory: root)
    let indexed = try await service.snapshot(NameSearchRequest(query: "", filters: NameSearchFilters(minimumSize: 2_147_483_648, maximumSize: 2_147_483_648)))
    XCTAssertEqual(indexed.totalCount, 1)
    XCTAssertEqual(try indexed.page().results.first?.indexedSize, 2_147_483_648)
    let actual = try await service.snapshot(NameSearchRequest(query: "", filters: NameSearchFilters(minimumSize: 2_147_483_649, maximumSize: 2_147_483_649)))
    XCTAssertEqual(actual.totalCount, 0)
}

func testNameModesCombineFiltersWithoutInterpretingLiteralPunctuation() async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/filter-fixtures/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for name in ["type:doc.txt", "type:doc.md"] {
        try Data("fixture".utf8).write(to: root.appendingPathComponent(name))
    }
    let service = try FsearchService(sampleDirectory: root)
    for mode in [NameMatchMode.contains, .prefix, .fuzzy] {
        let snapshot = try await service.snapshot(NameSearchRequest(query: "type:doc", mode: mode, filters: NameSearchFilters(extensions: [" .TXT "])))
        XCTAssertEqual(try snapshot.page().results.map { URL(fileURLWithPath: $0.path).lastPathComponent }, ["type:doc.txt"])
    }
}

}
