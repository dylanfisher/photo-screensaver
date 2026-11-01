import Combine
import Foundation
import Settings

/// What the settings window shows and changes (docs/decisions/0009-settings-window.md).
///
/// The config file stays the source of truth: the window shows what the file held when last
/// read, and each change goes into the file through `Settings.update` and is read back before
/// `change` returns. While the file can't be used, nothing is written, and `fileError` says why.
@MainActor
public final class SettingsModel: ObservableObject {
  /// The file's settings as of its last good read; `starter` until one.
  @Published public private(set) var settings = Settings.starter
  /// Why the file can't be used, or nil when it can.
  @Published public private(set) var fileError: String?
  /// The keys the file leaves out, while it can't be used.
  @Published public private(set) var missingKeys: [Settings.MissingKey] = []
  /// Why the last change wasn't saved; nil once one is.
  @Published public private(set) var changeError: String?
  /// The command whose key is being recorded.
  @Published public private(set) var recording: Command?
  /// Why the last key pressed while recording can't be the command's key.
  @Published public private(set) var refusal: String?

  public let fileURL: URL
  /// Told after each change is written, so the app applies it as it does any edit to the file.
  private let changed: @MainActor () -> Void

  public init(fileURL: URL = Settings.fileURL, changed: @escaping @MainActor () -> Void) {
    self.fileURL = fileURL
    self.changed = changed
    reload()
  }

  public var isFileBroken: Bool { fileError != nil }

  /// Reads the file again, as after an edit to it.
  public func reload() {
    switch Settings.read(at: fileURL) {
    case .settings(let read):
      if read != settings { settings = read }
      if fileError != nil {
        fileError = nil
        changeError = nil
      }
      if !missingKeys.isEmpty { missingKeys = [] }
    case .broken(let error, let missing):
      fileError = error
      missingKeys = missing
      // A key half recorded would only be refused.
      stopRecording()
    }
  }

  /// Makes `change` to the file and reads it back. A change that throws, or that the file
  /// refuses, is shown in `changeError` and leaves the window showing the file as it is.
  public func change(_ change: (inout Settings) throws -> Void) {
    do {
      try write(change)
      changeError = nil
    } catch {
      changeError = "\(error)"
    }
  }

  public func set<Value>(_ path: WritableKeyPath<Settings, Value>, to value: Value) {
    change { $0[keyPath: path] = value }
  }

  private func write(_ change: (inout Settings) throws -> Void) throws {
    defer { reload() }
    try Settings.update(at: fileURL, change)
    changed()
  }

  // MARK: Fields

  /// Sets a number from what was typed in its field.
  public func setNumber(_ path: WritableKeyPath<Settings, Double>, from text: String) {
    change { $0[keyPath: path] = try Self.number(text) }
  }

  public func setCount(_ path: WritableKeyPath<Settings, Int>, from text: String) {
    change { $0[keyPath: path] = try Self.count(text) }
  }

  /// A number as its field shows it and the file writes it: "5", "1.5".
  public nonisolated static func text(_ value: Double) -> String {
    value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
  }

  nonisolated static func number(_ text: String) throws -> Double {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard let value = Double(trimmed), value.isFinite else {
      throw InputError(description: "\"\(trimmed)\" isn't a number")
    }
    return value
  }

  nonisolated static func count(_ text: String) throws -> Int {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard let value = Int(trimmed) else {
      throw InputError(description: "\"\(trimmed)\" isn't a whole number")
    }
    return value
  }

  /// Sets the library folder, written from the home folder as `~/…` when it's inside it.
  public func setLibrary(_ folder: URL) {
    set(\.libraryPath, to: Self.written(folder))
  }

  nonisolated static func written(_ folder: URL) -> String {
    (folder.standardizedFileURL.path as NSString).abbreviatingWithTildeInPath
  }

