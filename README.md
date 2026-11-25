# Abysm

Typed Objective-C runtime interop for Swift 6: resolve classes, validate selector method signatures against the runtime's actual type encodings before dispatch, read and write dynamic properties, and bridge Objective-C exceptions into Swift errors.

```swift
import Abysm
import Foundation

let numbers = try RuntimeClass("NSNumber")
let make = try numbers.method(
    "numberWithInteger:",
    kind: .class,
    as: ((Int) -> NSNumber?).self
)
let answer = try make(42)
```

## Requirements

- Swift 6.3+ (Swift 6 language mode)
- macOS 15+ or iOS 18+

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/g-cqd/Abysm.git", branch: "main")
]
```

Pin a specific `revision:` for reproducible builds.

## Capabilities

- **Signature-verified dispatch:** validates Swift parameter and return types against Objective-C runtime type encodings before invoking a selector, throwing `RuntimeError.signatureMismatch` on mismatch.
- **Exception containment:** catches Objective-C `NSException`s across the bridge and surfaces them as typed Swift errors.
- **Image scoping & dynamic properties:** verify which loaded image defines a class and access properties with typed handles.

## Documentation

- [Architecture Decisions](docs/adr/)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)

## License

[MIT](LICENSE)
