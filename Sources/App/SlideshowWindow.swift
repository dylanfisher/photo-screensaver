import AppKit
import Core
import Settings

/// A borderless black window over the whole screen, above everything including the menu bar.
/// Each photo is its own layer, faded in over the previous one.
final class SlideshowWindow {
  /// How long a message shows before it fades.
  static let messageSeconds = 2.0

  private let window: KeyWindow
  private let root = CALayer()
  private var current: CALayer?
  /// The photo fading out under `current`. A new photo removes it at once, so stepping fast
  /// never holds more than two decoded photos, at 60–160 MB each.
  private var outgoing: CALayer?
  private let message = CALayer()
  private let messageText = CATextLayer()
  /// Bumped by each message, so only the latest one's timer fades it.
  private var messageCount = 0

  /// Called with each key press, including repeats from a key held down.
  var onKey: ((NSEvent) -> Void)? {
    get { window.onKey }
    set { window.onKey = newValue }
  }

  /// Whether key presses reach this window: it's the key window of the active app.
  var getsKeys: Bool { NSApp.isActive && window.isKeyWindow }

  init(screen: NSScreen) {
    window = KeyWindow(
      contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.setFrame(screen.frame, display: false)
    window.level = .screenSaver
    window.backgroundColor = .black
    window.hasShadow = false
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

    let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
    // Layer-hosting: assign the layer before turning layers on, or AppKit manages it instead.
    view.layer = root
    view.wantsLayer = true
    root.backgroundColor = .black
    root.masksToBounds = true
    window.contentView = view

    // Above every photo, which are added later.
    message.zPosition = 1
    message.opacity = 0
    message.backgroundColor = CGColor(gray: 0, alpha: 0.6)
    message.cornerRadius = 12
    messageText.contentsScale = screen.backingScaleFactor
    message.addSublayer(messageText)
    root.addSublayer(message)
  }

  /// Activates the app, since macOS ignores cursor hiding from a background app, and makes the
  /// window key so key presses come here.
  func open() {
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    NSCursor.hide()
  }

  /// Hides the app again, which hands focus back to whatever was in front before.
  func close() {
    window.orderOut(nil)
    NSCursor.unhide()
    NSApp.hide(nil)
    discard(current)
    discard(outgoing)
    current = nil
    outgoing = nil
  }

  func show(_ photo: Photo, settings: Settings) {
    let view = root.bounds.size
    let layer = CALayer()
    layer.contents = photo.image
    layer.contentsGravity = .resize
    // Photos are decoded at 2× their shown size; trilinear filtering keeps the downscale sharp
    // without shimmering while Ken Burns moves them.
    layer.minificationFilter = .trilinear
    layer.bounds = CGRect(
      origin: .zero, size: displayedSize(photo: photo.size, in: view, scaling: settings.scaling))
    layer.position = CGPoint(x: view.width / 2, y: view.height / 2)

    var generator = SystemRandomNumberGenerator()
    let move =
      settings.kenBurns
      ? KenBurns.random(
        photo: photo.size, view: view, scaling: settings.scaling, using: &generator)
      : .still

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.transform = Self.transform(move.end)
    root.addSublayer(layer)
    CATransaction.commit()

    // Keep moving through the next fade, so the photo never stops before it disappears.
    let pan = CABasicAnimation(keyPath: "transform")
    pan.fromValue = Self.transform(move.start)
    pan.toValue = Self.transform(move.end)
    pan.duration = settings.slideSeconds + settings.transitionSeconds
    pan.timingFunction = CAMediaTimingFunction(name: .linear)
    layer.add(pan, forKey: "kenBurns")

    // A zero-length CABasicAnimation runs for the 0.25 s default, so a cut skips them entirely.
    let fade = settings.transitionSeconds
    if fade > 0 {
      let fadeIn = CABasicAnimation(keyPath: "opacity")
      fadeIn.fromValue = 0
      fadeIn.toValue = 1
      fadeIn.duration = fade
      layer.add(fadeIn, forKey: "fade")
    }

    discard(outgoing)
    outgoing = nil
    // Fade the old photo out too: in `fit` mode the new one may not cover it.
    if let previous = current {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      previous.opacity = 0
      CATransaction.commit()
      if fade > 0 {
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1
        fadeOut.toValue = 0
        fadeOut.duration = fade
        previous.add(fadeOut, forKey: "fade")
        outgoing = previous
        // Weak, so a photo a newer one already removed isn't kept until this runs.
        DispatchQueue.main.asyncAfter(deadline: .now() + fade) { [weak self, weak previous] in
          guard let self, let previous, previous === self.outgoing else { return }
          self.discard(previous)
          self.outgoing = nil
        }
      } else {
        discard(previous)
      }
    }
    current = layer
  }

  /// Takes a photo off screen and lets go of its pixels.
  private func discard(_ layer: CALayer?) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer?.removeFromSuperlayer()
    layer?.contents = nil
    CATransaction.commit()
  }

