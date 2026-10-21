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

    func testSampleSmokeOptionsKeepPathsOutOfFileOpenArguments() {
        let directory = "/project/fixtures/sample with spaces"
        let output = "/project/.build/smoke output"
        let arguments = ["FsearchSample", "--sample-directory=\(directory)", "--smoke", "--smoke-output=\(output)"]
        XCTAssertEqual(ApplicationStartup(arguments: arguments,
                                          applicationSupport: URL(fileURLWithPath: "/unused"),
                                          home: URL(fileURLWithPath: "/Users/test")),
                       .sample(URL(fileURLWithPath: directory)))
        XCTAssertEqual(ApplicationStartup.smokeOutput(arguments: arguments),
                       URL(fileURLWithPath: output, isDirectory: true))
        XCTAssertEqual(ApplicationStartup.smokeOutput(arguments: ["FsearchSample", directory, "--smoke", output]),
                       ApplicationStartup.smokeOutput(arguments: arguments))
        XCTAssertNil(ApplicationStartup.smokeOutput(arguments: ["FsearchSample", directory]))
    }
}
