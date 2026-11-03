import AppKit
import Core
import Settings
import SwiftUI

// SwiftUI has a `Settings` scene too; this file means the config type.
import struct Settings.Settings

/// One pane of the settings window, chosen from its toolbar: a control for each of its keys of
/// config.json, in sections. Each row has its label right-aligned on the left, and its control
/// with a short line under it on the right, as in the Mac's own settings windows
/// (docs/decisions/0012-settings-panes.md). macOS 12 has no `Grid`, so the label column has a
/// fixed width.
struct SettingsView: View {
  /// What the window's buttons do in the rest of the app.
  struct Actions {
    let openFile: () -> Void
    let revealFile: () -> Void
    let rescan: () -> Void
  }

  enum Pane: String, CaseIterable {
    case general, slideshow, schedule, camera, keys, advanced

    var title: String {
      switch self {
      case .general: return "General"
      case .slideshow: return "Slideshow"
      case .schedule: return "Schedule"
      case .camera: return "Camera"
      case .keys: return "Keys"
      case .advanced: return "Advanced"
      }
    }

    /// An SF Symbol from macOS 12's set.
    var symbol: String {
      switch self {
      case .general: return "gearshape"
      case .slideshow: return "play.rectangle"
      case .schedule: return "clock"
      case .camera: return "camera"
      case .keys: return "keyboard"
      case .advanced: return "gearshape.2"
      }
    }
  }

  @ObservedObject var model: SettingsModel
  let actions: Actions
  /// What's typed in the fields and not yet saved, shared by every pane.
  let edits: PendingEdits
  let pane: Pane

