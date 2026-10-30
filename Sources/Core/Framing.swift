import CoreGraphics
import Settings

/// Size a photo is drawn at on a screen of `view` size before any Ken Burns zoom.
/// `fill` covers the screen and crops; `fit` shows the whole photo.
public func displayedSize(photo: CGSize, in view: CGSize, scaling: Settings.Scaling) -> CGSize {
  let widthRatio = view.width / photo.width
  let heightRatio = view.height / photo.height
  let scale = scaling == .fill ? max(widthRatio, heightRatio) : min(widthRatio, heightRatio)
  return CGSize(width: photo.width * scale, height: photo.height * scale)
}

/// Longest edge, in pixels, to decode a photo at: 2× its displayed size on a screen of
/// `screenPixels` when zoomed in by `zoom`, so it stays sharp at the deepest Ken Burns zoom.
/// Capped at the original, since decoding never scales up.
public func decodeLongEdge(
  photo: CGSize, screenPixels: CGSize, scaling: Settings.Scaling, zoom: CGFloat
) -> Int {
  let shown = displayedSize(photo: photo, in: screenPixels, scaling: scaling)
  let wanted = (2 * zoom * max(shown.width, shown.height)).rounded()
  return Int(min(wanted, max(photo.width, photo.height)))
}
