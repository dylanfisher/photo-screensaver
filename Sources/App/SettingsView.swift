import AppKit
import Core
import Settings
import SwiftUI

// SwiftUI has a `Settings` scene too; this file means the config type.
import struct Settings.Settings

/// The settings window's content: a control for every key of config.json, in sections, each
/// label on the left with a line saying what it does and its control on the right
/// (docs/decisions/0009-settings-window.md). macOS 12 has no grouped form style, so the sections
/// stack in a padded scroll view.
struct SettingsView: View {
  /// What the window's buttons do in the rest of the app.
  struct Actions {
    let openFile: () -> Void
    let revealFile: () -> Void
    let rescan: () -> Void
  }

  @ObservedObject var model: SettingsModel
  let actions: Actions

  static let width: CGFloat = 580
  /// Wide enough for "Range of months" and the longest slide length.
  private static let pickerWidth: CGFloat = 190
  private static let numberWidth: CGFloat = 70

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if model.isFileBroken || model.changeError != nil {
          problems
        }
        Group {
          library
          slideshow
          timeframe
          offHours
          motion
          keys
        }
        .disabled(model.isFileBroken)
        file
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(width: Self.width)
    .frame(minHeight: 360, idealHeight: 680)
  }

  // MARK: Sections

  private var problems: some View {
    SettingsSection {
      Label(
        model.isFileBroken
          ? "Settings can't change until config.json is fixed."
          : "The last change wasn't saved.",
        systemImage: "exclamationmark.triangle.fill"
      )
      .foregroundColor(.orange)
      .font(.headline)
      ForEach(
        Array([model.fileError, model.changeError].compactMap { $0 }.enumerated()), id: \.offset
      ) { _, error in
        Text(error)
          .font(.callout)
          .textSelection(.enabled)
      }
      if !model.missingKeys.isEmpty {
        Text("Add these keys to config.json, here with their defaults:")
          .font(.callout)
        VStack(alignment: .leading, spacing: 2) {
          ForEach(model.missingKeys, id: \.path) { key in
            Text("\(key.path): \(key.value)")
          }
        }
        .font(.system(.callout, design: .monospaced))
        .textSelection(.enabled)
        Text("A dotted name goes inside its object: keys.pause is \"pause\" under \"keys\".")
          .font(.callout)
          .foregroundColor(.secondary)
      }
      if model.isFileBroken {
        Button("Open config.json", action: actions.openFile)
      }
    }
  }

  private var library: some View {
    SettingsSection("Library") {
      SettingRow("Photos folder", detail: model.settings.libraryPath) {
        Button("Choose…", action: chooseLibrary)
      }
      SettingRow("Scan", detail: "Reads the folder again for new, changed and removed photos.") {
        Button("Rescan Now", action: actions.rescan)
      }
    }
  }

  private var slideshow: some View {
    SettingsSection("Slideshow") {
      SettingRow("Start after", detail: "Minutes without keyboard or mouse input.") {
        numberField(\.idleMinutes, unit: "min")
      }
      SettingRow("Show each photo for", detail: "Keys 1–5 choose these too.") {
        Picker("Show each photo for", selection: binding(\.slideSeconds)) {
          ForEach(model.slideChoices, id: \.self) { seconds in
            Text(SettingsModel.describe(slideSeconds: seconds)).tag(seconds)
          }
        }
        .labelsHidden()
        .frame(width: Self.pickerWidth)
      }
      SettingRow("Crossfade", detail: "Seconds; shorter than each photo shows.") {
        numberField(\.transitionSeconds, unit: "s")
      }
      SettingRow("Scaling", detail: "Fill crops the edges; Fit shows the whole photo.") {
        Picker("Scaling", selection: binding(\.scaling)) {
          Text("Fill the screen").tag(Settings.Scaling.fill)
          Text("Fit the photo").tag(Settings.Scaling.fit)
        }
        .labelsHidden()
        .frame(width: Self.pickerWidth)
      }
      SettingRow("Orientation", detail: "Which photos show, by their shape.") {
        Picker("Orientation", selection: binding(\.orientation)) {
          Text("Any").tag(Settings.Orientation.any)
          Text("Landscape only").tag(Settings.Orientation.landscape)
          Text("Portrait only").tag(Settings.Orientation.portrait)
        }
        .labelsHidden()
        .frame(width: Self.pickerWidth)
      }
      SettingRow("Ken Burns", detail: "A slow pan and zoom on each photo.") {
        switchToggle("Ken Burns", isOn: binding(\.kenBurns))
      }
      SettingRow("Photos decoded ahead", detail: "Each can take 60–160 MB of memory.") {
        CommitField(value: "\(model.settings.preloadCount)", width: Self.numberWidth) {
          model.setCount(\.preloadCount, from: $0)
        }
      }
    }
  }

  private var timeframe: some View {
    SettingsSection("Timeframe") {
      SettingRow("Show photos from", detail: model.settings.timeframe.title) {
        Picker(
          "Show photos from",
          selection: Binding(
            get: { model.timeframeKind },
            set: { model.setTimeframeKind($0, today: Self.thisMonth()) })
        ) {
          ForEach(SettingsModel.TimeframeKind.allCases, id: \.self) { kind in
            Text(kind.title).tag(kind)
          }
        }
        .labelsHidden()
        .frame(width: Self.pickerWidth)
      }
      switch model.settings.timeframe {
      case .all, .onThisDay:
        EmptyView()
      case .lastMonths(let months):
        SettingRow("Months", detail: "Back from today's date.") {
          CommitField(value: "\(months)", width: Self.numberWidth) { model.setMonths(from: $0) }
        }
      case .range(let from, let to):
        SettingRow("From", detail: "The first month, like 2014-01.") {
          CommitField(value: from.prefix, width: Self.numberWidth + 20) {
            model.setRange(first: true, from: $0)
          }
        }
        SettingRow("To", detail: "The last month, included.") {
          CommitField(value: to.prefix, width: Self.numberWidth + 20) {
            model.setRange(first: false, from: $0)
          }
        }
      }
    }
  }

  private var offHours: some View {
    SettingsSection("Off hours") {
      SettingRow(
        "Off hours", detail: "The slideshow doesn't start and the camera stays off."
      ) {
        switchToggle("Off hours", isOn: binding(\.offHours.enabled))
      }
      SettingRow("Start", detail: "24-hour time, like 00:00.") {
        timeField(\.offHours.start)
      }
      SettingRow("End", detail: "A start later than the end spans midnight.") {
        timeField(\.offHours.end)
      }
    }
  }

  private var motion: some View {
    SettingsSection("Motion") {
      SettingRow("Use the camera", detail: "Sleeps the display when no one is around.") {
        switchToggle("Use the camera", isOn: binding(\.motion.enabled))
      }
      Group {
        SettingRow("Check every", detail: "The longest gap between camera checks.") {
          numberField(\.motion.checkEveryMinutes, unit: "min")
        }
        SettingRow("Quick check after", detail: "Confirms an empty room; the first gap once off.") {
          numberField(\.motion.quickCheckEverySeconds, unit: "s")
        }
        SettingRow("Watch for", detail: "Longest each check runs; it stops at the first motion.") {
          numberField(\.motion.sampleSeconds, unit: "s")
        }
        SettingRow("Light sensor", detail: "Checks at once when the room's light changes.") {
          switchToggle("Light sensor", isOn: binding(\.motion.useLightSensor))
        }
        SettingRow("Threshold", detail: "Fraction (0–1) of a grid cell that must change.") {
          numberField(\.motion.threshold, unit: "")
        }
      }
      .disabled(!model.settings.motion.enabled)
    }
  }

  private var keys: some View {
    SettingsSection("Keys") {
      Text("While the slideshow shows. Click a key, then press the new one; Esc cancels.")
        .font(.callout)
        .foregroundColor(.secondary)
      ForEach(Command.allCases, id: \.self) { command in
        HStack {
          Text(command.title)
          Spacer()
          Button {
            model.toggleRecording(command)
          } label: {
            Text(model.recording == command ? "Press a key…" : model.settings.keys[command].symbols)
              .frame(minWidth: 110)
              .foregroundColor(model.recording == command ? .secondary : .primary)
          }
          .help(model.recording == command ? "Press a key, or Esc to cancel" : "Click to record")
        }
        if model.recording == command, let refusal = model.refusal {
          Text(refusal)
            .font(.callout)
            .foregroundColor(.orange)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Button("Restore Default Keys", action: model.restoreDefaultKeys)
    }
  }

  private var file: some View {
    SettingsSection("config.json") {
      Text((model.fileURL.path as NSString).abbreviatingWithTildeInPath)
        .font(.callout)
        .foregroundColor(.secondary)
        .textSelection(.enabled)
      HStack {
        Button("Open config.json", action: actions.openFile)
        Button("Reveal in Finder", action: actions.revealFile)
      }
      Text("Changes here are saved to the file, and edits to the file show here.")
        .font(.callout)
        .foregroundColor(.secondary)
    }
  }

  // MARK: Parts

  /// A control's binding to the setting at `path`: it shows the file's value and saves a change.
  private func binding<Value>(_ path: WritableKeyPath<Settings, Value>) -> Binding<Value> {
    Binding(get: { model.settings[keyPath: path] }, set: { model.set(path, to: $0) })
  }

  private func switchToggle(_ title: String, isOn: Binding<Bool>) -> some View {
    Toggle(title, isOn: isOn)
      .labelsHidden()
      .toggleStyle(.switch)
  }

  private func numberField(_ path: WritableKeyPath<Settings, Double>, unit: String) -> some View {
    HStack(spacing: 4) {
      CommitField(
        value: SettingsModel.text(model.settings[keyPath: path]), width: Self.numberWidth
      ) { model.setNumber(path, from: $0) }
      Text(unit)
        .foregroundColor(.secondary)
        .frame(width: 26, alignment: .leading)
    }
  }

  private func timeField(_ path: WritableKeyPath<Settings, String>) -> some View {
    CommitField(value: model.settings[keyPath: path], width: Self.numberWidth) {
      model.set(path, to: $0.trimmingCharacters(in: .whitespaces))
    }
  }

  /// Asks for the photos folder in an open panel on the settings window.
  private func chooseLibrary() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.directoryURL = model.settings.libraryURL
    panel.prompt = "Choose"
    panel.message = "Choose the folder to show photos from. It's only read, never changed."
    let done = { [model] (response: NSApplication.ModalResponse) in
      guard response == .OK, let folder = panel.url else { return }
      model.setLibrary(folder)
    }
    if let window = NSApp.keyWindow {
      panel.beginSheetModal(for: window, completionHandler: done)
    } else {
      panel.begin(completionHandler: done)
    }
  }

  /// This month in the Mac's time zone, which a new range of months ends on.
  private static func thisMonth() -> CaptureMonth {
    let today = Calendar.current.dateComponents([.year, .month], from: Date())
    guard let year = today.year, let month = today.month else {
      preconditionFailure("dateComponents gives the components asked for")
    }
    return CaptureMonth(year: year, month: month)
  }
}

