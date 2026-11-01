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
