import Foundation

/// The list of photo files under the library folder, as paths relative to it. Scanning tens of
/// thousands of files over SMB takes a while, so the last scan is cached on disk and used at
/// launch while a fresh scan runs.
public struct PhotoIndex: Codable, Equatable {
  public let root: String
  public let paths: [String]
  /// Folders and files the scan couldn't read. Their photos are missing from `paths`.
  public let unreadableCount: Int

  static let extensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "png", "tif", "tiff"]
  /// System folders a NAS keeps inside shares: Synology thumbnails and recycle bin.
  static let skippedFolders: Set<String> = ["@eaDir", "#recycle", "#snapshot"]

  public static var cacheURL: URL {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
    return caches[0].appendingPathComponent("photo-screensaver/index.json")
  }

  public static func scan(_ root: URL) throws -> PhotoIndex {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { throw IndexError(description: "library folder not found: \(root.path)") }

    var unreadable = 0
    var rootError: Error?
    let keys: [URLResourceKey] = [.isDirectoryKey]
    guard
      let walker = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles, .skipsPackageDescendants],
        errorHandler: { url, error in
          // A subfolder that can't be read costs its photos; the root failing costs all of them.
          if url.standardizedFileURL == root.standardizedFileURL { rootError = error }
          unreadable += 1
          return true
        })
    else { throw IndexError(description: "can't read library folder: \(root.path)") }

    let prefix = root.standardizedFileURL.path + "/"
    var paths: [String] = []
    for case let url as URL in walker {
      guard let isDirectory = try? url.resourceValues(forKeys: Set(keys)).isDirectory else {
        unreadable += 1
        continue
      }
      if isDirectory {
        if skippedFolders.contains(url.lastPathComponent) { walker.skipDescendants() }
        continue
      }
      guard extensions.contains(url.pathExtension.lowercased()) else { continue }
      let path = url.standardizedFileURL.path
      guard path.hasPrefix(prefix) else {
        throw IndexError(description: "\(path) is outside the library folder \(root.path)")
      }
      paths.append(String(path.dropFirst(prefix.count)))
    }
    if let rootError {
      throw IndexError(description: "can't read library folder \(root.path): \(rootError)")
    }
    return PhotoIndex(root: root.path, paths: paths.sorted(), unreadableCount: unreadable)
  }

  /// The cached index for `root`, or nil if there is none or it belongs to another folder.
  public static func cached(for root: URL, at url: URL = cacheURL) throws -> PhotoIndex? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let index = try JSONDecoder().decode(PhotoIndex.self, from: Data(contentsOf: url))
    return index.root == root.path ? index : nil
  }

  public func save(to url: URL = cacheURL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(self).write(to: url, options: .atomic)
  }

  public func url(for path: String) -> URL {
    URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent(path)
  }
}

public struct IndexError: Error, CustomStringConvertible {
  public let description: String
}
