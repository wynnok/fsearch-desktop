import Darwin
import Foundation
import FsearchService
import XCTest

final class PermissionCoverageTests: XCTestCase {
    func testDefaultEngineEntryRejectsNonDedicatedEnvironmentBeforeCreatingIndex() throws {
        let previousPermissionEnvironment = ProcessInfo.processInfo.environment["FSEARCH_PERMISSION_ENV"]
        let previousWorkspace = ProcessInfo.processInfo.environment["FSEARCH_PERMISSION_WORKSPACE"]
        unsetenv("FSEARCH_PERMISSION_ENV")
        unsetenv("FSEARCH_PERMISSION_WORKSPACE")
        defer {
            restore("FSEARCH_PERMISSION_ENV", value: previousPermissionEnvironment)
            restore("FSEARCH_PERMISSION_WORKSPACE", value: previousWorkspace)
        }

        let index = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/permission-test-index/\(UUID().uuidString)", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: index.path))

        XCTAssertThrowsError(try FsearchService(realEngineIndexDirectory: index)) { error in
            guard case FsearchError.initialization(let message) = error else {
                return XCTFail("Expected initialization error, got \(error)")
            }
            XCTAssertTrue(message.contains("FSEARCH_PERMISSION_ENV"), message)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: index.path))
    }

    func testReportRequiresSignatureAndEveryPermissionPhase() {
        let complete = PermissionValidationPhase.allCases.map { evidence(for: $0) }
        let verified = PermissionValidationReport.evaluate(signature: signature(), probes: complete)
        XCTAssertEqual(verified.gate, PermissionValidationReport.Gate.verified)
        XCTAssertTrue(verified.reasons.isEmpty)

        let missingSignature = PermissionValidationReport.evaluate(signature: nil, probes: complete)
        XCTAssertEqual(missingSignature.gate, PermissionValidationReport.Gate.unverified)
        XCTAssertTrue(missingSignature.reasons.contains { $0.contains("signature") })

        let missingPhase = PermissionValidationReport.evaluate(
            signature: signature(),
            probes: complete.filter { $0.phase != PermissionValidationPhase.revoke }
        )
        XCTAssertEqual(missingPhase.gate, PermissionValidationReport.Gate.unverified)
        XCTAssertTrue(missingPhase.reasons.contains { $0.contains("revoke") })
    }

    func testFullDiskAccessDoesNotReplaceProtectedLocationHit() {
        var probes = PermissionValidationPhase.allCases.map { evidence(for: $0) }
        let grantIndex = try! XCTUnwrap(probes.firstIndex { $0.phase == PermissionValidationPhase.grant })
        probes[grantIndex] = evidence(for: .grant, fullDiskAccess: true, searchMatched: false)

        let report = PermissionValidationReport.evaluate(signature: signature(), probes: probes)
        XCTAssertEqual(report.gate, PermissionValidationReport.Gate.unverified)
        XCTAssertTrue(report.reasons.contains { $0.contains("grant") && $0.contains("search") })
    }

    func testMaterializedICloudPlaceholderKeepsGateUnverified() {
        var probes = PermissionValidationPhase.allCases.map { evidence(for: $0) }
        let grantIndex = try! XCTUnwrap(probes.firstIndex { $0.phase == PermissionValidationPhase.grant })
        probes[grantIndex] = evidence(for: .grant, iCloudMaterialization: .materialized)

        let report = PermissionValidationReport.evaluate(signature: signature(), probes: probes)
        XCTAssertEqual(report.gate, PermissionValidationReport.Gate.unverified)
        XCTAssertTrue(report.reasons.contains { $0.contains("iCloud") })
    }

    func testMissingSentinelCannotPassAnyPhase() {
        var probes = PermissionValidationPhase.allCases.map { evidence(for: $0) }
        let skipIndex = try! XCTUnwrap(probes.firstIndex { $0.phase == PermissionValidationPhase.skip })
        probes[skipIndex] = evidence(for: .skip, exists: false)

        let report = PermissionValidationReport.evaluate(signature: signature(), probes: probes)
        XCTAssertEqual(report.gate, PermissionValidationReport.Gate.unverified)
        XCTAssertTrue(report.reasons.contains { $0.contains("skip") && $0.contains("does not exist") })
    }

    func testUnsettledContentIndexCannotPass() {
        for unsettled in [
            evidence(for: .grant, contentPending: 1),
            evidence(for: .grant, contentSettled: false, contentSettleReason: "timeout"),
            evidence(
                for: .grant,
                contentDocs: 0,
                contentPending: 0,
                contentSettled: false,
                contentSettleReason: "contentDocs=0; contentPending=0"
            )
        ] {
            var probes = PermissionValidationPhase.allCases.map { evidence(for: $0) }
            let grantIndex = try! XCTUnwrap(
                probes.firstIndex { $0.phase == PermissionValidationPhase.grant }
            )
            probes[grantIndex] = unsettled
            let report = PermissionValidationReport.evaluate(signature: signature(), probes: probes)
            XCTAssertEqual(report.gate, PermissionValidationReport.Gate.unverified)
            XCTAssertTrue(report.reasons.contains { $0.contains("grant") && $0.contains("content") })
        }
    }

    private func evidence(
        for phase: PermissionValidationPhase,
        exists: Bool = true,
        fullDiskAccess: Bool = false,
        searchMatched: Bool? = nil,
        contentDocs: Int? = 1,
        contentPending: Int = 0,
        contentSettled: Bool = true,
        contentSettleReason: String? = nil,
        iCloudMaterialization: PermissionICloudMaterialization = .notMaterialized
    ) -> PermissionProbeEvidence {
        let expectedMatch = phase == .grant || phase == .recheck || phase == .restart
        let location = PermissionProtectedLocationEvidence(
            name: "protected",
            path: "/Users/example/Library/Application Support/protected",
            exists: exists,
            directReadable: searchMatched ?? expectedMatch,
            searchMatched: searchMatched ?? expectedMatch,
            searchComplete: true
        )
        let stat = PermissionICloudStat(
            exists: true,
            size: 42,
            isUbiquitous: true,
            downloadingStatus: "notDownloaded",
            error: nil
        )
        let iCloud = PermissionICloudEvidence(
            configured: true,
            path: "/Users/example/Library/Mobile Documents/example.icloud",
            materialization: iCloudMaterialization,
            before: stat,
            after: stat,
            reason: nil
        )
        return PermissionProbeEvidence(
            phase: phase,
            timestamp: "2026-10-13T00:00:00Z",
            status: ServiceStatus(
                mode: "engine",
                ready: true,
                engineValidated: true,
                upstreamVersion: "0.2.1 / test",
                owner: true,
                entries: 10,
                dirs: 2,
                indexBytes: 1024,
                contentDocs: contentDocs,
                contentSegments: 1,
                contentBytes: 512,
                contentPending: contentPending,
                fullDiskAccess: fullDiskAccess
            ),
            locations: [location],
            iCloud: iCloud,
            contentSettled: contentSettled,
            contentSettleReason: contentSettleReason
        )
    }

    private func signature() -> PermissionSignatureEvidence {
        PermissionSignatureEvidence(
            appPath: "/Applications/FsearchSample.app",
            signingAuthority: "Developer ID Application: Example (TEAMID)",
            teamIdentifier: "TEAMID",
            codesignVerified: true,
            developerIDApplication: true
        )
    }

    private func restore(_ name: String, value: String?) {
        if let value {
            setenv(name, value, 1)
        } else {
            unsetenv(name)
        }
    }
}
