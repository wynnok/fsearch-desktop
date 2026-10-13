import Foundation

public enum NameMatchMode: String, Codable, Sendable, CaseIterable {
    case contains
    case fuzzy
    case prefix
    case suffix
    case wholeName

    public var defaultSort: NameSort {
        self == .fuzzy ? .relevance : .ascending
    }
}

public struct NameSearchRequest: Codable, Sendable {
    public let query: String
    public let mode: NameMatchMode
    public let scopePath: String?
    public let showsHidden: Bool
    public let filters: NameSearchFilters

    public init(query: String, mode: NameMatchMode = .contains, scopePath: String? = nil,
                showsHidden: Bool = true, filters: NameSearchFilters = NameSearchFilters()) {
        self.query = query
        self.mode = mode
        self.scopePath = scopePath
        self.showsHidden = showsHidden
        self.filters = filters
    }

    func bridgeRequest(id: String = UUID().uuidString) throws -> SearchRequest {
        try filters.validate()
        let nameRequest = nameBridgeRequest(id: id)
        return SearchRequest(id: id, query: nameRequest.query, mode: nameRequest.mode,
                             scopePath: scopePath, showsHidden: showsHidden, filters: filters)
    }

    private func nameBridgeRequest(id: String) -> SearchRequest {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return SearchRequest(id: id, query: "", mode: .contains)
        }
        switch mode {
        case .contains:
            return SearchRequest(id: id, query: query, mode: .contains)
        case .fuzzy:
            return SearchRequest(id: id, query: query, mode: .fuzzy)
        case .prefix:
            return SearchRequest(id: id, query: regexQuery(pattern: "^(?:\(literalAlternatives))"),
                                 mode: .advanced)
        case .suffix:
            return SearchRequest(id: id, query: regexQuery(pattern: "(?:\(literalAlternatives))$"),
                                 mode: .advanced)
        case .wholeName:
            return SearchRequest(id: id, query: regexQuery(pattern: "^(?:\(literalAlternatives))$"),
                                 mode: .advanced)
        }
    }

    private var literalAlternatives: String {
        let composed = query.precomposedStringWithCanonicalMapping
        let decomposed = query.decomposedStringWithCanonicalMapping
        var forms = [composed]
        if decomposed != composed {
            forms.append(decomposed)
        }
        return forms.map(Self.literalRegex).joined(separator: "|")
    }

    private static func literalRegex(_ value: String) -> String {
        NSRegularExpression.escapedPattern(for: value)
            .replacingOccurrences(of: " ", with: "\\x20")
            .replacingOccurrences(of: "\"", with: "\\x22")
    }

    private func regexQuery(pattern: String) -> String {
        "\"re:\(pattern)\""
    }
}

extension FsearchService {
    public func snapshot(
        _ request: NameSearchRequest,
        sort: NameSort? = nil,
        maximumResults: Int? = nil
    ) throws -> NameSnapshot {
        try snapshot(
            request.bridgeRequest(),
            sort: sort ?? request.mode.defaultSort,
            maximumResults: maximumResults
        )
    }
}
