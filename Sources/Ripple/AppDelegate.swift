import AppKit
import Combine
import RippleCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// After being woken by a peer, don't treat our own display wake as a reason to wake everyone again.
    private static let remoteWakeEchoWindow: TimeInterval = 15
    private static let minAutoWakeInterval: TimeInterval = 5

    private let settings = AppSettings.shared
    private let power = PowerManager()
    private let hotKeys = HotKeyManager()
    private lazy var network = PeerNetwork(installID: settings.installID, localName: localName)
    private let localName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName

    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var isMenuOpen = false
    private var ignoreScreenWakeUntil = Date.distantPast
    private var lastAutoWake = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Opening Ripple while it already runs (say, from the login agent) would advertise this Mac twice.
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
            NSApp.terminate(nil)
            return
        }
        installMainMenu()
        LoginItem.refresh()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setStatusIcon("display.2")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        network.onWake = { [weak self] in self?.handleRemoteWake() }
        network.onPeersChanged = { [weak self] in self?.refreshOpenMenu() }
        hotKeys.action = { [weak self] in self?.wakeAll() }

        settings.$pairingCode
            .sink { [weak self] code in self?.network.signer = code.isEmpty ? nil : MessageSigner(pairingCode: code) }
            .store(in: &cancellables)
        settings.$keepAwake.combineLatest(settings.$keepAwakeOnlyOnAC)
            .sink { [weak self] enabled, onlyOnAC in self?.power.configure(enabled: enabled, onlyOnAC: onlyOnAC) }
            .store(in: &cancellables)
        settings.$shortcut
            .sink { [weak self] shortcut in self?.hotKeys.register(shortcut) }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(screensDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil
        )

        network.start()
        if settings.pairingCode.isEmpty { showSettings() }
    }

    // MARK: - Waking

    @objc private func wakeAll() {
        guard !settings.pairingCode.isEmpty else { return showSettings() }
        network.broadcastWake()
        flashStatusIcon()
    }

    @objc private func screensDidWake() {
        let now = Date()
        guard settings.autoWake, !settings.pairingCode.isEmpty,
              now > ignoreScreenWakeUntil,
              now.timeIntervalSince(lastAutoWake) > Self.minAutoWakeInterval else { return }
        lastAutoWake = now
        log.info("Display woke; waking peers")
        network.broadcastWake()
    }

    private func handleRemoteWake() {
        ignoreScreenWakeUntil = Date().addingTimeInterval(Self.remoteWakeEchoWindow)
        power.wakeDisplay()
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        network.pingAll()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }

    private func refreshOpenMenu() {
        if isMenuOpen, let menu = statusItem.menu { rebuild(menu) }
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(disabledItem("Ripple · \(localName)"))
        menu.addItem(.separator())

        if settings.pairingCode.isEmpty {
            menu.addItem(item("Set a Pairing Code…", #selector(showSettings)))
        } else {
            let peers = network.peers
            if peers.isEmpty { menu.addItem(disabledItem("No other Macs found")) }
            for peer in peers {
                let (symbol, detail) = describe(peer.status)
                let peerItem = disabledItem(detail.map { "\(peer.name) — \($0)" } ?? peer.name)
                peerItem.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                menu.addItem(peerItem)
            }
        }
        menu.addItem(.separator())

        let wakeItem = item("Wake All Macs", #selector(wakeAll))
        if let shortcut = settings.shortcut, let key = shortcut.menuKeyEquivalent {
            wakeItem.keyEquivalent = key
            wakeItem.keyEquivalentModifierMask = shortcut.modifierFlags
        }
        menu.addItem(wakeItem)
        menu.addItem(.separator())

        menu.addItem(toggle("Wake Others When This Mac Wakes", settings.autoWake, #selector(toggleAutoWake)))
        let keepAwakeTitle = settings.keepAwake && !power.isKeepingAwake
            ? "Keep This Mac Awake (paused on battery)"
            : "Keep This Mac Awake"
        menu.addItem(toggle(keepAwakeTitle, settings.keepAwake, #selector(toggleKeepAwake)))
        let acItem = toggle("Only on Power Adapter", settings.keepAwakeOnlyOnAC, #selector(toggleOnlyOnAC))
        acItem.indentationLevel = 1
        acItem.action = settings.keepAwake ? #selector(toggleOnlyOnAC) : nil
        menu.addItem(acItem)
        menu.addItem(.separator())

        menu.addItem(toggle("Open at Login", LoginItem.isEnabled, #selector(toggleOpenAtLogin)))
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        menu.addItem(item("Quit Ripple", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private func describe(_ status: PeerNetwork.PeerStatus) -> (symbol: String, detail: String?) {
        switch status {
        case .verified: return ("checkmark.circle.fill", nil)
        case .checking: return ("ellipsis.circle", "checking…")
        case .mismatch: return ("exclamationmark.triangle.fill", "pairing code doesn't match")
        case .noResponse: return ("questionmark.circle", "not responding")
        }
    }

    private func item(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        return item
    }

    private func toggle(_ title: String, _ isOn: Bool, _ action: Selector) -> NSMenuItem {
        let item = item(title, action)
        item.state = isOn ? .on : .off
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func toggleAutoWake() { settings.autoWake.toggle() }
    @objc private func toggleKeepAwake() { settings.keepAwake.toggle() }
    @objc private func toggleOnlyOnAC() { settings.keepAwakeOnlyOnAC.toggle() }

    @objc private func toggleOpenAtLogin() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }

    // MARK: - Settings window

    @objc private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings) { [weak self] recording in
                guard let self else { return }
                recording ? self.hotKeys.unregister() : self.hotKeys.register(self.settings.shortcut)
            }
            let controller = NSHostingController(rootView: view)
            controller.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: controller)
            window.title = "Ripple Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Menu bar apps have no visible main menu, but one is still needed for ⌘C/⌘V/⌘W in the settings window.
    private func installMainMenu() {
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    // MARK: - Status icon

    private func setStatusIcon(_ symbol: String) {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Ripple")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func flashStatusIcon() {
        setStatusIcon("bolt.fill")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.setStatusIcon("display.2") }
    }
}
