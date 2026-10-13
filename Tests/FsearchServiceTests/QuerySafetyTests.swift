import Foundation
import Darwin
@_spi(Testing) import FsearchService
import XCTest

final class QuerySafetyTests: XCTestCase {
    private func withSample(_ body: (URL) async throws -> Void) async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/query-safety/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(root)
    }

    func testOrdinaryNamesKeepPunctuationAsData() async throws {
        try await withSample { root in
            let names = ["ext:txt.md", "two words.txt", "say\"hello.txt", "line\nbreak.txt", "[draft]*?.txt"]
            for name in names + ["ordinary.txt"] {
                try Data("sample".utf8).write(to: root.appendingPathComponent(name))
            }
            let service = try FsearchService(sampleDirectory: root)
            for name in names {
                let response = try await service.search(SearchRequest(query: name))
                XCTAssertEqual(response.results.map { URL(fileURLWithPath: $0.path).lastPathComponent }, [name])
            }
        }
    }

    func testNameSearchMatchesBothUnicodeNormalizationForms() async throws {
        try await withSample { root in
            let name = "cafe\u{301}-笔记😀.txt"
            try Data("sample".utf8).write(to: root.appendingPathComponent(name))
            let service = try FsearchService(sampleDirectory: root)
            for query in ["café", "cafe\u{301}", "笔记😀"] {
                let response = try await service.search(SearchRequest(query: query))
                XCTAssertEqual(response.results.map { URL(fileURLWithPath: $0.path).lastPathComponent }, [name])
            }
        }
    }

    func testInvalidRequestsAreSanitizedAndServiceRecovers() async throws {
        try await withSample { root in
            try Data("sample".utf8).write(to: root.appendingPathComponent("safe.txt"))
            let service = try FsearchService(sampleDirectory: root)
            let privateQuery = "re:[/private/secret-document-body"
            let invalid = [SearchRequest(id: "", query: "safe"),
                           SearchRequest(query: "safe\u{0}"),
                           SearchRequest(query: privateQuery, mode: .advanced),
                           SearchRequest(query: "grep:secret-document-body", mode: .advanced)]
            for request in invalid {
                do {
                    _ = try await service.search(request)
                    XCTFail("Invalid request must fail")
                } catch FsearchError.query(let message) {
                    XCTAssertFalse(message.contains("secret-document-body"))
                    XCTAssertFalse(message.contains(root.path))
                }
                let recovered = try await service.search(SearchRequest(query: "safe"))
                XCTAssertEqual(recovered.results.count, 1)
            }
            for mode in [SearchMode.contains, .advanced] {
                let empty = try await service.search(SearchRequest(query: " \n", mode: mode))
                XCTAssertTrue(empty.results.isEmpty)
            }
        }
    }

    #if DEBUG
    func testActualRustPanicBecomesRecoverableBridgeError() async throws {
        try await withSample { root in
            try Data("sample".utf8).write(to: root.appendingPathComponent("safe.txt"))
            let service = try FsearchService(sampleDirectory: root)
            do {
                try await service.injectQueryPanic()
                XCTFail("Injected Rust panic must become an error")
            } catch FsearchError.bridge(let message) {
                XCTAssertEqual(message, "Fsearch query failed inside Rust")
            }
            let response = try await service.search(SearchRequest(query: "safe"))
            XCTAssertEqual(response.results.count, 1)
        }
    }
    #endif

    func testRepeatedQueriesAndServiceReleaseHaveBoundedResourceGrowth() async throws {
        try await withSample { root in
            try Data("sample".utf8).write(to: root.appendingPathComponent("safe-笔记😀.txt"))
            for _ in 0..<100 { try await runServiceBatch(root, count: 10) }
            let baseline = try residentPeak()
            try await runServiceBatch(root, count: 5_000)
            for _ in 0..<200 { try await runServiceBatch(root, count: 10) }
            let final = try residentPeak()
            let growth = max(0, final - baseline)
            print("QuerySafety resources: 7000 queries, 201 released services; peak RSS baseline=\(baseline), final=\(final), growth=\(growth) bytes")
            XCTAssertLessThan(growth, 64 * 1024 * 1024)
        }
    }

    private func runServiceBatch(_ root: URL, count: Int) async throws {
        let service = try FsearchService(sampleDirectory: root)
        for _ in 0..<count {
            let response = try await service.search(SearchRequest(query: "笔记😀"))
            XCTAssertEqual(response.results.count, 1)
        }
        // The only handle owner leaves scope here; its deinit frees the Rust sample.
    }

    private func residentPeak() throws -> Int {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else {
            throw FsearchError.bridge("Cannot measure process resources")
        }
        return usage.ru_maxrss // macOS reports bytes, not KiB.
    }
}
