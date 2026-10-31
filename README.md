# photo-screensaver

A lightweight macOS menu-bar app that shows a shuffled, full-screen slideshow of a NAS photo
library, with optional motion-activated display wake.

## Requirements

- macOS 12 or later
- Xcode 14.2, selected with `sudo xcode-select -s /Applications/Xcode.app`, with its first-launch
  setup done (`sudo xcodebuild -runFirstLaunch`)
- The photo library mounted as a folder, such as an SMB share under `/Volumes`

## Use it

| Task | Command |
|---|---|
| Set up for development | `./scripts/setup` |
| Build and launch | `./scripts/dev` |
| Install, start at login | `./scripts/install` (`--uninstall` removes it) |
| Test | `./scripts/test` |
| Everything before a commit | `./scripts/check` |

Agents and contributors: start with [AGENTS.md](AGENTS.md).

The app lives in the menu bar. The slideshow starts after `idleMinutes` without input, or from
**Show Slideshow** in the menu, and any key press or mouse movement ends it. Problems (an
unmounted share, a bad setting, camera access denied) appear in the menu with a ⚠︎ icon.

## Settings

**Edit Settings…** in the menu opens
`~/Library/Application Support/photo-screensaver/config.json`. The app creates it on first launch
and reloads it on save. Every key is required.

| Key | Meaning |
|---|---|
| `libraryPath` | Folder to show photos from, searched recursively. Never written to. |
| `idleMinutes` | Minutes without input before the slideshow starts. |
| `slideSeconds` | How long each photo shows. |
| `transitionSeconds` | Crossfade length; less than `slideSeconds`. |
| `scaling` | `fill` covers the screen and crops; `fit` shows the whole photo. |
| `orientation` | `any`, `landscape`, or `portrait`. |
| `kenBurns` | Slow pan and zoom on each photo. |
| `preloadCount` | Photos decoded ahead. Each can take 60–160 MB. |
| `motion.enabled` | Use the camera to sleep the display when no one is around. |
| `motion.checkEveryMinutes` | Time between camera checks while the slideshow is up, and the longest gap while the display is off. |
| `motion.quickCheckEverySeconds` | Time before a second check confirms an empty room, and the first gap once the display is off. Gaps then double up to `checkEveryMinutes`. Shorter wakes the display sooner but runs the camera more. |
| `motion.sampleSeconds` | Longest each check watches, after a 1-second warm-up. It stops as soon as it sees motion. |
| `motion.threshold` | Fraction (0–1) of any one cell of an 8×6 grid over the camera image that must change to count as motion. Lower catches smaller or more distant movement. |
| `offHours.enabled` | Turn the slideshow off for part of each day. |
| `offHours.start`, `offHours.end` | 24-hour local times like `"00:00"` and `"09:00"`. A start later than the end spans midnight. In between, the slideshow doesn't start and the camera stays off. A slideshow that's showing when they begin stops, and the display sleeps. Choosing **Show Slideshow** still works. |

The library index is cached in `~/Library/Caches/photo-screensaver/` and rescanned at launch,
daily, and from **Rescan Library**.

## macOS setup

- **Screen saver and display sleep:** set the macOS screen saver to *Never*, and make display
  sleep longer than `idleMinutes`, or macOS gets there first. The slideshow keeps the display on
  while it shows.
- **Motion mode and the lock screen:** when no motion is seen, the display sleeps. If macOS
  requires a password after the display sleeps, motion wakes it to the login window instead of
  the slideshow. Turn that off in System Preferences › Security & Privacy for a picture-frame
  setup.
- **Permissions:** on first use macOS asks to let the app read the network volume and, with
  motion on, use the camera.
- **Stable permissions across rebuilds:** macOS ties permissions to the app's signature, and
  `./scripts/dev` signs ad hoc unless a certificate named `PhotoScreensaver Local` exists. Make one
  once in Keychain Access › Certificate Assistant › Create a Certificate: name
  `PhotoScreensaver Local`, identity type *Self Signed Root*, certificate type *Code Signing*.
