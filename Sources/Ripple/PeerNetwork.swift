import Foundation
import Network
import os
import RippleCore

let log = Logger(subsystem: "com.xinding.Ripple", category: "app")

/// Advertises this Mac over Bonjour, tracks other Ripple Macs, and exchanges signed UDP messages.
/// All callbacks run on the main queue.
final class PeerNetwork {
    enum PeerStatus { case checking, verified, mismatch, noResponse }
    struct Peer { let name: String; let status: PeerStatus }

    static let serviceType = "_ripple-wake._udp"
    static let maxMessageAge: TimeInterval = 120
    private static let pingTimeout: TimeInterval = 3
    private static let pingInterval: TimeInterval = 30
    /// A wake is resent a few times in case the network is still coming up right after the display wakes.
    private static let wakeSendDelays: [TimeInterval] = [0, 2, 5]

    var onWake: (() -> Void)?
    var onPeersChanged: (() -> Void)?
    var signer: MessageSigner? {
        didSet {
            status.removeAll()
            pingAll()
        }
    }

    private let installID: UUID
    private let localName: String
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var ownServiceName: String?
    private var browseResults: Set<NWBrowser.Result> = []
    private var outbound: [String: NWConnection] = [:]
    private var inbound: [ObjectIdentifier: NWConnection] = [:]
    private var status: [String: PeerStatus] = [:]
    private var lastPingSent: [String: Date] = [:]
    private var lastPong: [String: Date] = [:]
    private var seenMessageIDs: [UUID: Date] = [:]
    private var pingTimer: Timer?

    init(installID: UUID, localName: String) {
        self.installID = installID
        self.localName = localName
    }

    var peers: [Peer] {
        outbound.keys.sorted().map { Peer(name: $0, status: status[$0] ?? .checking) }
    }

    func start() {
        startListener()
        startBrowser()
        pingTimer = Timer.scheduledTimer(withTimeInterval: Self.pingInterval, repeats: true) { [weak self] _ in
            self?.pingAll()
        }
    }

