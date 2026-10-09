// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ripple",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Ripple", targets: ["Ripple"])],
    targets: [
        .target(name: "RippleCore"),
        .executableTarget(
            name: "Ripple",
            dependencies: ["RippleCore"],
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("Carbon")]
        ),
        .testTarget(name: "RippleCoreTests", dependencies: ["RippleCore"])
    ]
)
