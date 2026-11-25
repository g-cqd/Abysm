import Foundation

enum DocumentationLayout {
    struct Record: Equatable {
        var url: URL
        var text: String

        var status: String? {
            lines.first { $0.hasPrefix("status:") }
                .map { String($0.dropFirst("status:".count)).trimmingCharacters(in: .whitespaces) }
        }

        var titleCount: Int {
            lines.count { $0.hasPrefix("# ") }
        }

        private var lines: [Substring] {
            text.split(separator: "\n", omittingEmptySubsequences: false)
        }
    }

    static let repositoryRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func decisionRecords() throws -> [Record] {
        let dir = repositoryRoot.appending(path: "docs/adr")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".md") && $0 != "README.md" }
            .sorted()
        return try names.map { name in
            let url = dir.appending(path: name)
            return Record(url: url, text: try String(contentsOf: url, encoding: .utf8))
        }
    }

    static func repeatedNumbers(in names: [String]) -> [String] {
        var counts: [String: Int] = [:]
        for name in names {
            let prefix = String(name.prefix(4))
            if prefix.count == 4, prefix.allSatisfy(\.isNumber) {
                counts[prefix, default: 0] += 1
            }
        }
        return counts.filter { $0.value > 1 }.map(\.key).sorted()
    }
}
