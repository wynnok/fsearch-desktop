// swift-tools-version: 6.0
import PackageDescription
import Foundation

let rustLibraryDirectory = ProcessInfo.processInfo.environment["FSEARCH_RUST_LIBRARY_DIR"] ?? ".build/rust/debug"

let package = Package(
    name: "FsearchDesktop",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FsearchService", targets: ["FsearchService"]),
        .executable(name: "FsearchSample", targets: ["FsearchSample"]),
        .executable(name: "FsearchEngineCheck", targets: ["FsearchEngineCheck"])
    ],
    targets: [
        .systemLibrary(name: "CFsearch"),
        .target(
            name: "FsearchService",
            dependencies: ["CFsearch"],
            linkerSettings: [
                .unsafeFlags(["-L\(rustLibraryDirectory)"]),
                .linkedLibrary("fsearch_bridge"),
                .linkedLibrary("c++"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        .executableTarget(name: "FsearchSample", dependencies: ["FsearchService"]),
        .executableTarget(name: "FsearchEngineCheck", dependencies: ["FsearchService"]),
        .testTarget(name: "FsearchServiceTests", dependencies: ["FsearchService"])
    ]
)
