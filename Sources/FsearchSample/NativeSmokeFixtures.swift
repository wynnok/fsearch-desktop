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
            for number in [1, 2, 3, 10, 20] {
                let file = directory.appendingPathComponent("demo\(number).txt")
                try Data(repeating: 0, count: number * 4096).write(to: file)
                try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(number))],
                                                      ofItemAtPath: file.path)
            }
            return directory
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
