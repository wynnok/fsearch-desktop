import Foundation

public struct ContentSearchRequest: Encodable, Sendable {
    public let id: String
    public let pattern: String
    public let limit: Int
    public init(id: String = UUID().uuidString, pattern: String, limit: Int = 100) {
        self.id = id
        self.pattern = pattern
        self.limit = limit
    }
}

public struct ContentLine: Decodable, Sendable {
    public let line: Int
    public let text: String
    public let ranges: [[Int]]
}

public struct ContentFile: Decodable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let lines: [ContentLine]
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
}