/// A section: its title as a heading, and its rows beneath.
private struct SettingsSection<Content: View>: View {
  let title: String?
  @ViewBuilder let content: Content

  init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let title {
        Text(title).font(.headline)
      }
      content
    }
  }
}

/// A setting's title, with a line under it saying what it does, and its control on the right.
private struct SettingRow<Control: View>: View {
  let title: String
  let detail: String
  @ViewBuilder let control: Control

  init(_ title: String, detail: String, @ViewBuilder control: () -> Control) {
    self.title = title
    self.detail = detail
    self.control = control()
  }

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
        Text(detail)
          .font(.callout)
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 12)
      control
    }
  }
}

/// A text field that saves what was typed on Return or when it loses focus, rather than at
/// each keystroke, which would save "0" on the way to "09:00". After saving, and whenever the
/// file's value changes, it shows the file's value, so text the file refused or wrote another way
/// ("05" for 5) doesn't stay looking saved.
private struct CommitField: View {
  let value: String
  let width: CGFloat
  let commit: (String) -> Void

  @EnvironmentObject private var edits: PendingEdits
  @State private var id = UUID()
  @State private var draft = ""
  @FocusState private var focused: Bool

  var body: some View {
    TextField("", text: $draft)
      .labelsHidden()
      .multilineTextAlignment(.trailing)
      .frame(width: width)
      .focused($focused)
      .onSubmit(save)
      .onChange(of: focused) { isFocused in
        if !isFocused { save() }
      }
      .onChange(of: draft) { text in
        if text == value {
          edits.remove(id)
        } else {
          edits.set(id) { commit(text) }
        }
      }
      .onChange(of: value) { draft = $0 }
      .onAppear { draft = value }
  }

  private func save() {
    edits.remove(id)
    guard draft != value else { return }
    commit(draft)
    // A change the file took arrives as a new `value` too.
    draft = value
  }
}

/// What's typed in the settings window's fields and not yet saved. A field saves as it loses
/// focus, but SwiftUI reports that only after the window has closed, so closing the window or
/// quitting saves these first.
@MainActor
final class PendingEdits: ObservableObject {
  private var saves: [UUID: () -> Void] = [:]

  func set(_ id: UUID, save: @escaping () -> Void) {
    saves[id] = save
  }

  func remove(_ id: UUID) {
    saves[id] = nil
  }

  func save() {
    let pending = saves
    saves = [:]
    for save in pending.values { save() }
  }
}
