import Foundation
import XCTest
@testable import RippleCore

private final class MemoryDefaults: PreferenceDomains {
    var domains: [String: [String: Any]] = [:]
    func persistentDomain(forName domainName: String) -> [String: Any]? { domains[domainName] }
    func setPersistentDomain(_ domain: [String: Any], forName domainName: String) { domains[domainName] = domain }
    func removePersistentDomain(forName domainName: String) { domains[domainName] = nil }
}

final class LegacyMigrationTests: XCTestCase {
    private let legacy = "com.xinding.Ripple"
    private let domain = "io.github.xinding33.ripple"
    private let defaults = MemoryDefaults()
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testDefaultsMoveToNewDomainOnce() {
        defaults.setPersistentDomain(["pairingCode": "ABCD-EFGH-JKLM-NPQR", "installID": "old", "autoWake": false], forName: legacy)
        defaults.setPersistentDomain(["installID": "new"], forName: domain)
        LegacyMigration.migrateDefaults(from: legacy, to: domain, in: defaults)
        let migrated = defaults.persistentDomain(forName: domain)
        XCTAssertEqual(migrated?["pairingCode"] as? String, "ABCD-EFGH-JKLM-NPQR")
        XCTAssertEqual(migrated?["autoWake"] as? Bool, false)
        XCTAssertEqual(migrated?["installID"] as? String, "new")
        XCTAssertNil(defaults.persistentDomain(forName: legacy))

        defaults.setPersistentDomain(["pairingCode": "ZZZZ-ZZZZ-ZZZZ-ZZZZ"], forName: domain)
        LegacyMigration.migrateDefaults(from: legacy, to: domain, in: defaults)
        XCTAssertEqual(defaults.persistentDomain(forName: domain)?["pairingCode"] as? String, "ZZZZ-ZZZZ-ZZZZ-ZZZZ")
    }

    func testLegacyAgentIsReplacedWithOneForThisApp() throws {
        let old = LaunchAgent(label: legacy, directory: folder)
        let new = LaunchAgent(label: domain, directory: folder)
        try old.write(executable: "/opt/homebrew/opt/ripple/Ripple.app/Contents/MacOS/Ripple")
        try new.replace(old, executable: "/Applications/Ripple.app/Contents/MacOS/Ripple")
        XCTAssertFalse(old.exists)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: new.url), format: nil) as? [String: Any])
        XCTAssertEqual(plist["Label"] as? String, domain)
        XCTAssertEqual(plist["ProgramArguments"] as? [String], ["/Applications/Ripple.app/Contents/MacOS/Ripple"])
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
    }

    func testNoLegacyAgentLeavesOpenAtLoginOff() throws {
        let new = LaunchAgent(label: domain, directory: folder)
        try new.replace(LaunchAgent(label: legacy, directory: folder), executable: "/Applications/Ripple.app/Contents/MacOS/Ripple")
        XCTAssertFalse(new.exists)
    }
}
