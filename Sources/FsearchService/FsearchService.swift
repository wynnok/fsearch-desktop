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

    init(directory: URL) throws {
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

    deinit { fsearch_sample_close(pointer) }
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
    private let sampleDirectory: URL

    public init(sampleDirectory: URL) throws {
        handle = try SampleHandle(directory: sampleDirectory)
        self.sampleDirectory = sampleDirectory
    }

    public func refreshSample() throws {
        handle = try SampleHandle(directory: sampleDirectory)
    }

    public func search(_ request: SearchRequest) throws -> SearchResponse {
        try performSearch(request)
    }

    #if DEBUG
    @_spi(Testing) public func injectQueryPanic() throws {
        _ = try performSearch(SearchRequest(query: "sample"), injectPanic: true)
    }
    #endif

    private func performSearch(_ request: SearchRequest, injectPanic: Bool = false) throws -> SearchResponse {
        let json = String(decoding: try JSONEncoder().encode(BridgeRequest(request)), as: UTF8.self)
        let output = json.withCString { input in
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
