// swift-tools-version: 6.3
import PackageDescription

var strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .strictMemorySafety(),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility")
]

if Context.environment["ABYSM_WERROR"] != nil {
    strictSettings.append(.unsafeFlags(["-warnings-as-errors"]))
}

let package = Package(
    name: "Abysm",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "Abysm", targets: ["Abysm"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/Aemi-Studio/aemi.git",
            revision: "32f1d61e0ee2fe19af99c1c1a040f1fbdae91d4a"
        )
    ],
    targets: [
        .target(name: "CAbysm", publicHeadersPath: "include"),
        .target(
            name: "Abysm",
            dependencies: [
                "CAbysm",
                .product(name: "InternedStrings", package: "aemi")
            ],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "AbysmTests",
            dependencies: ["Abysm"],
            swiftSettings: strictSettings
        )
    ]
)
