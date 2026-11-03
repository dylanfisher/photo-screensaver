# 0012. Settings in toolbar panes, with labels in a right-aligned column

- **Date:** 2026-11-03
- **Status:** accepted
- **Amends:** [0009](0009-settings-window.md) (the window's layout)

## Context

The settings window stacked seven sections in one scroll view, each row with its title and a
description on the left and its control on the right. The owner asked for clearer groups and
pointed to music-player's Settings window (its ADRs 0017 and 0042): a toolbar of panes, and in
each, labels right-aligned in one column with the control and one short line beside them.

## Decision

- **Six panes in a `.preference` toolbar.** General (library folder, rescan, which photos show),
  Slideshow (timing, scaling, Ken Burns), Schedule (idle start, off hours, battery), Camera
  (motion checks), Keys, and Advanced (photos decoded ahead, the config file). The window
  isn't resizable; it takes each pane's height and keeps its top edge when the pane changes.
  It opens at the pane shown last. The problems banner shows at the top of every pane.
- **Rows as in the Mac's own settings.** The label is right-aligned in a fixed column, since
  macOS 12 has no `Grid`; the control is on the right with one short line under it. A Boolean
  is a checkbox whose title says what it does, so it has no line. Off hours' two times share a
  row.
- **Keys in three groups**, Photos, Speed and App, by an exhaustive switch over `Command`, so a
  new command can't be left out of the pane.
- **Switching panes saves what's typed** and stops a key being recorded, since the fields go
  away without SwiftUI reporting that they lost focus.

## Alternatives considered

- **One scroll view with clearer headings** — rejected: the owner asked for music-player's
  layout, and the Keys section alone fills most of a screen.
- **A SwiftUI `TabView`** — rejected: on macOS 12 it draws segmented tabs inside the window,
  not the toolbar panes music-player and the Mac's own settings use.

## Consequences

The layout is checked by hand on the 2015 MacBook Pro, as before; tests don't cover the window.
