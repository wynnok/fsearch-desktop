import Foundation

public enum NameSort: String, Sendable {
    case relevance
    case ascending
    case descending
    case sizeAscending
    case sizeDescending
    case modifiedAscending
    case modifiedDescending

    public var ascendingDirection: Bool {
        switch self {
        case .relevance, .ascending, .sizeAscending, .modifiedAscending: true
        case .descending, .sizeDescending, .modifiedDescending: false
        }
    }
}

public enum SnapshotError: Error, Equatable, LocalizedError, Sendable {
    case invalidPageSize
    case foreignCursor
    case invalidMaximumResults

    public var errorDescription: String? {
        switch self {
        case .invalidPageSize: "每页结果数必须大于零"
        case .foreignCursor: "分页位置不属于当前结果快照"
        case .invalidMaximumResults: "结果限制必须大于零"
        }
    }
}

public struct SnapshotCursor: Sendable {
    fileprivate let snapshotID: UUID
    fileprivate let offset: Int
}

public struct SnapshotPage: Sendable {
    public let snapshotID: UUID
    public let requestID: String
    public let results: [SearchResult]
    public let nextCursor: SnapshotCursor?
    public let isComplete: Bool
    public let totalCount: Int?
}

// Owns one immutable result set. Refreshing the service cannot change its pages.
public struct NameSnapshot: Sendable {
    public let id: UUID
    public let requestID: String
    public let isComplete: Bool
    public let sort: NameSort
    public var loadedCount: Int { results.count }
    public var totalCount: Int? { isComplete ? results.count : nil }
    private let results: [SearchResult]

    fileprivate init(response: SearchResponse, sort: NameSort) {
        id = UUID()
        requestID = response.requestID
        isComplete = response.isComplete
        self.sort = sort
        if sort == .relevance {
            results = response.results
            return
        }
        results = response.results.sorted { lhs, rhs in
            let comparison: ComparisonResult
            switch sort {
            case .relevance:
                comparison = .orderedSame
            case .ascending, .descending:
                let leftName = URL(fileURLWithPath: lhs.path).lastPathComponent
                let rightName = URL(fileURLWithPath: rhs.path).lastPathComponent
                comparison = leftName.localizedStandardCompare(rightName)
            case .sizeAscending, .sizeDescending:
                comparison = lhs.indexedSize == rhs.indexedSize ? .orderedSame
                    : lhs.indexedSize < rhs.indexedSize ? .orderedAscending : .orderedDescending
            case .modifiedAscending, .modifiedDescending:
                comparison = lhs.modifiedAt == rhs.modifiedAt ? .orderedSame
                    : lhs.modifiedAt < rhs.modifiedAt ? .orderedAscending : .orderedDescending
            }
            if comparison == .orderedSame {
                // Byte order also separates canonically equivalent Unicode paths.
                return sort.ascendingDirection
                    ? lhs.path.utf8.lexicographicallyPrecedes(rhs.path.utf8)
                    : rhs.path.utf8.lexicographicallyPrecedes(lhs.path.utf8)
            }
            return comparison == (sort.ascendingDirection ? .orderedAscending : .orderedDescending)
        }
    }

    public func page(after cursor: SnapshotCursor? = nil, pageSize: Int = 50) throws -> SnapshotPage {
        guard pageSize > 0 else { throw SnapshotError.invalidPageSize }
        if let cursor, cursor.snapshotID != id { throw SnapshotError.foreignCursor }
        let start = cursor?.offset ?? 0
        let end = start + min(pageSize, results.count - start)
        return SnapshotPage(
            snapshotID: id, requestID: requestID, results: Array(results[start..<end]),
            nextCursor: end < results.count ? SnapshotCursor(snapshotID: id, offset: end) : nil,
            isComplete: isComplete, totalCount: totalCount
        )
    }
}

extension FsearchService {
    public func snapshot(
        _ request: SearchRequest,
        sort: NameSort = .ascending,
        maximumResults: Int? = nil
    ) throws -> NameSnapshot {
        try Task.checkCancellation()
        if let maximumResults, maximumResults <= 0 { throw SnapshotError.invalidMaximumResults }
        let response = try search(SearchRequest(
            id: request.id, query: request.query, limit: maximumResults ?? request.limit,
            mode: request.mode, collectAll: maximumResults == nil,
            scopePath: request.scopePath, showsHidden: request.showsHidden, filters: request.filters
        ))
        return NameSnapshot(response: response, sort: sort)
    }
}
