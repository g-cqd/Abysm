internal import CAbysm
import Foundation
import Synchronization

/// The single place a message is sent. Every size is checked in the shim against the runtime's own signature.
enum Invocation {
    static func send(
        to target: AnyObject,
        selector: Selector,
        arguments: ArgumentBuffer,
        resultEncoding: String?,
        decode: (UnsafeRawPointer) throws(RuntimeError) -> Void
    ) throws(RuntimeError) {
        try RuntimeAccess.checkEnabled()
        let name = NSStringFromSelector(selector)

        var resultSize = 0
        if let resultEncoding { unsafe NSGetSizeAndAlignment(resultEncoding, &resultSize, nil) }
        var storage = [UInt8](repeating: 0, count: max(resultSize, 16))

        var exception: NSString?
        let argumentCount = arguments.offsets.count
        let status: AbysmStatus = arguments.bytes.withUnsafeBytes { bytes in
            // One pointer per argument, into the buffer that stays alive for the whole call.
            let pointers: [UnsafeRawPointer?] = unsafe arguments.offsets.map { offset in
                unsafe bytes.baseAddress.map { unsafe $0 + offset }
            }
            return pointers.withUnsafeBufferPointer { argumentPointers in
                arguments.sizes.withUnsafeBufferPointer { sizes in
                    storage.withUnsafeMutableBytes { result in
                        unsafe abysm_invoke(
                            target, selector, argumentCount, argumentPointers.baseAddress,
                            sizes.baseAddress, result.baseAddress, resultSize, &exception)
                    }
                }
            }
        }
        // The arguments' objects must outlive the call.
        withExtendedLifetime(arguments.retained) {}

        switch status {
            case .OK:
                // The shim transfers a +1 object result. Keep it alive through decoding (including a thrown
                // type mismatch), then balance it. The decoded Swift value holds its own reference.
                var decodeError: RuntimeError?
                storage.withUnsafeBytes { bytes in
                    guard let pointer = bytes.baseAddress else {
                        decodeError = .sizeMismatch(selector: name)
                        return
                    }
                    let object: Unmanaged<AnyObject>? =
                        resultEncoding == "@"
                        ? unsafe pointer.loadUnaligned(as: UnsafeRawPointer?.self)
                            .map {
                                unsafe Unmanaged<AnyObject>.fromOpaque($0)
                            } : nil
                    defer { unsafe object?.release() }
                    do {
                        try unsafe decode(pointer)
                    } catch let error as RuntimeError {
                        decodeError = error
                    } catch {
                        preconditionFailure("decoder violated its typed-throws contract")
                    }
                }
                if let decodeError { throw decodeError }
            case .noSignature:
                throw .selectorNotFound(class: String(describing: type(of: target)), selector: name)
            case .argumentCount:
                throw .argumentCount(selector: name, expected: 0, actual: arguments.offsets.count)
            case .sizeMismatch:
                throw .sizeMismatch(selector: name)
            case .raised:
                throw .raised(selector: name, exception: (exception as String?) ?? "unknown")
            @unknown default:
                throw .sizeMismatch(selector: name)
        }
    }

    // MARK: - Fast IMP dispatch helpers

    /// Dispatches a verified 0-arg scalar/void/object getter or 1-arg scalar setter through direct
    /// IMP invocation when the signature matches a known fast shape, falling back to `NSInvocation`
    /// for everything else. Eliminates heap allocations for `ArgumentBuffer`, `NSInvocation`, and
    /// `NSMethodSignature` on hot paths while keeping `@try/@catch` containment identical.
    static func sendScalarGetter<Value: ObjCValue>(
        to target: AnyObject,
        selector: Selector,
        name: String,
        as _: Value.Type
    ) throws(RuntimeError) -> Value? {
        try RuntimeAccess.checkEnabled()
        var exception: NSString?
        switch Value.objcEncoding {
            case "B":
                var out = ObjCBool(false)
                let status = unsafe abysm_call_b(target, selector, &out, &exception)
                try checkFastStatus(status, target: target, selector: name, exception: exception)
                return out.boolValue as? Value
            case "d":
                var out: Double = 0
                let status = unsafe abysm_call_d(target, selector, &out, &exception)
                try checkFastStatus(status, target: target, selector: name, exception: exception)
                if Value.self == Double.self { return out as? Value }
                if Value.self == CGFloat.self { return CGFloat(out) as? Value }
                return nil
            case "q":
                var out: Int64 = 0
                let status = unsafe abysm_call_q(target, selector, &out, &exception)
                try checkFastStatus(status, target: target, selector: name, exception: exception)
                return (Int(out) as? Value)
            case "I":
                var out: UInt32 = 0
                let status = unsafe abysm_call_I(target, selector, &out, &exception)
                try checkFastStatus(status, target: target, selector: name, exception: exception)
                return (out as? Value)
            default:
                return nil
        }
    }

