import AppKit
import Darwin

@MainActor
private final class SmokeApplication {
    private(set) var stopRequested = false
    var running: NSRunningApplication? {
        didSet {
            if stopRequested { running?.forceTerminate() }
        }
    }

    func stop() {
        stopRequested = true
        running?.forceTerminate()
    }
}

@main
private struct InstalledSmokeLauncher {
    @MainActor
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("Installed smoke launch failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func run() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 5 else {
            throw NSError(domain: "InstalledSmokeLauncher", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Expected executable, sample directory, output directory and log path"
            ])
        }
        let executable = URL(fileURLWithPath: arguments[1])
        let bundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let output = URL(fileURLWithPath: arguments[3])
        let log = arguments[4]
        freopen(log, "a", stdout)
        freopen(log, "a", stderr)

        let state = SmokeApplication()
        let signals = [SIGTERM, SIGINT].map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { Task { @MainActor in state.stop() } }
            source.resume()
            return source
        }
        defer {
            signals.forEach { $0.cancel() }
            state.stop()
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        // Bare paths are treated as file-open requests and can suppress SwiftUI's initial window.
        configuration.arguments = ["--sample-directory=\(arguments[2])", "--smoke", "--smoke-output=\(arguments[3])"]
        configuration.environment = ProcessInfo.processInfo.environment.merging(["FSEARCH_NATIVE_SMOKE_LOG": log]) {
            _, value in value
        }
        let application = try await NSWorkspace.shared.openApplication(at: bundle, configuration: configuration)
        state.running = application
        try Data("\(application.processIdentifier)\n".utf8).write(to: URL(fileURLWithPath: log + ".pid"))
        if state.stopRequested { throw CancellationError() }
        print("Installed smoke application PID: \(application.processIdentifier)")
        fflush(stdout)
        while !application.isTerminated {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard (try? String(contentsOf: output.appendingPathComponent("smoke-complete.txt"), encoding: .utf8)) == "passed\n" else {
            throw NSError(domain: "InstalledSmokeLauncher", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Application exited without completing the smoke checks"
            ])
        }
    }
}
