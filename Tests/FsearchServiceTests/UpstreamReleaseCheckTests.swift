import Foundation
import XCTest

final class UpstreamReleaseCheckTests: XCTestCase {
    func testControlledUpstreamReleaseCheckSuite() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let testScript = projectRoot
            .appendingPathComponent("scripts/tests/test-check-upstream-release.sh")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [testScript.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        let details = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, details)
    }
}
