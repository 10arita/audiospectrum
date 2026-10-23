// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AudioSpectrum",
    platforms: [.macOS("14.2")],
    products: [
        .executable(name: "AudioSpectrum", targets: ["AudioSpectrum"]),
        .library(name: "SpectrumCore", targets: ["SpectrumCore"])
    ],
    targets: [
        .target(name: "SpectrumCore"),
        .executableTarget(name: "AudioSpectrum", dependencies: ["SpectrumCore"]),
        .testTarget(name: "SpectrumCoreTests", dependencies: ["SpectrumCore"])
    ],
    swiftLanguageVersions: [.v5]
)