    /// Sends a signed wake to every known peer. Returns the number of peers it was sent to.
    @discardableResult
    func broadcastWake() -> Int {
        guard signer != nil else { return 0 }
        let message = makeMessage(.wake)
        for delay in Self.wakeSendDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                for connection in self.outbound.values { self.send(message, on: connection) }
            }
        }
        log.info("Broadcast wake to \(self.outbound.count) peer(s)")
        return outbound.count
    }

    func pingAll() {
        for name in outbound.keys { ping(name) }
    }

    // MARK: - Listener (incoming wakes and pings)

    private func startListener() {
        do {
            let listener = try NWListener(using: .udp)
            listener.service = NWListener.Service(name: localName, type: Self.serviceType)
            listener.serviceRegistrationUpdateHandler = { [weak self] change in
                guard let self, case let .add(endpoint) = change,
                      case let .service(name, _, _, _) = endpoint else { return }
                log.info("Advertising as \(name, privacy: .public)")
                self.ownServiceName = name
                self.rebuildPeers()
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard case let .failed(error) = state else { return }
                log.error("Listener failed: \(error.localizedDescription, privacy: .public); retrying")
                listener?.cancel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self?.startListener() }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            log.error("Couldn't create listener: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func accept(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        inbound[key] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.inbound[key] = nil
            default: break
            }
        }
        connection.start(queue: .main)
        receive(on: connection, peerName: nil)
    }

    // MARK: - Browser (outgoing connections to peers)

    private func startBrowser() {
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .udp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.browseResults = results
            self?.rebuildPeers()
        }
        browser.stateUpdateHandler = { [weak self, weak browser] state in
            guard case let .failed(error) = state else { return }
            log.error("Browser failed: \(error.localizedDescription, privacy: .public); retrying")
            browser?.cancel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self?.startBrowser() }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func rebuildPeers() {
        // The same service can show up once per network interface; keep one endpoint per name.
        var endpoints: [String: NWEndpoint] = [:]
        for result in browseResults {
            guard case let .service(name, _, _, _) = result.endpoint,
                  name != ownServiceName, endpoints[name] == nil else { continue }
            endpoints[name] = result.endpoint
        }

        for (name, connection) in outbound where endpoints[name] == nil {
            connection.cancel()
            outbound[name] = nil
            status[name] = nil
        }
        for (name, endpoint) in endpoints where outbound[name] == nil {
            log.info("Found peer \(name, privacy: .public)")
            outbound[name] = makeConnection(to: endpoint, peerName: name)
            ping(name)
        }
        onPeersChanged?()
    }

    private func makeConnection(to endpoint: NWEndpoint, peerName: String) -> NWConnection {
        let connection = NWConnection(to: endpoint, using: .udp)
        connection.start(queue: .main)
        receive(on: connection, peerName: peerName)
        return connection
    }

    /// Replaces a peer's connection, e.g. after it stops answering because its address changed.
    private func resetConnection(_ name: String) {
        guard let old = outbound[name] else { return }
        old.cancel()
        outbound[name] = makeConnection(to: old.endpoint, peerName: name)
    }

    private func ping(_ name: String) {
        guard let connection = outbound[name], signer != nil else { return }
        let sentAt = Date()
        lastPingSent[name] = sentAt
        if status[name] == nil { status[name] = .checking }
        send(makeMessage(.ping), on: connection)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pingTimeout) { [weak self] in
            guard let self, self.lastPingSent[name] == sentAt,
                  (self.lastPong[name] ?? .distantPast) < sentAt,
                  self.status[name] != .mismatch else { return }
            self.status[name] = .noResponse
            self.resetConnection(name)
            self.onPeersChanged?()
        }
    }

    // MARK: - Messages

    private func receive(on connection: NWConnection, peerName: String?) {
        connection.receiveMessage { [weak self, weak connection] data, _, _, error in
            guard let self, let connection else { return }
            if let data, !data.isEmpty { self.handle(data, from: connection, peerName: peerName) }
            if error == nil || connection.state == .ready {
                self.receive(on: connection, peerName: peerName)
            }
        }
    }

    private func handle(_ data: Data, from connection: NWConnection, peerName: String?) {
        guard let message = try? JSONDecoder().decode(Message.self, from: data),
              message.sender != installID else { return }

        if message.kind == .authFailed {
            if let peerName {
                log.notice("\(peerName, privacy: .public) rejected our pairing code")
                status[peerName] = .mismatch
                onPeersChanged?()
            }
            return
        }

        guard let signer, signer.verify(message) else {
            log.notice("Rejected \(message.kind.rawValue, privacy: .public) from \(message.senderName, privacy: .public): bad signature")
            if message.kind == .ping { send(makeMessage(.authFailed), on: connection) }
            if message.kind == .pong, let peerName {
                status[peerName] = .mismatch
                onPeersChanged?()
            }
            return
        }

        let age = abs(Date().timeIntervalSince1970 - Double(message.timestamp) / 1000)
        guard age < Self.maxMessageAge else { return }
        seenMessageIDs = seenMessageIDs.filter { $0.value.timeIntervalSinceNow > -Self.maxMessageAge * 2 }
        guard seenMessageIDs[message.id] == nil else { return }
        seenMessageIDs[message.id] = Date()

        switch message.kind {
        case .wake:
            log.info("Wake requested by \(message.senderName, privacy: .public)")
            onWake?()
        case .ping:
            send(makeMessage(.pong), on: connection)
        case .pong:
            guard let peerName else { return }
            lastPong[peerName] = Date()
            if status[peerName] != .verified { log.info("Verified peer \(peerName, privacy: .public)") }
            status[peerName] = .verified
            onPeersChanged?()
        case .authFailed:
            break
        }
    }

    private func makeMessage(_ kind: MessageKind) -> Message {
        var message = Message(kind: kind, sender: installID, senderName: localName)
        if kind != .authFailed { signer?.sign(&message) }
        return message
    }

    private func send(_ message: Message, on connection: NWConnection) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }
}
