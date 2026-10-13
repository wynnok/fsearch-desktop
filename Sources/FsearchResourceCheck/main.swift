import Darwin
import Foundation
import FsearchService

private enum ResourceCheckFailure: Error, LocalizedError {
    case usage(String)
    case refused(String)
    case measurement(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message), .refused(let message), .measurement(let message): message
        }
    }

    var exitCode: Int32 {
        switch self {
        case .usage, .refused: 2
        case .measurement: 1
        }
    }
}

private struct QuerySpec {
    let query: String
    let mode: SearchMode
    let limit: Int
}

private struct QueryTiming: Encodable {
    let phase: String
    let query: String
    let mode: String
    let seconds: Double
    let resultCount: Int
    let isComplete: Bool
}

private struct Percentiles: Encodable {
    let sampleCount: Int
    let p50Seconds: Double
    let p95Seconds: Double
}

private struct NullableDouble: Encodable {
    let value: Double?

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value {
            try container.encode(value)
        } else {
            try container.encodeNil()
        }
    }
}

private struct NullableUInt64: Encodable {
    let value: UInt64?

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value {
            try container.encode(value)
        } else {
            try container.encodeNil()
        }
    }
}

private struct NullableEngineStatus: Encodable {
    let value: EngineStatusReport?

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value {
            try container.encode(value)
        } else {
            try container.encodeNil()
        }
    }
}

private struct CorpusStats: Encodable {
    let path: String
    let fileCount: Int
    let totalBytes: UInt64
    let indexDirectoryBytes: NullableUInt64
    let unavailable: [String: String]
}

private struct SyntheticReport: Encodable {
    let measurementKind = "synthetic-sample"
    let synthetic = true
    let isDefaultIndexCost = false
    let isClientPerformanceGuarantee = false
    let statement = "This measures the in-memory sample Searcher over an explicit corpus; it is not the cost of the default full index and is not a client performance guarantee."
    let corpus: CorpusStats
    let queryCount: Int
    let queries: [QueryTiming]
    let cold: Percentiles
    let warm: Percentiles
    let defaultIndexCostSeconds = NullableDouble(value: nil)
    let defaultIndexPeakRSSBytes = NullableUInt64(value: nil)
    let unavailable: [String: String]
}

private struct EngineStatusReport: Encodable {
    let mode: String
    let ready: Bool
    let engineValidated: Bool
    let upstreamVersion: String
    let owner: Bool?
    let entries: Int?
    let dirs: Int?
    let indexBytes: Int?
    let contentDocs: Int?
    let contentSegments: Int?
    let contentBytes: Int?
    let contentPending: Int?
    let fullDiskAccess: Bool?
    let unavailable: [String: String]

    private enum CodingKeys: String, CodingKey {
        case mode, ready, engineValidated, upstreamVersion, owner, entries, dirs, indexBytes
        case contentDocs, contentSegments, contentBytes, contentPending, fullDiskAccess, unavailable
    }

    init(_ status: ServiceStatus) {
        mode = status.mode
        ready = status.ready
        engineValidated = status.engineValidated
        upstreamVersion = status.upstreamVersion
        owner = status.owner
        entries = status.entries
        dirs = status.dirs
        indexBytes = status.indexBytes
        contentDocs = status.contentDocs
        contentSegments = status.contentSegments
        contentBytes = status.contentBytes
        contentPending = status.contentPending
        fullDiskAccess = status.fullDiskAccess
        var reasons: [String: String] = [:]
        if status.entries == nil { reasons["entries"] = "The bridge did not return entries." }
        if status.dirs == nil { reasons["dirs"] = "The bridge did not return dirs." }
        if status.indexBytes == nil { reasons["indexBytes"] = "The bridge did not return indexBytes." }
        if status.contentDocs == nil { reasons["contentDocs"] = "The bridge did not return contentDocs." }
        if status.contentSegments == nil {
            reasons["contentSegments"] = "The bridge did not return contentSegments."
        }
        if status.contentBytes == nil { reasons["contentBytes"] = "The bridge did not return contentBytes." }
        if status.contentPending == nil {
            reasons["contentPending"] = "The bridge did not return contentPending."
        }
        if status.fullDiskAccess == nil {
            reasons["fullDiskAccess"] = "The bridge did not return fullDiskAccess."
        }
        unavailable = reasons
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(ready, forKey: .ready)
        try container.encode(engineValidated, forKey: .engineValidated)
        try container.encode(upstreamVersion, forKey: .upstreamVersion)
        try container.encode(owner, forKey: .owner)
        try container.encode(entries, forKey: .entries)
        try container.encode(dirs, forKey: .dirs)
        try container.encode(indexBytes, forKey: .indexBytes)
        try container.encode(contentDocs, forKey: .contentDocs)
        try container.encode(contentSegments, forKey: .contentSegments)
        try container.encode(contentBytes, forKey: .contentBytes)
        try container.encode(contentPending, forKey: .contentPending)
        try container.encode(fullDiskAccess, forKey: .fullDiskAccess)
        try container.encode(unavailable, forKey: .unavailable)
    }
}

