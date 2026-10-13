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
        let highlighted = result.files[0].lines[0].nativeRanges
            .map { String(result.files[0].lines[0].text[$0]) }
            .joined()
        try EngineCheck.require(highlighted == "银河😀", "UTF-8 ranges did not convert into native text ranges")

        let literal = try await service.grep(ContentSearchRequest(
            pattern: "a.b",
            mode: .literal,
            scopePath: fixture.appendingPathComponent("options").path
        ))
        try EngineCheck.require(literal.files.map(\.path) == [
            fixture.appendingPathComponent("options/literal.txt").path
        ], "Literal content mode interpreted punctuation")

        let regex = try await service.grep(ContentSearchRequest(
            pattern: "a[.]b|axb",
            mode: .regex,
            scopePath: fixture.appendingPathComponent("options").path
        ))
        try EngineCheck.require(Set(regex.files.map(\.path)) == Set([
            fixture.appendingPathComponent("options/literal.txt").path,
            fixture.appendingPathComponent("options/regex.txt").path
        ]), "Regex content mode did not match expected candidates")

        let caseFile = fixture.appendingPathComponent("options/case.txt").path
        let smart = try await service.grep(ContentSearchRequest(pattern: "alpha", caseMode: .smart))
        try EngineCheck.require(smart.files.contains { $0.path == caseFile }, "Smart case did not ignore lowercase input")
        let sensitive = try await service.grep(ContentSearchRequest(pattern: "ALPHA", caseMode: .sensitive))
        try EngineCheck.require(!sensitive.files.contains { $0.path == caseFile }, "Sensitive case ignored letter case")
        let insensitive = try await service.grep(ContentSearchRequest(pattern: "ALPHA", caseMode: .insensitive))
        try EngineCheck.require(insensitive.files.contains { $0.path == caseFile }, "Insensitive case did not match")

        let selected = try await service.grep(ContentSearchRequest(
            pattern: "filter-target",
            limit: 1,
            scopePath: fixture.appendingPathComponent("selected").path,
            showsHidden: false,
            filters: NameSearchFilters(kind: .file, extensions: ["txt"], minimumSize: 1)
        ))
        try EngineCheck.require(selected.files.map(\.path) == [
            fixture.appendingPathComponent("selected/only.txt").path
        ], "Content scope, hidden switch or attribute filters were not reused")

        do {
            _ = try await service.grep(ContentSearchRequest(pattern: "[", mode: .regex))
            throw FsearchError.bridge("Invalid regex unexpectedly succeeded")
        } catch FsearchError.query(let message) {
            try EngineCheck.require(!message.isEmpty, "Invalid regex error lost its reason")
        }
        let recovered = try await service.grep(ContentSearchRequest(pattern: "银河😀"))
        try EngineCheck.require(recovered.files.count == 1, "Invalid regex recovery did not preserve a usable query")

        let firstPage = try await service.grep(ContentSearchRequest(
            pattern: "cursor-match",
            limit: 1,
            scopePath: fixture.appendingPathComponent("pagination").path
        ))
        try EngineCheck.require(firstPage.files.count == 1, "Content cursor fixture did not fill its first page")
        guard let cursor = firstPage.next else {
            throw FsearchError.bridge("Content cursor was not supplied for a limited result")
        }
        var paths = Set(firstPage.files.map(\.path))
        var page = firstPage
        for _ in 0..<3 where page.next != nil {
            page = try await service.grep(ContentSearchRequest(
                pattern: "cursor-match",
                limit: 1,
                scopePath: fixture.appendingPathComponent("pagination").path,
                cursor: page.next
            ))
            let newPaths = Set(page.files.map(\.path))
            try EngineCheck.require(paths.isDisjoint(with: newPaths), "Content cursor repeated a file")
            paths.formUnion(newPaths)
        }
        try EngineCheck.require(paths.count == 3, "Content cursor did not reach every limited page")
        try EngineCheck.require(cursor == firstPage.next, "Content page lost its cursor semantics")

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
        print("CONTENT_VALIDATION_PASSED literal/regex/case/scope/filter/invalid-regex/cursor/Unicode/CRLF/update/unsupported/no-match")
    }
}
