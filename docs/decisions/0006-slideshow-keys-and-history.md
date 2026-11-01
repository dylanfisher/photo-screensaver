# 0006. Keys run commands in the slideshow window, and history keeps only photo IDs

- **Date:** 2026-11-01
- **Status:** accepted

## Context

The slideshow ended on any input: the idle check reads the HID system's time since the last
key press or mouse event. Stepping through photos and changing speed from the keyboard means
some keys must keep the slideshow up while every other key still ends it. More commands are
coming (photo info, a ⌘K command list, a settings window that records keys), and each needs a
name in the config file, a title to list it by, and a default key.

The Mac is a 2015 MacBook Pro. A decoded photo takes 60–160 MB, and the feed already decodes
one at a time so a slow NAS read never has two in memory.

## Decision

**One `Command` enum in Settings.** Its raw value is the command's name under `keys` in
config.json; it also has the title, the default key, and, for the speed commands, the fixed
`slideSeconds` each sets. Settings is the only tier Core and App both import, and the key
setting is validated there, like every other setting. A new command is one case and one line in
each of its switches, which the compiler asks for.

**Keys are text, parsed and checked with the rest of the file.** `KeySpec` reads `"right"`,
`"1"` or `"shift+cmd+k"`, in any modifier order and case, and writes back one form. Every
command needs a key, so a misspelled name fails as missing, and two commands on one key fail
with both names. **A key is matched by its position, not what it types.** Each key code maps to
the key's name or the character it types on a US ANSI keyboard without Shift, and keypad digits
to the same digits, so `"1"` is the key left of 2 on a French layout too, where it types `&`,
and on a Cyrillic one, where letters type nothing the file could name otherwise. `shift+1` is
the 1 key with Shift, not `!`, and a character no US key types unshifted, such as `!` or `é`,
fails when the file is read. That table is pure data, so it lives in Settings with `KeySpec`,
where it's tested; App only reads the key code and the modifiers from the `NSEvent`.

**The window judges keys, the idle check judges the mouse.** While the photos show and the
slideshow window is the key window of the active app, the idle check counts only mouse and
trackpad events, and the window gets each key press. `Presence.respond(toKey:…)` decides: a
bound key runs its command, an unbound key ends the slideshow after the existing grace period.
While the display is off, any key ends it, through both paths. If the window isn't key, as when
another app took focus, the idle check counts keys again, so keys never stop ending the
slideshow. Repeats from a held key step through photos but don't save the speed again.

**History is photo IDs, and going back decodes again.** `SlideHistory` keeps the last 200 IDs
and a target: a photo in the history, or a new one from the feed. Back and forward move the
target; forward past the end is always one new photo, so pressing ahead of a slow load doesn't
skip any. `PhotoFeed.photo(_:)` decodes a revisited photo without keeping it, waiting for a
preload under way and holding off the next one, so there is still one decode at a time.

**Every step restarts the slide loop.** Each command moves the target and restarts the loop,
which shows the target and then waits a full slide. A load still running for an earlier step is
cancelled, so holding ← decodes the photo it stops on, plus at most the one already being
decoded. A target that is already on screen isn't decoded again.

**Speed keys save through the file.** A speed key reads config.json, sets `slideSeconds`, and
writes it back whole, only if it's still valid; then the app reloads it like any edit. The
reload acts only on what changed, and a `slideSeconds` change only restarts the slide timer and
stretches the current pan, so the feed and its preloaded photos stay. A file with errors is left
alone and the error shows on screen.

## Alternatives considered

- **Matching by the character the layout types** — rejected: on AZERTY the digit row types
  `&é"'(` unshifted, so the speed keys never matched, and a non-Latin layout types no letter the
  config could name.

- **A local key monitor (`NSEvent.addLocalMonitorForEvents`)** — rejected: it needs the app
  active just like the window does, and adds a second path for the same events.
- **Keeping decoded photos for history** — rejected: a few steps back would hold hundreds of MB
  of memory, on a Mac that has 8 or 16 GB.
- **Waiting a moment before decoding, to coalesce held keys** — rejected: it delays every single
  press, and cancelling the earlier load already limits a burst to two decodes.
- **Writing `settings` from memory** — rejected: it would overwrite a hand edit made since the
  last poll, or replace a file that has an error with the last good one.
- **Configurable speed presets** — rejected by the owner: the keys can move, the five lengths
  are fixed.

## Consequences

- A speed key rewrites config.json in the app's own format: pretty-printed, keys sorted.
- A key bound with ⌘ depends on AppKit passing an unhandled key equivalent on as a key press,
  which the ⌘K command list will exercise first.
- Going back to a photo a rescan removed shows an error in the menu and leaves the current photo
  up; the next step moves past it.
- History starts again when the library folder changes, since its IDs belong to the old
  database rows.
