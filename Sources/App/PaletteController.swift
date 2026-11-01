import AppKit
import Core
import Settings

/// What the palette over the slideshow lists and does: every command with its key, narrowed as
/// the user types, and the timeframe picker with how many photos each choice shows. Lives
/// while the palette is open.
@MainActor
final class PaletteController {
  /// What the palette asks of the app.
  struct Actions {
    /// Runs a command chosen from the list. The app closes the palette first.
    let run: (Command) -> Void
    /// Closes the palette.
    let close: () -> Void
    /// Reads every count the timeframe picker shows, off the main thread.
    let countChoices: (@escaping @MainActor (Result<TimeframePicker.Counts, Error>) -> Void) -> Void
    /// Counts the photos one timeframe shows, off the main thread.
    let count: (Timeframe, @escaping @MainActor (Result<Int, Error>) -> Void) -> Void
    /// Saves and shows a timeframe with `count` photos, and closes the palette.
    let apply: (Timeframe, _ count: Int) -> Void
  }

  private let view: PaletteView
  private let keys: Settings.Keys
  /// The timeframe in the settings, which the picker starts on.
  private let current: Timeframe
  /// Whether the scan is still reading capture dates, so counts may grow.
  private let readingDates: Bool
  private let actions: Actions

  /// The commands the list shows, filtered.
  private var commands: [Command] = []
  /// The picker's choices, filtered.
  private var choices: [TimeframePicker.Choice] = []
  private var query = ""
  /// Nil until read, and kept, so going back from the custom range doesn't count again.
  private var counts: TimeframePicker.Counts?
  private var countError: Error?
  private var range: TimeframePicker.MonthRange?
  private var rangeCount: Int?
  /// Bumped by each step of the range, so only the latest count is shown.
  private var rangeGeneration = 0

  init(
    view: PaletteView, keys: Settings.Keys, current: Timeframe, readingDates: Bool,
    actions: Actions
  ) {
    self.view = view
    self.keys = keys
    self.current = current
    self.readingDates = readingDates
    self.actions = actions
  }

  // MARK: Commands

  func showCommands() {
    commands = CommandPalette.commands
    view.onQuery = { [weak self] query in self?.filterCommands(query) }
    view.onChoose = { [weak self] index in
      guard let self else { return }
      let command = self.commands[index]
      // Choosing a timeframe is the palette's own work: it stays open.
      if command == .timeframe { return self.showTimeframes() }
      self.actions.run(command)
    }
    view.onStep = nil
    view.onBack = actions.close
    view.show(
      header: .filter(placeholder: "Type a command"), rows: commandRows(),
      footer: Self.commandHints)
  }

  private static let commandHints = "↑↓ to choose · ↩ to run · esc to close"

  private func filterCommands(_ query: String) {
    commands = CommandPalette.filter(CommandPalette.commands, by: query) { $0.title }
    view.update(
      rows: commandRows(), selection: 0,
      footer: commands.isEmpty ? "No command matches" : Self.commandHints)
  }

  private func commandRows() -> [PaletteView.Row] {
    commands.map { PaletteView.Row(title: $0.title, detail: keys[$0].symbols) }
  }

  // MARK: Timeframes

  /// Lists the choices at once, with their counts as they arrive.
  func showTimeframes() {
    query = ""
    choices = allChoices()
    view.onQuery = { [weak self] query in
      guard let self else { return }
      self.query = query
      self.choices = self.filtered(self.allChoices())
      self.view.update(rows: self.timeframeRows(), selection: 0, footer: self.timeframeFooter())
    }
    view.onChoose = { [weak self] index in
      guard let self else { return }
      self.choose(self.choices[index])
    }
    view.onStep = nil
    view.onBack = actions.close
    // A year isn't listed until the counts arrive; until then a range selects the custom one.
    let selected =
      choices.firstIndex(of: .timeframe(current)) ?? choices.firstIndex(of: .customRange) ?? 0
    view.show(
      header: .filter(placeholder: "Choose a timeframe, or type a year"), rows: timeframeRows(),
      selection: selected, footer: timeframeFooter())
    guard counts == nil else { return }
    actions.countChoices { [weak self] result in
      guard let self else { return }
      switch result {
      case .success(let counts): self.counts = counts
      case .failure(let error): self.countError = error
      }
      // The years come after the fixed choices, so a selection the user made stays put. One
      // still where it opened moves to the current year, now that it's listed.
      self.choices = self.filtered(self.allChoices())
      if self.query.isEmpty, self.view.selection == selected,
        let index = self.choices.firstIndex(of: .timeframe(self.current))
      {
        self.view.update(
          rows: self.timeframeRows(), selection: index, footer: self.timeframeFooter())
      } else {
        self.view.update(rows: self.timeframeRows(), footer: self.timeframeFooter())
      }
    }
  }

  private func allChoices() -> [TimeframePicker.Choice] {
    TimeframePicker.choices(years: counts.map { Array($0.years.keys) } ?? [])
  }

  private func filtered(_ choices: [TimeframePicker.Choice]) -> [TimeframePicker.Choice] {
    CommandPalette.filter(choices, by: query, title: Self.title)
  }

