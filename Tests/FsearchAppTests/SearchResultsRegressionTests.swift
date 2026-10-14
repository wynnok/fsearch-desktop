import Foundation
import XCTest
@testable import FsearchSample

@MainActor
final class SearchResultsRegressionTests: XCTestCase {
    func testChangingScopeBeforeEnteringQueryDoesNotAutomaticallyEnumerateFolder() async throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let root = project.appendingPathComponent(".build/result-regression/\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = project.appendingPathComponent("fixtures/sample")
        let model = SearchModel(arguments: ["FsearchSample", fixture.path],
                                preferences: LocalPreferences(url: root.appendingPathComponent("preferences.json")))
        model.query = ""
        model.configuration.scope = .folder(fixture.path)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertEqual(model.statusKind, .prompt)
        await model.search()
        XCTAssertFalse(model.results.isEmpty, "Explicit scope-only queries must remain available")
    }

    func testNormalLaunchShows157MatchesWithoutTwoRowPagination() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/result-regression/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 1...157 {
            try Data("fixture".utf8).write(to: root.appendingPathComponent("claude\(index).txt"))
        }
        let model = SearchModel(arguments: ["FsearchSample", root.path],
                                preferences: LocalPreferences(url: root.appendingPathComponent("preferences.json")))
        model.query = "claude"
        await model.search()
        XCTAssertEqual(model.results.count, 157)
        XCTAssertNil(model.nextCursor)
        XCTAssertTrue(model.message.contains("157 / 157"))
    }
}