    static func sendScalarSetter<Value: ObjCValue>(
        to target: AnyObject,
        selector: Selector,
        name: String,
        value: Value
    ) throws(RuntimeError) -> Bool {
        try RuntimeAccess.checkEnabled()
        var exception: NSString?
        switch Value.objcEncoding {
            case "B":
                guard let b = value as? Bool else { return false }
                let status = unsafe abysm_call_v_b(target, selector, b, &exception)
                try checkFastStatus(status, target: target, selector: name, exception: exception)
                return true
            case "d":
                let d: Double
                if let raw = value as? Double {
                    d = raw
                } else if let raw = value as? CGFloat {
                    d = Double(raw)
                } else {
                    return false
                }
                let status = unsafe abysm_call_v_d(target, selector, d, &exception)
                try checkFastStatus(status, target: target, selector: name, exception: exception)
                return true
            case "q":
                guard let i = value as? Int else { return false }
                let status = unsafe abysm_call_v_q(target, selector, Int64(i), &exception)
                try checkFastStatus(status, target: target, selector: name, exception: exception)
                return true
            default:
                return false
        }
    }

    private static func checkFastStatus(
        _ status: AbysmStatus,
        target: AnyObject,
        selector: String,
        exception: NSString?
    ) throws(RuntimeError) {
        switch status {
            case .OK:
                return
            case .noSignature:
                throw .selectorNotFound(class: String(describing: type(of: target)), selector: selector)
            case .raised:
                throw .raised(selector: selector, exception: (exception as String?) ?? "unknown")
            default:
                throw .sizeMismatch(selector: selector)
        }
    }

    /// The expected signature for a declaration: result, receiver, selector, then each argument.
    static func signature(result: String, arguments: [String]) -> String {
        result + "@:" + arguments.joined()
    }

    private struct VerificationKey: Hashable {
        var cls: ObjectIdentifier
        var selector: String
        var classMethod: Bool
        var expected: String
    }

    /// Verdicts already reached. A signature does not change while a class stays loaded, so a verdict is computed
    /// once per (class, selector, declaration) and every later access costs a dictionary lookup instead of building
    /// an \`NSMethodSignature\`. Failures are cached too, so a symbol that is gone is not re-derived every frame.
    private static let verdicts = Mutex<[VerificationKey: RuntimeError?]>([:])

    /// Checks whether `cls` implements `selector`.
    static func hasSelector(class cls: AnyClass, selector: String, classMethod: Bool) -> Bool {
        let sel = NSSelectorFromString(selector)
        return abysm_signature(cls, sel, classMethod) != nil
    }

    /// Checks the runtime's signature for a selector against the declaration.
    static func verify(
        class cls: AnyClass,
        selector: String,
        classMethod: Bool,
        expected: String
    ) throws(RuntimeError) {
        let key = VerificationKey(
            cls: ObjectIdentifier(cls), selector: selector, classMethod: classMethod, expected: expected)
        if let cached = verdicts.withLock({ $0[key] }) {
            if let error = cached { throw error }
            return
        }
        let verdict = compute(class: cls, selector: selector, classMethod: classMethod, expected: expected)
        verdicts.withLock { $0[key] = .some(verdict) }
        if let verdict { throw verdict }
    }

    private static func compute(
        class cls: AnyClass,
        selector: String,
        classMethod: Bool,
        expected: String
    ) -> RuntimeError? {
        let sel = NSSelectorFromString(selector)
        guard let actual = abysm_signature(cls, sel, classMethod) else {
            return .selectorNotFound(class: NSStringFromClass(cls), selector: selector)
        }
        guard actual == expected else {
            return .signatureMismatch(selector: selector, expected: expected, actual: actual)
        }
        return nil
    }
}
