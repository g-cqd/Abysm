# CI

`.github/workflows/ci.yml` calls the family's pinned swift-ci workflow, configured by `action.json`, next to this
package's iOS Simulator job; run the same checks locally with `.ci/swift-ci local`.

Each change runs quality (swift-format, the shipped-library discipline over `Sources`, the analyzers), the macOS
debug tests and macOS AddressSanitizer (on every change, as before), and the tests on an iOS Simulator for the
iOS 18.6 floor and the latest runtime. Release and ThreadSanitizer runs are nightly or manual. There is no Linux
leg: the runtime interoperation needs Objective-C.

`baselines/dolly.json` accepts the duplication that predates dolly's adoption (7 findings); only a new one fails.
