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
    private var currentQuery: (request: SearchRequest, sort: NameSort, maximumResults: Int?, pageSize: Int)?

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
        currentQuery = nil
    }

    public func cancel() {
        invalidate()
        phase = .cancelled
    }

    public func query(_ request: SearchRequest, sort: NameSort = .ascending,
                      maximumResults: Int? = nil, pageSize: Int = 50,
                      refresh: Bool = false) async {
        invalidate()
        currentQuery = (request, sort, maximumResults, pageSize)
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

    public func query(_ request: NameSearchRequest, sort: NameSort? = nil,
                      maximumResults: Int? = nil, pageSize: Int = 50,
                      refresh: Bool = false) async {
        do {
            await query(
                try request.bridgeRequest(),
                sort: sort ?? request.mode.defaultSort,
                maximumResults: maximumResults,
                pageSize: pageSize,
                refresh: refresh
            )
        } catch {
            invalidate()
            phase = .failed(error.localizedDescription)
        }
    }

    public func loadMore(pageSize: Int = 50) throws {
        guard let snapshot, let nextCursor, !isBusy else { return }
        let page = try snapshot.page(after: nextCursor, pageSize: pageSize)
        results.append(contentsOf: page.results)
        self.nextCursor = page.nextCursor
    }

    // The upstream service already applied its notifications; no second watcher.
    public func refreshCurrentQuery() async {
        guard let query = currentQuery, task == nil,
              phase == .complete || phase == .partial else { return }
        let refreshGeneration = generation
        let loader = self.loader
        let work = Task { try await loader(query.request, query.sort, query.maximumResults, false) }
        task = work
        defer { if generation == refreshGeneration { task = nil } }
        do {
            let result = try await work.value
            guard generation == refreshGeneration else { return }
            try Task.checkCancellation()
            guard snapshot?.hasSameResults(as: result) != true else { return }
            let loadedWindow = max(query.pageSize, results.count)
            let page = try result.page(pageSize: loadedWindow)
            snapshot = result
            results = page.results
            nextCursor = page.nextCursor
            phase = result.isComplete ? .complete : .partial
        } catch {
            guard generation == refreshGeneration else { return }
            phase = error is CancellationError ? .cancelled : .failed(error.localizedDescription)
        }
    }

    public func ensureVisible(path: String) throws -> Bool {
        guard let snapshot, !isBusy else { return false }
        if results.contains(where: { $0.path == path }) { return true }
        let all = try snapshot.page(pageSize: max(1, snapshot.loadedCount))
        guard let index = all.results.firstIndex(where: { $0.path == path }) else { return false }
        let page = try snapshot.page(pageSize: max(results.count, index + 1))
        results = page.results
        nextCursor = page.nextCursor
        return true
    }
}
