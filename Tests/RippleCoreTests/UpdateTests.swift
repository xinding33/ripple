import Foundation
import XCTest
@testable import RippleCore

final class UpdateTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testVersionsCompareNumerically() throws {
        func version(_ string: String) throws -> Version { try XCTUnwrap(Version(string)) }
        XCTAssertLessThan(try version("1.9.0"), try version("1.10.0"))
        XCTAssertLessThan(try version("1.1.0"), try version("v1.1.1"))
        XCTAssertEqual(try version("v1.1"), try version("1.1.0"))
        XCTAssertEqual(try version("v1.1.0").description, "1.1.0")
        XCTAssertNil(Version("1.1.0-beta"))
        XCTAssertNil(Version(""))
    }

    func testReleaseFindsTheZip() throws {
        let json = """
            {"tag_name": "v1.2.0", "html_url": "https://github.com/xinding33/ripple/releases/tag/v1.2.0",
             "assets": [
               {"name": "notes.txt", "browser_download_url": "https://example.com/notes.txt"},
               {"name": "Ripple-1.2.0.zip",
                "browser_download_url": "https://github.com/xinding33/ripple/releases/download/v1.2.0/Ripple-1.2.0.zip"}]}
            """
        let release = try Release(gitHubJSON: Data(json.utf8))
        XCTAssertEqual(release.version, Version("1.2.0"))
        XCTAssertEqual(release.page.absoluteString, "https://github.com/xinding33/ripple/releases/tag/v1.2.0")
        XCTAssertEqual(release.download.lastPathComponent, "Ripple-1.2.0.zip")

        let noZip = #"{"tag_name": "v1.2.0", "html_url": "https://example.com", "assets": []}"#
        XCTAssertThrowsError(try Release(gitHubJSON: Data(noZip.utf8))) {
            XCTAssertEqual($0 as? UpdateError, .noDownload)
        }
    }

    func testInstallsUpdateSignedLikeTheApp() throws {
        let app = try makeApp(in: "installed", version: "1.1.0")
        let update = try zip(makeApp(in: "update", version: "1.2.0"))
        try Updater.install(zip: update, version: XCTUnwrap(Version("1.2.0")), replacing: app)
        XCTAssertEqual(version(of: app), "1.2.0")
    }

    func testRejectsUpdateSignedDifferently() throws {
        let app = try makeApp(in: "installed", version: "1.1.0")
        let update = try zip(makeApp(in: "update", identifier: "test.impostor", version: "1.2.0"))
        XCTAssertThrowsError(try Updater.install(zip: update, version: XCTUnwrap(Version("1.2.0")), replacing: app)) {
            XCTAssertEqual($0 as? UpdateError, .badSignature)
        }
        XCTAssertEqual(version(of: app), "1.1.0")
    }

    func testRejectsUpdateOfTheWrongVersion() throws {
        let app = try makeApp(in: "installed", version: "1.1.0")
        let update = try zip(makeApp(in: "update", version: "1.0.0"))
        XCTAssertThrowsError(try Updater.install(zip: update, version: XCTUnwrap(Version("1.2.0")), replacing: app)) {
            XCTAssertEqual($0 as? UpdateError, .wrongVersion)
        }
        XCTAssertEqual(version(of: app), "1.1.0")
    }

    func testRejectsModifiedUpdate() throws {
        let app = try makeApp(in: "installed", version: "1.1.0")
        let update = try makeApp(in: "update", version: "1.2.0")
        try Data("tampered".utf8).write(to: update.appendingPathComponent("Contents/MacOS/Ripple"))
        XCTAssertThrowsError(try Updater.install(zip: zip(update), version: XCTUnwrap(Version("1.2.0")), replacing: app)) {
            XCTAssertEqual($0 as? UpdateError, .badSignature)
        }
        XCTAssertEqual(version(of: app), "1.1.0")
    }

    func testSourceBuildIsNotDeveloperIDSigned() throws {
        XCTAssertFalse(Updater.isDeveloperIDSigned(try makeApp(in: "installed", version: "1.1.0")))
    }

    // MARK: - Fixtures

    /// An ad-hoc signed Ripple.app whose designated requirement is just its identifier.
    private func makeApp(in name: String, identifier: String = "test.ripple", version: String) throws -> URL {
        let app = folder.appendingPathComponent(name).appendingPathComponent("Ripple.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: macOS.appendingPathComponent("Ripple").path)
        let info: NSDictionary = [
            "CFBundleIdentifier": identifier, "CFBundleExecutable": "Ripple",
            "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version,
        ]
        try info.write(to: app.appendingPathComponent("Contents/Info.plist"))
        try run("/usr/bin/codesign", "--force", "--sign", "-", "-r=designated => identifier \"\(identifier)\"", app.path)
        return app
    }

    /// Zips `app` the way scripts/release.sh does.
    private func zip(_ app: URL) throws -> URL {
        let zip = app.deletingLastPathComponent().appendingPathComponent("Ripple.zip")
        try run("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app.path, zip.path)
        return zip
    }

    private func run(_ path: String, _ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "\(path) \(arguments)")
    }

    private func version(of app: URL) -> String? {
        NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
    }
}
