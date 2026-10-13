import Combine
import Foundation

public enum SnapshotQueryPhase: Equatable, Sendable {
    case idle, loading, complete, partial, cancelled
    case failed(String)
}

// Public UI boundary: only the newest request owns results, count and pagination.
@MainActor
public final class SnapshotQueryController: ObservableObject {
    public typealias Loader = @Sendable (SearchRequest, NameSort, Int?, Bool) async throws -> NameSnapshot
    @Published public private(set) var phase: SnapshotQueryPhase = .idle
    @Published public private(set) var results: [SearchResult] = []
    @Published public private(set) var snapshot: NameSnapshot?
    @Published public private(set) var nextCursor: SnapshotCursor?
    public var isBusy: Bool { phase == .loading }
    public var totalCount: Int? { snapshot?.totalCount }
    private let loader: Loader
    private var generation = 0
    private var task: Task<NameSnapshot, Error>?

    public init(loader: @escaping Loader) { self.loader = loader }

    public convenience init(service: FsearchService) {
        self.init { request, sort, maximumResults, refresh in
            try Task.checkCancellation()
            if refresh { try await service.refreshSample() }
            try Task.checkCancellation()
            return try await service.snapshot(request, sort: sort, maximumResults: maximumResults)
        }
    }

    // Existing rows remain selectable while their count/cursor are invalidated.
    public func invalidate() {
        generation += 1
        task?.cancel()
        task = nil
        snapshot = nil
        nextCursor = nil
        phase = .idle
    }

    public func cancel() {
        invalidate()
        phase = .cancelled
    }

    public func query(_ request: SearchRequest, sort: NameSort = .ascending,
                      maximumResults: Int? = nil, pageSize: Int = 50,
                      refresh: Bool = false) async {
        invalidate()
        let currentGeneration = generation
        phase = .loading
        let loader = self.loader
        let work = Task { try await loader(request, sort, maximumResults, refresh) }
        task = work
        do {
            let result = try await work.value
            guard currentGeneration == generation else { return }
            try Task.checkCancellation()
            let page = try result.page(pageSize: pageSize)
            snapshot = result
            results = page.results
            nextCursor = page.nextCursor
            phase = result.isComplete ? .complete : .partial
        } catch {
            guard currentGeneration == generation else { return }
            phase = error is CancellationError ? .cancelled : .failed(error.localizedDescription)
        }
        if currentGeneration == generation { task = nil }
    }

    public func loadMore(pageSize: Int = 50) throws {
        guard let snapshot, let nextCursor, !isBusy else { return }
        let page = try snapshot.page(after: nextCursor, pageSize: pageSize)
        results.append(contentsOf: page.results)
        self.nextCursor = page.nextCursor
    }
}
