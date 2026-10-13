import Foundation
import FsearchService
import XCTest

final class FsearchServiceTests: XCTestCase {
    private var sampleDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/sample", isDirectory: true)
    }

    func testNameQueryReturnsRealSampleFiles() async throws {
        let service = try FsearchService(sampleDirectory: sampleDirectory)
        let response = try await service.search(SearchRequest(id: "report-query", query: "report"))
        XCTAssertEqual(response.requestID, "report-query")
        XCTAssertEqual(Set(response.results.map { URL(fileURLWithPath: $0.path).lastPathComponent }),
                       ["report2.txt", "report10.txt"])
        for result in response.results {
            XCTAssertEqual(URL(fileURLWithPath: result.path).deletingLastPathComponent(), sampleDirectory)
            let bytes = try Data(contentsOf: URL(fileURLWithPath: result.path))
            XCTAssertEqual(result.indexedSize, UInt64(bytes.count))
            XCTAssertEqual(result.kind, 0)
        }
        XCTAssertEqual(response.status.mode, "sample")
        XCTAssertTrue(response.status.ready)
        XCTAssertFalse(response.status.engineValidated)
        XCTAssertEqual(response.status.upstreamVersion,
                       "0.2.1 / 88e63fdf850cf7749deae8198b187accd21f8ba5")
    }

    func testEmptyInputDoesNotListAllSamples() async throws {
        let service = try FsearchService(sampleDirectory: sampleDirectory)
        let response = try await service.search(SearchRequest(query: "  \n"))
        XCTAssertTrue(response.results.isEmpty)
    }

    func testNoMatchIsASuccessfulEmptyResponse() async throws {
        let service = try FsearchService(sampleDirectory: sampleDirectory)
        let response = try await service.search(SearchRequest(query: "^absent-fixture-name$", mode: .advanced))
        XCTAssertTrue(response.results.isEmpty)
        XCTAssertTrue(response.status.ready)
    }

    func testUnicodeFilenameSurvivesTheBridge() async throws {
        let service = try FsearchService(sampleDirectory: sampleDirectory)
        let response = try await service.search(SearchRequest(query: "笔记"))
        XCTAssertEqual(response.results.map(\.path), [sampleDirectory.appendingPathComponent("笔记😀.md").path])
    }

    func testInvalidQueryIsRecoverable() async throws {
        let service = try FsearchService(sampleDirectory: sampleDirectory)
        do {
            _ = try await service.search(SearchRequest(query: "re:[", mode: .advanced))
            XCTFail("Invalid regex must fail")
        } catch FsearchError.query(let message) {
            XCTAssertFalse(message.isEmpty)
        }
        let response = try await service.search(SearchRequest(query: "report"))
        XCTAssertEqual(response.results.count, 2)
    }

    func testInvalidResultLimitIsRejected() async throws {
        let service = try FsearchService(sampleDirectory: sampleDirectory)
        for limit in [-1, 0, 1001] {
            do {
                _ = try await service.search(SearchRequest(query: "report", limit: limit))
                XCTFail("Unsupported result limit must fail")
            } catch FsearchError.query(let message) {
                XCTAssertFalse(message.isEmpty)
            }
        }
    }

    func testServiceSearchesNewCallerControlledFiles() async throws {
        let directory = sampleDirectory.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/service-fixtures/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let filename = "created-\(UUID().uuidString).txt"
        try Data("live".utf8).write(to: directory.appendingPathComponent(filename))
        let service = try FsearchService(sampleDirectory: directory)
        let response = try await service.search(SearchRequest(query: "^created-", mode: .advanced))
        XCTAssertEqual(response.results.map(\.path), [directory.appendingPathComponent(filename).path])
        XCTAssertEqual(response.results.first?.indexedSize, 4)
    }

    func testRequestedLimitBoundsLoadedResults() async throws {
        let service = try FsearchService(sampleDirectory: sampleDirectory)
        let response = try await service.search(SearchRequest(query: "report", limit: 1))
        XCTAssertEqual(response.results.count, 1)
        XCTAssertTrue(["report2.txt", "report10.txt"].contains(
            URL(fileURLWithPath: try XCTUnwrap(response.results.first).path).lastPathComponent
        ))
    }

    func testMissingSampleDirectoryFailsInitialization() throws {
        let directory = sampleDirectory.appendingPathComponent("absent-\(UUID().uuidString)")
        XCTAssertThrowsError(try FsearchService(sampleDirectory: directory)) { error in
            guard case FsearchError.initialization = error else {
                return XCTFail("Expected initialization error, got \(error)")
            }
        }
    }
}
