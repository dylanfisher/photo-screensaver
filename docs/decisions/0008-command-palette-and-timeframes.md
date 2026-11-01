# 0008. A ⌘K command list over the slideshow, and a timeframe saved in config.json

- **Date:** 2026-11-01
- **Status:** accepted

## Context

The slideshow's keys (ADR 0006) need a list to find them by, and a few commands that don't
deserve a memorable key: pause, rescan, open settings. The owner also wants to show photos from
part of the library, by when they were taken: one year, a range of months, the last year, or
"on this day" in past years. The library database has the capture date as `YYYY-MM-DD HH:MM:SS`
text with an index (ADR 0005), over 100,000 rows, read on a 2015 MacBook Pro. The choice is
kept across launches.

The slideshow window is borderless and its photos are a layer-hosting view. Before this, no key
with ⌘ had been tried in it.

## Decision

**A panel with a text field, beside the photos.** ⌘K (`palette`) opens a panel centered over
the photos, listing every command but itself with its key, as macOS menus write it (⇧⌘K, →,
Space). Typing filters by title, ignoring case and accents: titles with a word starting with
each typed word first, then those containing them. ↑/↓ choose, Return runs, Escape or a click
outside closes. It's an `NSVisualEffectView` with an `NSTextField`, for typing, deleting and
input methods that a drawn layer would have to rebuild. A layer-hosting view can't have
subviews, so the window's content is now a plain view holding the photos' view and the panel
side by side; the photos are drawn as before.

**While it's open, the palette has the keyboard and the mouse can't end the slideshow.** The
slide timer stops after showing the photo it's on, and closing gives that photo a whole slide.
The idle check leaves out the pointer, and closing resets the time input is counted from, so
moving the pointer to click a row doesn't end the slideshow a second later. Keys still count
whenever the window doesn't get them, as after ⌘Tab to another app. The pointer shows while it's
open. With no input of any kind for 60 seconds the palette closes, so one left open doesn't hold
a photo, and a lit display, for good.

**Keys with ⌘ or ⌃ go through `performKeyEquivalent`.** AppKit offers those keys to the window
as key equivalents before anything else, and what reaches `keyDown` afterwards depends on the
menus and the first responder. The window takes every one there and hands it to the same
handler as other keys: a bound one runs its command, an unbound one ends the slideshow after
the grace period, like any other key. With the palette open the handler gives them to it
instead: its own key closes it, ⌘A, ⌘C, ⌘V and ⌘X edit the filter, since the app has no Edit
menu to send them, and any other does nothing. Arrows, Return and Escape reach the panel as the
text field's editor commands, or as key presses when the custom range has the keyboard.

**Every command keeps a required key.** `pause` is Space, `timeframe` T, `rescan` ⌘R, `settings`
⌘, and `palette` ⌘K. Allowing `null` for commands only in the list was considered and not done:
every command is cheap to bind, a key with ⌘ is hard to press by accident, and one shape for
`keys` keeps the settings window's key recorder simple. Rescan is on ⌘R so that someone pressing
R to leave doesn't start a scan.

**Pause is not saved.** It stops the slide timer until pressed again; stepping still works, and
each slideshow starts playing. The Ken Burns pan runs on to its end.

**Open Settings leaves the slideshow first.** It sends the same event as user activity, then
opens the settings through the menu's action, so the settings window replaces it in one place.

**`timeframe` is an object with a kind and only that kind's fields.**

```json
{"kind": "all"}
{"kind": "onThisDay"}
{"kind": "lastMonths", "months": 12}
{"kind": "range", "from": "2014-01", "to": "2014-12"}
```

A field another kind has, or a misspelled one, fails when the file is read rather than being
ignored. Months are 1 to 1200, months are `YYYY-MM`, and `from` can't be after `to`. A year is a
range from January to December; there's no separate kind for it.

**Relative kinds follow the calendar.** The feed works the filter out from today's date, in the
Mac's time zone, each time it has shown every photo; nothing is frozen when it's chosen. "On this
day" is the seven days from three before today to three after, counted in this year's
calendar, as month and day in any year: Mar 1 2026 is Feb 26 to Mar 4. The days are compared as
`MM-DD` text, so a window that crosses from Feb 28 to Mar 1 also takes in Feb 29 photos from leap
years, every year, and one that stops at Feb 28 doesn't. A window near New Year wraps (Dec 30 is
Dec 27 to Jan 2). "Last N months" runs from today's date N months ago through the end of today.

**Ranges use the index; "on this day" reads it all.** A range compares whole `taken_at` text, so
`2014-01 ≤ taken_at < 2015-01` is an index search. "On this day" compares `substr(taken_at, 6,
5)`, the `MM-DD`, which no index serves, but SQLite reads the covering `photos_taken_at` index
rather than the table. On 150,000 synthetic rows (system SQLite, M1 Max, warm cache):

| Query | Time |
|---|---|
| Count, all photos | 9 ms |
| Count, on this day | 11 ms; 17 ms wrapping New Year |
| Count, a year or the last 12 months | under 0.2 ms |
| Count per year | 23 ms |
| IDs, on this day | 11 ms |

The 2015 Mac is likely three to five times slower, which is still well under a slide.

**The picker counts off the main thread, once.** Choosing a timeframe (T, or from the list)
shows all time, on this day, the last 12 months, "Custom range…", then each year with photos,
newest first, each with its count. The counts are one batch on the app's database queue; the
list shows at once and fills in, and the years join below the fixed rows so a selection doesn't
move. The custom range steps its months with ←/→, a year with Shift, and counts again after each
step. While the scan is still reading capture dates the panel says so, since counts can grow. A
choice with no photos says so and isn't applied.

**A choice saves like the speed keys.** It reads config.json, sets `timeframe`, and writes it
back whole, then applies it like any edit (ADR 0006). A timeframe change rebuilds the feed from
the database, without a rescan, and the slideshow moves on to a photo from it at once. Photos
without a capture date show only under `all` (ADR 0005).

## Alternatives considered

- **Drawing the panel in Core Animation, like the info panel** — rejected: typing, deleting and
  input methods come with a text field and would have to be rebuilt.
- **An `NSTableView` for the rows** — rejected: a fixed set of row views covering at most nine
  rows is less code for lists of a few dozen.
- **A local event monitor for ⌘ keys** — rejected for the reasons in ADR 0006.
- **A month-day column, or an index on `substr(taken_at, 6, 5)`** — rejected: a second copy of
  the date (ADR 0005), for a query that takes tens of milliseconds without it.
- **Freezing "on this day" and "last 12 months" into dates when chosen** — rejected: a
  slideshow left running would show last week's day.
- **Counting each picker row as its own query, shown as it arrives** — rejected: the batch is
  about 45 ms here, and one callback keeps the list from reshuffling.
- **Leaving out "on this day" photos from Feb 29 except in leap years** — rejected: they'd
  never show three years in four.
- **Counting the days in a fixed leap year** — tried first: it made Feb 29 a day of every year,
  so in other years the window around Mar 1 began a day late and the one around Feb 28 ended a
  day early.

## Consequences

- A config.json from before this needs `timeframe` and keys for `pause`, `timeframe`, `rescan`,
  `settings` and `palette`; the menu names the first one missing.
- If AppKit offers keys with ⌃ as key equivalents too, the window takes them before the
  palette's text field, and its Emacs-style editing keys don't work there.
- "Last 12 months" and "on this day" can show nothing on some days, as when a library has no
  recent photos; the menu then shows the feed's error until the timeframe changes.
- The query timings are from this Mac. If the old Mac shows the picker late, the year counts
  can move into the scan's summary.
