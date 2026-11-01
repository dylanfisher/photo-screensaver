import Darwin
import Foundation

extension Settings {
  /// How many times `update` makes its change before it gives up, when the file changes under
  /// each try.
  static let updateAttempts = 3

  /// Makes `change` to the settings in the config file, writes them back, and returns them.
  ///
  /// The change is made to what the file holds, never to settings kept in memory, so an edit
  /// made in an editor since the last read isn't overwritten. A file with an error isn't
  /// written, and neither are settings the change makes invalid; both throw. A change that
  /// leaves the settings as they were writes nothing, so a file formatted by hand stays as it
  /// is. The new file is written beside the old one, with its permissions, and renamed over it
  /// only if it still has the bytes the change was made to; when it doesn't, as when an editor
  /// saved meanwhile, the change is made again to the new contents, up to `updateAttempts`
  /// times. A symbolic link at `url` stays: the file it leads to is replaced.
  @discardableResult
  public static func update(at url: URL = fileURL, _ change: (inout Settings) throws -> Void)
    throws -> Settings
  {
    let destination = url.resolvingSymlinksInPath()
    for _ in 0..<updateAttempts {
      let found = try Data(contentsOf: destination)
      let current = try decode(found)
      var changed = current
      try change(&changed)
      guard changed != current else { return current }
      try changed.validate()
      if try replace(destination, holding: found, with: changed.encoded()) { return changed }
    }
    throw SettingsError(
      description:
        "config.json changed while it was being saved, \(updateAttempts) times; try again")
  }

  /// Writes `data` beside `url` and renames it over `url` if `url` still has `found`'s bytes,
  /// returning whether it did. That leaves the microseconds between the check and the rename.
  private static func replace(_ url: URL, holding found: Data, with data: Data) throws -> Bool {
    let files = FileManager.default
    let partial = url.deletingLastPathComponent()
      .appendingPathComponent(".\(url.lastPathComponent).partial-\(UUID().uuidString)")
    try data.write(to: partial, options: .withoutOverwriting)
    do {
      var info = stat()
      guard stat(url.path, &info) == 0, chmod(partial.path, info.st_mode & 0o7777) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
      guard try Data(contentsOf: url) == found else {
        try files.removeItem(at: partial)
        return false
      }
      guard rename(partial.path, url.path) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
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
}
