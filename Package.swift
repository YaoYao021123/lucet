// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MediaWorkbench",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MediaCore", targets: ["MediaCore"]),
        .executable(name: "media-probe", targets: ["MediaProbe"]),
        .executable(name: "media-workbench", targets: ["MediaWorkbenchApp"]),
        .executable(name: "media-benchmark", targets: ["MediaBenchmark"])
    ],
    targets: [
        .target(name: "MediaCore"),
        .executableTarget(name: "MediaProbe", dependencies: ["MediaCore"]),
        .executableTarget(name: "MediaWorkbenchApp", dependencies: ["MediaCore"]),
        .executableTarget(name: "MediaBenchmark", dependencies: ["MediaCore"]),
        .testTarget(name: "MediaCoreTests", dependencies: ["MediaCore"])
    ]
)
