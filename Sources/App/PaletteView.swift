import AppKit
import Settings

/// The panel the command list and the timeframe picker show in, centered over the slideshow: a
/// header, either a field to filter by or a title, a list of rows with a title on the left and
/// a key or a count on the right, and a line of hints. Dark and translucent, like the info
/// panel.
///
/// It only shows rows and reports what's done with them; `PaletteController` decides what they
/// are.
final class PaletteView: NSVisualEffectView, NSTextFieldDelegate {
  struct Row: Equatable {
    var title: String
    /// On the right: the command's key, or how many photos match.
    var detail: String
    /// A value that ← and → step through, drawn between arrows, like a month.
    var steps = false
  }

  enum Header: Equatable {
    /// A field that filters the rows as the user types. ↑ and ↓ still move through the rows.
    case filter(placeholder: String)
    /// A fixed title. All keys go to the rows.
    case title(String)
  }

  static let width: CGFloat = 560
  static let visibleRows = 9
  private static let rowHeight: CGFloat = 34
  private static let headerHeight: CGFloat = 52
  private static let footerHeight: CGFloat = 30
  private static let inset: CGFloat = 8
  private static let cornerRadius: CGFloat = 12
  /// The width of a stepping row's value, with its arrows either side.
  static let stepperWidth: CGFloat = 170
  static let arrowWidth: CGFloat = 28

  /// Called with the field's text as the user types.
  var onQuery: ((String) -> Void)?
  /// Return, or a click, on the row at this index of `rows`.
  var onChoose: ((Int) -> Void)?
  /// ← or → on a stepping row: the row, whether forward, and whether Shift was held.
  var onStep: ((_ row: Int, _ forward: Bool, _ large: Bool) -> Void)?
  /// Escape.
  var onBack: (() -> Void)?

  private(set) var rows: [Row] = []
  private(set) var selection = 0
  /// The row at the top of the list, when there are more than fit.
  private var firstVisible = 0
  private var header = Header.filter(placeholder: "")
  private let field = NSTextField()
  private let separator = NSView()
  private var rowViews: [PaletteRowView] = []
  private let footer = NSTextField(labelWithString: "")