private struct ContentSettleReport: Encodable {
    let waitedSeconds: Double
    let timedOut: Bool
    let condition: String
    let status: EngineStatusReport
}

private struct SaveReport: Encodable {
    let requestedAfterSeconds: Double
    let waitSeconds: Double
    let completionObserved: NullableUInt64
    let note: String
}

private struct BuildReport: Encodable {
    let measurementKind = "confined-engine-build"
    let usesDefaultEngineIndexing = true
    let isClientPerformanceGuarantee = false
    let scope = "confined controlled fixture in the project .build directory"
    let workspace: String
    let fixture: String
    let indexDirectory: String
    let readyAfterSeconds: Double
    let peakRSSBytes: UInt64
    let statusAtReady: EngineStatusReport
    let contentSettle: ContentSettleReport
    let warmQueryCount: Int
    let warmQueries: [QueryTiming]
    let warm: Percentiles
    let save: SaveReport
    let statusAfterSave: EngineStatusReport
    let unavailable: [String: String]
}

private struct IdleReport: Encodable {
    let measurementKind = "confined-engine-idle"
    let usesDefaultEngineIndexing = true
    let isClientPerformanceGuarantee = false
    let workspace: String
    let requestedSeconds: Int
    let contentSettled: Bool
    let settleTimeoutSeconds: Double
    let settleWaitedSeconds: Double
    let statusAtReady: EngineStatusReport
    let statusAfterSettle: EngineStatusReport
    let observedSeconds: NullableDouble
    let statusAtIdleStart: NullableEngineStatus
    let statusAfterIdle: NullableEngineStatus
    let queriedDuringIdle = false
    let savedDuringIdle = false
    let unavailable: [String: String]
}

private struct IdleReadyEvent: Encodable {
    let contentSettled = true
    let settleWaitedSeconds: Double
    let status: EngineStatusReport
}

@main
private struct FsearchResourceCheck {
    private static let querySpecs = [
        QuerySpec(query: "resource", mode: .contains, limit: 200),
        QuerySpec(query: "txt", mode: .contains, limit: 200),
        QuerySpec(query: ".txt", mode: .advanced, limit: 200),
        QuerySpec(query: "^absent-resource-token$", mode: .advanced, limit: 200)
    ]

