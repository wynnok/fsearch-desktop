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
        response = nil
        files = []
        phase = .loading
        message = "文本查询中…"

        do {
            let result = try await loader(request)
            guard currentGeneration == generation else { return }
            response = result
            files = result.files
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
        do {
            let result = try await loader(request.continuing(at: cursor))
            guard currentGeneration == generation else { return }
            appendUnique(result.files)
            response = result
            finish(result, continued: true)
        } catch {
            guard currentGeneration == generation else { return }
            phase = .failed(error.localizedDescription)
            message = "继续文本查询失败：\(error.localizedDescription)"
        }
    }

    public func invalidate(message: String) {
        generation += 1
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
        let existing = Set(files.map(\.path))
        files.append(contentsOf: newFiles.filter { !existing.contains($0.path) })
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
