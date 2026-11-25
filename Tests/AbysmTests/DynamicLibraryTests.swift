import CoreGraphics
import Foundation
import QuartzCore
import Testing

@testable import Abysm

@Suite("DynamicLibrary and IMP fast paths", .serialized)
struct DynamicLibraryAndFastPathTests {
    init() { RuntimeAccess.resetResolutions() }

    @Test func `DynamicLibrary resolves verified C functions and globals from CoreGraphics`() throws {
        let cg = try DynamicLibrary(.coreGraphics)
        let mainDisplay: @convention(c) () -> UInt32 = try cg.function("CGMainDisplayID")
        _ = mainDisplay()

        let kShowCursor: CFString = try cg.global("kCGDisplayStreamShowCursor")
        #expect(!(kShowCursor as String).isEmpty)

        #expect(cg.hasSymbol("CGDisplayStreamStart"))
        #expect(!cg.hasSymbol("abysm_nonexistent_symbol_xyz"))
    }

    @Test func `DynamicLibrary reports missing libraries and missing symbols cleanly`() throws {
        #expect(throws: RuntimeError.self) {
            _ = try DynamicLibrary(Image("AbysmNonexistentFramework", path: "/nonexistent/Abysm.dylib"))
        }
        let cf = try DynamicLibrary(.coreFoundation)
        #expect(throws: RuntimeError.cSymbolNotFound(symbol: "abysm_missing_fn", image: "CoreFoundation")) {
            let _: @convention(c) () -> Void = try cf.function("abysm_missing_fn")
        }
    }

    @Test func `DynamicLibrary respects RuntimeAccess policy switch`() throws {
        RuntimeAccess.isEnabled = false
        defer { RuntimeAccess.isEnabled = true }
        #expect(throws: RuntimeError.disabled) {
            _ = try DynamicLibrary(.coreGraphics)
        }
    }

    @Test func `DynamicLibrary dladdr origin verification catches wrong owning image`() throws {
        // `CFRelease` is exported by CoreFoundation, not AppKit.
        let cf = try DynamicLibrary(.coreFoundation)
        _ = try unsafe cf.symbolAddress("CFRelease", verifyOrigin: true)
    }

    @Test func `scalar fast paths read and write Bool, Double, Int, UInt32 without NSInvocation`() throws {
        let layer = CALayer()
        let obj = RuntimeObject(layer)
        #expect(obj.writeIfSupported(14.5, to: "cornerRadius"))
        #expect(try obj.read("cornerRadius", as: Double.self) == 14.5)

        #expect(obj.writeIfSupported(true, to: "hidden"))
        #expect(try obj.read("isHidden", as: Bool.self) == true)

        #expect(!obj.writeIfSupported(true, to: "abysmNonexistentProperty"))
        #expect(obj.responds(to: "setCornerRadius:"))
        #expect(!obj.responds(to: "abysmNonexistentSelector:"))
    }

    @Test func `scalar fast path still catches Objective-C exceptions cleanly`() throws {
        @objc final class RaisingHost: NSObject {
            @objc var exploding: Double {
                NSException(name: .genericException, reason: "boom").raise()
                return 0
            }
        }
        let obj = RuntimeObject(RaisingHost())
        #expect(throws: RuntimeError.raised(selector: "exploding", exception: "NSGenericException")) {
            _ = try obj.read("exploding", as: Double.self)
        }
    }
}
