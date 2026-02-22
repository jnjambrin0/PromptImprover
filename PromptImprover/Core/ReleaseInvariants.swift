import Foundation

struct ReleaseVersion: Equatable, Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^[0-9]+(\.[0-9]+){0,2}$"#, options: .regularExpression) != nil else {
            return nil
        }

        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard let major = Int(parts[0]) else {
            return nil
        }

        let minor = parts.count > 1 ? Int(parts[1]) ?? -1 : 0
        let patch = parts.count > 2 ? Int(parts[2]) ?? -1 : 0
        guard minor >= 0, patch >= 0 else {
            return nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    var normalized: String {
        "\(major).\(minor).\(patch)"
    }
}

enum ReleaseInvariantViolation: Error, Equatable {
    case invalidBundleVersion(String)
    case invalidShortVersion(String)
    case nonMonotonicBuildVersion(current: String, highestPublished: String)
    case bundleIdentifierMismatch(expected: String, found: String)
    case appcastVersionMismatch(expectedBuild: String, foundBuild: String)
    case appcastShortVersionMismatch(expectedShort: String, foundShort: String)
}

struct ReleaseInvariantValidator {
    static func validateBundleIdentifier(expected: String, found: String) throws {
        guard expected == found else {
            throw ReleaseInvariantViolation.bundleIdentifierMismatch(expected: expected, found: found)
        }
    }

    static func validateBundleVersion(_ version: String) throws -> ReleaseVersion {
        guard let parsed = ReleaseVersion(rawValue: version) else {
            throw ReleaseInvariantViolation.invalidBundleVersion(version)
        }
        return parsed
    }

    static func validateShortVersion(_ version: String) throws -> ReleaseVersion {
        guard let parsed = ReleaseVersion(rawValue: version) else {
            throw ReleaseInvariantViolation.invalidShortVersion(version)
        }
        return parsed
    }

    static func validateMonotonicBuildVersion(current: String, published: [String]) throws {
        let currentVersion = try validateBundleVersion(current)

        let highestPublished = published
            .compactMap { ReleaseVersion(rawValue: $0) }
            .max()

        if let highestPublished, currentVersion <= highestPublished {
            throw ReleaseInvariantViolation.nonMonotonicBuildVersion(
                current: currentVersion.normalized,
                highestPublished: highestPublished.normalized
            )
        }
    }

    static func validateAppcastMapping(
        expectedBuildVersion: String,
        expectedShortVersion: String,
        appcastBuildVersion: String,
        appcastShortVersion: String
    ) throws {
        guard expectedBuildVersion == appcastBuildVersion else {
            throw ReleaseInvariantViolation.appcastVersionMismatch(
                expectedBuild: expectedBuildVersion,
                foundBuild: appcastBuildVersion
            )
        }

        guard expectedShortVersion == appcastShortVersion else {
            throw ReleaseInvariantViolation.appcastShortVersionMismatch(
                expectedShort: expectedShortVersion,
                foundShort: appcastShortVersion
            )
        }
    }
}
