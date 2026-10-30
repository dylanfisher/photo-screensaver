import AVFoundation
import Primitives

public struct MotionError: Error, CustomStringConvertible {
  public let description: String
}

/// Turns the camera on for a few seconds and reports whether anything moved. Frames are compared
/// in memory at 64×48 grayscale and never kept.
public final class MotionDetector: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
  /// Ignored from the first frame on, while the camera adjusts its exposure.
  static let warmUpSeconds = 1.0
  /// The camera can take a few seconds to start on older Macs, longer if another app holds it.
  static let startTimeoutSeconds = 6.0
  /// Frames are compared this far apart, so slow movement still adds up to a visible change.
  static let compareEverySeconds = 0.5

  private let queue = DispatchQueue(label: "photo-screensaver.motion")
  /// startRunning can block for seconds while another app holds the camera; on its own queue it
  /// can't hold up frame handling, the start timeout, or cancellation.
  private let sessionQueue = DispatchQueue(label: "photo-screensaver.motion-session")
  // Touched only on `queue`.
  private var reference: (frame: GrayFrame, time: Double)?
  private var maxChange = 0.0
  private var comparisons = 0
  private var firstFrameTime: Double?

  /// True when at least `threshold` of the image changed between any two compared frames
  /// during `seconds`, after the warm-up. Throws if the camera delivers too few frames to
  /// tell, rather than reporting no motion and sleeping the display on someone.
  public func detect(for seconds: Double, threshold: Double) async throws -> Bool {
    try await Self.requestAccess()
    guard let camera = AVCaptureDevice.default(for: .video) else {
      throw MotionError(description: "no camera found")
    }
    let session = AVCaptureSession()
    session.sessionPreset = .low
    let input = try AVCaptureDeviceInput(device: camera)
    let output = AVCaptureVideoDataOutput()
    output.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    ]
    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(self, queue: queue)
    guard session.canAddInput(input), session.canAddOutput(output) else {
      throw MotionError(description: "camera can't be configured for capture")
    }
    session.addInput(input)
    session.addOutput(output)

    queue.sync {
      reference = nil
      maxChange = 0
      comparisons = 0
      firstFrameTime = nil
    }
    sessionQueue.async { session.startRunning() }
    // Detach first so a stopping session can't feed frames into the next check.
    let stop = { [sessionQueue] in
      output.setSampleBufferDelegate(nil, queue: nil)
      sessionQueue.async { session.stopRunning() }
    }
    do {
      let deadline = CACurrentMediaTime() + Self.startTimeoutSeconds
      while queue.sync(execute: { firstFrameTime == nil }) {
        guard CACurrentMediaTime() < deadline else {
          throw MotionError(
            description:
              "camera sent no frames in \(Int(Self.startTimeoutSeconds)) s; is another app using it?"
          )
        }
        try await Task.sleep(nanoseconds: 100_000_000)
      }
      try await Task.sleep(nanoseconds: UInt64((Self.warmUpSeconds + seconds) * 1e9))
    } catch {
      // Cancelled or timed out: the camera must still go off.
      stop()
      throw error
    }
    stop()
    let (change, compared) = queue.sync { (maxChange, comparisons) }
    guard compared > 0 else {
      throw MotionError(description: "camera sent too few frames to compare")
    }
    return change >= threshold
  }

  public func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    let now = CACurrentMediaTime()
    if firstFrameTime == nil { firstFrameTime = now }
    guard let firstFrameTime, now - firstFrameTime >= Self.warmUpSeconds,
      let pixels = CMSampleBufferGetImageBuffer(sampleBuffer)
    else { return }
    if let reference, now - reference.time < Self.compareEverySeconds { return }

    CVPixelBufferLockBaseAddress(pixels, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
    guard let luma = CVPixelBufferGetBaseAddressOfPlane(pixels, 0) else { return }
    let frame = GrayFrame(
      sampling: luma.assumingMemoryBound(to: UInt8.self),
      width: CVPixelBufferGetWidthOfPlane(pixels, 0),
      height: CVPixelBufferGetHeightOfPlane(pixels, 0),
      bytesPerRow: CVPixelBufferGetBytesPerRowOfPlane(pixels, 0),
      toWidth: 64, height: 48)
    if let reference {
      maxChange = max(maxChange, frame.changedFraction(from: reference.frame))
      comparisons += 1
    }
    reference = (frame, now)
  }

  private static func requestAccess() async throws {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      return
    case .notDetermined:
      if await AVCaptureDevice.requestAccess(for: .video) { return }
    default:
      break
    }
    throw MotionError(
      description:
        "camera access denied; allow it in System Preferences › Security & Privacy › Camera")
  }
}
