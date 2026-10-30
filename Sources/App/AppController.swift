import AppKit
import Core
import Settings
import os

/// Owns the app's state and connects the parts: watches for idle, runs the slideshow and motion
/// checks, and shows status and errors in the menu bar.
@MainActor
final class AppController: NSObject, NSApplicationDelegate {
  /// Input after entering a state, beyond this, counts as the user coming back. Absorbs the click
  /// on "Show Slideshow" and any input-like event from waking the display.
  static let inputGraceSeconds = 1.0
  static let rescanEverySeconds = 24 * 60 * 60.0

  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let power = DisplayPower()
  private let detector = MotionDetector()
  private let log = Logger(subsystem: "com.dylanfisher.photo-screensaver", category: "app")

  private var settings: Settings?
  /// Modification date of the settings file when last read; polled to pick up edits.
  private var settingsModified: Date?
  private var index: PhotoIndex?
  private var feed: PhotoFeed?
  private var scanning = false
  private var presence = Presence.desktop
  /// Uptime when `presence` last changed. Uptime, like the input idle time it's compared with,
  /// stops while the Mac sleeps; wall-clock time doesn't.
  private var enteredAt = ProcessInfo.processInfo.systemUptime
  private var window: SlideshowWindow?
  private var slideTask: Task<Void, Never>?
  private var motionTask: Task<Void, Never>?

