import Foundation
import XCTest
@testable import FsearchSample

final class ApplicationStartupTests: XCTestCase {
    func testFinderLaunchUsesDesktopEngineAndIndependentPersistentIndex() {
        let support = URL(fileURLWithPath: "/Users/test/Library/Application Support")
        let home = URL(fileURLWithPath: "/Users/test")
        let expected = ApplicationStartup.desktop(
            index: URL(fileURLWithPath: "/Users/test/Library/Application Support/FsearchDesktop/index", isDirectory: true),
            home: home
        )
        for arguments in [["/Applications/FsearchDesktop.app/Contents/MacOS/FsearchSample"],
                          ["FsearchSample", "-psn_0_12345"],
                          ["FsearchSample", "-ApplePersistenceIgnoreState", "YES"]] {
            XCTAssertEqual(ApplicationStartup(arguments: arguments, applicationSupport: support, home: home), expected)
        }
    }

    func testExplicitSampleLaunchRetainsConfinedDevelopmentWorkflow() {
        XCTAssertEqual(ApplicationStartup(arguments: ["FsearchSample", "/project/fixtures/sample"],
                                          applicationSupport: URL(fileURLWithPath: "/unused"),
                                          home: URL(fileURLWithPath: "/Users/test")),
                       .sample(URL(fileURLWithPath: "/project/fixtures/sample")))
    }
}
