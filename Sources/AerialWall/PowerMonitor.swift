import Foundation
import IOKit.ps

/// Watches the Mac's power source and reports whether it is on AC power.
/// Desktop Macs with no battery always report true.
final class PowerMonitor {
    var onChange: ((_ isOnACPower: Bool) -> Void)?
    private var runLoopSource: CFRunLoopSource?

    static func isOnACPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeRetainedValue() as String?
        else { return true }
        return type == kIOPMACPowerKey
    }

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.onChange?(PowerMonitor.isOnACPower())
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else { return }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
    }
}