  private static let width: CGFloat = 560
  static let padding: CGFloat = 20
  static let labelWidth: CGFloat = 170
  static let columnSpacing: CGFloat = 12
  /// The right column, where controls and their lines go.
  static let controlWidth = width - 2 * padding - labelWidth - columnSpacing
  /// Wide enough for "Range of months" and the longest slide length.
  private static let pickerWidth: CGFloat = 190
  private static let numberWidth: CGFloat = 70

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      if model.isFileBroken || model.changeError != nil {
        problems
      }
      content
    }
    .padding(Self.padding)
    .frame(width: Self.width, alignment: .topLeading)
    // The window takes the pane's height, and changes with it.
    .fixedSize()
    .environmentObject(edits)
  }

  @ViewBuilder private var content: some View {
    switch pane {
    case .general:
      Group {
        library
        photos
      }
      .disabled(model.isFileBroken)
    case .slideshow:
      Group {
        timing
        look
      }
      .disabled(model.isFileBroken)
    case .schedule:
      Group {
        start
        offHours
        battery
      }
      .disabled(model.isFileBroken)
    case .camera:
      Group {
        camera
        checks
      }
      .disabled(model.isFileBroken)
    case .keys:
      keys
        .disabled(model.isFileBroken)
    case .advanced:
      memory
        .disabled(model.isFileBroken)
      file
    }
  }

  // MARK: Problems

  private var problems: some View {
    VStack(alignment: .leading, spacing: 8) {
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
          .fixedSize(horizontal: false, vertical: true)
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
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.1)))
  }

  // MARK: General

  private var library: some View {
    SettingsSection("Library") {
      SettingRow("Photos folder", detail: "Only read, never changed.") {
        HStack(spacing: 8) {
          Text((model.settings.libraryURL.path as NSString).abbreviatingWithTildeInPath)
            .font(.system(.callout, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
          Button("Choose…", action: chooseLibrary)
        }
      }
      SettingRow("Scan", detail: "Finds new, changed and removed photos.") {
        Button("Rescan Now", action: actions.rescan)
      }
    }
  }

  private var photos: some View {
    SettingsSection("Photos") {
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
        SettingRow("Months", detail: "The first and last month, like 2014-01; both included.") {
          HStack(spacing: 6) {
            CommitField(value: from.prefix, width: Self.numberWidth + 20) {
              model.setRange(first: true, from: $0)
            }
            Text("to")
            CommitField(value: to.prefix, width: Self.numberWidth + 20) {
              model.setRange(first: false, from: $0)
            }
          }
        }
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
    }
  }

  // MARK: Slideshow

  private var timing: some View {
    SettingsSection("Timing") {
      SettingRow("Show each photo for", detail: "Keys 1–5 choose these too.") {
        Picker("Show each photo for", selection: binding(\.slideSeconds)) {
          ForEach(model.slideChoices, id: \.self) { seconds in
            Text(SettingsModel.describe(slideSeconds: seconds)).tag(seconds)
          }
        }
        .labelsHidden()
        .frame(width: Self.pickerWidth)
      }
      SettingRow("Crossfade", detail: "Shorter than each photo shows.") {
        numberField(\.transitionSeconds, unit: "s")
      }
    }
  }

  private var look: some View {
    SettingsSection("Look") {
      SettingRow("Scaling", detail: "Fill crops the edges; Fit shows the whole photo.") {
        Picker("Scaling", selection: binding(\.scaling)) {
          Text("Fill the screen").tag(Settings.Scaling.fill)
          Text("Fit the photo").tag(Settings.Scaling.fit)
        }
        .labelsHidden()
        .frame(width: Self.pickerWidth)
      }
      SettingRow("Ken Burns") {
        Toggle("Slowly pan and zoom each photo", isOn: binding(\.kenBurns))
      }
    }
  }

  // MARK: Schedule

  private var start: some View {
    SettingsSection("Start") {
      SettingRow("Start after", detail: "Without keyboard or mouse input.") {
        numberField(\.idleMinutes, unit: "min")
      }
    }
  }

  private var offHours: some View {
    SettingsSection("Off hours") {
      SettingRow("Off hours") {
        Toggle("Don't start, and keep the camera off", isOn: binding(\.offHours.enabled))
      }
      SettingRow("Between", detail: "24-hour times. A start after the end spans midnight.") {
        HStack(spacing: 6) {
          timeField(\.offHours.start)
          Text("and")
          timeField(\.offHours.end)
        }
      }
      .disabled(!model.settings.offHours.enabled)
    }
  }

  private var battery: some View {
    SettingsSection("Battery") {
      SettingRow("On battery", detail: "Without a power adapter.") {
        Picker("On battery", selection: binding(\.battery.mode)) {
          Text("Runs as on power").tag(Settings.Battery.Mode.always)
          Text("Stops after a time").tag(Settings.Battery.Mode.limited)
          Text("Doesn't run").tag(Settings.Battery.Mode.never)
        }
        .labelsHidden()
        .frame(width: Self.pickerWidth)
      }
      SettingRow("Stop after", detail: "Then the display sleeps, and the Mac can too.") {
        numberField(\.battery.limitMinutes, unit: "min")
      }
      .disabled(model.settings.battery.mode != .limited)
    }
  }

  // MARK: Camera

  private var camera: some View {
    SettingsSection("Motion") {
      SettingRow("Camera") {
        Toggle("Sleep the display when no one is around", isOn: binding(\.motion.enabled))
      }
      SettingRow("Light sensor") {
        Toggle(
          "Check at once when the room's light changes", isOn: binding(\.motion.useLightSensor))
      }
      .disabled(!model.settings.motion.enabled)
      SettingRow("Threshold", detail: "Fraction (0–1) of a grid cell that must change.") {
        numberField(\.motion.threshold, unit: "")
      }
      .disabled(!model.settings.motion.enabled)
    }
  }

  private var checks: some View {
    SettingsSection("Checks") {
      SettingRow("Check every", detail: "The longest gap between checks.") {
        numberField(\.motion.checkEveryMinutes, unit: "min")
      }
      SettingRow("Quick check after", detail: "Confirms an empty room; the first gap once off.") {
        numberField(\.motion.quickCheckEverySeconds, unit: "s")
      }
      SettingRow("Watch for", detail: "Each check stops at the first motion.") {
        numberField(\.motion.sampleSeconds, unit: "s")
      }
    }
    .disabled(!model.settings.motion.enabled)
  }

  // MARK: Keys

  /// The keys pane's sections, each with its commands.
  private enum KeyGroup: CaseIterable {
    case photos, speed, app

    var title: String {
      switch self {
      case .photos: return "Photos"
      case .speed: return "Speed"
      case .app: return "App"
      }
    }

    var commands: [Command] {
      Command.allCases.filter { Self(command: $0) == self }
    }

    init(command: Command) {
      switch command {
      case .next, .previous, .pause, .info, .hideInfo: self = .photos
      case .speed1, .speed2, .speed3, .speed4, .speed5: self = .speed
      case .timeframe, .rescan, .settings, .palette: self = .app
      }
    }
  }

  private var keys: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("While the slideshow shows. Click a key, then press the new one; Esc cancels.")
        .font(.callout)
        .foregroundColor(.secondary)
      ForEach(KeyGroup.allCases, id: \.self) { group in
        SettingsSection(group.title) {
          ForEach(group.commands, id: \.self) { command in
            SettingRow(command.title, colon: false, detail: keyDetail(command)) {
              Button {
                model.toggleRecording(command)
              } label: {
                Text(
                  model.recording == command
                    ? "Press a key…" : model.settings.keys[command].symbols
                )
                .frame(minWidth: 110)
                .foregroundColor(model.recording == command ? .secondary : .primary)
              }
              .help(
                model.recording == command ? "Press a key, or Esc to cancel" : "Click to record")
            }
          }
        }
      }
      SettingRow("") {
        Button("Restore Default Keys") { model.restoreDefaultKeys() }
      }
    }
  }

  /// Why the key being recorded for `command` was refused, in orange under its button.
  private func keyDetail(_ command: Command) -> SettingRowDetail? {
    guard model.recording == command, let refusal = model.refusal else { return nil }
    return SettingRowDetail(text: refusal, color: .orange)
  }

  // MARK: Advanced

  private var memory: some View {
    SettingsSection("Memory") {
      SettingRow("Photos decoded ahead", detail: "Each can take 60–160 MB of memory.") {
        CommitField(value: "\(model.settings.preloadCount)", width: Self.numberWidth) {
          model.setCount(\.preloadCount, from: $0)
        }
      }
    }
  }

  private var file: some View {
    SettingsSection("Settings file") {
      SettingRow("config.json", detail: "Changes here save to the file; edits there show here.") {
        VStack(alignment: .leading, spacing: 8) {
          Text((model.fileURL.path as NSString).abbreviatingWithTildeInPath)
            .font(.system(.callout, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
          HStack {
            Button("Open config.json", action: actions.openFile)
            Button("Reveal in Finder", action: actions.revealFile)
          }
        }
      }
    }
  }

  // MARK: Parts

  /// A control's binding to the setting at `path`: it shows the file's value and saves a change.
  private func binding<Value>(_ path: WritableKeyPath<Settings, Value>) -> Binding<Value> {
    Binding(get: { model.settings[keyPath: path] }, set: { model.set(path, to: $0) })
  }

  private func numberField(_ path: WritableKeyPath<Settings, Double>, unit: String) -> some View {
    HStack(spacing: 4) {
      CommitField(
        value: SettingsModel.text(model.settings[keyPath: path]), width: Self.numberWidth
      ) { model.setNumber(path, from: $0) }
      if !unit.isEmpty {
        Text(unit)
          .foregroundColor(.secondary)
      }
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

/// A section: its title as a bold heading over the control column, and its rows beneath.
private struct SettingsSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.headline)
        .padding(.leading, SettingsView.labelWidth + SettingsView.columnSpacing)
      content
    }
  }
}

