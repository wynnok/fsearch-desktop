import Foundation
import FsearchService
import XCTest

final class NameSearchModeTests: XCTestCase {
    private func withSample(
        _ paths: [String],
        body: (URL) async throws -> Void
    ) async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/name-mode-fixtures/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for path in paths {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: url)
        }
        try await body(root)
    }

    func testPrefixSuffixAndWholeNameMatchLiteralCaseInsensitiveNames() async throws {
        try await withSample([
            "Alpha Report.txt",
            "Alpha Report.md",
            "draft alpha.txt",
            "Alpha Report.txt.bak"
        ]) { root in
            let service = try FsearchService(sampleDirectory: root)
            let cases: [(NameMatchMode, String, [String])] = [
                (.prefix, "alpha report", ["Alpha Report.md", "Alpha Report.txt", "Alpha Report.txt.bak"]),
                (.suffix, ".TXT", ["Alpha Report.txt", "draft alpha.txt"]),
                (.wholeName, "ALPHA REPORT.TXT", ["Alpha Report.txt"])
            ]

            for (mode, query, expected) in cases {
                let snapshot = try await service.snapshot(NameSearchRequest(query: query, mode: mode))
                XCTAssertEqual(
                    try snapshot.page(pageSize: 20).results.map { URL(fileURLWithPath: $0.path).lastPathComponent },
                    expected,
                    "\(mode.rawValue): \(query)"
                )
            }
        }
    }

    func testFuzzyFindsTypoAndDefaultsToRelevanceOrder() async throws {
        try await withSample(["main.rs", "manifest.txt"]) { root in
            let service = try FsearchService(sampleDirectory: root)
            let snapshot = try await service.snapshot(
                NameSearchRequest(query: "mian.rs", mode: .fuzzy)
            )

            XCTAssertEqual(snapshot.sort.rawValue, "relevance")
            XCTAssertEqual(
                try snapshot.page(pageSize: 20).results.map { URL(fileURLWithPath: $0.path).lastPathComponent },
                ["main.rs"]
            )
        }
    }

    func testLiteralNameModesPreserveQueryLanguagePunctuation() async throws {
        try await withSample([
            "type:doc.txt",
            "quote \"draft\".txt",
            "other.md"
        ]) { root in
            let service = try FsearchService(sampleDirectory: root)

            let prefix = try await service.snapshot(
                NameSearchRequest(query: "type:", mode: .prefix)
            )
            XCTAssertEqual(
                try prefix.page(pageSize: 20).results.map { URL(fileURLWithPath: $0.path).lastPathComponent },
                ["type:doc.txt"]
            )

            let wholeName = try await service.snapshot(
                NameSearchRequest(query: "quote \"draft\".txt", mode: .wholeName),
                sort: .ascending
            )
            XCTAssertEqual(
                try wholeName.page(pageSize: 20).results.map { URL(fileURLWithPath: $0.path).lastPathComponent },
                ["quote \"draft\".txt"]
            )
        }
    }

    func testBlankNameRequestReturnsAnEmptyCompleteSnapshot() async throws {
        try await withSample(["file1.txt", "file2.txt"]) { root in
            let service = try FsearchService(sampleDirectory: root)
            let snapshot = try await service.snapshot(
                NameSearchRequest(query: " \n", mode: .fuzzy)
            )
            let page = try snapshot.page(pageSize: 20)

            XCTAssertTrue(page.results.isEmpty)
            XCTAssertEqual(page.totalCount, 0)
            XCTAssertTrue(page.isComplete)
        }
    }

    @MainActor
    func testControllerAppliesModeDefaultUnlessUserChoseASort() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/name-mode-fixtures/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["file1.txt", "file2.txt"] {
            try Data("fixture".utf8).write(to: root.appendingPathComponent(name))
        }

        let service = try FsearchService(sampleDirectory: root)
        let controller = SnapshotQueryController(service: service)

        await controller.query(NameSearchRequest(query: "file", mode: .fuzzy))
        XCTAssertEqual(controller.snapshot?.sort.rawValue, "relevance")

        await controller.query(
            NameSearchRequest(query: "file", mode: .fuzzy),
            sort: .descending
        )
        XCTAssertEqual(controller.snapshot?.sort.rawValue, "descending")

        await controller.query(NameSearchRequest(query: "file", mode: .contains))
        XCTAssertEqual(controller.snapshot?.sort.rawValue, "ascending")
    }
}
