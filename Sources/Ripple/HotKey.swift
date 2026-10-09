import AppKit
import Carbon.HIToolbox

struct Shortcut: Codable, Equatable {
    var keyCode: UInt16
    /// Raw `NSEvent.ModifierFlags`, limited to ⌃⌥⇧⌘.
    var modifiers: UInt
    /// Display name of the key, e.g. "W" or "Space".
    var key: String

    static let defaultWakeAll = Shortcut(
        keyCode: UInt16(kVK_ANSI_W),
        modifiers: NSEvent.ModifierFlags([.control, .option, .command]).rawValue,
        key: "W"
    )

    init(keyCode: UInt16, modifiers: UInt, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// Returns nil unless the event has at least one modifier other than Shift.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        guard !flags.subtracting(.shift).isEmpty else { return nil }
        self.init(keyCode: event.keyCode, modifiers: flags.rawValue, key: Self.keyName(for: event))
    }

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var displayString: String {
        var result = ""
        if modifierFlags.contains(.control) { result += "⌃" }
        if modifierFlags.contains(.option) { result += "⌥" }
        if modifierFlags.contains(.shift) { result += "⇧" }
        if modifierFlags.contains(.command) { result += "⌘" }
        return result + key
    }

    /// The equivalent for showing this shortcut on an NSMenuItem, if it can be expressed as one.
    var menuKeyEquivalent: String? {
        if key == "Space" { return " " }
        return key.count == 1 ? key.lowercased() : nil
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifierFlags.contains(.control) { result |= UInt32(controlKey) }
        if modifierFlags.contains(.option) { result |= UInt32(optionKey) }
        if modifierFlags.contains(.shift) { result |= UInt32(shiftKey) }
        if modifierFlags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    private static func keyName(for event: NSEvent) -> String {
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case let code where functionKeys.contains(code):
            return "F\(functionKeys.firstIndex(of: code)! + 1)"
        default:
            return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}

/// Registers a single system-wide hotkey through Carbon, which doesn't require Accessibility permission.
final class HotKeyManager {
    var action: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue().action?()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    func register(_ shortcut: Shortcut?) {
        unregister()
        guard let shortcut else { return }
        let id = EventHotKeyID(signature: OSType(0x5754_4B45), id: 1) // 'WTKE'
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode), shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        if status != noErr {
            log.error("Couldn't register \(shortcut.displayString, privacy: .public) (error \(status)); another app may be using it")
        }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }
}
