import Foundation

enum ApplicationStartup: Equatable {
    case desktop(index: URL, home: URL)
    case sample(URL)

    init(arguments: [String], applicationSupport: URL, home: URL) {
        if arguments.count < 2 || arguments[1].hasPrefix("-psn_") || arguments[1] == "-ApplePersistenceIgnoreState" {
            self = .desktop(index: applicationSupport.appendingPathComponent("FsearchDesktop/index", isDirectory: true),
                            home: home)
        } else {
            self = .sample(URL(fileURLWithPath: arguments[1]))
        }
    }
}