/// The line under a row's control.
private struct SettingRowDetail {
  let text: String
  var color = Color.secondary
}

/// A setting's label, right-aligned in the left column, and on the right its control with a
/// line under it saying what it does. A checkbox's own title says that, so it has no line.
private struct SettingRow<Control: View>: View {
  let title: String
  let detail: SettingRowDetail?
  @ViewBuilder let control: Control

  init(
    _ title: String, colon: Bool = true, detail: String? = nil,
    @ViewBuilder control: () -> Control
  ) {
    self.init(title, colon: colon, detail: detail.map { SettingRowDetail(text: $0) }) {
      control()
    }
  }

  init(
    _ title: String, colon: Bool = true, detail: SettingRowDetail?,
    @ViewBuilder control: () -> Control
  ) {
    self.title = colon && !title.isEmpty ? title + ":" : title
    self.detail = detail
    self.control = control()
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: SettingsView.columnSpacing) {
      Text(title)
        .multilineTextAlignment(.trailing)
        .frame(width: SettingsView.labelWidth, alignment: .trailing)
      VStack(alignment: .leading, spacing: 4) {
        control
        if let detail {
          Text(detail.text)
            .font(.system(size: NSFont.smallSystemFontSize))
            .foregroundColor(detail.color)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(width: SettingsView.controlWidth, alignment: .leading)
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
