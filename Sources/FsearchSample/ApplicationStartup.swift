import Foundation

enum ApplicationStartup: Equatable {
    case desktop(index: URL, home: URL)
    case sample(URL)

    init(arguments: [String], applicationSupport: URL, home: URL) {
        if arguments.count < 2 || arguments[1].hasPrefix("-psn_") || arguments[1] == "-ApplePersistenceIgnoreState" {
            self = .desktop(index: applicationSupport.appendingPathComponent("FsearchDesktop/index", isDirectory: true),
                            home: home)
        } else {
            let argument = arguments[1]
            let path = argument.hasPrefix("--sample-directory=")
                ? String(argument.dropFirst("--sample-directory=".count)) : argument
            self = .sample(URL(fileURLWithPath: path))
        }
    }

    static func smokeOutput(arguments: [String]) -> URL? {
        guard arguments.count == 4, arguments[2] == "--smoke" else { return nil }
        let argument = arguments[3]
        let path = argument.hasPrefix("--smoke-output=")
            ? String(argument.dropFirst("--smoke-output=".count)) : argument
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
