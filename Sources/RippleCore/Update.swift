import Foundation
import Security

/// A version like 1.1.0, compared part by part, so 1.10 comes after 1.9 and 1.1 equals 1.1.0.
public struct Version: Comparable, CustomStringConvertible {
    public let parts: [Int]
    public let description: String

    /// Parses "1.1.0" or a tag like "v1.1.0".
    public init?(_ string: String) {
        let text = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.allSatisfy({ $0 != nil }) else { return nil }
        self.parts = parts.compactMap { $0 }
        description = text
    }

    private func padded(to count: Int) -> [Int] {
        parts + Array(repeating: 0, count: max(0, count - parts.count))
    }

    public static func == (a: Version, b: Version) -> Bool {
        let count = max(a.parts.count, b.parts.count)
        return a.padded(to: count) == b.padded(to: count)
    }

    public static func < (a: Version, b: Version) -> Bool {
        let count = max(a.parts.count, b.parts.count)
        return a.padded(to: count).lexicographicallyPrecedes(b.padded(to: count))
    }
}

public enum UpdateError: LocalizedError, Equatable {
    case noDownload, httpStatus(Int), unzipFailed, badSignature, wrongVersion

    public var errorDescription: String? {
        switch self {
        case .noDownload: return "The latest release has no Ripple download."
        case .httpStatus(let status): return "GitHub responded with HTTP status \(status)."
        case .unzipFailed: return "The download couldn't be unzipped."
        case .badSignature: return "The download isn't signed by Ripple's developer."
        case .wrongVersion: return "The download isn't the version it should be."
        }
    }
}

/// A release published on GitHub.
public struct Release {
    public let version: Version
    /// The release notes.
    public let page: URL
    /// Ripple-VERSION.zip, as published by .github/workflows/release.yml.
    public let download: URL

    /// Parses a response from GitHub's latest release API.
    public init(gitHubJSON data: Data) throws {
        struct Response: Decodable {
            struct Asset: Decodable {
                let name: String
                let browserDownloadUrl: URL
            }
            let tagName: String
            let htmlUrl: URL
            let assets: [Asset]
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(Response.self, from: data)
        guard let version = Version(response.tagName),
              let asset = response.assets.first(where: { $0.name == "Ripple-\(version).zip" })
        else { throw UpdateError.noDownload }
        self.version = version
        page = response.htmlUrl
        download = asset.browserDownloadUrl
    }
}

/// Updates Ripple in place from its GitHub releases. An update is installed only if it's signed to
/// satisfy the designated requirement of the app it replaces, so only release builds take releases.
public enum Updater {
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/xinding33/ripple/releases/latest")!

    public static func latestRelease() async throws -> Release {
        var request = URLRequest(url: latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response)
        return try Release(gitHubJSON: data)
    }

    /// Downloads `release` and installs it in place of `app`. Relaunch afterwards to run it.
    public static func install(_ release: Release, replacing app: URL) async throws {
        let (zip, response) = try await URLSession.shared.download(from: release.download)
        defer { try? FileManager.default.removeItem(at: zip) }
        try check(response)
        try install(zip: zip, version: release.version, replacing: app)
    }

    /// Unzips Ripple.app from `zip`, checks that it's `version` and is signed to satisfy `app`'s
    /// designated requirement, then swaps it in for `app`.
    public static func install(zip: URL, version: Version, replacing app: URL) throws {
        let requirement = try designatedRequirement(of: app)
        let files = FileManager.default
        // On the same volume as the app, so the swap is a rename.
        let staging = try files.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true)
        defer { try? files.removeItem(at: staging) }

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, staging.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else { throw UpdateError.unzipFailed }

        let update = staging.appendingPathComponent("Ripple.app")
        guard satisfies(update, requirement) else { throw UpdateError.badSignature }
        let info = NSDictionary(contentsOf: update.appendingPathComponent("Contents/Info.plist"))
        guard let updateVersion = (info?["CFBundleShortVersionString"] as? String).flatMap(Version.init),
              updateVersion == version
        else { throw UpdateError.wrongVersion }

        _ = try files.replaceItemAt(app, withItemAt: update)
    }

    /// Whether `app` is signed with a Developer ID, as releases are. Builds from source aren't, so
    /// they can't install releases.
    public static func isDeveloperIDSigned(_ app: URL) -> Bool {
        let developerID = "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(developerID as CFString, [], &requirement) == errSecSuccess,
              let requirement
        else { return false }
        return satisfies(app, requirement)
    }

    static func designatedRequirement(of app: URL) throws -> SecRequirement {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess, let requirement
        else { throw UpdateError.badSignature }
        return requirement
    }

    static func satisfies(_ app: URL, _ requirement: SecRequirement) -> Bool {
        var code: SecStaticCode?
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return false }
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    private static func check(_ response: URLResponse) throws {
        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
            throw UpdateError.httpStatus(status)
        }
    }
}
