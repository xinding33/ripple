import Foundation
import XCTest
@testable import RippleCore

final class MessageTests: XCTestCase {
    private func signedWake(code: String = "ABCD-EFGH-JKLM-NPQR") -> Message {
        var message = Message(kind: .wake, sender: UUID(), senderName: "Mac Studio")
        MessageSigner(pairingCode: code).sign(&message)
        return message
    }

    func testSignedMessageVerifiesWithSameCode() {
        XCTAssertTrue(MessageSigner(pairingCode: "ABCD-EFGH-JKLM-NPQR").verify(signedWake()))
    }

    func testCodeIsCaseAndWhitespaceInsensitive() {
        XCTAssertTrue(MessageSigner(pairingCode: "  abcd-efgh-jklm-npqr\n").verify(signedWake()))
    }

    func testDifferentCodeFails() {
        XCTAssertFalse(MessageSigner(pairingCode: "ZZZZ-ZZZZ-ZZZZ-ZZZZ").verify(signedWake()))
    }

    func testTamperedFieldsFail() {
        let signer = MessageSigner(pairingCode: "ABCD-EFGH-JKLM-NPQR")
        var kind = signedWake(); kind.kind = .ping
        var time = signedWake(); time.timestamp += 1
        var name = signedWake(); name.senderName = "Someone Else"
        var unsigned = signedWake(); unsigned.signature = nil
        for message in [kind, time, name, unsigned] {
            XCTAssertFalse(signer.verify(message))
        }
    }

    func testSignatureSurvivesJSONRoundTrip() throws {
        let data = try JSONEncoder().encode(signedWake())
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertTrue(MessageSigner(pairingCode: "ABCD-EFGH-JKLM-NPQR").verify(decoded))
    }

    func testGeneratedCodeFormat() {
        let code = PairingCode.generate()
        XCTAssertNotNil(code.range(of: #"^[A-HJ-NP-Z2-9]{4}(-[A-HJ-NP-Z2-9]{4}){3}$"#, options: .regularExpression))
        XCTAssertNotEqual(code, PairingCode.generate())
    }
}