    private static var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private static var buildRoot: URL {
        projectRoot.appendingPathComponent(".build", isDirectory: true)
    }

    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch let failure as ResourceCheckFailure {
            fputs("FsearchResourceCheck: \(failure.localizedDescription)\n", stderr)
            exit(failure.exitCode)
        } catch {
            fputs("FsearchResourceCheck: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run(_ arguments: [String]) async throws {
        guard let command = arguments.first else {
            throw ResourceCheckFailure.usage(
                "Usage: FsearchResourceCheck synthetic <corpusDir> <output.json> | " +
                "build <workspace> <output.json> | idle <workspace> <seconds> <output.json>"
            )
        }
        switch command {
        case "synthetic":
            guard arguments.count == 3 else {
                throw ResourceCheckFailure.usage("Usage: FsearchResourceCheck synthetic <corpusDir> <output.json>")
            }
            try await synthetic(corpusPath: arguments[1], outputPath: arguments[2])
        case "build":
            guard arguments.count == 3 else {
                throw ResourceCheckFailure.usage("Usage: FsearchResourceCheck build <workspace> <output.json>")
            }
            try await build(workspacePath: arguments[1], outputPath: arguments[2])
        case "idle":
            guard arguments.count == 4, let seconds = Int(arguments[2]), seconds >= 0 else {
                throw ResourceCheckFailure.usage(
                    "Usage: FsearchResourceCheck idle <workspace> <seconds> <output.json>"
                )
            }
            try await idle(workspacePath: arguments[1], seconds: seconds, outputPath: arguments[3])
        default:
            throw ResourceCheckFailure.usage("Unknown command: \(command)")
        }
    }

    private static func synthetic(corpusPath: String, outputPath: String) async throws {
        let corpus = try existingDirectory(corpusPath, label: "corpus")
        try requireInside(corpus, projectRoot, label: "corpus")
        try validateOutput(outputPath)

        let service = try FsearchService(sampleDirectory: corpus)
        var samples: [QueryTiming] = []
        for spec in querySpecs {
            samples.append(try await timedQuery(service, spec: spec, phase: "cold"))
        }
        for _ in 0..<5 {
            for spec in querySpecs {
                samples.append(try await timedQuery(service, spec: spec, phase: "warm"))
            }
        }
        let cold = percentileReport(samples.filter { $0.phase == "cold" }.map(\.seconds))
        let warm = percentileReport(samples.filter { $0.phase == "warm" }.map(\.seconds))
        let report = SyntheticReport(
            corpus: try corpusStats(corpus),
            queryCount: samples.count,
            queries: samples,
            cold: cold,
            warm: warm,
            unavailable: [
                "defaultIndexCostSeconds": "Synthetic mode never starts the Engine or builds a default index.",
                "defaultIndexPeakRSSBytes": "Synthetic mode never starts the Engine or builds a default index."
            ]
        )
        try writeJSON(report, to: URL(fileURLWithPath: outputPath))
    }

    private static func build(workspacePath: String, outputPath: String) async throws {
        let workspace = try workspace(at: workspacePath)
        let fixture = try existingDirectory(
            workspace.appendingPathComponent("fixtures").path, label: "workspace fixtures"
        )
        let index = workspace.appendingPathComponent("index", isDirectory: true)
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: true)
        let resolvedIndex = index.resolvingSymlinksInPath()
        try requireSeparate(fixture: fixture, index: resolvedIndex)
        try requireSentinel(in: workspace)
        try validateOutput(outputPath)

        let startedAt = Date()
        let service = try FsearchService(confinedEngineDirectory: fixture, indexDirectory: resolvedIndex)
        let ready = try await waitUntilReady(service, timeout: environmentDouble(
            "FSEARCH_RESOURCE_READY_TIMEOUT", default: 180
        ))
        let readyAfter = Date().timeIntervalSince(startedAt)
        let settleStart = Date()
        let settle = try await waitForContent(service, initial: ready, timeout: environmentDouble(
            "FSEARCH_RESOURCE_CONTENT_TIMEOUT", default: 180
        ))
        let settleReport = ContentSettleReport(
            waitedSeconds: Date().timeIntervalSince(settleStart),
            timedOut: settle.timedOut,
            condition: "contentPending == 0 and contentDocs > 0",
            status: EngineStatusReport(settle.status)
        )

        var warmSamples: [QueryTiming] = []
        let warmRuns = max(1, Int(ProcessInfo.processInfo.environment["FSEARCH_RESOURCE_WARM_RUNS"] ?? "") ?? 5)
        for _ in 0..<warmRuns {
            for spec in querySpecs {
                warmSamples.append(try await timedQuery(service, spec: spec, phase: "warm"))
            }
        }
        let saveRequestedAfter = Date().timeIntervalSince(startedAt)
        try await service.saveIndex()
        let saveWait = environmentDouble("FSEARCH_RESOURCE_SAVE_WAIT", default: 3)
        try await Task.sleep(for: .seconds(saveWait))
        let statusAfterSave = try await service.status()
        let report = BuildReport(
            workspace: workspace.path,
            fixture: fixture.path,
            indexDirectory: resolvedIndex.path,
            readyAfterSeconds: readyAfter,
            peakRSSBytes: peakRSSBytes(),
            statusAtReady: EngineStatusReport(ready),
            contentSettle: settleReport,
            warmQueryCount: warmSamples.count,
            warmQueries: warmSamples,
            warm: percentileReport(warmSamples.map(\.seconds)),
            save: SaveReport(
                requestedAfterSeconds: saveRequestedAfter,
                waitSeconds: saveWait,
                completionObserved: NullableUInt64(value: nil),
                note: "Engine.save() is asynchronous; this only records the bounded wait before process exit."
            ),
            statusAfterSave: EngineStatusReport(statusAfterSave),
            unavailable: [
                "save.completionObserved": "The public Engine API does not expose save completion."
            ]
        )
        try writeJSON(report, to: URL(fileURLWithPath: outputPath))
    }

