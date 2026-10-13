import Foundation
#if DEBUG
@_spi(Testing) import FsearchService
#else
import FsearchService
#endif

// Each invocation owns one real Engine. Process exit stops upstream workers.
@main struct EngineCheck {
    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw FsearchError.bridge(message) }
    }

    static func waitFor(_ service: FsearchService, query: String, names: Set<String>) async throws {
        for _ in 0..<200 {
            if let response = try? await service.search(SearchRequest(query: query, collectAll: true)),
               Set(response.results.map { URL(fileURLWithPath: $0.path).lastPathComponent }) == names { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw FsearchError.bridge("Engine query did not converge: \(query)")
    }

    static func main() async {
        do { try await run() }
        catch {
            fputs("Engine validation failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func run() async throws {
        let args = CommandLine.arguments
        guard args.count == 3 else { throw FsearchError.bridge("Usage: FsearchEngineCheck <workspace> <first|recover|owner|follower>") }
        let workspace = URL(fileURLWithPath: args[1]).resolvingSymlinksInPath()
        let fixture = workspace.appendingPathComponent("fixtures")
        let index = workspace.appendingPathComponent("index")
        let service = try FsearchService(confinedEngineDirectory: fixture, indexDirectory: index)
        for _ in 0..<200 {
            if try await service.status().ready { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let status = try await service.status()
        try require(status.ready && status.engineValidated && status.mode == "engine", "Engine did not become ready")
        print("Confinement installed before Engine; outside sentinel read denied; name index ready")
        if args[2] == "content" {
            try await ContentCheck.run(service: service, fixture: fixture)
            return
        }
            #if DEBUG
            do {
                try await service.injectEngineQueryPanic()
                throw FsearchError.bridge("Injected Engine panic did not fail")
            } catch FsearchError.bridge(let message) {
                try require(message != "Injected Engine panic did not fail", "Injected Engine panic escaped validation")
                print("Injected Engine panic contained: \(message)")
            }
            try await waitFor(service, query: "engine-proof", names: ["engine-proof.txt"])
            #endif
        switch args[2] {
        case "first":
            try require(status.owner == true, "First Engine did not own independent index")
            try await waitFor(service, query: "engine-proof", names: ["engine-proof.txt"])
            _ = try await service.changes()
            let subdirectory = fixture.appendingPathComponent("nested")
            try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
            let added = subdirectory.appendingPathComponent("engine-added.txt")
            try Data("new content".utf8).write(to: added)
            try await waitFor(service, query: "engine-added", names: ["engine-added.txt"])
            let renamed = subdirectory.appendingPathComponent("engine-renamed.txt")
            try FileManager.default.moveItem(at: added, to: renamed)
            try Data("modified content grows".utf8).write(to: renamed)
            try await waitFor(service, query: "engine-renamed", names: ["engine-renamed.txt"])
            let modified = try await service.search(SearchRequest(query: "engine-renamed", collectAll: true))
            try require(modified.results.first?.indexedSize == 22, "Modified indexed size did not update")
            try await waitFor(service, query: "engine-added", names: [])
            try FileManager.default.removeItem(at: subdirectory)
            try await waitFor(service, query: "engine-renamed", names: [])
            var changes: [IndexChange] = []
            for _ in 0..<30 {
                changes.append(contentsOf: try await service.changes())
                if !changes.isEmpty { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            try require(!changes.isEmpty && changes.allSatisfy { $0.path.hasPrefix(fixture.path) }, "Public service delivered no fixture change notifications")
            try Data("persisted".utf8).write(to: fixture.appendingPathComponent("engine-persist.txt"))
            try await waitFor(service, query: "engine-persist", names: ["engine-persist.txt"])
            try await service.saveIndex()
            try await Task.sleep(for: .seconds(3))
            print("Real Engine create/rename/modify/delete + public changes + save: passed")
        case "recover":
            try require(status.owner == true, "Restart did not acquire released process lock")
            try await waitFor(service, query: "engine-persist", names: ["engine-persist.txt"])
            let snapshot = try await service.snapshot(SearchRequest(query: "engine-"))
            try require(snapshot.isComplete && snapshot.totalCount == 2, "Recovered complete snapshot mismatch")
            print("New process recovered saved index and independently acquired owner lock: passed")
        case "owner":
            try require(status.owner == true, "Owner mode did not acquire lock")
            try await service.saveIndex()
            try Data("ready".utf8).write(to: index.appendingPathComponent("owner-ready"))
            print("Owner ready")
            while true { try await Task.sleep(for: .seconds(1)) }
        case "follower":
            try require(status.owner == false, "Second process incorrectly acquired writer lock")
            try await waitFor(service, query: "engine-persist", names: ["engine-persist.txt"])
            print("Second process follows independent client index without another writer: passed")
        default: throw FsearchError.bridge("Unknown Engine validation phase")
        }
    }
}
