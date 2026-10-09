import CryptoKit
import Foundation

public enum MessageKind: String, Codable {
    case wake, ping, pong
    /// Unsigned reply to a ping whose signature didn't verify, so the sender can report a code mismatch.
    case authFailed
}

public struct Message: Codable {
    public var kind: MessageKind
    public var id: UUID
    public var sender: UUID
    public var senderName: String
    /// Milliseconds since 1970; receivers reject messages that are too old.
    public var timestamp: Int64
    public var signature: String?

    public init(kind: MessageKind, id: UUID = UUID(), sender: UUID, senderName: String,
                timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000), signature: String? = nil) {
        self.kind = kind
        self.id = id
        self.sender = sender
        self.senderName = senderName
        self.timestamp = timestamp
        self.signature = signature
    }

    var signedPayload: Data {
        Data("\(kind.rawValue)|\(id.uuidString)|\(sender.uuidString)|\(senderName)|\(timestamp)".utf8)
    }
}

public struct MessageSigner {
    private let key: SymmetricKey

    public init(pairingCode: String) {
        key = SymmetricKey(data: SHA256.hash(data: Data("ripple-v1:\(PairingCode.normalize(pairingCode))".utf8)))
    }

    public func sign(_ message: inout Message) {
        let mac = HMAC<SHA256>.authenticationCode(for: message.signedPayload, using: key)
        message.signature = Data(mac).base64EncodedString()
    }

    public func verify(_ message: Message) -> Bool {
        guard let signature = message.signature, let mac = Data(base64Encoded: signature) else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: message.signedPayload, using: key)
    }
}

public enum PairingCode {
    public static func normalize(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Four groups of four characters, skipping look-alikes (0/O, 1/I).
    public static func generate() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return (0..<4)
            .map { _ in String((0..<4).map { _ in alphabet.randomElement()! }) }
            .joined(separator: "-")
    }
}
