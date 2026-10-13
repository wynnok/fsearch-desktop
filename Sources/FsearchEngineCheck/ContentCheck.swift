import Foundation
import FsearchService

enum ContentCheck {
    static func run(service: FsearchService, fixture: URL) async throws {
        var response: ContentSearchResponse?
        for _ in 0..<200 {
            response = try await service.grep(ContentSearchRequest(pattern: "银河😀"))
            if response?.files.count == 1 && response?.files.first?.lines.count == 2 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard let result = response else { throw FsearchError.bridge("Content response unavailable") }
        try EngineCheck.require(result.files.map(\.path) == [fixture.appendingPathComponent("first.txt").path], "Content file grouping or document eligibility failed")
        try EngineCheck.require(result.files[0].lines.map(\.line) == [1, 2], "CRLF line numbers changed")
        try EngineCheck.require(result.files[0].lines.map(\.text) == ["银河😀 first", "银河😀 second"], "Unicode or CRLF snippet changed")
        try EngineCheck.require(result.displayedOccurrences == 2, "File and match counts were conflated")
        try EngineCheck.require(result.files[0].lines[0].ranges == [[0, 10]], "Upstream UTF-8 ranges were not preserved")
        let none = try await service.grep(ContentSearchRequest(pattern: "absent-content-pattern"))
        try EngineCheck.require(none.files.isEmpty, "No-match content query returned files")
        try Data("replacement text\r\n".utf8).write(to: fixture.appendingPathComponent("first.txt"))
        var changed = false
        for _ in 0..<200 {
            let updated = try await service.grep(ContentSearchRequest(pattern: "replacement text"))
            if updated.files.first?.lines.first?.text == "replacement text" { changed = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        try EngineCheck.require(changed, "Updated content did not converge")
        let old = try await service.grep(ContentSearchRequest(pattern: "银河😀"))
        try EngineCheck.require(old.files.isEmpty, "Old body still matched after file update")
        print("CONTENT_VALIDATION_PASSED files=1 occurrences=2 Unicode/CRLF/update/unsupported/no-match")
    }
}