  /// Restarts the current photo's pan from where it is, to last a slide of the new length and
  /// its fade, so it doesn't stop partway through a longer slide.
  func retime(settings: Settings) {
    guard let layer = current, let pan = layer.animation(forKey: "kenBurns") as? CABasicAnimation,
      let now = layer.presentation()?.transform
    else { return }
    let retimed = CABasicAnimation(keyPath: "transform")
    retimed.fromValue = now
    retimed.toValue = pan.toValue
    retimed.duration = settings.slideSeconds + settings.transitionSeconds
    retimed.timingFunction = CAMediaTimingFunction(name: .linear)
    layer.add(retimed, forKey: "kenBurns")
  }

  /// Shows `text` near the bottom of the screen for `messageSeconds`, light on a dark panel so
  /// it reads over any photo. A new message replaces the one showing.
  func showMessage(_ text: String) {
    let font = NSFont.systemFont(ofSize: 28, weight: .medium)
    let attributed = NSAttributedString(
      string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
    let textSize = attributed.size()
    let padding = CGSize(width: 24, height: 12)
    let textFrame = CGRect(
      x: padding.width, y: padding.height, width: ceil(textSize.width),
      height: ceil(textSize.height))

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    messageText.string = attributed
    messageText.frame = textFrame
    message.bounds = textFrame.insetBy(dx: -padding.width, dy: -padding.height)
    message.bounds.origin = .zero
    message.position = CGPoint(x: root.bounds.midX, y: root.bounds.height * 0.12)
    message.removeAnimation(forKey: "fade")
    message.opacity = 1
    CATransaction.commit()

    messageCount += 1
    let count = messageCount
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.messageSeconds) { [weak self] in
      guard let self, count == self.messageCount else { return }
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      self.message.opacity = 0
      CATransaction.commit()
      let fadeOut = CABasicAnimation(keyPath: "opacity")
      fadeOut.fromValue = 1
      fadeOut.toValue = 0
      fadeOut.duration = 0.5
      self.message.add(fadeOut, forKey: "fade")
    }
  }

  /// Size of the screen in pixels, which photos are decoded against.
  static func pixelSize(of screen: NSScreen) -> CGSize {
    CGSize(
      width: screen.frame.width * screen.backingScaleFactor,
      height: screen.frame.height * screen.backingScaleFactor)
  }

  private static func transform(_ frame: KenBurns.Frame) -> CATransform3D {
    CATransform3DConcat(
      CATransform3DMakeScale(frame.scale, frame.scale, 1),
      CATransform3DMakeTranslation(frame.offset.x, frame.offset.y, 0))
  }
}

/// A borderless window can't become key by default, and then gets no key presses.
private final class KeyWindow: NSWindow {
  var onKey: ((NSEvent) -> Void)?

  override var canBecomeKey: Bool { true }

  override func keyDown(with event: NSEvent) {
    onKey?(event)
  }
}
