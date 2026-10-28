import Foundation

/// A released version: `MAJOR.MINOR.PATCH`, optionally `-beta.N` or the fork's `-konata.N`.
struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int
    /// Nil on a stable release, which outranks every prerelease of the same triple.
    let beta: Int?
    /// The fork's stable revision; nil on upstream's plain triple.
    let fork: Int?

    init?(_ text: String) {
        var body = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        // Release tags carry a leading `v`; `CFBundleShortVersionString` never does.
        if body.first == "v" { body = body.dropFirst() }

        let halves = body.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = halves[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3,
            let major = Self.number(numbers[0]),
            let minor = Self.number(numbers[1]),
            let patch = Self.number(numbers[2])
        else { return nil }

        var beta: Int?
        var fork: Int?
        if halves.count == 2 {
            let suffix = halves[1].split(separator: ".", omittingEmptySubsequences: false)
            guard suffix.count == 2, let count = Self.number(suffix[1]) else { return nil }
            switch suffix[0] {
            case "beta": beta = count
            case "konata": fork = count
            // `beta` and this fork's stable suffix are the only channels that ship.
            default: return nil
            }
        }
        self.major = major
        self.minor = minor
        self.patch = patch
        self.beta = beta
        self.fork = fork
    }

    var isPrerelease: Bool { beta != nil }

    var description: String {
        let triple = "\(major).\(minor).\(patch)"
        if let beta { return "\(triple)-beta.\(beta)" }
        return fork.map { "\(triple)-konata.\($0)" } ?? triple
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.beta, rhs.beta) {
        case (.some, nil): return true
        case (nil, .some): return false
        case (.some(let left), .some(let right)) where left != right: return left < right
        default: break
        }
        return (lhs.fork ?? 0) < (rhs.fork ?? 0)
    }

    /// Rejects a signed or padded field, which `Int` would silently reinterpret.
    private static func number(_ text: Substring) -> Int? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(text)
    }
}

extension AppVersion: Codable {
    init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = AppVersion(text) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(), debugDescription: "Not a version: \(text)")
        }
        self = parsed
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
