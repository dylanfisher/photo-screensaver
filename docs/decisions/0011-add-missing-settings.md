# 0011. Add missing settings at launch

- **Date:** 2026-11-03
- **Status:** accepted

## Context

ADR 0009 left missing keys for the owner to paste in, since filling them from defaults is a
migration. Then `battery` (ADR 0010) became a required key, and an existing config.json stopped
loading until it was added by hand. The owner asked for new settings to be added on their own.

## Decision

At launch, `Settings.addMissingKeys` adds each key `starter` has and the file leaves out, with
`starter`'s value, and writes the file through the same writer as `Settings.update`. It adds
them only when the result decodes and validates. A file with an unknown key, such as a
misspelling, or any other error is left as it is, and the load reports it with the missing keys
as before. Reloads while the app runs don't add keys, since a key that disappears then is more
likely an edit in progress.

## Alternatives considered

- **Pasting keys in by hand (ADR 0009)** — rejected by the owner: every new setting broke the
  running config until it was added.
- **Decoding leniently, with defaults in memory only** — rejected: the file would no longer
  hold every setting, and the settings window writes the whole file anyway.
- **Adding keys to a file that has other errors** — rejected: it would write a file that still
  doesn't load, and hide which keys the owner left out from what the app added.

## Consequences

A misspelled key still fails, as an unknown key, so filling gaps doesn't hide typos. Writing the
file reformats it, as any change from the settings window does.
