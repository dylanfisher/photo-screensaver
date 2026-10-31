import AppKit
import Core
import Settings

/// A borderless black window over the whole screen, above everything including the menu bar.
/// Each photo is its own layer, faded in over the previous one.
final class SlideshowWindow {
  private let window: NSWindow
  private let root = CALayer()
  private var current: CALayer?
  private var activeObserver: NSObjectProtocol?

  init(screen: NSScreen) {
    window = NSWindow(
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
  }

  /// Activates the app, since macOS ignores cursor hiding from a background app. Activation
  /// finishes later, so the cursor is hidden once it does. Moving the mouse ends the slideshow,
  /// so hiding it until then is enough.
  func open() {
    activeObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { _ in NSCursor.setHiddenUntilMouseMoves(true) }
    window.orderFrontRegardless()
    keepFront()
  }

  /// Takes focus back if another app took it, which would show the cursor again.
  func keepFront() {
    if NSApp.isActive {
      NSCursor.setHiddenUntilMouseMoves(true)
    } else {
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  /// Hides the app again, which hands focus back to whatever was in front before.
  func close() {
    window.orderOut(nil)
    activeObserver.map(NotificationCenter.default.removeObserver)
    activeObserver = nil
    NSCursor.setHiddenUntilMouseMoves(false)
    NSApp.hide(nil)
    current?.removeFromSuperlayer()
    current = nil
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

    // Fade the old photo out too: in `fit` mode the new one may not cover it.
    if let previous = current {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      previous.opacity = 0
      if fade == 0 { previous.removeFromSuperlayer() }
      CATransaction.commit()
      if fade > 0 {
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1
        fadeOut.toValue = 0
        fadeOut.duration = fade
        previous.add(fadeOut, forKey: "fade")
        DispatchQueue.main.asyncAfter(deadline: .now() + fade) {
          previous.removeFromSuperlayer()
        }
      }
    }
    current = layer
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
