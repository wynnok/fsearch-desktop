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

    public init(query: String, mode: NameMatchMode = .contains) {
        self.query = query
        self.mode = mode
    }

    func bridgeRequest(id: String = UUID().uuidString) -> SearchRequest {
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
