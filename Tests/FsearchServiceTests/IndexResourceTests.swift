import Foundation
import XCTest

final class IndexResourceTests: XCTestCase {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func resourceCheckExecutable() throws -> URL {
        let candidates = [
            projectRoot.appendingPathComponent(".build/debug/FsearchResourceCheck"),
            projectRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/FsearchResourceCheck"),
            projectRoot.appendingPathComponent(".build/x86_64-apple-macosx/debug/FsearchResourceCheck")
        ]
        return try XCTUnwrap(candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) },
                            "FsearchResourceCheck was not built")
    }

    func testSyntheticReportDoesNotClaimDefaultIndexCost() throws {
        let root = projectRoot.appendingPathComponent(
            ".build/index-resource-tests/\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let filenames = ["resource1.txt", "resource2.txt", "resource10.txt"]
        for filename in filenames {
            try Data("resource-content".utf8).write(to: root.appendingPathComponent(filename))
        }
        let output = root.appendingPathComponent("report.json")

        let process = Process()
        process.executableURL = try resourceCheckExecutable()
        process.arguments = ["synthetic", root.path, output.path]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        XCTAssertEqual(process.terminationStatus, 0,
                       String(decoding: errorData, as: UTF8.self))
        let report = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any]
        )
        XCTAssertEqual(report["measurementKind"] as? String, "synthetic-sample")
        XCTAssertEqual(report["isDefaultIndexCost"] as? Bool, false)
        XCTAssertEqual(report["isClientPerformanceGuarantee"] as? Bool, false)
        XCTAssertTrue(report["defaultIndexCostSeconds"] is NSNull)
        XCTAssertNotNil(report["unavailable"] as? [String: String])

        let queries = try XCTUnwrap(report["queries"] as? [[String: Any]])
        let completeQuery = try XCTUnwrap(queries.first { $0["query"] as? String == "resource" })
        XCTAssertEqual(completeQuery["resultCount"] as? Int, filenames.count)
        XCTAssertEqual(report["queryCount"] as? Int, queries.count)
    }

    func testResourceScriptRequiresSettledIdleBeforeFinalReport() throws {
        let script = try String(
            contentsOf: projectRoot.appendingPathComponent("scripts/index-resources.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(script.contains("IDLE_UNSETTLED"))
        XCTAssertTrue(script.contains("FSEARCH_RESOURCE_IDLE_SETTLE_SECONDS"))
        XCTAssertTrue(script.contains(".phases.build.contentSettle.timedOut == false"))
        XCTAssertTrue(script.contains(".phases.idle.contentSettled == true"))
        XCTAssertTrue(script.contains(".phases.idle.externalSamples.sampleCount > 0"))
        XCTAssertTrue(script.contains("Missing required commands"))
        XCTAssertTrue(script.contains("jq --version"))
    }
}
