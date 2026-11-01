import AppKit
import Core

/// The photo info panel in the slideshow's bottom-left corner: white text on a dark translucent
/// panel, so it reads over any photo. Sized for the screen it's on.
final class InfoPanel {
  static let fadeSeconds = 0.3

  let layer = CALayer()
  private let text = CATextLayer()
  /// Points per point of a 900-point-tall screen, such as a 1440×900 MacBook Pro's, which the
  /// sizes below are chosen for.
  private let scale: CGFloat

  init(screen: NSScreen) {
    scale = screen.frame.height / 900
    layer.opacity = 0
    layer.backgroundColor = CGColor(gray: 0, alpha: 0.55)
    layer.cornerRadius = 10 * scale
    layer.anchorPoint = .zero
    text.contentsScale = screen.backingScaleFactor
    text.isWrapped = true
    layer.addSublayer(text)
  }

  /// Shows `info` in the bottom-left corner of `bounds`, fading it in if it's hidden. A panel
  /// already showing changes in place.
  func show(_ info: PhotoInfo, in bounds: CGRect) {
    let attributed = Self.text(info, scale: scale)
    let margin = 28 * scale
    let padding = CGSize(width: 16 * scale, height: 12 * scale)
    // A third of the screen keeps it clear of the speed message, centered below.
    let maxTextWidth = bounds.width / 3 - 2 * padding.width
    let size = attributed.boundingRect(
      with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading]
    ).size
    // A point taller than AppKit measures, since the text layer lays lines out with Core Text,
    // whose line heights can come out a fraction larger.
    let textFrame = CGRect(
      x: padding.width, y: padding.height, width: ceil(size.width),
      height: ceil(size.height) + 1)

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    text.string = attributed
    text.frame = textFrame
    layer.bounds = CGRect(
      x: 0, y: 0, width: textFrame.width + 2 * padding.width,
      height: textFrame.height + 2 * padding.height)
    layer.position = CGPoint(x: bounds.minX + margin, y: bounds.minY + margin)
    let hidden = layer.opacity == 0
    layer.opacity = 1
    CATransaction.commit()
    if hidden { fade(from: 0, to: 1) }
  }

  func hide() {
    guard layer.opacity != 0 else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.opacity = 0
    CATransaction.commit()
    fade(from: 1, to: 0)
  }

  private func fade(from start: Float, to end: Float) {
    let fade = CABasicAnimation(keyPath: "opacity")
    // From where a fade under way has got to, so toggling quickly doesn't jump.
    fade.fromValue = layer.presentation()?.opacity ?? start
    fade.toValue = end
    fade.duration = Self.fadeSeconds
    layer.add(fade, forKey: "fade")
  }

  /// Headlines in a larger font, then the details, one line each unless a line is too long.
  private static func text(_ info: PhotoInfo, scale: CGFloat) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.paragraphSpacing = 3 * scale
    let headline: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 19 * scale, weight: .semibold),
      .foregroundColor: NSColor.white, .paragraphStyle: paragraph,
    ]
    let detail: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 13 * scale),
      .foregroundColor: NSColor(white: 1, alpha: 0.85), .paragraphStyle: paragraph,
    ]
    let lines =
      info.headlines.map { ($0, headline) } + info.details.map { ($0, detail) }
    let result = NSMutableAttributedString()
    for (index, (line, attributes)) in lines.enumerated() {
      let ending = index == lines.count - 1 ? "" : "\n"
      result.append(NSAttributedString(string: line + ending, attributes: attributes))
    }
    return result
  }
}
