/// The framework that defines a runtime class, matched against the runtime's own record of where the class came from
/// (`class_getImageName`). A class of the same name from another image is treated as missing: a renamed class and
/// a different framework's class are not the same thing.
public struct Image: Sendable, Hashable, ExpressibleByStringLiteral {
    /// The image's file name, without extension: `QuartzCore`, `UIKitCore`, `BaseBoard`, `SkyLight`.
    public var name: String
    /// Optional explicit filesystem path (used by ``DynamicLibrary`` for private frameworks).
    public var path: String?

    public init(_ name: String, path: String? = nil) {
        self.name = name
        self.path = path
    }

    public init(stringLiteral value: String) {
        self.name = value
        self.path = nil
    }

    public static let quartzCore = Image(
        "QuartzCore",
        path: "/System/Library/Frameworks/QuartzCore.framework/QuartzCore"
    )
    public static let uiKitCore = Image(
        "UIKitCore",
        path: "/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore"
    )
    public static let appKit = Image(
        "AppKit",
        path: "/System/Library/Frameworks/AppKit.framework/AppKit"
    )
    public static let foundation = Image(
        "Foundation",
        path: "/System/Library/Frameworks/Foundation.framework/Foundation"
    )
    public static let coreGraphics = Image(
        "CoreGraphics",
        path: "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
    )
    public static let coreFoundation = Image(
        "CoreFoundation",
        path: "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
    )
    public static let skyLight = Image(
        "SkyLight",
        path: "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    )
    public static let coreDisplay = Image(
        "CoreDisplay",
        path: "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay"
    )
    public static let coreVideo = Image(
        "CoreVideo",
        path: "/System/Library/Frameworks/CoreVideo.framework/CoreVideo"
    )
    public static let videoToolbox = Image(
        "VideoToolbox",
        path: "/System/Library/Frameworks/VideoToolbox.framework/VideoToolbox"
    )

    /// Candidate system paths tried when opening this image dynamically.
    var candidatePaths: [String] {
        if let path { return [path] }
        return [
            "/System/Library/Frameworks/\(name).framework/\(name)",
            "/System/Library/PrivateFrameworks/\(name).framework/\(name)",
            "/usr/lib/lib\(name).dylib",
            name
        ]
    }
}
