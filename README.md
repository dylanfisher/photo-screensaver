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
| Install | `./scripts/setup` |
| Build and launch | `./scripts/dev` |
| Test | `./scripts/test` |
| Everything before a commit | `./scripts/check` |

Agents and contributors: start with [AGENTS.md](AGENTS.md).
