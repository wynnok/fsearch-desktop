import Foundation
import XCTest

final class ReleasePreflightTests: XCTestCase {
    func testReleaseCommandRejectsMissingOrStaleAcceptance() throws {
        let result = try runBash(arguments: [root.appendingPathComponent("scripts/tests/test-release-preflight.sh").path])
        XCTAssertEqual(result.status, 0, result.output)
    }

    func testUnsignedReleaseVersionMatchesTag() throws {
        let script = root.appendingPathComponent("scripts/unsigned-release-version.sh")

        let current = try runBash(arguments: [script.path, "v0.1.1-unsigned"])
        XCTAssertEqual(current.status, 0)
        XCTAssertEqual(current.output.trimmingCharacters(in: .whitespacesAndNewlines), "0.1.1")

        let revision = try runBash(arguments: [script.path, "v0.1.0-unsigned.2"])
        XCTAssertEqual(revision.status, 0)
        XCTAssertEqual(revision.output.trimmingCharacters(in: .whitespacesAndNewlines), "0.1.0")

        let stable = try runBash(arguments: [script.path, "v0.1.1"])
        XCTAssertNotEqual(stable.status, 0)

        let leadingZero = try runBash(arguments: [script.path, "v01.1.1-unsigned"])
        XCTAssertNotEqual(leadingZero.status, 0)
    }

    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func runBash(arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }
}
