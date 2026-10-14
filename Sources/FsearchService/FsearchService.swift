import CFsearch
import Foundation

public enum SearchMode: String, Codable, Sendable {
    case contains
    case fuzzy
    case advanced
}

public struct SearchRequest: Codable, Sendable {
    public let id: String
    public let query: String
    public let limit: Int
    public let mode: SearchMode
    public let collectAll: Bool
    public let scopePath: String?
    public let showsHidden: Bool
    public let filters: NameSearchFilters

    public init(id: String = UUID().uuidString, query: String, limit: Int = 50,
                mode: SearchMode = .contains, collectAll: Bool = false,
                scopePath: String? = nil, showsHidden: Bool = true,
                filters: NameSearchFilters = NameSearchFilters()) {
        self.id = id
        self.query = query
        self.limit = limit
        self.mode = mode
        self.collectAll = collectAll
        self.scopePath = scopePath
        self.showsHidden = showsHidden
        self.filters = filters
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

public struct ServiceStatus: Codable, Sendable, Equatable {
    public let mode: String
    public let ready: Bool
    public let engineValidated: Bool
    public let upstreamVersion: String
    public let owner: Bool?
    public let entries: Int?
    public let dirs: Int?
    public let indexBytes: Int?
    public let contentDocs: Int?
    public let contentSegments: Int?
    public let contentBytes: Int?
    public let contentPending: Int?
    public let fullDiskAccess: Bool?

    public init(mode: String, ready: Bool, engineValidated: Bool, upstreamVersion: String,
                owner: Bool? = nil, entries: Int? = nil, dirs: Int? = nil,
                indexBytes: Int? = nil, contentDocs: Int? = nil,
                contentSegments: Int? = nil, contentBytes: Int? = nil,
                contentPending: Int? = nil, fullDiskAccess: Bool? = nil) {
        self.mode = mode
        self.ready = ready
        self.engineValidated = engineValidated
        self.upstreamVersion = upstreamVersion
        self.owner = owner
        self.entries = entries
        self.dirs = dirs
        self.indexBytes = indexBytes
        self.contentDocs = contentDocs
        self.contentSegments = contentSegments
        self.contentBytes = contentBytes
        self.contentPending = contentPending
        self.fullDiskAccess = fullDiskAccess
    }
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

public enum PermissionValidationPhase: String, Codable, CaseIterable, Sendable {
    case skip
    case grant
    case recheck
    case restart
    case revoke

    public var expectsProtectedCoverage: Bool {
        switch self {
        case .grant, .recheck, .restart: true
        case .skip, .revoke: false
        }
    }
}

public struct PermissionProtectedLocationEvidence: Codable, Sendable, Equatable {
    public let name: String
    public let path: String
    public let exists: Bool
    public let directReadable: Bool
    public let searchMatched: Bool
    public let searchComplete: Bool

    public init(name: String, path: String, exists: Bool, directReadable: Bool,
                searchMatched: Bool, searchComplete: Bool) {
        self.name = name
        self.path = path
        self.exists = exists
        self.directReadable = directReadable
        self.searchMatched = searchMatched
        self.searchComplete = searchComplete
    }
}

public struct PermissionICloudStat: Codable, Sendable, Equatable {
    public let exists: Bool
    public let size: Int64?
    public let isUbiquitous: Bool?
    public let downloadingStatus: String?
    public let error: String?

    public init(exists: Bool, size: Int64?, isUbiquitous: Bool?,
                downloadingStatus: String?, error: String?) {
        self.exists = exists
        self.size = size
        self.isUbiquitous = isUbiquitous
        self.downloadingStatus = downloadingStatus
        self.error = error
    }
}

public enum PermissionICloudMaterialization: String, Codable, Sendable, Equatable {
    case notMaterialized
    case materialized
    case unverified
}

public struct PermissionICloudEvidence: Codable, Sendable, Equatable {
    public let configured: Bool
    public let path: String?
    public let materialization: PermissionICloudMaterialization
    public let before: PermissionICloudStat?
    public let after: PermissionICloudStat?
    public let reason: String?

    public init(configured: Bool, path: String?,
                materialization: PermissionICloudMaterialization,
                before: PermissionICloudStat?, after: PermissionICloudStat?, reason: String?) {
        self.configured = configured
        self.path = path
        self.materialization = materialization
        self.before = before
        self.after = after
        self.reason = reason
    }
}

public struct PermissionPhaseAssessment: Codable, Sendable, Equatable {
    public let passed: Bool
    public let reasons: [String]

    public init(passed: Bool, reasons: [String]) {
        self.passed = passed
        self.reasons = reasons
    }
}

public struct PermissionProbeEvidence: Codable, Sendable, Equatable {
    public let phase: PermissionValidationPhase
    public let timestamp: String
    public let status: ServiceStatus
    public let locations: [PermissionProtectedLocationEvidence]
    public let iCloud: PermissionICloudEvidence
    public let contentSettled: Bool
    public let contentSettleReason: String?
    public let assessment: PermissionPhaseAssessment

    public init(phase: PermissionValidationPhase, timestamp: String, status: ServiceStatus,
                locations: [PermissionProtectedLocationEvidence],
                iCloud: PermissionICloudEvidence,
                contentSettled: Bool = true,
                contentSettleReason: String? = nil) {
        self.phase = phase
        self.timestamp = timestamp
        self.status = status
        self.locations = locations
        self.iCloud = iCloud
        self.contentSettled = contentSettled
        self.contentSettleReason = contentSettleReason
        assessment = Self.assess(
            phase: phase,
            status: status,
            locations: locations,
            iCloud: iCloud,
            contentSettled: contentSettled,
            contentSettleReason: contentSettleReason
        )
    }

    private enum CodingKeys: String, CodingKey {
        case phase
        case timestamp
        case status
        case locations
        case iCloud
        case contentSettled
        case contentSettleReason
        case assessment
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phase = try container.decode(PermissionValidationPhase.self, forKey: .phase)
        timestamp = try container.decode(String.self, forKey: .timestamp)
        status = try container.decode(ServiceStatus.self, forKey: .status)
        locations = try container.decode([PermissionProtectedLocationEvidence].self, forKey: .locations)
        iCloud = try container.decode(PermissionICloudEvidence.self, forKey: .iCloud)
        contentSettled = try container.decodeIfPresent(Bool.self, forKey: .contentSettled) ?? false
        contentSettleReason = try container.decodeIfPresent(String.self, forKey: .contentSettleReason)
        assessment = Self.assess(
            phase: phase,
            status: status,
            locations: locations,
            iCloud: iCloud,
            contentSettled: contentSettled,
            contentSettleReason: contentSettleReason
        )
    }

    public static func assess(
        phase: PermissionValidationPhase,
        status: ServiceStatus,
        locations: [PermissionProtectedLocationEvidence],
        iCloud: PermissionICloudEvidence,
        contentSettled: Bool,
        contentSettleReason: String?
    ) -> PermissionPhaseAssessment {
        var reasons: [String] = []
        if !status.ready {
            reasons.append("\(phase.rawValue): Engine is not ready")
        }
        if !contentSettled {
            let detail = contentSettleReason.map { ": \($0)" } ?? ""
            reasons.append("\(phase.rawValue): content index did not settle\(detail)")
        } else if status.contentPending != 0 {
            let pending = status.contentPending.map(String.init) ?? "unknown"
            reasons.append("\(phase.rawValue): content index still has \(pending) pending items")
        }
        if locations.isEmpty {
            reasons.append("\(phase.rawValue): no protected locations were recorded")
        }
        for location in locations {
            let label = "\(phase.rawValue):\(location.name)"
            if !location.exists {
                reasons.append("\(label) protected sentinel does not exist")
            }
            if !location.searchComplete {
                reasons.append("\(label) search result is incomplete")
            }
            if phase.expectsProtectedCoverage {
                if !location.directReadable {
                    reasons.append("\(label) direct read did not succeed")
                }
                if !location.searchMatched {
                    reasons.append("\(label) search did not hit the protected sentinel")
                }
            } else {
                if location.directReadable {
                    reasons.append("\(label) direct read succeeded before coverage was expected")
                }
                if location.searchMatched {
                    reasons.append("\(label) search hit the protected sentinel before coverage was expected")
                }
            }
        }
        if !iCloud.configured {
            reasons.append("\(phase.rawValue): iCloud placeholder was not configured")
        } else if iCloud.materialization != .notMaterialized {
            reasons.append("\(phase.rawValue): iCloud placeholder was not proven unmaterialized")
        } else {
            guard let before = iCloud.before, let after = iCloud.after,
                  before.exists, after.exists, before.isUbiquitous == true,
                  after.isUbiquitous == true, let beforeSize = before.size,
                  let afterSize = after.size, beforeSize == afterSize,
                  before.downloadingStatus == "notDownloaded",
                  after.downloadingStatus == "notDownloaded" else {
                reasons.append("\(phase.rawValue): iCloud placeholder stat evidence is incomplete")
                return PermissionPhaseAssessment(passed: false, reasons: reasons)
            }
        }
        return PermissionPhaseAssessment(passed: reasons.isEmpty, reasons: reasons)
    }
}

public struct PermissionSignatureEvidence: Codable, Sendable, Equatable {
    public let appPath: String
    public let signingAuthority: String?
    public let teamIdentifier: String?
    public let codesignVerified: Bool
    public let developerIDApplication: Bool

    public init(appPath: String, signingAuthority: String?, teamIdentifier: String?,
                codesignVerified: Bool, developerIDApplication: Bool) {
        self.appPath = appPath
        self.signingAuthority = signingAuthority
        self.teamIdentifier = teamIdentifier
        self.codesignVerified = codesignVerified
        self.developerIDApplication = developerIDApplication
    }
}

public struct PermissionValidationReport: Codable, Sendable, Equatable {
    public enum Gate: String, Codable, Sendable, Equatable {
        case verified
        case unverified
    }

    public let gate: Gate
    public let reasons: [String]

    public static func evaluate(
        signature: PermissionSignatureEvidence?,
        probes: [PermissionProbeEvidence]
    ) -> PermissionValidationReport {
        var reasons: [String] = []
        if let signature {
            if !signature.codesignVerified || !signature.developerIDApplication
                || signature.signingAuthority?.hasPrefix("Developer ID Application:") != true {
                reasons.append("signature is not a verified Developer ID Application")
            }
        } else {
            reasons.append("signature evidence is missing")
        }
        let grouped = Dictionary(grouping: probes, by: \.phase)
        for phase in PermissionValidationPhase.allCases {
            let matches = grouped[phase] ?? []
            if matches.count != 1 {
                reasons.append("missing or duplicate phase: \(phase.rawValue)")
                continue
            }
            reasons.append(contentsOf: matches[0].assessment.reasons)
        }
        return PermissionValidationReport(
            gate: reasons.isEmpty ? .verified : .unverified,
            reasons: reasons
        )
    }
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

    init(realEngineIndexDirectory: URL) throws {
        guard !realEngineIndexDirectory.path.utf8.contains(0) else {
            throw FsearchError.initialization("Engine 索引路径包含 NUL")
        }
        isEngine = true
        var error: UnsafeMutablePointer<CChar>?
        let handle = realEngineIndexDirectory.path.withCString { index in
            fsearch_real_engine_open(index, &error)
        }
        defer { if let error { fsearch_string_free(error) } }
        guard let handle else {
            throw FsearchError.initialization(
                error.map { String(cString: $0) } ?? "无法启动权限验证 Engine"
            )
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
    let scopePath: String?
    let showsHidden: Bool
    let filters: NameSearchFilters

    init(_ request: SearchRequest) {
        id = request.id
        query = request.query
        limit = request.limit
        mode = request.mode
        collectAll = request.collectAll
        scopePath = request.scopePath
        showsHidden = request.showsHidden
        filters = request.filters
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

    // Starts upstream's default Engine in a dedicated permission-validation
    // workspace. The Rust gate rejects ordinary development processes.
    public init(realEngineIndexDirectory: URL) throws {
        handle = try SampleHandle(realEngineIndexDirectory: realEngineIndexDirectory)
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

    public func grep(_ request: ContentSearchRequest) throws -> ContentSearchResponse {
        guard handle.isEngine else { throw FsearchError.query("样本名称服务不提供正文搜索；需要真实 Engine 模式。") }
        try request.validate()
        let json = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        let response = try json.withCString {
            try decodeOwned(fsearch_engine_grep(handle.pointer, $0), as: ContentSearchResponse.self)
        }
        guard response.requestID == request.id else { throw FsearchError.bridge("正文响应标识不一致") }
        if let error = response.error { throw FsearchError.query(error) }
        return response
    }

    #if DEBUG
    @_spi(Testing) public func injectEngineQueryPanic() throws {
        guard handle.isEngine else { throw FsearchError.bridge("Panic injection requires Engine mode") }
        let json = String(decoding: try JSONEncoder().encode(
            BridgeRequest(SearchRequest(query: "engine-proof"))
        ), as: UTF8.self)
        let response = try json.withCString {
            try decodeOwned(fsearch_engine_test_panic(handle.pointer, $0), as: BridgeResponse.self)
        }
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
