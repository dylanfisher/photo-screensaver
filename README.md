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
**Show Slideshow** in the menu. Mouse movement, a click, or any key without a command ends it.
Problems (an unmounted share, a bad setting, camera access denied) appear in the menu with a ⚠︎
icon.

While the slideshow shows, these keys work, and each can be changed under `keys` in the settings:

| Key | Command (`keys` name) | Does |
|---|---|---|
| → | `next` | Shows the next photo. After going back, steps forward through those photos first. |
| ← | `previous` | Goes back through the photos shown before. |
| ↑ | `info` | Shows or hides the photo's details in the bottom-left corner: where and when it was taken, camera, lens, exposure, size, and its folder and file name. It stays open from photo to photo until pressed again. |
| Space | `pause` | Stops the slideshow on the photo it's on, or starts it again. Each slideshow starts playing. |
| T | `timeframe` | Chooses which photos show by when they were taken (below). |
| 1–5 | `speed1` … `speed5` | Shows each photo for 5 s, 15 s, 30 s, 1 min or 5 min, and saves that as `slideSeconds`. |
| ⌘R | `rescan` | Rescans the library, like **Rescan Library** in the menu. |
| ⌘, | `settings` | Ends the slideshow and opens the settings. |
| ⌘K | `palette` | Lists every command with its key, to run one by name. |

Moving to another photo, or changing speed, gives the photo on screen a full `slideSeconds`.
While the display is off, any key wakes it to the desktop.

In the ⌘K list, type to narrow it, ↑/↓ to choose, and Return to run; Escape or a click outside
closes it. While it's open the slideshow waits, keys go to the list, and the pointer can be used
without ending the slideshow.

The timeframe picker lists all time, on this day (three days either side of today's date, in
every year), the last 12 months, each year with photos, and a custom range of months, each with
how many photos it shows. Type to narrow it, such as a year. In the custom range, ←/→ change a
month, Shift+←/→ a year, and Return shows those photos. A choice is saved as `timeframe`, and the
menu shows it. Photos without a capture date show only under all time.

The info panel shows a photo's place as a name like "Shibuya, Tokyo, Japan". For that, the app
sends the photo's GPS coordinates, and nothing else, to Apple's geocoding service, only for the
photo on screen while the panel is open, and keeps the name in the library database so nearby
photos don't ask again. Until a name arrives, or offline, it shows the coordinates. It needs no
location permission.

## Settings

**Edit Settings…** in the menu opens
`~/Library/Application Support/photo-screensaver/config.json`. The app creates it on first launch
and reloads it on save. Every key is required, and a key it doesn't know is an error.

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
| `motion.useLightSensor` | Watch the ambient light sensor beside the camera, and check for motion straight away when the room's light changes suddenly: a light switched on while the display is off, or off while the slideshow shows. The sensor doesn't use the camera. Intel MacBooks only. |
| `motion.threshold` | Fraction (0–1) of any one cell of an 8×6 grid over the camera image that must change to count as motion. Lower catches smaller or more distant movement. |
| `offHours.enabled` | Turn the slideshow off for part of each day. |
| `offHours.start`, `offHours.end` | 24-hour local times like `"00:00"` and `"09:00"`. A start later than the end spans midnight. In between, the slideshow doesn't start and the camera stays off. A slideshow that's showing when they begin stops, and the display sleeps. Choosing **Show Slideshow** still works. |
| `timeframe` | Which photos show, by capture date: `{"kind": "all"}`, `{"kind": "onThisDay"}`, `{"kind": "lastMonths", "months": 12}`, or `{"kind": "range", "from": "2014-01", "to": "2014-12"}`, with only that kind's fields. The picker (T) writes it. |
| `keys.<command>` | Key for each command in the table above, like `"right"`, `"1"` or `"cmd+k"`: modifiers (`ctrl`, `option`, `shift`, `cmd`) joined by `+`, then one character or `left`, `right`, `up`, `down`, `space`, `tab`, `return`, `escape`, `delete`, `forwarddelete` or `plus` (the keypad's +; the + over = is `"shift+="`). A character names the key that types it on a US keyboard without Shift, whatever layout the Mac uses: `"1"` is the key left of 2 even where it types `&`, and `!` is `"shift+1"`. Every command needs a key, and no two can share one. |

The library database, `~/Library/Caches/photo-screensaver/library.sqlite`, is rescanned at
launch, daily, and from **Rescan Library**. The first scan also reads each photo's date, camera
and location, which can take tens of minutes for a large library on a NAS; photos show while it
runs, and the menu shows how far it has got. Later scans read only new and changed files.

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
