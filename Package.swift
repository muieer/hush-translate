// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HushTranslate",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "HushTranslate", targets: ["HushTranslate"])
    ],
    dependencies: [
        // 全局快捷键注册（基于 Carbon RegisterEventHotKey，不需辅助功能权限）
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", exact: "2.4.0")
    ],
    targets: [
        .executableTarget(
            name: "HushTranslate",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Sources/Translate",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                // Carbon 用于 RegisterEventHotKey
                .linkedFramework("Carbon")
            ]
        ),
        .testTarget(
            name: "HushTranslateTests",
            dependencies: ["HushTranslate"],
            path: "Tests/HushTranslateTests"
        )
    ]
)
