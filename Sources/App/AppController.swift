import AppKit
import Core
import Primitives
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
  /// The app's own connection to the library database, for choosing the library folder and
  /// counting its photos. The scan and the feed open their own.
  private let library = LibraryConnection()
  /// Whether the last `openLibrary` succeeded, so `library` describes the settings' folder.
  private var libraryOpen = false
  /// Bumped by each `openLibrary`, so the results of an earlier one are ignored.
  private var libraryGeneration = 0
  private var photoCount = 0
  private var feed: PhotoFeed?
  private var scan: LibraryScan?
  private var scanProgress: LibraryScan.Progress?
  private var presence = Presence.desktop
  /// Uptime when `presence` last changed. Uptime, like the input idle time it's compared with,
  /// stops while the Mac sleeps; wall-clock time doesn't.
  private var enteredAt = ProcessInfo.processInfo.systemUptime
  private var window: SlideshowWindow?
  private var history = SlideHistory()
  /// The photo in `window`, so stepping back to it, or changing speed, doesn't decode it again.
  private var shownID: Int64?
  private var slideTask: Task<Void, Never>?
  private var motionTask: Task<Void, Never>?
  /// Uptime when the scheduled motion check starts; until then its task is only waiting.
  private var motionCheckAt: Double?
  /// Opened on first use, so a Mac without the sensor only errors when it's turned on.
  private var lightSensor: LightSensor?
  private var lightWatch = LightWatch()
  /// Whether it was off hours at the last tick, so a running slideshow is stopped once as they
  /// begin, and one started by hand during them keeps going.
  private var wasOffHours = false

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
    checkOffHours()
    checkInput()
    checkLight()
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
      // Its next write would fail anyway, once the database is in use for the new folder.
      scan?.cancel()
      // Its photo IDs belong to the old library.
      history = SlideHistory()
      openLibrary(for: loaded)
    } else if loaded.scaling != old?.scaling || loaded.orientation != old?.orientation
      || loaded.preloadCount != old?.preloadCount || loaded.kenBurns != old?.kenBurns
    {
      rebuildFeed()
    }
    if loaded.slideSeconds != old?.slideSeconds, slideTask != nil {
      // The current photo gets a whole slide at the new speed.
      window?.retime(settings: loaded)
      runSlides()
    }
    if loaded.motion != old?.motion {
      errors["motion"] = nil
      errors["light"] = nil
      motionTask?.cancel()
      motionTask = nil
      if !loaded.motion.enabled { send(.motionOff) }
      if case .displayOff = presence {
        keepAwake(display: false)
      } else if presence != .desktop {
        keepAwake(display: true)
      }
      scheduleMotionCheck()
    }
  }

  /// Starts from what the database already has, so the slideshow can run while the rescan
  /// that follows walks the library.
  private func openLibrary(for settings: Settings) {
    libraryOpen = false
    libraryGeneration += 1
    let generation = libraryGeneration
    photoCount = 0
    rebuildFeed()
    library.open(root: settings.libraryURL) { result in
      guard generation == self.libraryGeneration else { return }
      self.record("database") {
        self.photoCount = try result.get()
        self.libraryOpen = true
      }
      self.rebuildFeed()
      self.rescan()
    }
  }

  @objc private func rescan() {
    guard let root = settings?.libraryURL, libraryOpen, scan == nil else { return }
    var continuation: AsyncStream<LibraryScan.Progress>.Continuation?
    let stream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation = $0 }
    let scan = LibraryScan(databaseURL: PhotoLibrary.defaultURL, root: root, progress: continuation)
    self.scan = scan
    scanProgress = nil
    updateMenu()
    Task {
      for await progress in stream { show(progress, of: scan) }
    }
    // A dispatch queue rather than a Task: the scan blocks on network reads for a while, and
    // the cooperative thread pool is only a few threads wide on this Mac.
    DispatchQueue.global(qos: .utility).async {
      let result = Result { try scan.run() }
      Task { @MainActor in self.finishScan(result, root: root) }
    }
  }

  private func show(_ progress: LibraryScan.Progress, of scan: LibraryScan) {
    guard scan === self.scan else { return }
    let walkJustFinished = progress.walkFinished && scanProgress?.walkFinished != true
    scanProgress = progress
    // New photos can be shown from here on, while their details are still being read.
    if walkJustFinished { refreshPhotos() }
    updateMenu()
  }

  private func finishScan(_ result: Result<LibraryScan.Summary, Error>, root: URL) {
    scan = nil
    scanProgress = nil
    // Settings may have moved to another library while this scan ran.
    guard root == settings?.libraryURL else { return rescan() }
    switch result {
    case .success(let summary):
      log.notice(
        "scan: \(summary.found, privacy: .public) found, \(summary.read, privacy: .public) read, \(summary.failed, privacy: .public) failed, \(summary.removed, privacy: .public) removed, readers \(summary.readerTrace, privacy: .public)"
      )
      var problems: [String] = []
      if summary.listedNothing {
        // More likely a share hiccup than a library that emptied out.
        problems.append("Scan found no photos in \(root.path); keeping the previous ones")
      }
      if summary.unreadable > 0 {
        problems.append("\(summary.unreadable) library files or folders couldn't be read")
      }
      if summary.failed > 0 {
        problems.append("\(summary.failed) photos couldn't be read; the next scan tries again")
      }
      errors["library"] = problems.isEmpty ? nil : problems.joined(separator: "; ")
    case .failure(let error):
      errors["library"] = "Library: \(error)"
    }
    // A failed scan keeps what it stored, so this picks that up too.
    refreshPhotos()
  }

  private func refreshPhotos() {
    guard libraryOpen else { return }
    let generation = libraryGeneration
    library.count { result in
      guard generation == self.libraryGeneration else { return }
      self.record("database") { self.photoCount = try result.get() }
      if let feed = self.feed { Task { await feed.reload() } } else { self.rebuildFeed() }
      self.updateMenu()
    }
  }

  private func rebuildFeed() {
    feed?.dropAsync()
    feed = nil
    if let settings, libraryOpen, photoCount > 0, let screen = NSScreen.main {
      record("feed") {
        feed = try PhotoFeed(
          databaseURL: PhotoLibrary.defaultURL, root: settings.libraryURL, settings: settings,
          screenPixels: SlideshowWindow.pixelSize(of: screen))
      }
    }
    updateMenu()
  }

  // MARK: Presence

  private func checkOffHours() {
    let offHours = settings?.offHours.contains(Date()) == true
    if offHours && !wasOffHours { send(.offHoursBegan) }
    wasOffHours = offHours
  }

  private func checkInput() {
    let idle = DisplayPower.secondsSinceUserInput(
      countingKeys: presence.idleCheckCountsKeys(windowGetsKeys: window?.getsKeys == true))
    switch presence {
    case .desktop:
      if let settings, feed != nil, !wasOffHours, idle >= settings.idleMinutes * 60 {
        send(.userIdle)
      }
    case .showing, .displayOff:
      if idle < ProcessInfo.processInfo.systemUptime - enteredAt - Self.inputGraceSeconds {
        send(.userActive)
      }
    }
  }

  private func handleKey(_ event: NSEvent) {
    let bound = KeySpec(event).flatMap { settings?.keys.command(for: $0) }
    let inGracePeriod =
      ProcessInfo.processInfo.systemUptime - enteredAt <= Self.inputGraceSeconds
    switch presence.respond(toKey: bound, isRepeat: event.isARepeat, inGracePeriod: inGracePeriod)
    {
    case .run(let command): run(command)
    case .exit: send(.userActive)
    case .ignore: break
    }
  }

  /// One sensor read is cheap and doesn't use the camera, so it runs every tick.
  private func checkLight() {
    guard presence != .desktop, let motion = settings?.motion, motion.enabled,
      motion.useLightSensor
    else { return }
    do {
      let sensor = try lightSensor ?? LightSensor()
      lightSensor = sensor
      let level = try sensor.read()
      errors["light"] = nil
      let now = ProcessInfo.processInfo.systemUptime
      if let change = lightWatch.add(level, at: now), presence.checksNow(after: change) {
        log.notice(
          "light \(String(describing: change), privacy: .public) to \(level, privacy: .public): checking for motion now"
        )
        checkMotionNow()
      }
    } catch {
      errors["light"] = "Light sensor: \(error)"
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
        "\(String(describing: event), privacy: .public): \(String(describing: from), privacy: .public) → \(String(describing: next), privacy: .public)"
      )
    }
    presence = next
    for effect in effects { perform(effect) }
    if !effects.isEmpty {
      enteredAt = ProcessInfo.processInfo.systemUptime
      lightWatch.settle(at: enteredAt)
    }
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
      window.onKey = { [weak self] event in self?.handleKey(event) }
      window.open()
      self.window = window
      keepAwake(display: true)
      startSlides()
    case .stopSlideshow:
      stopSlides()
      window?.close()
      window = nil
      shownID = nil
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

  /// Moves on from the photo shown before, as when the slideshow starts or the display wakes.
  private func startSlides() {
    history.forward()
    runSlides()
  }

  /// Shows the history's target, then a slide's length later steps forward and repeats.
  /// Restarting it is how every change takes effect: a step shows its photo with a whole slide
  /// ahead of it, and a load still under way for an earlier step is dropped.
  private func runSlides() {
    slideTask?.cancel()
    slideTask = Task {
      // `window` is nil once the slideshow closes, which also ends this loop.
      while !Task.isCancelled, let settings, let window {
        if let feed {
          do {
            let photo: Photo?
            switch history.target {
            case .photo(let id) where id == shownID: photo = nil
            case .photo(let id): photo = try await feed.photo(id)
            case .new: photo = try await feed.next()
            }
            if Task.isCancelled { return }
            if let photo {
              if history.target == .new { history.add(photo.id) }
              window.show(photo, settings: settings)
              shownID = photo.id
            }
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
        if Task.isCancelled { return }
        history.forward()
      }
    }
  }

  private func run(_ command: Command) {
    switch command {
    case .next:
      history.forward()
      runSlides()
    case .previous:
      guard history.back() else { return }
      runSlides()
    case .speed1, .speed2, .speed3, .speed4, .speed5:
      guard let seconds = command.slideSeconds else {
        preconditionFailure("every speed command sets slideSeconds")
      }
      setSpeed(seconds, title: command.title)
    }
  }

  /// Saves the speed to the config file and applies it the way any edit to that file is
  /// applied. Reads the file first rather than saving `settings`, so a hand edit not yet picked
  /// up isn't overwritten, and a file with errors isn't replaced at all.
  private func setSpeed(_ seconds: Double, title: String) {
    do {
      var saved = try Settings.load()
      if saved.slideSeconds != seconds {
        saved.slideSeconds = seconds
        try saved.save()
      }
    } catch {
      window?.showMessage("Can't change speed: \(error)")
      return
    }
    reloadSettingsIfChanged()
    window?.showMessage(title)
  }

  /// Also drops preloaded photos, which can be hundreds of MB, while nothing is on screen.
  private func stopSlides() {
    slideTask?.cancel()
    slideTask = nil
    feed?.dropAsync()
  }

  /// Moves a waiting motion check to now. One already under way is left to finish.
  private func checkMotionNow() {
    guard let motionCheckAt, ProcessInfo.processInfo.systemUptime < motionCheckAt else { return }
    motionTask?.cancel()
    motionTask = nil
    scheduleMotionCheck(now: true)
  }

  private func scheduleMotionCheck(now: Bool = false) {
    guard motionTask == nil, let motion = settings?.motion,
      let scheduled = presence.secondsUntilMotionCheck(motion)
    else { return }
    let delay = now ? 0 : scheduled
    motionCheckAt = ProcessInfo.processInfo.systemUptime + delay
    motionTask = Task {
      do {
        try await Task.sleep(nanoseconds: UInt64(delay * 1e9))
        let moved = try await detector.detect(
          for: motion.sampleSeconds, threshold: motion.threshold)
        // A cancelled task must not touch `motionTask`: it may already be a newer one.
        guard !Task.isCancelled else { return }
        motionTask = nil
        errors["motion"] = nil
        send(moved ? .motionSeen : .noMotion)
      } catch {
        guard !Task.isCancelled else { return }
        // The state stays as it was; try again next interval in case the camera was busy.
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
    if let progress = scanProgress, progress.unread > 0 {
      let read = progress.photos - progress.unread
      menu.addItem(
        disabled:
          "Reading photo details: \(read.formatted()) of \(progress.photos.formatted())")
    }
    for error in errors.values.sorted() { menu.addItem(disabled: "⚠︎ \(error)") }
    menu.addItem(.separator())
    let show = menu.addItem(
      withTitle: "Show Slideshow", action: #selector(showNow), keyEquivalent: "")
    show.isEnabled = feed != nil && presence == .desktop
    menu.addItem(withTitle: "Edit Settings…", action: #selector(editSettings), keyEquivalent: "")
    let rescanItem = menu.addItem(
      withTitle: "Rescan Library", action: #selector(rescan), keyEquivalent: "")
    rescanItem.isEnabled = scan == nil && libraryOpen
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
      item.target = self
    }
    statusItem.menu = menu
  }

  private func statusLine() -> String {
    guard libraryOpen else { return "No library database" }
    let count = "\(photoCount.formatted()) photos"
    guard scan != nil, scanProgress?.walkFinished != true else { return count }
    return "\(count) · scanning… \((scanProgress?.found ?? 0).formatted()) found"
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

/// Runs the app's database work on a serial queue that owns the connection, so the main thread
/// never waits on it: opening can rebuild the tables, choosing another folder deletes every row,
/// counting reads every row, and a write can wait up to 5 s behind the scan's.
///
/// `@unchecked Sendable` because `connection` is only touched on `queue`.
private final class LibraryConnection: @unchecked Sendable {
  private let queue = DispatchQueue(
    label: "com.dylanfisher.photo-screensaver.library", qos: .userInitiated)
  private var connection: PhotoLibrary?
  private let log = Logger(subsystem: "com.dylanfisher.photo-screensaver", category: "app")

  /// Opens the database for `root`, discarding the photos of any other folder, and calls `done`
  /// with how many photos it can show.
  func open(root: URL, then done: @escaping @MainActor (Result<Int, Error>) -> Void) {
    run(done) { [self] in
      connection = nil
      let library = try openDatabase()
      try library.use(root: root)
      connection = library
      return try library.count()
    }
  }

  /// Only after an `open` that succeeded.
  func count(then done: @escaping @MainActor (Result<Int, Error>) -> Void) {
    run(done) { [self] in
      guard let connection else { preconditionFailure("counted photos before the database opened") }
      return try connection.count()
    }
  }

  private func run(
    _ done: @escaping @MainActor (Result<Int, Error>) -> Void, _ body: @escaping () throws -> Int
  ) {
    queue.async {
      let result = Result(catching: body)
      Task { @MainActor in done(result) }
    }
  }

  /// A file SQLite can't read is deleted and started anew: everything in it comes from the
  /// library folder, and the rescan puts it back.
  private func openDatabase() throws -> PhotoLibrary {
    do {
      return try PhotoLibrary(at: PhotoLibrary.defaultURL)
    } catch let error as SQLiteError where error.isUnreadableFile {
      try PhotoLibrary.discard(at: PhotoLibrary.defaultURL)
      log.error("discarded unreadable library database: \(error, privacy: .public)")
      return try PhotoLibrary(at: PhotoLibrary.defaultURL)
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