  /// The slide lengths to choose from: the speed keys' five, and the file's own if it's
  /// another.
  public var slideChoices: [Double] {
    let speeds = Command.allCases.compactMap(\.slideSeconds)
    return speeds.contains(settings.slideSeconds) ? speeds : speeds + [settings.slideSeconds]
  }

  /// Like "15 seconds", or for a length no speed key sets, "Custom: 45.5 seconds".
  public nonisolated static func describe(slideSeconds: Double) -> String {
    if Command.allCases.contains(where: { $0.slideSeconds == slideSeconds }) {
      return Command.describe(seconds: slideSeconds)
    }
    return "Custom: \(text(slideSeconds)) seconds"
  }

  // MARK: Timeframe

  /// The timeframe kinds, as the window's picker lists them.
  public enum TimeframeKind: CaseIterable {
    case all, onThisDay, lastMonths, range

    public var title: String {
      switch self {
      case .all: return Timeframe.all.title
      case .onThisDay: return Timeframe.onThisDay.title
      case .lastMonths: return "Last months"
      case .range: return "Range of months"
      }
    }
  }

  public var timeframeKind: TimeframeKind {
    switch settings.timeframe {
    case .all: return .all
    case .onThisDay: return .onThisDay
    case .lastMonths: return .lastMonths
    case .range: return .range
    }
  }

  /// Switches to `kind`, starting from the timeframe picker's recent months, or this year so
  /// far as of `today`. The kind already set keeps its fields.
  public func setTimeframeKind(_ kind: TimeframeKind, today: CaptureMonth) {
    guard kind != timeframeKind else { return }
    switch kind {
    case .all: set(\.timeframe, to: .all)
    case .onThisDay: set(\.timeframe, to: .onThisDay)
    case .lastMonths: set(\.timeframe, to: .lastMonths(TimeframePicker.recentMonths))
    case .range:
      set(\.timeframe, to: .range(from: CaptureMonth(year: today.year, month: 1), to: today))
    }
  }

  public func setMonths(from text: String) {
    change { $0.timeframe = .lastMonths(try Self.count(text)) }
  }

  /// Sets the range's first month (`first`) or last from `YYYY-MM` text.
  public func setRange(first: Bool, from text: String) {
    change { settings in
      guard case .range(let from, let to) = settings.timeframe else {
        throw InputError(description: "the timeframe isn't a range of months")
      }
      let month = try CaptureMonth(parsing: text.trimmingCharacters(in: .whitespaces))
      settings.timeframe = first ? .range(from: month, to: to) : .range(from: from, to: month)
    }
  }

  // MARK: Keys

  /// Listens for `command`'s key, or stops if it already is.
  public func toggleRecording(_ command: Command) {
    if recording == command {
      stopRecording()
    } else {
      recording = command
      refusal = nil
    }
  }

  public func stopRecording() {
    if recording != nil { recording = nil }
    if refusal != nil { refusal = nil }
  }

  /// Takes a key pressed while recording, and returns whether it did. `spec` is nil for a key
  /// that has no name. Esc without modifiers stops; a key the file takes becomes the command's
  /// key; any other says why in `refusal` and keeps listening.
  public func record(_ spec: KeySpec?) -> Bool {
    guard let command = recording else { return false }
    guard let spec else {
      refusal = "That key has no name in config.json, so it can't run a command."
      return true
    }
    if spec == KeySpec(.named(.escape)) {
      stopRecording()
      return true
    }
    do {
      // The file's own check refuses a key another command has.
      try write { settings in
        let keys = settings.keys
        settings.keys = Settings.Keys { $0 == command ? spec : keys[$0] }
      }
      changeError = nil
      stopRecording()
    } catch {
      refusal = "\(spec.symbols) can't be \(command.title): \(error)"
    }
    return true
  }

  public func restoreDefaultKeys() {
    stopRecording()
    set(\.keys, to: Settings.Keys(\.defaultKey))
  }

  /// Why what was typed in a field isn't a value for it.
  private struct InputError: Error, CustomStringConvertible {
    let description: String
  }
}
