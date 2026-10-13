import CFsearch
import Foundation

public enum SearchMode: String, Codable, Sendable {
    case contains
    case advanced
}

public struct SearchRequest: Codable, Sendable {
    public let id: String
    public let query: String
    public let limit: Int
    public let mode: SearchMode
    public let collectAll: Bool

    public init(id: String = UUID().uuidString, query: String, limit: Int = 50,
                mode: SearchMode = .contains, collectAll: Bool = false) {
        self.id = id
        self.query = query
        self.limit = limit
        self.mode = mode
        self.collectAll = collectAll
    }
}

public struct SearchResult: Codable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let kind: UInt8
    public let indexedSize: UInt64
    public let modifiedAt: UInt32
    public let score: Int32
}

public struct ServiceStatus: Codable, Sendable {
    public let mode: String
    public let ready: Bool
    public let engineValidated: Bool
    public let upstreamVersion: String
    public let owner: Bool?
    public let entries: Int?
    public let contentPending: Int?
}

public struct IndexChange: Codable, Sendable {
    public let path: String
    public let recursive: Bool
}

public struct SearchResponse: Codable, Sendable {
    public let requestID: String
    public let results: [SearchResult]
    public let status: ServiceStatus
    public let isComplete: Bool
}

public enum FsearchError: Error, Equatable, LocalizedError, Sendable {
    case initialization(String)
    case query(String)
    case bridge(String)

    public var errorDescription: String? {
        switch self {
        case .initialization(let message), .query(let message), .bridge(let message): message
        }
    }
}

// Kept private to the actor: Sendable only permits its nonisolated deinit.
private final class SampleHandle: @unchecked Sendable {
    let pointer: UnsafeMutableRawPointer
    let isEngine: Bool

    init(directory: URL) throws {
        isEngine = false
        guard !directory.path.utf8.contains(0) else {
            throw FsearchError.initialization("样本路径包含 NUL")
        }
        var error: UnsafeMutablePointer<CChar>?
        let handle = directory.path.withCString { fsearch_sample_open($0, &error) }
        defer { if let error { fsearch_string_free(error) } }
        guard let handle else {
            throw FsearchError.initialization(error.map { String(cString: $0) } ?? "无法打开样本")
        }
        pointer = handle
    }

    init(engineDirectory: URL, indexDirectory: URL) throws {
        guard !engineDirectory.path.utf8.contains(0), !indexDirectory.path.utf8.contains(0) else {
            throw FsearchError.initialization("Engine 路径包含 NUL")
        }
        isEngine = true
        var error: UnsafeMutablePointer<CChar>?
        let handle = engineDirectory.path.withCString { directory in
            indexDirectory.path.withCString { fsearch_engine_open(directory, $0, &error) }
        }
        defer { if let error { fsearch_string_free(error) } }
        guard let handle else {
            throw FsearchError.initialization(error.map { String(cString: $0) } ?? "无法启动受限 Engine")
        }
        pointer = handle
    }

    deinit {
        if isEngine { fsearch_engine_close(pointer) } else { fsearch_sample_close(pointer) }
    }
}

private struct BridgeResponse: Decodable {
    let requestID: String
    let results: [SearchResult]
    let status: ServiceStatus
    let error: String?
    let errorKind: String?
    let isComplete: Bool
}

private struct BridgeRequest: Encodable {
    let id: String
    let query: String
    let limit: Int
    let mode: SearchMode
    let collectAll: Bool
    let ordinaryForms: [String]

    init(_ request: SearchRequest) {
        id = request.id
        query = request.query
        limit = request.limit
        mode = request.mode
        collectAll = request.collectAll
        ordinaryForms = [request.query.precomposedStringWithCanonicalMapping,
                         request.query.decomposedStringWithCanonicalMapping]
    }
}

// Actor ownership serializes calls and keeps Rust's handle off the UI thread.
public actor FsearchService {
    private var handle: SampleHandle
    private let sampleDirectory: URL?

    public init(sampleDirectory: URL) throws {
        handle = try SampleHandle(directory: sampleDirectory)
        self.sampleDirectory = sampleDirectory
    }

    // Installs irreversible file-read confinement on this process before Engine
    // starts. Use only in a dedicated validation process, never in the default app.
    public init(confinedEngineDirectory: URL, indexDirectory: URL) throws {
        handle = try SampleHandle(engineDirectory: confinedEngineDirectory, indexDirectory: indexDirectory)
        sampleDirectory = nil
    }

    public func refreshSample() throws {
        guard let sampleDirectory else { throw FsearchError.bridge("真实 Engine 通过变更通知刷新") }
        handle = try SampleHandle(directory: sampleDirectory)
    }

    public func status() throws -> ServiceStatus {
        guard handle.isEngine else { return try search(SearchRequest(query: "")).status }
        return try decodeOwned(fsearch_engine_status(handle.pointer), as: ServiceStatus.self)
    }

    public func changes() throws -> [IndexChange] {
        guard handle.isEngine else { return [] }
        return try decodeOwned(fsearch_engine_changes(handle.pointer), as: [IndexChange].self)
    }

    public func saveIndex() throws {
        guard handle.isEngine else { throw FsearchError.bridge("样本索引不会持久保存") }
        fsearch_engine_save(handle.pointer)
    }

    private func decodeOwned<T: Decodable>(_ output: UnsafeMutablePointer<CChar>?, as type: T.Type) throws -> T {
        guard let output else { throw FsearchError.bridge("桥接未返回响应") }
        defer { fsearch_string_free(output) }
        return try JSONDecoder().decode(type, from: Data(String(cString: output).utf8))
    }

    public func search(_ request: SearchRequest) throws -> SearchResponse {
        try performSearch(request)
    }

    #if DEBUG
    @_spi(Testing) public func injectEngineQueryPanic() throws {
        guard handle.isEngine else { throw FsearchError.bridge("Panic injection requires Engine mode") }
        let response = try decodeOwned(
            fsearch_engine_test_panic(handle.pointer, String(decoding: try JSONEncoder().encode(
                BridgeRequest(SearchRequest(query: "engine-proof"))
            ), as: UTF8.self).withCString { $0 }),
            as: BridgeResponse.self
        )
        if let message = response.error {
            throw response.errorKind == "bridge" ? FsearchError.bridge(message) : FsearchError.query(message)
        }
    }
    #endif

    #if DEBUG
    @_spi(Testing) public func injectQueryPanic() throws {
        _ = try performSearch(SearchRequest(query: "sample"), injectPanic: true)
    }
    #endif

    private func performSearch(_ request: SearchRequest, injectPanic: Bool = false) throws -> SearchResponse {
        let json = String(decoding: try JSONEncoder().encode(BridgeRequest(request)), as: UTF8.self)
        let output = json.withCString { input in
            if handle.isEngine { return fsearch_engine_search(handle.pointer, input) }
            #if DEBUG
            if injectPanic { return fsearch_sample_test_panic(handle.pointer, input) }
            #endif
            return fsearch_sample_search(handle.pointer, input)
        }
        guard let output else {
            throw FsearchError.bridge("桥接未返回响应")
        }
        defer { fsearch_string_free(output) }
        let response = try JSONDecoder().decode(
            BridgeResponse.self, from: Data(String(cString: output).utf8)
        )
        guard response.requestID == request.id else {
            throw FsearchError.bridge("响应的请求标识不一致")
        }
        if let error = response.error {
            if response.errorKind == "bridge" { throw FsearchError.bridge(error) }
            throw FsearchError.query(error)
        }
        return SearchResponse(
            requestID: response.requestID, results: response.results, status: response.status,
            isComplete: response.isComplete
        )
    }
}
