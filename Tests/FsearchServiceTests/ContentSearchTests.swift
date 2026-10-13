import Foundation
import XCTest

final class ContentSearchTests: XCTestCase {
    func testRealEngineLiteralContentJourneyInIndependentProcess() throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let root = project.appendingPathComponent(".build/content-tests/\(UUID().uuidString)")
        let fixtures = root.appendingPathComponent("fixtures")
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("excluded sentinel".utf8).write(to: root.appendingPathComponent("confinement-denied.txt"))
        try Data("银河😀 first\r\n银河😀 second\r\n".utf8).write(to: fixtures.appendingPathComponent("first.txt"))
        try Data("unrelated text".utf8).write(to: fixtures.appendingPathComponent("second.md"))
        try Data("银河😀 unsupported document".utf8).write(to: fixtures.appendingPathComponent("unsupported.pdf"))
        let process = Process()
        process.executableURL = project.appendingPathComponent(".build/debug/FsearchEngineCheck")
        process.arguments = [root.path, "content"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let result = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, result)
        XCTAssertTrue(result.contains("CONTENT_VALIDATION_PASSED"), result)
    }
}
