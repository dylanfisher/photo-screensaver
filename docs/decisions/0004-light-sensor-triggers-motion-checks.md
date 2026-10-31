# 0004. The ambient light sensor triggers motion checks early

- **Date:** 2026-10-30
- **Status:** accepted

## Context

Motion checks back off while the display is off ([0003](0003-motion-checks-per-cell-with-backoff.md)),
so someone coming back after a long absence can wait up to `checkEveryMinutes` for the display to
wake. Checking more often means running the camera more, with its light showing each time.

The MacBook Pro (2015) has an ambient light sensor beside the camera. Reading it takes one IOKit
call and doesn't touch the camera, so it can run every second.

## Decision

While the slideshow shows or the display is off, read the sensor every second. A sudden change
moves the next motion check to now: brighter while the display is off, darker while the
slideshow shows. The camera check still decides what happens to the display.

## Alternatives considered

- **Switching the display on light alone** — rejected: daylight, timed lamps and headlights
  change the light with no one there, and people sit in the dark.
- **Brightness from the camera image** — rejected: auto-exposure evens it out, macOS doesn't
  expose the exposure settings to correct for that, and it needs the camera on.
- **A documented API** — none on macOS 12 exposes the sensor. AppleLMUController is
  undocumented and specific to Intel Macs, so a Mac without it reports an error in the menu
  and runs on timed checks alone.

## Consequences

- The display's own light reaches the sensor, so readings are ignored for a few seconds after
  each display or slideshow change.
- Brightness changes between photos, in a room lit mostly by the screen, can register as
  darker and start an extra check. That costs a camera check, not a wrong display state.
- The change factor and dark-room floor in `LightWatch` are first guesses. Tune them from the
  `light …: checking for motion now` log lines.
