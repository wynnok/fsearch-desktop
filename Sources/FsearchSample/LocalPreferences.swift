import Foundation
import FsearchService

// Explicit preference allowlist: queries, paths, results and errors never enter this file.
struct LocalPreferences {
    let url: URL

    static var applicationStore: LocalPreferences {
        let base: URL
        if Bundle.main.bundleURL.pathExtension == "app" {
            base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("FsearchDesktop", isDirectory: true)
        } else {
            base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/client-settings", isDirectory: true)
        }
        return LocalPreferences(url: base.appendingPathComponent("preferences.json"))
    }

    var onboardingDismissed: Bool { read()?.onboardingDismissed ?? false }

    @MainActor
    func restore(configuration: inout SearchConfiguration, selection: SearchSelectionState) {
        guard let stored = read() else { return }
        configuration.nameMode = stored.nameMode
        configuration.sortPreference = stored.sort.flatMap(NameSort.init(rawValue:))
        configuration.showsHidden = stored.showsHidden
        selection.isInspectorVisible = stored.inspectorVisible
    }

    @MainActor
    func save(configuration: SearchConfiguration, inspectorVisible: Bool,
              onboardingDismissed: Bool? = nil) throws {
        let stored = Stored(nameMode: configuration.nameMode, sort: configuration.sortPreference?.rawValue,
                            showsHidden: configuration.showsHidden, inspectorVisible: inspectorVisible,
                            onboardingDismissed: onboardingDismissed ?? self.onboardingDismissed)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(stored).write(to: url, options: .atomic)
    }

    private func read() -> Stored? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Stored.self, from: data)
    }

    private struct Stored: Codable {
        let nameMode: NameMatchMode
        let sort: String?
        let showsHidden: Bool
        let inspectorVisible: Bool
        let onboardingDismissed: Bool
    }
}
