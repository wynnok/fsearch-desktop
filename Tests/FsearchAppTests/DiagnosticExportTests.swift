import Foundation
import FsearchService
import XCTest
@testable import FsearchSample

final class DiagnosticExportTests: XCTestCase {
    func testFinalExportPreservesPinnedEngineVersionAndCommit() async throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let root = project.appendingPathComponent(".build/diagnostic-tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try FsearchService(sampleDirectory: project.appendingPathComponent("fixtures/sample"))
        let status = try await service.status()
        let path = root.appendingPathComponent("diagnostics.json")
        try DiagnosticReport(status: status).write(to: path)
        let decoded = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any]
        XCTAssertEqual(decoded["engineVersion"] as? String, status.upstreamVersion)
        XCTAssertNotEqual(decoded["engineVersion"] as? String, "unknown")
    }

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

    func testFinalExportsKeepActionableCategoriesWithoutUntrustedVersionOrErrorText() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/diagnostic-tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let privateText = "/Users/隐私/秘密, '引号'\n正文-private-marker😀.txt"
        let errors: [(Error?, String)] = [
            (FsearchError.initialization(privateText), "initialization"),
            (FsearchError.query(privateText), "query"),
            (NSError(domain: privateText, code: 1, userInfo: [NSLocalizedDescriptionKey: privateText]), "other"),
            (nil, "none")
        ]
        for (error, category) in errors {
            let report = DiagnosticReport(status: ServiceStatus(mode: privateText, ready: false,
                engineValidated: false, upstreamVersion: "0.2.1 / \(privateText)"),
                error: error, stderr: privateText)
            let file = root.appendingPathComponent("\(category).json")
            try report.write(to: file)
            let data = try Data(contentsOf: file)
            let output = String(decoding: data, as: UTF8.self)
            let decoded = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            XCTAssertEqual(decoded["errorCategory"] as? String, category)
            XCTAssertEqual(decoded["engineVersion"] as? String, "unknown")
            XCTAssertFalse(output.contains("private-marker"))
            XCTAssertFalse(output.contains("隐私"))
            XCTAssertFalse(output.contains("引号"))
            XCTAssertFalse((decoded["errorExplanation"] as? String ?? "").isEmpty)
        }
    }

    func testExportToMissingDirectoryFailsWithoutCreatingReport() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/diagnostic-tests/\(UUID().uuidString)")
        let file = root.appendingPathComponent("missing/diagnostics.json")
        XCTAssertThrowsError(try DiagnosticReport(status: nil).write(to: file))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
