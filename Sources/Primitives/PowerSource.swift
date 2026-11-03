import IOKit.ps

public struct PowerSourceError: Error, CustomStringConvertible {
  public let description: String
}

/// Where the Mac's power comes from.
public enum PowerSource {
  /// Whether the Mac runs on its battery rather than a power adapter. A Mac without a battery
  /// is never on one.
  public static func onBattery() throws -> Bool {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue()
    else {
      throw PowerSourceError(description: "can't read the power source")
    }
    return type as String == kIOPSBatteryPowerValue
  }
}
