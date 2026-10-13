// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FsearchDesktop",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FsearchService", targets: ["FsearchService"]),
        .executable(name: "FsearchSample", targets: ["FsearchSample"])
    ],
    targets: [
        .systemLibrary(name: "CFsearch"),
        .target(
            name: "FsearchService",
            dependencies: ["CFsearch"],
            linkerSettings: [
                .unsafeFlags(["-L.build/rust/debug"]),
                .linkedLibrary("fsearch_bridge"),
                .linkedLibrary("c++"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        .executableTarget(name: "FsearchSample", dependencies: ["FsearchService"]),
        .testTarget(name: "FsearchServiceTests", dependencies: ["FsearchService"])
    ]
)
