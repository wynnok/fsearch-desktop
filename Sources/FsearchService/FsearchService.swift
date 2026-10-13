import CFsearch
import Foundation

public struct SearchRequest: Codable, Sendable {
    public let id: String
    public let query: String
    public let limit: Int

    public init(id: String = UUID().uuidString, query: String, limit: Int = 50) {
        self.id = id
        self.query = query
        self.limit = limit
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
    // Returned results are bounded by the request limit, not a total count.
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
}

// Actor ownership serializes calls and keeps Rust's handle off the UI thread.
public actor FsearchService {
    private let handle: SampleHandle

    public init(sampleDirectory: URL) throws {
        handle = try SampleHandle(directory: sampleDirectory)
    }

    public func search(_ request: SearchRequest) throws -> SearchResponse {
        let json = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        guard let output = json.withCString({ fsearch_sample_search(handle.pointer, $0) }) else {
            throw FsearchError.bridge("桥接未返回响应")
        }
        defer { fsearch_string_free(output) }
        let response = try JSONDecoder().decode(
            BridgeResponse.self, from: Data(String(cString: output).utf8)
        )
        guard response.requestID == request.id else {
            throw FsearchError.bridge("响应的请求标识不一致")
        }
        if let error = response.error { throw FsearchError.query(error) }
        return SearchResponse(
            requestID: response.requestID, results: response.results, status: response.status
        )
    }
}
