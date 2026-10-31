# 0003. Motion checks: per-cell change, confirmed sleep, backed-off wake checks

- **Date:** 2026-10-30
- **Status:** accepted

## Context

The camera can't stay on: its green light shows whenever it runs, and AGENTS.md limits it
to the check window. So motion is checked in short bursts. Each burst compared frames 0.5 s
apart and measured change as a fraction of the whole image. That missed someone sitting still,
or someone small in the frame across the room, and a single missed check slept the display on
them. While the display was off, checks ran only every `checkEveryMinutes`, so someone walking
back in could wait up to ten minutes for the display to wake.

The two mistakes don't cost the same. Sleeping the display on someone is a visible failure.
Leaving it on a few extra minutes costs a little power.

## Decision

- Change is measured per cell of an 8×6 grid, and the most-changed cell is what counts. Average
  brightness is taken out first, so exposure shifts and lamps don't read as motion.
- Each frame is compared with the previous one and with the first of the check, so slow
  movement adds up.
- A check stops as soon as it sees motion.
- The display sleeps after two empty checks in a row. The second follows the first after
  `quickCheckEverySeconds`, not the full interval.
- While the display is off, checks start `quickCheckEverySeconds` apart and double after each
  empty one, up to `checkEveryMinutes`.

## Alternatives considered

- **A fixed short interval while the display is off** — rejected: in an empty room overnight it
  flashes the camera light every few seconds for hours.
- **Keeping the camera on while the display is off** — rejected for the same reason, and
  AGENTS.md limits the camera to the check window.
- **A noise floor measured during warm-up** — deferred: frames from the warm-up are still
  changing exposure, so they overstate noise. Revisit if dim rooms cause false motion.
- **Settings for grid size and the empty-check count** — rejected: these are tuning constants,
  and `threshold` already gives one sensitivity setting.

## Consequences

- `threshold` now means a fraction of one cell, so values tuned for the whole image are far too
  sensitive.
- After a long absence it can take up to `checkEveryMinutes` to wake. Someone who steps out
  briefly gets a wake within about `quickCheckEverySeconds`.
- Crossfades change the light the screen throws on the room, which can register as motion while
  the slideshow shows. That error keeps the display on, so it is the cheap one.
