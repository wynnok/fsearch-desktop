import Combine
import Foundation

public enum ContentSearchPhase: Equatable, Sendable {
    case idle
    case loading
    case partial
    case complete
    case stopped(String)
    case failed(String)
}

@MainActor
public final class ContentSearchController: ObservableObject {
    public typealias Loader = (ContentSearchRequest) async throws -> ContentSearchResponse

    @Published public private(set) var response: ContentSearchResponse?
    @Published public private(set) var files: [ContentFile] = []
    @Published public private(set) var phase: ContentSearchPhase = .idle
    @Published public private(set) var message = "输入文本后查询。"

    public var busy: Bool { phase == .loading }
    public var canLoadMore: Bool { response?.next != nil && !busy }
    public var displayedOccurrences: Int {
        ContentSearchResponse.occurrenceCount(in: files)
    }

    private let loader: Loader
    private var generation = 0
    private var currentRequest: ContentSearchRequest?
    private var removedPaths = RemovedResultPaths()
    private var restartContinuation = false
    private var loadedPageCount = 0

    public init(loader: @escaping Loader) {
        self.loader = loader
    }

    public convenience init(service: FsearchService) {
        self.init { request in
            try await service.grep(request)
        }
    }

    public func search(_ request: ContentSearchRequest) async {
        generation += 1
        let currentGeneration = generation
        currentRequest = request
        restartContinuation = false
        loadedPageCount = 0
        response = nil
        files = []
        phase = .loading
        message = "文本查询中…"

        do {
            let loaded = try await loader(request)
            guard currentGeneration == generation else { return }
            let result = excludingStaleResults(from: loaded)
            response = result
            files = result.files
            loadedPageCount = 1
            finish(result, continued: false)
        } catch {
            guard currentGeneration == generation else { return }
            phase = .failed(error.localizedDescription)
            message = "文本查询失败：\(error.localizedDescription)"
        }
    }

    public func loadMore() async {
        guard let request = currentRequest, let cursor = response?.next else {
            if let response, !response.complete {
                let reason = "上游已停止且未提供续查位置；当前结果可能不完整。"
                phase = .stopped(reason)
                message = reason
            }
            return
        }
        guard !busy else { return }

        generation += 1
        let currentGeneration = generation
        phase = .loading
        message = "继续文本查询中…"
        let restart = restartContinuation
        restartContinuation = false
        do {
            var pageRequest = restart ? request : request.continuing(at: cursor)
            let loaded = try await loader(pageRequest)
            guard currentGeneration == generation else { return }
            var result = excludingStaleResults(from: loaded)
            if restart {
                // Rebuild the loaded window against the new candidate order before publishing it.
                let desiredCount = files.count + request.limit
                var rebuilt: [ContentFile] = []
                var seen: Set<Data> = []
                var pages = 1
                rebuilt.append(contentsOf: result.files.filter { seen.insert(Data($0.path.utf8)).inserted })
                while pages <= loadedPageCount, rebuilt.count < desiredCount,
                      let next = result.next, next > (pageRequest.cursor ?? 0) {
                    pageRequest = request.continuing(at: next)
                    let loaded = try await loader(pageRequest)
                    guard currentGeneration == generation else { return }
                    result = excludingStaleResults(from: loaded)
                    rebuilt.append(contentsOf: result.files.filter { seen.insert(Data($0.path.utf8)).inserted })
                    pages += 1
                }
                files = rebuilt
                loadedPageCount = pages
            } else {
                appendUnique(result.files)
                loadedPageCount += 1
            }
            response = result
            finish(result, continued: true)
        } catch {
            guard currentGeneration == generation else { return }
            restartContinuation = restart
            phase = .failed(error.localizedDescription)
            message = "继续文本查询失败：\(error.localizedDescription)"
        }
    }

    public func removeResults(at path: String) {
        removedPaths.insert(path)
        applyRemoval(affecting: path) { isSameOrDescendantPath($0.path, of: path) }
    }

    package func removeMissingResults(under path: String) async {
        removedPaths.insert(path)
        let requestID = currentRequest?.id
        let missing = await missingPaths(in: files.map(\.path), under: path)
        guard currentRequest?.id == requestID else { return }
        applyRemoval(affecting: path) { missing.contains(Data($0.path.utf8)) }
    }

    private func applyRemoval(affecting path: String, where shouldRemove: (ContentFile) -> Bool) {
        if let scope = currentRequest?.scopePath, !isSameOrDescendantPath(path, of: scope),
           !isSameOrDescendantPath(scope, of: path) { return }
        files.removeAll(where: shouldRemove)
        guard let response else {
            restartContinuation = busy
            return
        }
        let visible = response.removingFiles(where: shouldRemove)
        self.response = visible
        if response.next != nil {
            // The engine cursor is an offset into candidates that can shift after deletion.
            restartContinuation = true
            if busy { generation += 1 }
        }
        if case .failed = phase { return }
        finish(visible, continued: false)
    }

    public func invalidate(message: String) {
        generation += 1
        currentRequest = nil
        restartContinuation = false
        response = nil
        files = []
        phase = .idle
        self.message = message
    }

    private func finish(_ result: ContentSearchResponse, continued: Bool) {
        let source = result.indexed ? "内容索引候选" : "直接读取候选"
        let prefix = continued ? "已继续" : "已显示"
        let counts = "\(files.count) 个文件 · \(prefix) \(displayedOccurrences) 处匹配"
        if let next = result.next {
            phase = .partial
            message = "\(counts) · \(source) · 未完成，可继续（续查位置 \(next)）"
        } else if !result.complete {
            let reason = "上游预算停止且没有续查位置；当前结果可能不完整。"
            phase = .stopped(reason)
            message = "\(counts) · \(source) · \(reason)"
        } else {
            phase = .complete
            message = "\(counts) · \(source) · 本次候选处理完成"
        }
    }

    private func appendUnique(_ newFiles: [ContentFile]) {
        var existing = Set(files.map { Data($0.path.utf8) })
        files.append(contentsOf: newFiles.filter { existing.insert(Data($0.path.utf8)).inserted })
    }

    private func excludingStaleResults(from response: ContentSearchResponse) -> ContentSearchResponse {
        guard let shouldRemove = removedPaths.staleResultPredicate() else { return response }
        return response.removingFiles { shouldRemove($0.path) }
    }
}

private extension ContentSearchResponse {
    func removingFiles(where shouldRemove: (ContentFile) -> Bool) -> ContentSearchResponse {
        ContentSearchResponse(
            requestID: requestID, files: files.filter { !shouldRemove($0) }, candidates: candidates,
            read: read, complete: complete, next: next, indexed: indexed, error: error
        )
    }
}

public extension ContentSearchRequest {
    func continuing(at cursor: Int) -> ContentSearchRequest {
        ContentSearchRequest(
            id: id,
            pattern: pattern,
            mode: mode,
            caseMode: caseMode,
            limit: limit,
            scopePath: scopePath,
            showsHidden: showsHidden,
            filters: filters,
            cursor: cursor
        )
    }
}