    private static func idle(workspacePath: String, seconds: Int, outputPath: String) async throws {
        let workspace = try workspace(at: workspacePath)
        let fixture = try existingDirectory(
            workspace.appendingPathComponent("fixtures").path, label: "workspace fixtures"
        )
        let index = try existingDirectory(
            workspace.appendingPathComponent("index").path, label: "workspace index"
        )
        try requireSeparate(fixture: fixture, index: index)
        try requireSentinel(in: workspace)
        try validateOutput(outputPath)

        let service = try FsearchService(confinedEngineDirectory: fixture, indexDirectory: index)
        let ready = try await waitUntilReady(service, timeout: environmentDouble(
            "FSEARCH_RESOURCE_READY_TIMEOUT", default: 180
        ))
        let settleTimeout = environmentDouble("FSEARCH_RESOURCE_IDLE_SETTLE_SECONDS", default: 180)
        let settleStart = Date()
        let settle = try await waitForIdleSettlement(service, initial: ready, timeout: settleTimeout)
        let settleWaited = Date().timeIntervalSince(settleStart)
        guard settle.settled else {
            let contentDocs = settle.status.contentDocs.map(String.init) ?? "null"
            let contentPending = settle.status.contentPending.map(String.init) ?? "null"
            let unsettled = IdleReport(
                workspace: workspace.path,
                requestedSeconds: seconds,
                contentSettled: false,
                settleTimeoutSeconds: settleTimeout,
                settleWaitedSeconds: settleWaited,
                statusAtReady: EngineStatusReport(ready),
                statusAfterSettle: EngineStatusReport(settle.status),
                observedSeconds: NullableDouble(value: nil),
                statusAtIdleStart: NullableEngineStatus(value: nil),
                statusAfterIdle: NullableEngineStatus(value: nil),
                unavailable: [
                    "idle.resourceSamples": "Idle sampling did not start because contentDocs=\(contentDocs) and " +
                        "contentPending=\(contentPending) did not satisfy contentDocs > 0 && contentPending == 0.",
                    "idle.statusAfterIdle": "No post-idle status exists before a settled idle interval."
                ]
            )
            try writeJSON(unsettled, to: URL(fileURLWithPath: outputPath))
            let event = try compactJSON(unsettled)
            try FileHandle.standardOutput.write(contentsOf: Data("IDLE_UNSETTLED \(event)\n".utf8))
            throw ResourceCheckFailure.measurement(
                "Idle content index did not settle within \(settleTimeout) seconds"
            )
        }

        let settleStatus = settle.status
        let readyJSON = try compactJSON(IdleReadyEvent(
            settleWaitedSeconds: settleWaited,
            status: EngineStatusReport(settleStatus)
        ))
        let readyEvent = Data("IDLE_READY \(readyJSON)\n".utf8)
        try FileHandle.standardOutput.write(contentsOf: readyEvent)

        let idleStart = Date()
        try await Task.sleep(for: .seconds(seconds))
        let observed = Date().timeIntervalSince(idleStart)
        let finalStatus = try await service.status()
        let report = IdleReport(
            workspace: workspace.path,
            requestedSeconds: seconds,
            contentSettled: true,
            settleTimeoutSeconds: settleTimeout,
            settleWaitedSeconds: settleWaited,
            statusAtReady: EngineStatusReport(ready),
            statusAfterSettle: EngineStatusReport(settleStatus),
            observedSeconds: NullableDouble(value: observed),
            statusAtIdleStart: NullableEngineStatus(value: EngineStatusReport(settleStatus)),
            statusAfterIdle: NullableEngineStatus(value: EngineStatusReport(finalStatus)),
            unavailable: [:]
        )
        try writeJSON(report, to: URL(fileURLWithPath: outputPath))
    }

    private static func timedQuery(
        _ service: FsearchService,
        spec: QuerySpec,
        phase: String
    ) async throws -> QueryTiming {
        let start = Date()
        let response = try await service.search(SearchRequest(
            query: spec.query, limit: spec.limit, mode: spec.mode, collectAll: false
        ))
        return QueryTiming(
            phase: phase,
            query: spec.query,
            mode: spec.mode.rawValue,
            seconds: Date().timeIntervalSince(start),
            resultCount: response.results.count,
            isComplete: response.isComplete
        )
    }

