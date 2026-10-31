import IOKit

public struct LightSensorError: Error, CustomStringConvertible {
  public let description: String
}

/// Reads the ambient light sensor beside the camera on Intel MacBooks, through the undocumented
/// AppleLMUController service. Readings are in the sensor's own units; only changes in them mean
/// anything. Reading doesn't use the camera.
public final class LightSensor {
  private let connection: io_connect_t

  public init() throws {
    let service = IOServiceGetMatchingService(
      kIOMainPortDefault, IOServiceMatching("AppleLMUController"))
    guard service != 0 else {
      throw LightSensorError(description: "no ambient light sensor found")
    }
    defer { IOObjectRelease(service) }
    var connection: io_connect_t = 0
    let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
    guard result == KERN_SUCCESS else {
      throw LightSensorError(description: "can't open the ambient light sensor (error \(result))")
    }
    self.connection = connection
  }

  deinit {
    IOServiceClose(connection)
  }

  /// The average of the sensor's two channels.
  public func read() throws -> Double {
    var values = [UInt64](repeating: 0, count: 2)
    var count: UInt32 = 2
    let result = IOConnectCallMethod(connection, 0, nil, 0, nil, 0, &values, &count, nil, nil)
    guard result == KERN_SUCCESS, count == 2 else {
      throw LightSensorError(description: "can't read the ambient light sensor (error \(result))")
    }
    return Double(values[0] + values[1]) / 2
  }
}
