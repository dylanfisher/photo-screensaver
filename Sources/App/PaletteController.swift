import AppKit
import Core
import Settings

/// What the palette over the slideshow lists and does: every command with its key, narrowed as
/// the user types. Lives while the palette is open.
@MainActor
final class PaletteController {
  private let view: PaletteView
  private let keys: Settings.Keys
  /// Runs a command chosen from the list. The app closes the palette first.
  private let run: (Command) -> Void
  /// Closes the palette.
  private let close: () -> Void
  /// The commands the list shows, filtered.
  private var commands: [Command] = []

  init(
    view: PaletteView, keys: Settings.Keys, run: @escaping (Command) -> Void,
    close: @escaping () -> Void
  ) {
    self.view = view
    self.keys = keys
    self.run = run
    self.close = close
  }

  func showCommands() {
    commands = CommandPalette.commands
    view.onQuery = { [weak self] query in self?.filterCommands(query) }
    view.onChoose = { [weak self] index in
      guard let self else { return }
      self.run(self.commands[index])
    }
    view.onStep = nil
    view.onBack = close
    view.show(
      header: .filter(placeholder: "Type a command"), rows: commandRows(),
      footer: "↑↓ to choose · ↩ to run · esc to close")
  }

  private func filterCommands(_ query: String) {
    commands = CommandPalette.filter(CommandPalette.commands, by: query) { $0.title }
    view.update(
      rows: commandRows(), selection: 0,
      footer: commands.isEmpty
        ? "No command matches" : "↑↓ to choose · ↩ to run · esc to close")
  }

  private func commandRows() -> [PaletteView.Row] {
    commands.map { PaletteView.Row(title: $0.title, detail: keys[$0].symbols) }
  }

  /// A key with ⌘ or ⌃ pressed while the palette is open, which the window routes here rather
  /// than to the text field. The palette's own key closes it again; ⌘A, ⌘C, ⌘V and ⌘X edit
  /// the filter, since the app has no Edit menu to send them; any other does nothing, so a
  /// slip doesn't end the slideshow.
  func handleShortcut(_ event: NSEvent) {
    guard let spec = KeySpec(event) else { return }
    if keys.command(for: spec) == .palette { return close() }
    guard spec.modifiers == .cmd, case .character(let character) = spec.key else { return }
    let edits: [Character: Selector] = [
      "a": #selector(NSText.selectAll(_:)), "c": #selector(NSText.copy(_:)),
      "v": #selector(NSText.paste(_:)), "x": #selector(NSText.cut(_:)),
    ]
    if let action = edits[character] { NSApp.sendAction(action, to: nil, from: nil) }
  }
}