    private static func waitUntilReady(
        _ service: FsearchService,
        timeout: Double
    ) async throws -> ServiceStatus {
        let deadline = Date().addingTimeInterval(timeout)
        var last = try await service.status()
        while !last.ready {
            guard Date() < deadline else {
                throw ResourceCheckFailure.measurement("Engine did not become ready within \(timeout) seconds")
            }
            try await Task.sleep(for: .milliseconds(100))
            last = try await service.status()
        }
        return last
    }

    private static func waitForContent(
        _ service: FsearchService,
        initial: ServiceStatus,
        timeout: Double
    ) async throws -> (status: ServiceStatus, timedOut: Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        var last = initial
        while true {
            if last.contentPending == 0, (last.contentDocs ?? 0) > 0 {
                return (last, false)
            }
            guard Date() < deadline else { return (last, true) }
            try await Task.sleep(for: .milliseconds(500))
            last = try await service.status()
        }
    }

    private static func waitForIdleSettlement(
        _ service: FsearchService,
        initial: ServiceStatus,
        timeout: Double
    ) async throws -> (status: ServiceStatus, settled: Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        var last = initial
        while true {
            if (last.contentDocs ?? 0) > 0, last.contentPending == 0 {
                return (last, true)
            }
            guard Date() < deadline else { return (last, false) }
            try await Task.sleep(for: .milliseconds(500))
            last = try await service.status()
        }
    }

    private static func percentileReport(_ samples: [Double]) -> Percentiles {
        let sorted = samples.sorted()
        return Percentiles(
            sampleCount: sorted.count,
            p50Seconds: percentile(sorted, 0.50),
            p95Seconds: percentile(sorted, 0.95)
        )
    }

    private static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let rank = max(0, Int(ceil(fraction * Double(sorted.count))) - 1)
        return sorted[min(rank, sorted.count - 1)]
    }

    private static func corpusStats(_ corpus: URL) throws -> CorpusStats {
        var count = 0
        var bytes: UInt64 = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: corpus,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: nil
        ) else {
            throw ResourceCheckFailure.measurement("Cannot enumerate corpus")
        }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isRegularFile == true {
                count += 1
                bytes += UInt64(max(0, values.fileSize ?? 0))
            }
        }
        return CorpusStats(
            path: corpus.path,
            fileCount: count,
            totalBytes: bytes,
            indexDirectoryBytes: NullableUInt64(value: nil),
            unavailable: [
                "indexDirectoryBytes": "Corpus statistics do not include an on-disk Engine index."
            ]
        )
    }

    private static func peakRSSBytes() -> UInt64 {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return UInt64(max(0, usage.ru_maxrss))
    }

    private static func environmentDouble(_ name: String, default value: Double) -> Double {
        guard let raw = ProcessInfo.processInfo.environment[name], let parsed = Double(raw) else {
            return value
        }
        return parsed
    }

    private static func workspace(at path: String) throws -> URL {
        let workspace = try existingDirectory(path, label: "workspace")
        try requireInside(workspace, buildRoot, label: "workspace")
        return workspace
    }

    private static func existingDirectory(_ path: String, label: String) throws -> URL {
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard url.path.hasPrefix("/"),
              FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ResourceCheckFailure.refused("The \(label) must be an existing directory")
        }
        return url
    }

    private static func requireInside(_ url: URL, _ root: URL, label: String) throws {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let candidate = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard candidate == rootPath || candidate.hasPrefix(rootPath + "/") else {
            throw ResourceCheckFailure.refused("The \(label) must be inside \(rootPath)")
        }
    }

    private static func requireSeparate(fixture: URL, index: URL) throws {
        let fixturePath = fixture.path
        let indexPath = index.path
        guard fixturePath != indexPath,
              !fixturePath.hasPrefix(indexPath + "/"),
              !indexPath.hasPrefix(fixturePath + "/") else {
            throw ResourceCheckFailure.refused("The Engine index must be separate from the fixture")
        }
    }

    private static func requireSentinel(in workspace: URL) throws {
        let sentinel = workspace.appendingPathComponent("confinement-denied.txt")
        guard FileManager.default.isReadableFile(atPath: sentinel.path) else {
            throw ResourceCheckFailure.refused(
                "Create confinement-denied.txt beside the fixtures before Engine validation"
            )
        }
    }

    private static func validateOutput(_ path: String) throws {
        let output = URL(fileURLWithPath: path).standardizedFileURL
        try requireInside(output.deletingLastPathComponent(), projectRoot, label: "output")
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(), withIntermediateDirectories: true
        )
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private static func compactJSON<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }
}