  init() {
    super.init(frame: .zero)
    material = .hudWindow
    blendingMode = .withinWindow
    // A borderless window over the screen saver level never looks active to AppKit.
    state = .active
    appearance = NSAppearance(named: .darkAqua)
    maskImage = Self.roundedMask(radius: Self.cornerRadius)
    isHidden = true

    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.font = .systemFont(ofSize: 22)
    field.textColor = .white
    field.cell?.usesSingleLineMode = true
    field.cell?.lineBreakMode = .byTruncatingTail
    field.delegate = self
    addSubview(field)

    separator.wantsLayer = true
    separator.layer?.backgroundColor = NSColor(white: 1, alpha: 0.15).cgColor
    addSubview(separator)

    for _ in 0..<Self.visibleRows {
      let row = PaletteRowView()
      row.onClick = { [weak self, weak row] x in
        guard let self, let row else { return }
        self.clicked(row: self.firstVisible + row.slot, x: x)
      }
      rowViews.append(row)
      addSubview(row)
    }
    for (slot, row) in rowViews.enumerated() { row.slot = slot }

    footer.font = .systemFont(ofSize: 12)
    footer.textColor = NSColor(white: 1, alpha: 0.55)
    footer.lineBreakMode = .byTruncatingTail
    addSubview(footer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { preconditionFailure("not loaded from a nib") }

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }

  /// Replaces what the panel shows, selecting `selection`, and takes the keyboard.
  func show(header: Header, rows: [Row], selection: Int = 0, footer: String) {
    self.header = header
    switch header {
    case .filter(let placeholder):
      field.isEditable = true
      field.isSelectable = true
      field.stringValue = ""
      field.placeholderAttributedString = NSAttributedString(
        string: placeholder,
        attributes: [
          .font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor(white: 1, alpha: 0.4),
        ])
    case .title(let title):
      field.isEditable = false
      field.isSelectable = false
      field.stringValue = title
    }
    self.rows = rows
    self.selection = min(max(selection, 0), max(rows.count - 1, 0))
    firstVisible = 0
    self.footer.stringValue = footer
    relayout()
    window?.makeFirstResponder(isTitle ? self : field)
  }

  /// Changes the rows, keeping the selection where it was as far as it can.
  func update(rows: [Row], footer: String? = nil) {
    self.rows = rows
    selection = min(selection, max(rows.count - 1, 0))
    if let footer { self.footer.stringValue = footer }
    relayout()
  }

  /// Changes the rows and selects `selection`, such as the first after the user types.
  func update(rows: [Row], selection: Int, footer: String? = nil) {
    self.selection = selection
    firstVisible = 0
    update(rows: rows, footer: footer)
  }

  func setFooter(_ text: String) {
    footer.stringValue = text
  }

  private var isTitle: Bool {
    if case .title = header { return true }
    return false
  }

  /// Sizes the panel for its rows, its top edge a little above the middle of the window so it
  /// doesn't jump as the list grows or shrinks.
  private func relayout() {
    guard let container = superview else { return }
    let visible = min(rows.count, Self.visibleRows)
    let listTop = Self.headerHeight + 1 + (visible > 0 ? Self.inset : 0)
    let listHeight = CGFloat(visible) * Self.rowHeight
    let height = listTop + listHeight + Self.footerHeight
    let top = container.bounds.height * 0.72
    frame = CGRect(
      x: (container.bounds.width - Self.width) / 2, y: top - height, width: Self.width,
      height: height)

    let fieldHeight = ceil(field.intrinsicContentSize.height)
    field.frame = CGRect(
      x: 18, y: (Self.headerHeight - fieldHeight) / 2, width: Self.width - 36, height: fieldHeight)
    separator.frame = CGRect(x: 0, y: Self.headerHeight, width: Self.width, height: 1)

    firstVisible = min(max(firstVisible, selection - Self.visibleRows + 1), selection)
    firstVisible = max(0, min(firstVisible, rows.count - visible))
    for (slot, view) in rowViews.enumerated() {
      let index = firstVisible + slot
      guard slot < visible, index < rows.count else {
        view.isHidden = true
        continue
      }
      view.isHidden = false
      view.frame = CGRect(
        x: Self.inset, y: listTop + CGFloat(slot) * Self.rowHeight,
        width: Self.width - 2 * Self.inset, height: Self.rowHeight)
      view.show(rows[index], selected: index == selection)
    }

    footer.frame = CGRect(
      x: 18, y: height - Self.footerHeight + 7, width: Self.width - 36, height: 16)
  }

  private func move(by offset: Int) {
    guard !rows.isEmpty else { return }
    selection = (selection + offset + rows.count) % rows.count
    relayout()
  }

  private func choose() {
    guard rows.indices.contains(selection) else { return }
    onChoose?(selection)
  }

  private func step(forward: Bool, large: Bool) {
    guard rows.indices.contains(selection), rows[selection].steps else { return }
    onStep?(selection, forward, large)
  }

  /// A click on a stepping row's arrows steps it; anywhere else on it only selects it. A click
  /// on any other row chooses it.
  private func clicked(row index: Int, x: CGFloat) {
    guard rows.indices.contains(index) else { return }
    selection = index
    relayout()
    guard rows[index].steps else { return choose() }
    let rowWidth = Self.width - 2 * Self.inset
    let stepperStart = rowWidth - Self.stepperWidth - 8
    if x >= stepperStart, x < stepperStart + Self.arrowWidth {
      step(forward: false, large: false)
    } else if x >= rowWidth - 8 - Self.arrowWidth, x < rowWidth {
      step(forward: true, large: false)
    }
  }

  // MARK: Keys

  /// Keys while the header is a title, when the panel itself has the keyboard.
  override func keyDown(with event: NSEvent) {
    // Keys are named by position, as everywhere in the app.
    guard case .named(let name)? = KeySpec.Key(keyCode: event.keyCode) else { return }
    let shift = event.modifierFlags.contains(.shift)
    switch name {
    case .up: move(by: -1)
    case .down: move(by: 1)
    case .left: step(forward: false, large: shift)
    case .right: step(forward: true, large: shift)
    case .return: choose()
    case .escape: onBack?()
    case .space, .tab, .delete, .plus, .forwardDelete: break
    }
  }

  /// Keys the filter field's editor doesn't type, while it has the keyboard.
  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    switch selector {
    case #selector(NSResponder.moveUp(_:)): move(by: -1)
    case #selector(NSResponder.moveDown(_:)): move(by: 1)
    case #selector(NSResponder.insertNewline(_:)): choose()
    // Escape is cancelOperation, or complete in a text view that has nothing to complete.
    case #selector(NSResponder.cancelOperation(_:)), #selector(NSTextView.complete(_:)): onBack?()
    // Tab would move the keyboard out of the field, where typing no longer filters.
    case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)): break
    default: return false
    }
    return true
  }

  func controlTextDidChange(_ notification: Notification) {
    onQuery?(field.stringValue)
  }

  // MARK: Mouse

  /// Clicks on the panel's background stay here, rather than reaching the window behind,
  /// where a click closes the panel.
  override func mouseDown(with event: NSEvent) {}

  /// Scrolls a list longer than the panel by one row per notch.
  override func scrollWheel(with event: NSEvent) {
    guard rows.count > Self.visibleRows, abs(event.scrollingDeltaY) >= 1 else { return }
    let offset = event.scrollingDeltaY > 0 ? -1 : 1
    firstVisible = max(0, min(firstVisible + offset, rows.count - Self.visibleRows))
    // Keep the selection on screen, or the next layout would scroll back to it.
    selection = min(max(selection, firstVisible), firstVisible + Self.visibleRows - 1)
    relayout()
  }

  /// A mask that rounds the corners of the blurred background, which ignores a layer's
  /// corner radius.
  private static func roundedMask(radius: CGFloat) -> NSImage {
    let edge = radius * 2 + 1
    let image = NSImage(size: CGSize(width: edge, height: edge), flipped: false) { rect in
      NSColor.black.setFill()
      NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
      return true
    }
    image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
    image.resizingMode = .stretch
    return image
  }
}