  /// Shown in the menu, one line each. Keyed so a later success clears only its own error.
  private var errors: [String: String] = [:] {
    didSet {
      guard errors != oldValue else { return }
      for (key, message) in errors where oldValue[key] != message {
        log.error("\(message, privacy: .public)")
      }
      updateMenu()
    }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    record("settings") { try Settings.createIfMissing() }
    reloadSettingsIfChanged()
    Timer.scheduledTimer(
      timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
    Timer.scheduledTimer(
      timeInterval: Self.rescanEverySeconds, target: self, selector: #selector(rescan),
      userInfo: nil, repeats: true)
  }

  @objc private func tick() {
    reloadSettingsIfChanged()
    checkInput()
  }

  // MARK: Settings and library

  /// Polling one local file each second is cheap, and unlike a folder watch it also catches
  /// editors that rewrite the file in place.
  private func reloadSettingsIfChanged() {
    let modified =
      try? FileManager.default.attributesOfItem(atPath: Settings.fileURL.path)[.modificationDate]
      as? Date
    guard modified != settingsModified else { return }
    settingsModified = modified

    let loaded: Settings
    do {
      loaded = try Settings.load()
      errors["settings"] = nil
    } catch {
      // Keep running on the last good settings; the menu shows what's wrong.
      errors["settings"] = "Settings: \(error)"
      return
    }
    guard loaded != settings else { return }
    let old = settings
    settings = loaded

    if loaded.libraryURL != old?.libraryURL {
      loadCachedIndex(for: loaded)
      rescan()
    } else if loaded.scaling != old?.scaling || loaded.orientation != old?.orientation
      || loaded.preloadCount != old?.preloadCount || loaded.kenBurns != old?.kenBurns
    {
      rebuildFeed()
    }
    if loaded.motion != old?.motion {
      errors["motion"] = nil
      motionTask?.cancel()
      motionTask = nil
      if !loaded.motion.enabled { send(.motionOff) }
      if presence != .desktop { keepAwake(display: presence == .showing) }
      scheduleMotionCheck()
    }
  }

  private func loadCachedIndex(for settings: Settings) {
    do {
      index = try PhotoIndex.cached(for: settings.libraryURL)
    } catch {
      // Stored data has one shape; anything else is discarded and the rescan replaces it.
      index = nil
      errors["cache"] = "Discarded unreadable library cache: \(error)"
    }
    rebuildFeed()
  }

  @objc private func rescan() {
    guard let root = settings?.libraryURL, !scanning else { return }
    scanning = true
    updateMenu()
    // A dispatch queue rather than a Task: the scan blocks on network reads for a while, and
    // the cooperative thread pool is only a few threads wide on this Mac.
    DispatchQueue.global(qos: .utility).async {
      let result = Result { try PhotoIndex.scan(root) }
      Task { @MainActor in self.finishScan(result, root: root) }
    }
  }

  private func finishScan(_ result: Result<PhotoIndex, Error>, root: URL) {
    scanning = false
    updateMenu()
    // Settings may have moved to another library while this scan ran.
    guard root == settings?.libraryURL else { return rescan() }
    let scanned: PhotoIndex
    switch result {
    case .success(let value):
      scanned = value
    case .failure(let error):
      errors["library"] = "Library: \(error)"
      return
    }
    if scanned.paths.isEmpty, let index, !index.paths.isEmpty {
      // More likely a share hiccup than a library that emptied out.
      errors["library"] = "Scan found no photos in \(root.path); keeping the previous index"
      return
    }
    errors["library"] =
      scanned.unreadableCount > 0
      ? "\(scanned.unreadableCount) library files or folders couldn't be read" : nil
    index = scanned
    record("cache") { try scanned.save() }
    if let feed { Task { await feed.replace(scanned) } } else { rebuildFeed() }
    updateMenu()
  }

  private func rebuildFeed() {
    feed?.dropAsync()
    feed = nil
    if let settings, let index, let screen = NSScreen.main {
      feed = PhotoFeed(
        index: index, settings: settings, screenPixels: SlideshowWindow.pixelSize(of: screen))
    }
    updateMenu()
  }

  // MARK: Presence

  private func checkInput() {
    let idle = DisplayPower.secondsSinceUserInput()
    switch presence {
    case .desktop:
      if let settings, feed != nil, idle >= settings.idleMinutes * 60 { send(.userIdle) }
    case .showing, .displayOff:
      if idle < ProcessInfo.processInfo.systemUptime - enteredAt - Self.inputGraceSeconds {
        send(.userActive)
      }
    }
  }

  @objc private func showNow() {
    send(.showNow)
  }

  private func send(_ event: Presence.Event) {
    let (next, effects) = presence.handle(event)
    if next != presence {
      let from = presence
      log.notice(
        "\(String(describing: event)): \(String(describing: from)) → \(String(describing: next))")
    }
    presence = next
    for effect in effects { perform(effect) }
    if !effects.isEmpty { enteredAt = ProcessInfo.processInfo.systemUptime }
    if presence == .desktop {
      motionTask?.cancel()
      motionTask = nil
    } else {
      scheduleMotionCheck()
    }
    updateMenu()
  }

  private func perform(_ effect: Presence.Effect) {
    switch effect {
    case .startSlideshow:
      guard let screen = NSScreen.main else {
        errors["screen"] = "No screen to show the slideshow on"
        // Nothing is showing, so don't claim it is: back to the desktop state.
        presence = .desktop
        return
      }
      errors["screen"] = nil
      let window = SlideshowWindow(screen: screen)
      window.open()
      self.window = window
      keepAwake(display: true)
      startSlides()
    case .stopSlideshow:
      stopSlides()
      window?.close()
      window = nil
      keepAwake(display: false)
    case .pauseSlideshow:
      stopSlides()
      keepAwake(display: false)
    case .resumeSlideshow:
      keepAwake(display: true)
      startSlides()
    case .sleepDisplay:
      record("display sleep") { try power.sleepDisplay() }
    case .wakeDisplay:
      record("display wake") { try power.wakeDisplay() }
    }
  }

  /// While the slideshow is up, the display stays on; while motion checks run, the Mac stays
  /// awake even with the display off, or the checks would stop.
  private func keepAwake(display: Bool) {
    let checkingMotion = presence != .desktop && settings?.motion.enabled == true
    record("display power") { try power.keepDisplayOn(display) }
    record("system power") { try power.keepSystemAwake(checkingMotion) }
  }

  private func startSlides() {
    slideTask?.cancel()
    slideTask = Task {
      // `window` is nil once the slideshow closes, which also ends this loop.
      while !Task.isCancelled, let settings, let window {
        if let feed {
          do {
            let photo = try await feed.next()
            if Task.isCancelled { return }
            window.show(photo, settings: settings)
            errors["photos"] = nil
          } catch is CancellationError {
            // The feed was replaced mid-load by a settings change; the next pass uses the new one.
            if Task.isCancelled { return }
            continue
          } catch {
            if Task.isCancelled { return }
            errors["photos"] = "Photos: \(error)"
          }
        } else {
          errors["photos"] = "No photos to show yet; waiting for the library scan"
        }
        try? await Task.sleep(nanoseconds: UInt64(settings.slideSeconds * 1e9))
      }
    }
  }

  /// Also drops preloaded photos, which can be hundreds of MB, while nothing is on screen.
  private func stopSlides() {
    slideTask?.cancel()
    slideTask = nil
    feed?.dropAsync()
  }

  private func scheduleMotionCheck() {
    guard motionTask == nil, presence != .desktop, let motion = settings?.motion, motion.enabled
    else { return }
    motionTask = Task {
      do {
        try await Task.sleep(nanoseconds: UInt64(motion.checkEveryMinutes * 60 * 1e9))
        let moved = try await detector.detect(
          for: motion.sampleSeconds, threshold: motion.threshold)
        // A cancelled task must not touch `motionTask`: it may already be a newer one.
        guard !Task.isCancelled else { return }
        motionTask = nil
        errors["motion"] = nil
        send(moved ? .motionSeen : .noMotion)
      } catch {
        guard !Task.isCancelled else { return }
        // The slideshow keeps showing; try again next interval in case the camera was busy.
        motionTask = nil
        errors["motion"] = "Motion: \(error)"
        scheduleMotionCheck()
      }
    }
  }

  private func record(_ key: String, _ action: () throws -> Void) {
    do {
      try action()
      errors[key] = nil
    } catch {
      errors[key] = "\(error)"
    }
  }

  // MARK: Menu

  private func updateMenu() {
    let symbol = errors.isEmpty ? "photo.on.rectangle" : "exclamationmark.triangle"
    statusItem.button?.image = NSImage(
      systemSymbolName: symbol, accessibilityDescription: "Photo Screensaver")

    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.addItem(disabled: statusLine())
    for error in errors.values.sorted() { menu.addItem(disabled: "⚠︎ \(error)") }
    menu.addItem(.separator())
    let show = menu.addItem(
      withTitle: "Show Slideshow", action: #selector(showNow), keyEquivalent: "")
    show.isEnabled = feed != nil && presence == .desktop
    menu.addItem(withTitle: "Edit Settings…", action: #selector(editSettings), keyEquivalent: "")
    let rescanItem = menu.addItem(
      withTitle: "Rescan Library", action: #selector(rescan), keyEquivalent: "")
    rescanItem.isEnabled = !scanning && settings != nil
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
      item.target = self
    }
    statusItem.menu = menu
  }

  private func statusLine() -> String {
    let count = index.map { "\($0.paths.count.formatted()) photos" } ?? "No library index yet"
    return scanning ? "\(count) · scanning…" : count
  }

  @objc private func editSettings() {
    let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
    NSWorkspace.shared.open(
      [Settings.fileURL], withApplicationAt: textEdit, configuration: .init()
    ) { _, error in
      Task { @MainActor in self.errors["edit"] = error.map { "Can't open settings: \($0)" } }
    }
  }
}

extension NSMenu {
  fileprivate func addItem(disabled title: String) {
    let item = addItem(withTitle: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
  }
}

extension PhotoFeed {
  /// Fire-and-forget `drop()` for callers on the main thread.
  fileprivate nonisolated func dropAsync() {
    Task { await drop() }
  }
}
