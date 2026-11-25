// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WindowShift",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "WindowShift", targets: ["WindowShift"])
    ],
    targets: [
        .executableTarget(
            name: "WindowShift",
            path: "Sources"
        ),
        .testTarget(
            name: "WindowShiftTests",
            dependencies: ["WindowShift"],
            path: "Tests/WindowShiftTests"
        )
    ]
)