  private static func title(of choice: TimeframePicker.Choice) -> String {
    switch choice {
    case .timeframe(let timeframe): return timeframe.title
    case .customRange: return "Custom range…"
    }
  }

  private func timeframeRows() -> [PaletteView.Row] {
    choices.map { choice in
      var detail = ""
      switch choice {
      case .timeframe(let timeframe):
        detail = counts?.count(of: timeframe).map(Self.photos) ?? (countError == nil ? "…" : "")
      case .customRange:
        // A range that isn't one of the listed years shows here, as what's showing now.
        if case .range = current, !allChoices().contains(.timeframe(current)) {
          detail = current.title
        }
      }
      var title = Self.title(of: choice)
      if choice == .timeframe(current) { title += "  ✓" }
      return PaletteView.Row(title: title, detail: detail)
    }
  }

  private func timeframeFooter(_ message: String? = nil) -> String {
    if let countError { return "Can't count photos: \(countError)" }
    var footer = message ?? "↑↓ to choose · ↩ to show · esc to close"
    if readingDates { footer += " (still reading photo dates)" }
    return footer
  }

  private func choose(_ choice: TimeframePicker.Choice) {
    switch choice {
    case .customRange:
      showRange()
    case .timeframe(let timeframe):
      guard let count = counts?.count(of: timeframe) else {
        return view.setFooter(timeframeFooter("Still counting photos…"))
      }
      apply(timeframe, count: count)
    }
  }

  /// Applies `timeframe` unless it would show nothing.
  private func apply(_ timeframe: Timeframe, count: Int) {
    guard count > 0 else {
      return view.setFooter(timeframeFooter("No photos taken in \(timeframe.title)"))
    }
    actions.apply(timeframe, count)
  }

  // MARK: Custom range

  private func showRange() {
    let today = Calendar.current.dateComponents([.year, .month], from: Date())
    guard let year = today.year, let month = today.month else {
      preconditionFailure("dateComponents gives the components asked for")
    }
    range = TimeframePicker.MonthRange(
      current: current, years: counts.map { Array($0.years.keys) } ?? [],
      today: CaptureMonth(year: year, month: month))
    view.onQuery = nil
    view.onStep = { [weak self] row, forward, large in
      guard let self, var range = self.range else { return }
      range.step(row == 0 ? .from : .to, by: (forward ? 1 : -1) * (large ? 12 : 1))
      guard range != self.range else { return }
      self.range = range
      self.countRange()
    }
    view.onChoose = { [weak self] _ in
      guard let self, let range = self.range else { return }
      guard let count = self.rangeCount else {
        return self.view.setFooter(self.timeframeFooter("Still counting photos…"))
      }
      self.apply(range.timeframe, count: count)
    }
    view.onBack = { [weak self] in self?.showTimeframes() }
    view.show(header: .title("Custom range"), rows: rangeRows(), footer: rangeFooter())
    countRange()
  }

  private func countRange() {
    guard let range else { return }
    rangeCount = nil
    rangeGeneration += 1
    let generation = rangeGeneration
    view.update(rows: rangeRows(), footer: rangeFooter())
    actions.count(range.timeframe) { [weak self] result in
      guard let self, generation == self.rangeGeneration else { return }
      switch result {
      case .success(let count):
        self.rangeCount = count
        self.view.update(rows: self.rangeRows(), footer: self.rangeFooter())
      case .failure(let error):
        self.view.setFooter("Can't count photos: \(error)")
      }
    }
  }

  private func rangeRows() -> [PaletteView.Row] {
    guard let range else { return [] }
    func month(_ month: CaptureMonth) -> String { "\(month.monthName) \(month.year)" }
    return [
      PaletteView.Row(title: "From", detail: month(range.from), steps: true),
      PaletteView.Row(title: "To", detail: month(range.to), steps: true),
      PaletteView.Row(
        title: "Show \(range.timeframe.title)", detail: rangeCount.map(Self.photos) ?? "…"),
    ]
  }

  private func rangeFooter() -> String {
    timeframeFooter("←→ month · ⇧←→ year · ↩ to show · esc to go back")
  }

  /// Like "3,812 photos".
  static func photos(_ count: Int) -> String {
    count == 1 ? "1 photo" : "\(count.formatted()) photos"
  }

  // MARK: Keys

  /// A key with ⌘ or ⌃ pressed while the palette is open, which the window routes here rather
  /// than to the text field. The palette's own key closes it again; ⌘A, ⌘C, ⌘V and ⌘X edit
  /// the filter, since the app has no Edit menu to send them; any other does nothing, so a
  /// slip doesn't end the slideshow.
  func handleShortcut(_ event: NSEvent) {
    guard let spec = KeySpec(event) else { return }
    if keys.command(for: spec) == .palette { return actions.close() }
    guard spec.modifiers == .cmd, case .character(let character) = spec.key else { return }
    let edits: [Character: Selector] = [
      "a": #selector(NSText.selectAll(_:)), "c": #selector(NSText.copy(_:)),
      "v": #selector(NSText.paste(_:)), "x": #selector(NSText.cut(_:)),
    ]
    if let action = edits[character] { NSApp.sendAction(action, to: nil, from: nil) }
  }
}
