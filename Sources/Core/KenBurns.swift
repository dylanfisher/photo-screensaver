import CoreGraphics
import Settings

/// A slow pan and zoom across one photo, from `start` to `end`. Both are applied to a layer of
/// `displayedSize(…)` centered on the screen: scale about the center, then offset.
public struct KenBurns: Equatable {
  public struct Frame: Equatable {
    public var scale: CGFloat
    public var offset: CGPoint
  }

  public var start: Frame
  public var end: Frame

  public static let still = KenBurns(
    start: Frame(scale: 1, offset: .zero), end: Frame(scale: 1, offset: .zero))

  /// Zoom range. Small on purpose: past ~20% the motion is noticeable rather than ambient.
  static let minScale: CGFloat = 1.04
  static let maxScale: CGFloat = 1.2

  /// A random move that never shows the background past a `fill` photo's edges, and never pans
  /// a `fit` photo along an axis where it is letterboxed.
  public static func random<G: RandomNumberGenerator>(
    photo: CGSize, view: CGSize, scaling: Settings.Scaling, using generator: inout G
  ) -> KenBurns {
    let base = displayedSize(photo: photo, in: view, scaling: scaling)
    var scales = [
      CGFloat.random(in: minScale...1.1, using: &generator),
      CGFloat.random(in: 1.12...maxScale, using: &generator),
    ]
    if Bool.random(using: &generator) { scales.reverse() }

    func frame(_ scale: CGFloat) -> Frame {
      // Room to pan on each side: how far the zoomed photo overhangs the screen.
      let room = CGSize(
        width: max(0, (base.width * scale - view.width) / 2),
        height: max(0, (base.height * scale - view.height) / 2))
      return Frame(
        scale: scale,
        offset: CGPoint(
          x: CGFloat.random(in: -room.width...room.width, using: &generator),
          y: CGFloat.random(in: -room.height...room.height, using: &generator)))
    }
    return KenBurns(start: frame(scales[0]), end: frame(scales[1]))
  }
}
