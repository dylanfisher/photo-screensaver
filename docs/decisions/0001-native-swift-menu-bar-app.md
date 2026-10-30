# 0001. Native Swift menu-bar app, decoding photos at 2× screen size

- **Date:** 2026-10-30
- **Status:** accepted

## Context

The app shows a shuffled, full-screen slideshow from a NAS photo library of tens of thousands of
images, mounted over SMB. It runs on a 2015 MacBook Pro, which tops out at macOS 12 (Monterey)
and has a 2560×1600 Retina display. It must stay light on CPU and memory, and it optionally uses
the camera to detect motion and sleep or wake the display. Photos must look as sharp as possible,
including during Ken Burns pans and zooms.

## Decision

Build a native Swift 5.7 AppKit menu-bar app with Swift Package Manager, using no third-party
runtime dependencies. Core Animation drives transitions and Ken Burns, ImageIO decodes, and
AVFoundation reads the camera. Each photo is decoded to at least 2× the display's native pixel size,
capped at the original's size, and only the current photo plus a few preloaded ones are held in
memory. Settings live in a hand-edited JSON file that the app reloads when it changes.

## Alternatives considered

- **Electron or another web runtime**: rejected. It costs hundreds of MB of RAM and constant CPU
  on old hardware, and a browser can't sleep or wake the display.
- **A `.saver` screensaver bundle**: rejected. macOS hosts it in a sandboxed process with no
  camera access, and gives it no control over when it starts.
- **Decoding at exactly screen size**: rejected. Ken Burns zooms make it look soft.
- **Decoding every photo at full size**: rejected. A 45-megapixel original is about 180 MB
  decoded, and the extra pixels beyond 2× are never seen.
- **A NAS API (such as Synology Photos)**: rejected. A mounted SMB share is a plain directory,
  with no credentials to store.
- **A settings window**: deferred. A JSON file is enough for one user, and a window is more UI to
  maintain.
- **`swift build --explicit-target-dependency-import-check`** for tier enforcement: not available
  in Swift 5.7, so `scripts/arch` checks `import` lines instead.

## Consequences

- Tests need Xcode 14.2, not just the Command Line Tools, because XCTest ships only with Xcode.
  Xcode must also have run its first-launch setup (`sudo xcodebuild -runFirstLaunch`), or the
  test runner crashes on startup.
- Camera permission requires a real `.app` bundle with `NSCameraUsageDescription`, so
  `scripts/dev` assembles one rather than running the bare binary.
- macOS 12 caps the APIs available: Swift 5.7, and no newer SwiftUI or Observation features.
