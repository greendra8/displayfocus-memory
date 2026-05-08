// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DisplayFocusMemory",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DisplayFocusMemory", targets: ["DisplayFocusMemory"])
    ],
    targets: [
        .executableTarget(
            name: "DisplayFocusMemory",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
