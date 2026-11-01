/// The photos shown so far, for stepping back through them and forward again before new ones
/// are drawn. Holds photo IDs only: a photo shown again is decoded again, since keeping decoded
/// photos would cost 60–160 MB each.
public struct SlideHistory {
  /// Photos kept, oldest first. Going back stops at the oldest.
  public static let limit = 200

  public enum Target: Equatable {
    /// A photo from the history.
    case photo(Int64)
    /// A new photo from the feed.
    case new
  }

  private var ids: [Int64] = []
  /// Index in `ids` of the target, or `ids.count` for a new photo.
  private var index = 0

  public init() {}

  /// What to show next: the photo stepped to, or a new one past the end of the history.
  public var target: Target {
    index < ids.count ? .photo(ids[index]) : .new
  }

  /// Steps to the next photo in the history, or past its end to a new one. Past the end, more
  /// steps still mean one new photo, so pressing ahead of a slow load doesn't skip photos.
  public mutating func forward() {
    index = min(index + 1, ids.count)
  }

  /// Steps to the previous photo. Returns false, changing nothing, at the oldest one kept.
  public mutating func back() -> Bool {
    guard index > 0 else { return false }
    index -= 1
    return true
  }

  /// Records a new photo from the feed as shown, which makes it the target.
  public mutating func add(_ id: Int64) {
    ids.append(id)
    if ids.count > Self.limit { ids.removeFirst(ids.count - Self.limit) }
    index = ids.count - 1
  }
}
