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

    func testActiveFilterCountCountsEnabledSections() {
        var configuration = SearchConfiguration()
        XCTAssertEqual(configuration.activeFilterCount, 0)
        configuration.filters.kind = .file
        XCTAssertEqual(configuration.activeFilterCount, 1)
        configuration.filters.extensions = ["txt", "md"]
        XCTAssertEqual(configuration.activeFilterCount, 2)
        configuration.filters.minimumSize = 1
        configuration.filters.maximumSize = 2
        XCTAssertEqual(configuration.activeFilterCount, 3)
        configuration.filters.modifiedAfter = 1
        XCTAssertEqual(configuration.activeFilterCount, 4)
        configuration.clearFilters()
        XCTAssertEqual(configuration.activeFilterCount, 0)
    }
}
