import Darwin
import Foundation

extension Settings {
  /// How many times `update` makes its change before it gives up, when the file changes under
  /// each try.
  static let updateAttempts = 3

  /// Makes `change` to the settings in the config file and writes them back, returning whether
  /// it wrote.
  ///
  /// The change is made to what the file holds, never to settings kept in memory, so an edit
  /// made in an editor since the last read isn't overwritten. A file with an error isn't
  /// written, and neither are settings the change makes invalid; both throw. A change that
  /// leaves the settings as they were writes nothing, so a file formatted by hand stays as it
  /// is. The new file is written beside the old one, with its permissions from the start, and
  /// renamed over it only if it still has the bytes the change was made to; when it doesn't, as
  /// when an editor saved meanwhile, the change is made again to the new contents, up to
  /// `updateAttempts` times. A symbolic link at `url` stays: the file it leads to is replaced.
  @discardableResult
  public static func update(at url: URL = fileURL, _ change: (inout Settings) throws -> Void)
    throws -> Bool
  {
    let destination = url.resolvingSymlinksInPath()
    for _ in 0..<updateAttempts {
      let found = try contents(of: destination)
      let current = try decode(found)
      var changed = current
      try change(&changed)
      guard changed != current else { return false }
      try changed.validate()
      if try replace(destination, holding: found, with: changed.encoded()) { return true }
    }
    throw SettingsError(
      description:
        "config.json changed while it was being saved, \(updateAttempts) times; try again")
  }

  /// Adds the keys `starter` has and the config file leaves out, with `starter`'s values, so a
  /// build that adds a setting runs with the file an older one wrote, and returns their paths,
  /// like `"battery.mode"`. Only when the file is a JSON object and the keys make it valid
  /// settings: a file with an unknown key or any other error stays as it is, for the load to
  /// report (docs/decisions/0011-add-missing-settings.md). Writes as `update` does. Only at
  /// launch, like `createIfMissing`: new keys come with a new build, and during a reload a key
  /// that's gone is more likely an edit under way.
  @discardableResult
  public static func addMissingKeys(at url: URL = fileURL) throws -> [String] {
    let destination = url.resolvingSymlinksInPath()
    let defaults = try JSONSerialization.jsonObject(with: starter.encoded())
    for _ in 0..<updateAttempts {
      let found = try contents(of: destination)
      // Text that isn't a JSON object has no keys to add to; the load says what's wrong.
      guard let file = try? JSONSerialization.jsonObject(with: found) as? [String: Any] else {
        return []
      }
      let missing = keys(in: defaults, notIn: file)
      guard !missing.isEmpty else { return [] }
      var filled = file
      for key in missing { set(key.value, at: key.path[...], in: &filled) }
      let settings: Settings
      do {
        settings = try decode(JSONSerialization.data(withJSONObject: filled))
      } catch {
        // The load that follows reads the file as it is and reports this error, with the
        // missing keys.
        return []
      }
      if try replace(destination, holding: found, with: settings.encoded()) {
        return missing.map { $0.path.joined(separator: ".") }
      }
    }
    throw SettingsError(
      description:
        "config.json changed while missing keys were being added, \(updateAttempts) times")
  }

  /// Sets `value` at `path` in `object`, inside the objects along it, which `keys(in:notIn:)`
  /// only names when they exist.
  private static func set(_ value: Any, at path: ArraySlice<String>, in object: inout [String: Any])
  {
    guard let key = path.first else { preconditionFailure("a key's path is never empty") }
    guard path.count > 1 else {
      object[key] = value
      return
    }
    guard var inner = object[key] as? [String: Any] else {
      preconditionFailure("keys(in:notIn:) names keys inside objects both files have")
    }
    set(value, at: path.dropFirst(), in: &inner)
    object[key] = inner
  }

  /// The file's bytes, or an error that says in words why they couldn't be read.
  private static func contents(of url: URL) throws -> Data {
    do {
      return try Data(contentsOf: url)
    } catch {
      throw SettingsError(
        description: "config.json couldn't be read: \(error.localizedDescription)")
    }
  }

  /// Writes `data` beside `url` and renames it over `url` if `url` still has `found`'s bytes,
  /// returning whether it did. That leaves the microseconds between the check and the rename.
  private static func replace(_ url: URL, holding found: Data, with data: Data) throws -> Bool {
    let files = FileManager.default
    let partial = url.deletingLastPathComponent()
      .appendingPathComponent(".\(url.lastPathComponent).partial-\(UUID().uuidString)")
    do {
      var info = stat()
      guard stat(url.path, &info) == 0 else { throw POSIXError.current }
      try write(data, to: partial, mode: info.st_mode & 0o7777)
      guard try contents(of: url) == found else {
        try files.removeItem(at: partial)
        return false
      }
      guard rename(partial.path, url.path) == 0 else { throw POSIXError.current }
      return true
    } catch {
      var description = "config.json wasn't saved: \(error.localizedDescription)"
      if files.fileExists(atPath: partial.path) {
        do {
          try files.removeItem(at: partial)
        } catch let cleanup {
          description += "; removing \(partial.path) then failed: \(cleanup.localizedDescription)"
        }
      }
      throw SettingsError(description: description)
    }
  }

  /// Creates `url`, which must not exist, with permissions `mode` before any byte is in it, so a
  /// file only its owner can read is never readable by others even for a moment.
  private static func write(_ data: Data, to url: URL, mode: mode_t) throws {
    // Created with no permissions for anyone else; `fchmod`, unlike `open`, ignores the umask.
    let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw POSIXError.current }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    guard fchmod(descriptor, mode) == 0 else { throw POSIXError.current }
    try handle.write(contentsOf: data)
    try handle.close()
  }
}

extension POSIXError {
  /// The error `errno` holds.
  fileprivate static var current: POSIXError {
    POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }
}
