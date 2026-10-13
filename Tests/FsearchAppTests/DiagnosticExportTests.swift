import Foundation
import FsearchService
import XCTest
@testable import FsearchSample

final class DiagnosticExportTests: XCTestCase {
    func testFinalExportKeepsFailureCategoryButExcludesRawPathsBodyAndStderr() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/diagnostic-tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("diagnostics.json")
        let report = DiagnosticReport(status: ServiceStatus(mode: "engine", ready: true,
            engineValidated: true, upstreamVersion: "0.2.1", contentPending: 4, fullDiskAccess: false),
            error: FsearchError.bridge("Permission denied: /Users/隐私/逗号,\n秘密正文.txt\n正文秘密"),
            stderr: "ERROR '/Users/用户名/秘密\\路径.txt': line 12 正文秘密")
        try report.write(to: path)
        let data = try Data(contentsOf: path)
        let output = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(output.contains("/Users/"))
        XCTAssertFalse(output.contains("隐私"))
        XCTAssertFalse(output.contains("正文秘密"))
        let decoded = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(decoded["errorCategory"] as? String, "bridge")
        XCTAssertEqual(decoded["engineVersion"] as? String, "0.2.1")
        XCTAssertNotNil(decoded["architecture"])
        XCTAssertNotNil(decoded["systemVersion"])
        XCTAssertFalse(output.contains("stderr"))
    }
}
