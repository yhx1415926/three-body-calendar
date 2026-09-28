// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TrisolarisCalendar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SimulationCore", targets: ["SimulationCore"]),
        .executable(name: "TrisolarisApp", targets: ["TrisolarisApp"]),
        .executable(name: "ScienceCheck", targets: ["ScienceCheck"])
    ],
    targets: [
        .target(
            name: "CRebound",
            path: "Vendor/REBOUND",
            exclude: ["LICENSE", "UPSTREAM.md", "src/Makefile", "src/Makefile.defs", "src/communication_mpi.c", "src/glad.c"],
            sources: ["src", "bridge.c"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("src"),
                .define("_GNU_SOURCE"),
                .define("_APPLE"),
                .define("GITHASH", to: "1509463f3e5802807e69dfd7db23ff4309c56909"),
                .unsafeFlags(["-fno-fast-math", "-ffp-contract=off", "-Wno-unknown-pragmas"])
            ],
            linkerSettings: [.linkedLibrary("m")]
        ),
        .target(name: "SimulationCore", dependencies: ["CRebound"], resources: [.process("Resources")]),
        .executableTarget(
            name: "TrisolarisApp",
            dependencies: ["SimulationCore"],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("MetalKit")]
        ),
        .executableTarget(name: "ScienceCheck", dependencies: ["SimulationCore"]),
        .executableTarget(name: "JourneySearch", dependencies: ["SimulationCore"]),
        .testTarget(name: "SimulationCoreTests", dependencies: ["SimulationCore"]),
        .testTarget(name: "TrisolarisAppTests", dependencies: ["TrisolarisApp", "SimulationCore"])
    ],
    swiftLanguageModes: [.v6],
    cLanguageStandard: .c99
)
