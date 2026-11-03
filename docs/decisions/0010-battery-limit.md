# 0010. A time limit on battery, counted while the slideshow is up

- **Date:** 2026-11-03
- **Status:** accepted

## Context

The slideshow holds power assertions that keep the display on, and with motion mode the Mac
awake, so a laptop left idle on battery runs down. Closing the lid still sleeps the Mac; the
drain is with the lid open. The owner asked for the slideshow to stop after a set time on
battery, or not to run on battery at all.

## Decision

`battery.mode` is `always`, `limited` or `never`, with `battery.limitMinutes` for `limited`.
`BatteryWatch` counts uptime while the slideshow is up on battery, display off included, since
motion checks keep the Mac awake then too. At the limit, Presence gets `batteryLimitReached`,
which ends the slideshow and sleeps the display as off hours do. Releasing the assertions lets
macOS's own idle sleep take over. `never` uses a limit of zero, so unplugging stops a running
slideshow on the next tick, and it also turns off **Show Slideshow**.

After a stop at the limit, the input idle time is still past `idleMinutes`, so the slideshow
doesn't start on its own again until input arrives after the stop, or the Mac is on power.

## Alternatives considered

- **A limit measured on the input idle time** (stop once idle passes `idleMinutes` plus the
  limit) — rejected: needs no state, but a hand start or an unplug partway through a long
  slideshow would get the wrong amount of time.
- **`limitMinutes: 0` meaning never** — rejected: a sentinel value hides a mode in a number.
- **Letting Show Slideshow run in `never` mode, as it does in off hours** — rejected: the point
  of `never` is to stop the battery draining, and a slideshow started by hand and forgotten
  drains it the same way.

## Consequences

Time on power doesn't count, and unplugging starts the count again. Uptime stops while the Mac
sleeps, so sleep doesn't count either. The power source is read each tick through IOKit, which
is cheap.