/// One row of the palette's list, highlighted when selected.
private final class PaletteRowView: NSView {
  /// Position among the visible rows, top first.
  var slot = 0
  /// Called with where the click was, from the row's left edge.
  var onClick: ((CGFloat) -> Void)?

  private let title = NSTextField(labelWithString: "")
  private let detail = NSTextField(labelWithString: "")
  private let back = NSTextField(labelWithString: "‹")
  private let forward = NSTextField(labelWithString: "›")

  init() {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 6
    title.font = .systemFont(ofSize: 15)
    title.textColor = .white
    title.lineBreakMode = .byTruncatingTail
    detail.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    detail.lineBreakMode = .byTruncatingHead
    for arrow in [back, forward] {
      arrow.font = .systemFont(ofSize: 18, weight: .medium)
      arrow.alignment = .center
    }
    for label in [title, detail, back, forward] { addSubview(label) }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { preconditionFailure("not loaded from a nib") }

  func show(_ row: PaletteView.Row, selected: Bool) {
    layer?.backgroundColor = selected ? NSColor.controlAccentColor.cgColor : nil
    title.stringValue = row.title
    detail.stringValue = row.detail
    let dim = NSColor(white: 1, alpha: selected ? 0.85 : 0.55)
    detail.textColor = row.steps ? .white : dim
    back.textColor = dim
    forward.textColor = dim
    back.isHidden = !row.steps
    forward.isHidden = !row.steps

    let height = bounds.height
    func centered(_ label: NSTextField, x: CGFloat, width: CGFloat) {
      let labelHeight = ceil(label.intrinsicContentSize.height)
      label.frame = CGRect(x: x, y: (height - labelHeight) / 2, width: width, height: labelHeight)
    }
    let right = bounds.width - 8
    let detailWidth: CGFloat
    if row.steps {
      detailWidth = PaletteView.stepperWidth
      let arrow = PaletteView.arrowWidth
      centered(back, x: right - detailWidth, width: arrow)
      centered(forward, x: right - arrow, width: arrow)
      detail.alignment = .center
      centered(detail, x: right - detailWidth + arrow, width: detailWidth - 2 * arrow)
    } else {
      // A label set to truncate has no intrinsic width, so measure its text. Plus the
      // cell's padding.
      detailWidth = min(ceil(detail.attributedStringValue.size().width) + 6, bounds.width / 2)
      detail.alignment = .right
      centered(detail, x: right - detailWidth, width: detailWidth)
    }
    centered(title, x: 10, width: right - detailWidth - 20)
  }

  /// The labels in the row don't take clicks; the row does.
  override func hitTest(_ point: NSPoint) -> NSView? {
    frame.contains(point) ? self : nil
  }

  override var isFlipped: Bool { true }

  override func mouseDown(with event: NSEvent) {
    onClick?(convert(event.locationInWindow, from: nil).x)
  }
}
