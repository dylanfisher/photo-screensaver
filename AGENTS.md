# AGENTS.md

Instructions for AI coding agents working in this repo. Humans: see [README.md](README.md).

**Keep this file under ~50 lines.** Anything longer lives in `docs/` and is linked from here.

## Stack

- **Language:** Swift 5.7, targeting macOS 12 (Monterey) on a 2015 MacBook Pro
- **Package manager:** Swift Package Manager; dev tools in their own package under `Tools/`
- **Framework:** AppKit menu-bar app; Core Animation, ImageIO, AVFoundation. No third-party runtime deps
- **Test framework:** XCTest (needs Xcode 14.2 as the active developer directory)
- **Layout:** `Sources/<Tier>/`, tests in `Tests/<Module>Tests/` — tiers and search recipes: [docs/map.md](docs/map.md)

## Commands

| Task | Command |
|---|---|
| Install / bootstrap | `./scripts/setup` |
| Run locally | `./scripts/dev` |
| Run tests | `./scripts/test` |
| Format in place | `./scripts/format` |
| **Full gate** | `./scripts/check` |

`./scripts/check` is the gate — see Definition of done.

## Principles

Non-negotiable, regardless of stack. Rationale: [docs/principles.md](docs/principles.md).

1. **Single source of truth.** Every fact — a constant, type, config value, copy string — is defined once and imported. Never re-declare, never re-derive. **Search before you create** — [docs/map.md](docs/map.md) has the recipes.
2. **Match the surrounding code.** Consistency beats personal preference. Read a neighboring file before writing a new one; map.md says which one is the neighbor.
3. **DRY on the third occurrence, not the second.** Premature abstraction costs more than duplication.
4. **Smallest change that solves the problem.** No drive-by refactors, renames, or reformatting outside the task.
5. **Fail loudly.** No empty catches, no silent fallbacks, no defaults that mask a missing value.
6. **Delete, don't comment out.** Git remembers.
7. **No new dependencies without asking first.** Say what it's for and what it replaces.
8. **Style is the formatter's job.** If a tool enforces it, it does not belong in this file or in review.

## Boundaries

- **The photo library is read-only.** Never write, move, rename, or delete anything under it. Tests use generated fixture images in a temp directory, never the NAS.
- **Camera frames never leave memory.** Not written to disk, not logged, not sent anywhere. The camera runs only for the configured check window.
- **macOS 12 APIs only.** Nothing newer, and no `#available` branches to reach past it.
- A new module goes in `Package.swift`, the Tiers table in docs/map.md, and `scripts/arch` together.
- `.build/` and `Tools/.build/` are generated — never edit them.
- **Pre-release:** breaking changes are fine. Stored data has one shape — no version fields, migrations, or compatibility shims; data that doesn't match is discarded. Delete this line at the first production release.

## Definition of done

- `./scripts/check` passes clean.
- New behavior has a test that fails without the change.
- No new dependencies, no new files outside the agreed layout, no TODOs left behind.
- If a decision was non-obvious, record it in `docs/decisions/`.
- Comments, docs, and commit messages follow [docs/writing.md](docs/writing.md).
