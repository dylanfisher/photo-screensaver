/// Hands out every element once in random order, then reshuffles. Unlike picking at random each
/// time, nothing repeats until the whole collection has been shown.
public struct ShuffleQueue<Element> {
  private let elements: [Element]
  private var pending: [Element] = []

  public init(_ elements: [Element]) {
    self.elements = elements
  }

  /// Returns nil only when the queue was created empty.
  public mutating func next() -> Element? {
    if pending.isEmpty { pending = elements.shuffled() }
    return pending.popLast()
  }
}
