# 0009. A settings window that changes config.json through one careful writer

- **Date:** 2026-11-01
- **Status:** accepted

## Context

**Edit Settings…** opened config.json in TextEdit. The owner wants a window with a control for
every key instead, on the 2015 MacBook Pro's macOS 12, with the file still the source of truth
and still editable by hand. The approach follows simple-spotlight's `macos-12` branch (its ADRs
0015 and 0016). Three things already wrote the file — the speed keys, the timeframe picker and
the starter file — each by reading it, changing one key and writing it back whole, which could
overwrite an edit saved in between. Phases since the last release added required keys
(`timeframe`, and `keys` for five commands), so an older config.json now fails with a missing
key.

## Decision

**A SwiftUI form in an AppKit window, macOS 12 APIs only.** `SettingsView` is hosted in an
`NSHostingController` in a titled, closable, resizable `NSWindow`, not a SwiftUI `Settings`
scene, which needs a main menu to open from. Without `.formStyle(.grouped)` and `LabeledContent`
(macOS 13), the sections stack in a padded scroll view: a heading, then rows with the title and
a one-line description on the left and the control on the right. The model is an
`ObservableObject` with `@Published` properties. There are no `#available` branches.

**Sections follow the file.** Library (folder from an open panel, written `~/…` inside the home
folder; Rescan Now), Slideshow (idle minutes, a picker of the five speed-key lengths plus the
file's own if it's another, crossfade, scaling, orientation, Ken Burns, photos decoded ahead),
Timeframe (kind, then months or from/to months), Off hours, Motion, Keys (one row per command,
by its title), and the file (its path, Open config.json, Reveal in Finder). Number and time
fields save on Return or when they lose focus, not at each keystroke, which would save `0` on
the way to `09:00`; closing the window or quitting saves what's still typed, since SwiftUI
reports the lost focus only after the window has gone. After saving, a field shows the file's
value again, so text the file refused, or wrote another way (`05` for 5), doesn't look saved.
Limits aren't repeated in the window: a value `validate()` refuses isn't
saved, and its message shows at the top.

**One writer, `Settings.update`.** It reads the file's bytes, decodes and validates them, makes
the change, validates the result, and encodes it as the starter file is (pretty-printed, keys
sorted). It writes beside the file, created owner-only and set to the file's permissions before any byte
goes in, so a private file is never readable by others, and renames over it only if the
file still has the bytes it read; otherwise it makes the change again to the new contents, up to
three times, then fails. A change that leaves the settings as they were writes nothing, so a
file formatted by hand isn't reformatted. A symbolic link at the path stays. The window, the
speed keys and the timeframe picker all go through it, and `Settings.save` is gone. Creating the
starter file at launch stays a plain write, since there's no file to compare against.

**Unknown keys are an error.** The JSON has no comments, so re-encoding the whole file loses
nothing except keys decoding doesn't read, which `Decodable` ignores. Decoding now compares the
file's keys with the decoded settings' own encoding and names any extra key, as the timeframe
object already did for its fields. A file that can be written has nothing to drop.

**The window shows the file.** The app already reads config.json each second and compares its
bytes, since HFS+ keeps modification dates to the second and a second save within it would go
unseen; when they change, the open window reads the file again. Writes are synchronous on the
main thread, since the file is small and local, and the model reads the file back before
`change` returns, so a toggle shows the written value at once and never flicks back. After a
write the app reloads the file through the same path as any edit, so there is one way a setting
applies.

**A broken file is never written.** The window lists the error, turns its controls off, and
keeps Open config.json. For a file that is JSON but leaves keys out, it lists each missing key
with the starter's value, like `keys.pause: "space"`, to paste in. There is no button that adds
them: filling the gaps from defaults is the migration that AGENTS.md's pre-release rule
excludes, and it would keep alive whatever else an old file got wrong under keys the user never
looked at.

**The key recorder.** Clicking a command's key listens; the next key press is the new key.
`KeySpec(event)` maps it by position, as the slideshow does. Esc without modifiers cancels. A key
with no name, or one another command has, is refused with the reason and the recorder keeps
listening; the conflict comes from writing it, so it is the file's own duplicate-key check and
message. The window takes key presses in `sendEvent` and `performKeyEquivalent` while
recording, before any text field or button, rather than through a local event monitor (ADR
0006). The repeats and release of the key it took are dropped, or Space or Return would reach
the button just recorded and start recording again. Restore Default Keys writes every command's `defaultKey`.

**Activation.** Showing the window calls `activate(ignoringOtherApps:)` and remembers the app
that was frontmost. Closing it activates that app again, unless the user has since switched to
another, or hides this app when there was none, as when the window was opened from the
slideshow's command list. Closing releases the window and its form; the model stays. The app has
no main menu, so the window takes ⌘W, ⌘Q, and ⌘A/⌘C/⌘V/⌘X for its text fields itself (the
palette shares the last four). These follow the layout, as menu shortcuts do, so ⌘C on Dvorak
is the key that types C; a layout without Latin letters falls back to the US key position. While
the window is on screen, idle time doesn't start the slideshow, which would cover it; Show
Slideshow from the menu still does, over the window.

**Where it lives.** The writer is config logic, in Settings with the only other reads of the
file. The model, with the field mapping and the recorder's rules, is in Core, where it's tested
against a temporary file. The view and the window are in App.

## Alternatives considered

- **Editing the file's text one key at a time, as simple-spotlight does** — rejected: its file
  has comments to keep, this one has none, and the app already writes it whole.
- **A button that fills in missing keys with defaults**, decoding the file leniently against
  `Settings.starter` — rejected as a compatibility shim; see above.
- **Ignoring unknown keys and keeping them on write**, by merging the encoding into the file's
  JSON — rejected: a misspelled key that is ignored is the silent failure every other key in
  the file already avoids.
- **Writing off the main thread and showing pending changes over the file's state** — rejected:
  the file is small and local, and an overlay of pending changes is most of
  simple-spotlight's model.
- **Steppers with ranges** — rejected: the ranges live in `validate()`, and a stepper would need a
  second copy.
- **A `DatePicker` for off hours** — rejected: the file holds `HH:mm` text, which a text field
  shows as written.

## Consequences

- A config.json with a key the app doesn't read now fails to load, naming it.
- A config.json from before `timeframe` and the newer `keys` fails until those keys are added,
  by hand or by deleting the file so the app writes the starter again.
- A value the file refuses goes back to the file's value in the field; the error, which names
  the refused value, shows until the next change.
- A settings window left open stops the slideshow from starting on its own until it's closed.
- The layout, activation and focus return are checked by hand on the 2015 MacBook Pro; tests
  cover the writer, the model and the recorder's rules, not the window.
