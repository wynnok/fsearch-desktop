@testable import FsearchSample
import FsearchService
import XCTest

final class SearchConfigurationTests: XCTestCase {
    func testEmptyDefaultScopeAndHiddenSwitchDoNotEnumerateIndex() throws {
        var configuration = SearchConfiguration()
        configuration.query = ""
        XCTAssertFalse(configuration.hasEffectiveQuery)
        XCTAssertTrue(configuration.showsHidden)
        configuration.showsHidden = false
        XCTAssertFalse(configuration.hasEffectiveQuery)
        configuration.filters.kind = .directory
        XCTAssertTrue(configuration.hasEffectiveQuery)
        configuration.clearFilters()
        XCTAssertFalse(configuration.hasEffectiveQuery)
        configuration.scope = .home
        XCTAssertTrue(configuration.hasEffectiveQuery)
    }

    func testInvalidConditionsRemainAvailableForCorrection() throws {
        var configuration = SearchConfiguration()
        configuration.query = ""
        configuration.filters.minimumSize = 100
        configuration.filters.maximumSize = 10
        XCTAssertThrowsError(try configuration.request())
        XCTAssertEqual(configuration.filters.minimumSize, 100)
        XCTAssertEqual(configuration.filters.maximumSize, 10)
        configuration.filters.maximumSize = nil
        XCTAssertEqual(try configuration.request().filters.minimumSize, 100)
    }
}
