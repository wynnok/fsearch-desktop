import Foundation

// The filesystem operation can finish before the engine updates its index.
// Only check the filesystem for results affected by an app-initiated removal.
struct RemovedResultPaths: Sendable {
    private var roots: [String] = []
    private(set) var revision = 0

    mutating func insert(_ path: String) {
        revision += 1
        let root = String(normalizedRoot(path))
        if !roots.contains(where: { isSameOrDescendantPath(root, of: $0) }) {
            roots.removeAll { isSameOrDescendantPath($0, of: root) }
            roots.append(root)
        }
    }

    func staleResultPredicate() -> ((String) -> Bool)? {
        guard !roots.isEmpty else { return nil }
        let exactPaths = Dictionary(uniqueKeysWithValues: roots.enumerated().map {
            (Data($0.element.utf8), $0.offset)
        })
        let prefixes = roots.enumerated().map {
            (index: $0.offset, bytes: Array(directoryPrefix(for: $0.element[...]).utf8))
        }
            .sorted { $0.bytes.lexicographicallyPrecedes($1.bytes) }
        var missingRoots: [Int: Bool] = [:]
        return { path in
            let exact = exactPaths[Data(path.utf8)]
            // With nested roots removed, only the immediately preceding prefix can contain this path.
            var low = 0
            var high = prefixes.count
            while exact == nil && low < high {
                let middle = low + (high - low) / 2
                if path.utf8.lexicographicallyPrecedes(prefixes[middle].bytes) { high = middle }
                else { low = middle + 1 }
            }
            let ancestor = low > 0 && path.utf8.starts(with: prefixes[low - 1].bytes)
                ? prefixes[low - 1].index : nil
            guard let index = exact ?? ancestor else { return false }
            let root = roots[index]
            let missing = missingRoots[index] ?? Self.isMissing(root)
            missingRoots[index] = missing
            if missing { return true }
            return exact == nil && Self.isMissing(path)
        }
    }

    static func isMissing(_ path: String) -> Bool {
        do {
            // Read the entry itself so that a recreated dangling symlink also survives.
            _ = try FileManager.default.attributesOfItem(atPath: path)
            return false
        } catch let error as CocoaError {
            return error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile
        } catch { return false }
    }
}

package func isSameOrDescendantPath(_ path: String, of root: String) -> Bool {
    let normalized = normalizedRoot(root)
    return path.utf8.elementsEqual(normalized.utf8) || path.utf8.starts(with: directoryPrefix(for: normalized).utf8)
}

private func normalizedRoot(_ path: String) -> Substring {
    guard path.hasSuffix("/") else { return path[...] }
    guard let last = path.lastIndex(where: { $0 != "/" }) else { return path.prefix(1) }
    return path[...last]
}

private func directoryPrefix(for root: Substring) -> String {
    root == "/" ? "/" : root + "/"
}

package func missingPaths(in paths: [String], under root: String) async -> Set<Data> {
    await Task.detached {
        Set(paths.lazy.filter {
            isSameOrDescendantPath($0, of: root) && RemovedResultPaths.isMissing($0)
        }.map { Data($0.utf8) })
    }.value
}
