import Darwin
import Foundation
import Synchronization

/// A verified dynamic library image (`dlopen`) whose C functions and data symbols are resolved
/// safely through `RuntimeAccess` policy, optional `dladdr` provenance verification, and once-only
/// diagnostic bookkeeping.
///
/// ```swift
/// let cg = try DynamicLibrary(.coreGraphics)
/// let start: @convention(c) (UnsafeMutableRawPointer) -> Int32 = try cg.function("CGDisplayStreamStart")
/// ```
@safe
public struct DynamicLibrary: @unchecked Sendable, Equatable {
    public let image: Image
    public let resolvedPath: String
    private let handle: UnsafeMutableRawPointer

    private struct CacheKey: Hashable {
        let name: String
        let path: String?
    }

    @safe
    private struct CachedLibrary: @unchecked Sendable {
        let resolvedPath: String
        let handle: UnsafeMutableRawPointer
    }

    /// Opened system library handles are cached process-wide; `RTLD_NOLOAD | RTLD_LAZY` is tried
    /// first so already-loaded system frameworks incur zero extra reference-count churn.
    private static let openCache = Mutex<[CacheKey: CachedLibrary]>([:])

    /// Opens `image`, verifying `RuntimeAccess.isEnabled` and recording the resolution.
    public init(_ image: Image, alreadyLoadedOnly: Bool = false) throws(RuntimeError) {
        let key = "dlopen:\(image.name)"
        do {
            try RuntimeAccess.checkEnabled()
            let cacheKey = CacheKey(name: image.name, path: image.path)
            if let cached = Self.openCache.withLock({ $0[cacheKey] }) {
                self.image = image
                self.resolvedPath = cached.resolvedPath
                unsafe self.handle = unsafe cached.handle
                RuntimeAccess.record(key, nil)
                return
            }

            let flags = alreadyLoadedOnly ? (RTLD_LAZY | RTLD_NOLOAD) : RTLD_LAZY
            var lastDetail: String?
            for candidate in image.candidatePaths {
                if let opened = unsafe dlopen(candidate, flags) {
                    let entry = unsafe CachedLibrary(resolvedPath: candidate, handle: opened)
                    Self.openCache.withLock { $0[cacheKey] = entry }
                    self.image = image
                    self.resolvedPath = candidate
                    unsafe self.handle = unsafe opened
                    RuntimeAccess.record(key, nil)
                    return
                }
                if let err = unsafe dlerror() {
                    lastDetail = unsafe String(cString: err)
                }
            }
            throw RuntimeError.libraryNotFound(
                path: image.path ?? image.name,
                detail: lastDetail
            )
        } catch let error as RuntimeError {
            RuntimeAccess.record(key, error)
            throw error
        } catch {
            fatalError("unreachable: only RuntimeError is thrown")
        }
    }

    /// Resolves a raw symbol address in this library, optionally verifying via `dladdr` that the
    /// symbol's owning image matches `image.name`.
    public func symbolAddress(
        _ name: String,
        verifyOrigin: Bool = false
    ) throws(RuntimeError) -> UnsafeMutableRawPointer {
        let recordKey = "\(image.name)::\(name)"
        do {
            try RuntimeAccess.checkEnabled()
            guard let ptr = unsafe dlsym(handle, name) else {
                throw RuntimeError.cSymbolNotFound(symbol: name, image: image.name)
            }
            if verifyOrigin {
                var info = unsafe Dl_info()
                let actual: String? =
                    if unsafe dladdr(ptr, &info) != 0, let fname = unsafe info.dli_fname {
                        (unsafe String(cString: fname) as NSString).lastPathComponent
                    } else {
                        nil
                    }
                guard actual == image.name else {
                    throw RuntimeError.cSymbolWrongImage(symbol: name, expected: image.name, actual: actual)
                }
            }
            RuntimeAccess.record(recordKey, nil)
            return unsafe ptr
        } catch let error as RuntimeError {
            RuntimeAccess.record(recordKey, error)
            throw error
        } catch {
            fatalError("unreachable: only RuntimeError is thrown")
        }
    }

    /// Resolves a typed `@convention(c)` function pointer from this library.
    ///
    /// Note: C symbols do not carry runtime type encodings in Mach-O, so `as:` states the caller's
    /// ABI contract, while Abysm enforces `RuntimeAccess.isEnabled`, `dlsym` resolution, optional
    /// `dladdr` origin verification, and single-fault telemetry.
    public func function<Function>(
        _ name: String,
        as _: Function.Type = Function.self,
        verifyOrigin: Bool = false
    ) throws(RuntimeError) -> Function {
        let ptr = try unsafe symbolAddress(name, verifyOrigin: verifyOrigin)
        return unsafe unsafeBitCast(ptr, to: Function.self)
    }

    /// Resolves a constant global symbol (for example `kCGDisplayStreamShowCursor` of type `CFString`)
    /// and reads its value out of the exported pointer slot.
    public func global<Value>(
        _ name: String,
        as _: Value.Type = Value.self,
        verifyOrigin: Bool = false
    ) throws(RuntimeError) -> Value {
        let ptr = try unsafe symbolAddress(name, verifyOrigin: verifyOrigin)
        return unsafe ptr.assumingMemoryBound(to: Value.self).pointee
    }

    /// Checks whether a symbol exists in this library without logging a failure fault.
    public func hasSymbol(_ name: String) -> Bool {
        guard RuntimeAccess.isEnabled else { return false }
        return unsafe dlsym(handle, name) != nil
    }

    public static func == (lhs: DynamicLibrary, rhs: DynamicLibrary) -> Bool {
        unsafe lhs.handle == rhs.handle
    }
}
