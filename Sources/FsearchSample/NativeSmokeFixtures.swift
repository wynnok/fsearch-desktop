import Foundation

enum NativeSmokeFixtures {
    static func create(under output: URL) throws -> URL {
        let directory = output.appendingPathComponent("fixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let names = [
            "demo20.txt", "demo10.txt", "demo3.txt", "demo2.txt", "demo1.txt",
            "type:doc.txt", "draft notes.txt", "quote \"draft\".txt", "line\nbreak.txt",
            "笔记😀.md", "cafe\u{301}.txt"
        ]
        do {
            for name in names {
                try Data("native verification fixture".utf8).write(to: directory.appendingPathComponent(name))
            }
            return directory
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
