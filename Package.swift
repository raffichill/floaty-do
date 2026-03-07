// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FloatyDo",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FloatyDoLib", targets: ["FloatyDoLib"]),
    ],
    targets: [
        .target(name: "FloatyDoLib", path: "Sources/FloatyDo", exclude: ["main.swift"]),
        .executableTarget(name: "FloatyDo", dependencies: ["FloatyDoLib"], path: "Sources/FloatyDoApp"),
        .testTarget(
            name: "FloatyDoTests",
            dependencies: ["FloatyDoLib"]
        ),
    ]
)
