import Foundation

public enum ContentPatternMode: String, Codable, Sendable, CaseIterable {
    case literal
    case regex
}

public enum ContentCaseMode: String, Codable, Sendable, CaseIterable {
    case smart
    case sensitive
    case insensitive
}

public struct ContentSearchRequest: Encodable, Sendable {
    public let id: String
    public let pattern: String
    public let mode: ContentPatternMode
    public let caseMode: ContentCaseMode
    public let limit: Int
    public let scopePath: String?
    public let showsHidden: Bool
    public let filters: NameSearchFilters
    public let cursor: Int?

    public init(
        id: String = UUID().uuidString,
        pattern: String,
        mode: ContentPatternMode = .literal,
        caseMode: ContentCaseMode = .smart,
        limit: Int = 100,
        scopePath: String? = nil,
        showsHidden: Bool = true,
        filters: NameSearchFilters = NameSearchFilters(),
        cursor: Int? = nil
    ) {
        self.id = id
        self.pattern = pattern
        self.mode = mode
        self.caseMode = caseMode
        self.limit = limit
        self.scopePath = scopePath
        self.showsHidden = showsHidden
        self.filters = filters
        self.cursor = cursor
    }

    public func validate() throws {
        guard !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !pattern.utf8.contains(0) else {
            throw FsearchError.query("请输入非空文本。")
        }
        guard (1...1000).contains(limit) else {
            throw FsearchError.query("文件数量限制须在 1...1000 内。")
        }
        if let cursor, cursor < 0 {
            throw FsearchError.query("内容续查位置无效。")
        }
        if let scopePath {
            guard scopePath.hasPrefix("/"), !scopePath.utf8.contains(0) else {
                throw FsearchError.query("搜索范围须为绝对路径。")
            }
        }
        try filters.validate()
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case pattern
        case mode
        case caseMode = "case"
        case limit
        case scopePath
        case showsHidden
        case filters
        case cursor
    }
}

public struct ContentLine: Decodable, Sendable {
    public let line: Int
    public let text: String
    public let ranges: [[Int]]

    public init(line: Int, text: String, ranges: [[Int]]) {
        self.line = line
        self.text = text
        self.ranges = ranges
    }
}

public struct ContentFile: Decodable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let lines: [ContentLine]

    public init(path: String, lines: [ContentLine]) {
        self.path = path
        self.lines = lines
    }
}

public struct ContentSearchResponse: Decodable, Sendable {
    public let requestID: String
    public let files: [ContentFile]
    public let candidates: Int
    public let read: Int
    public let complete: Bool
    public let next: Int?
    public let indexed: Bool
    public let error: String?
    public var displayedOccurrences: Int { files.reduce(0) { $0 + $1.lines.reduce(0) { $0 + $1.ranges.count } } }
    public var hasMore: Bool { !complete || next != nil }

    public init(
        requestID: String,
        files: [ContentFile],
        candidates: Int,
        read: Int,
        complete: Bool,
        next: Int?,
        indexed: Bool,
        error: String?
    ) {
        self.requestID = requestID
        self.files = files
        self.candidates = candidates
        self.read = read
        self.complete = complete
        self.next = next
        self.indexed = indexed
        self.error = error
    }
}
