import XCTest
@testable import FsearchSample

@MainActor
final class ManualUpdateTests: XCTestCase {
    func testNewReleaseAndNoReleaseAreHonest() async {
        let checker = ManualUpdateState(currentVersion: "0.1.0", fetch: {
            Data(#"{"tag_name":"v0.2.0","html_url":"https://github.com/wynnok/fsearch-desktop/releases/tag/v0.2.0","draft":false,"prerelease":false}"#.utf8)
        })
        await checker.check()
        XCTAssertEqual(checker.phase, .available("0.2.0"))
        let empty = ManualUpdateState(currentVersion: "0.1.0", fetch: { nil })
        await empty.check()
        XCTAssertEqual(empty.phase, .noRelease)
    }

    func testCurrentOlderAndUntrustedResponses() async {
        for (version, expected) in [("0.1.0", UpdatePhase.current), ("0.0.9", .current), ("0.10.0", .available("0.10.0"))] {
            let checker = ManualUpdateState(currentVersion: "0.1.0", fetch: {
                Data("{\"tag_name\":\"v\(version)\",\"html_url\":\"https://github.com/wynnok/fsearch-desktop/releases/tag/v\(version)\",\"draft\":false,\"prerelease\":false}".utf8)
            })
            await checker.check()
            XCTAssertEqual(checker.phase, expected)
        }
        let checker = ManualUpdateState(currentVersion: "0.1.0", fetch: {
            Data(#"{"tag_name":"v2.0.0","html_url":"https://example.com/download","draft":false,"prerelease":false}"#.utf8)
        })
        await checker.check()
        guard case .failed = checker.phase else { return XCTFail("Untrusted URL accepted") }
    }

    func testNetworkFailureDoesNotAdvertiseAnUpdate() async {
        let checker = ManualUpdateState(currentVersion: "0.1.0", fetch: { throw URLError(.notConnectedToInternet) })
        await checker.check()
        guard case .failed = checker.phase else { return XCTFail("Network error hidden") }
    }
}
