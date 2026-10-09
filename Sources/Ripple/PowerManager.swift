import Foundation
import IOKit.ps
import IOKit.pwr_mgt

final class PowerManager {
    private var enabled = false
    private var onlyOnAC = true
    private var assertionID: IOPMAssertionID = 0
    private(set) var isKeepingAwake = false
    private var powerSourceRunLoopSource: CFRunLoopSource?

    init() {
        // Re-evaluate the keep-awake assertion whenever the power source changes (plugged in / unplugged).
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            Unmanaged<PowerManager>.fromOpaque(context).takeUnretainedValue().update()
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            powerSourceRunLoopSource = source
        }
    }

    func configure(enabled: Bool, onlyOnAC: Bool) {
        self.enabled = enabled
        self.onlyOnAC = onlyOnAC
        update()
    }

    static var isOnACPower: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return true }
        return (type as String) == kIOPMACPowerKey
    }

    /// Wakes the display the same way `caffeinate -u` does: by declaring local user activity.
    func wakeDisplay() {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionDeclareUserActivity("Ripple wake request" as CFString, kIOPMUserActiveLocal, &id)
        guard result == kIOReturnSuccess else {
            log.error("IOPMAssertionDeclareUserActivity failed: \(result)")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { IOPMAssertionRelease(id) }
    }

    private func update() {
        let shouldKeepAwake = enabled && (!onlyOnAC || Self.isOnACPower)
        if shouldKeepAwake && !isKeepingAwake {
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertPreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Ripple keeps this Mac reachable so it can wake with your other Macs" as CFString,
                &assertionID
            )
            isKeepingAwake = result == kIOReturnSuccess
        } else if !shouldKeepAwake && isKeepingAwake {
            IOPMAssertionRelease(assertionID)
            isKeepingAwake = false
        }
    }
}
