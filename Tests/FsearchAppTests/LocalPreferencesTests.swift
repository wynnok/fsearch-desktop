import XCTest
@testable import FsearchSample

@MainActor
final class LocalPreferencesTests: XCTestCase {
    func testRestartRestoresPreferencesWithoutInputOrSelection() throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/preference-tests/\(UUID().uuidString)")
        let store = LocalPreferences(url: directory.appendingPathComponent("preferences.json"))
        var configuration = SearchConfiguration()
        configuration.query = "private query 😀 /Users/tester/Documents/password.txt"
        configuration.nameMode = .prefix
        configuration.sort = .descending
        let selection = SearchSelectionState()
        selection.selectedPath = "/Users/tester/Documents/password.txt"
        selection.isInspectorVisible = false
        try store.save(configuration: configuration, inspectorVisible: selection.isInspectorVisible)
        let reloaded = LocalPreferences(url: store.url)
        var fresh = SearchConfiguration()
        let freshSelection = SearchSelectionState()
        reloaded.restore(configuration: &fresh, selection: freshSelection)
        XCTAssertEqual(fresh.nameMode, .prefix)
        XCTAssertEqual(fresh.sort, .descending)
        XCTAssertFalse(freshSelection.isInspectorVisible)
        XCTAssertNotEqual(fresh.query, configuration.query)
        XCTAssertNil(freshSelection.selectedPath)
        let output = try String(contentsOf: store.url, encoding: .utf8)
        XCTAssertFalse(output.contains("private query"))
        XCTAssertFalse(output.contains("/Users/"))
        try FileManager.default.removeItem(at: directory)
    }

    func testNewApplicationModelRestoresPreferencesButStartsWithFreshQuery() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent(".build/preference-tests/\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalPreferences(url: directory.appendingPathComponent("preferences.json"))
        let arguments = ["FsearchSample", root.appendingPathComponent("fixtures/sample").path]
        let first = SearchModel(arguments: arguments, preferences: store)
        first.query = "private query"
        first.nameMode = .suffix
        first.configuration.showsHidden = false
        first.selection = "/private/selected/file"
        first.permissionStatus.skipOnboarding()
        let restarted = SearchModel(arguments: arguments, preferences: store)
        XCTAssertEqual(restarted.nameMode, .suffix)
        XCTAssertFalse(restarted.configuration.showsHidden)
        XCTAssertFalse(restarted.permissionStatus.showOnboarding)
        XCTAssertEqual(restarted.query, "report")
        XCTAssertNil(restarted.selection)
        XCTAssertTrue(try String(contentsOf: store.url, encoding: .utf8).contains("suffix"))
        XCTAssertFalse(try String(contentsOf: store.url, encoding: .utf8).contains("private"))
    }
}
