import FsearchService
import XCTest

final class ContentSearchOptionsTests: XCTestCase {
    func testContentRequestCarriesModeCaseScopeAndSharedFilters() throws {
        let request = ContentSearchRequest(
            pattern: "item-[0-9]+",
            mode: .regex,
            caseMode: .sensitive,
            scopePath: "/tmp/fixture",
            showsHidden: false,
            filters: NameSearchFilters(kind: .file, extensions: ["txt"], minimumSize: 12)
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )
        XCTAssertEqual(object["pattern"] as? String, "item-[0-9]+")
        XCTAssertEqual(object["mode"] as? String, "regex")
        XCTAssertEqual(object["case"] as? String, "sensitive")
        XCTAssertEqual(object["scopePath"] as? String, "/tmp/fixture")
        XCTAssertEqual(object["showsHidden"] as? Bool, false)
        XCTAssertEqual((object["filters"] as? [String: Any])?["extensions"] as? [String], ["txt"])
        XCTAssertEqual((object["filters"] as? [String: Any])?["minimumSize"] as? Int, 12)
    }

    func testInvalidOptionsRemainAvailableForCorrection() {
        let request = ContentSearchRequest(
            pattern: "[",
            mode: .regex,
            scopePath: "relative",
            filters: NameSearchFilters(minimumSize: 100, maximumSize: 10)
        )

        XCTAssertEqual(request.pattern, "[")
        XCTAssertEqual(request.mode, .regex)
        XCTAssertThrowsError(try request.validate())
    }
}
