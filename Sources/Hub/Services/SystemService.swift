import Foundation
import IOKit.ps
import Observation

@Observable @MainActor
final class SystemService {
    var batteryLevel: Int?
    var isCharging = false
    var onAC = false
    var minutesLeft: Int?

    func refresh() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            batteryLevel = desc[kIOPSCurrentCapacityKey] as? Int
            isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            onAC = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let left = desc[kIOPSTimeToEmptyKey] as? Int ?? -1
            minutesLeft = (!onAC && left > 0) ? left : nil
        }
    }

}
