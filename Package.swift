// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MPCMidiConverter",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "MPCMidiConverterCore",
            targets: ["MPCMidiConverterCore"]
        ),
        .executable(
            name: "mpc-midi-converter",
            targets: ["MPCMidiConverterCLI"]
        ),
        .executable(
            name: "MPCMidiConverterApp",
            targets: ["MPCMidiConverterApp"]
        )
    ],
    targets: [
        .target(
            name: "MPCMidiConverterCore"
        ),
        .executableTarget(
            name: "MPCMidiConverterCLI",
            dependencies: ["MPCMidiConverterCore"]
        ),
        .executableTarget(
            name: "MPCMidiConverterApp",
            dependencies: ["MPCMidiConverterCore"]
        ),
        .testTarget(
            name: "MPCMidiConverterCoreTests",
            dependencies: ["MPCMidiConverterCore"]
        )
    ]
)
