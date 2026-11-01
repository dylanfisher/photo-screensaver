# 0005. Keep the library in SQLite, and read photo details from a bounded prefix

- **Date:** 2026-11-01
- **Status:** accepted

## Context

The library is over 100,000 photos on a Synology NAS over SMB. The app cached the walk's path
list as JSON and shuffled paths. Coming features need more per photo: an info panel (capture
date, camera, lens, exposure, location), a timeframe filter over capture dates, a per-year
count, and a cached place name per location. Reading all that means opening every file once,
which at tens of milliseconds per file over SMB is tens of minutes on the first run, so it must
be incremental, resumable, and must not stop the slideshow meanwhile.

## Decision

**SQLite, rebuilt on any schema change.** `PhotoLibrary` keeps one row per photo, keyed by its
path relative to the library folder, in `~/Library/Caches/photo-screensaver/library.sqlite`
(Caches, since it can always be rebuilt from the files). The folder is stored too, and another
folder discards the photos. The `CREATE` SQL is the schema's identity, as in music-player's ADR
0008: a stored text that differs from the build's drops every table and rebuilds, and the next
scan refills it. No version numbers or migrations before the first release. A file SQLite can't
read is deleted and started anew. The wrapper (`SQLiteDatabase`) links the system libsqlite3
and uses nothing newer than 3.36, the version macOS 12 ships.

**Capture date as text.** `taken_at` is EXIF DateTimeOriginal as `YYYY-MM-DD HH:MM:SS`, with
OffsetTimeOriginal in `taken_offset` when the camera recorded one. That is the camera's clock in
whatever zone it was set to, which is what "taken in July 2021" means to the owner, and most
photos carry no offset to turn it into an instant. The text sorts by date, so its `YYYY-MM`
prefix is the sortable year and month: a timeframe is `taken_at >= '2020-01' AND taken_at <
'2021-01'` on an index, and a year count groups on the first four characters. A separate year
or month column would be a second copy of the same fact.

**Read a 128 KiB prefix, and the rest only when it isn't enough.** Measured on this Mac with a
6000×4000 JPEG (23 MB) and HEIC (12 MB):

- Through a `CGDataProvider`, ImageIO asked for the whole file in one call before returning
  properties, for both formats.
- Through `CGImageSourceCreateWithURL`, on a freshly attached disk image, it read 16 KB of the
  JPEG and 512 KB of the HEIC from disk. That's the local volume's paging, and what it does on
  smbfs isn't something this Mac can show.
- An incremental source fed a 64–256 KB prefix as unfinished data gave the JPEG's properties
  but none for the HEIC, whose metadata is all in its first 3 KB. The same prefix handed over as
  complete data gave every property of both, from as little as 4 KB.

So `PhotoMetadata.read` opens the file with `F_NOCACHE` and `F_RDAHEAD` off, reads the first
128 KiB, and gives that to `CGImageSourceCreateWithData` as if it were the whole file. It reads
the rest only when the prefix has no image size, or has no EXIF and the file isn't a JPEG: a
JPEG's EXIF comes before its size, but HEIF, PNG and TIFF can keep it anywhere. 128 KiB holds a
JPEG's EXIF segment (64 KB at most) and the ICC and XMP segments that come before its size.

**Read while walking, tuned on the NAS.** `LibraryScan` ports music-player's pipeline (its ADRs
0009 and 0010), scaled down. Four listers walk depth-first and commit each folder's new and
changed files before moving on; a changed file is replaced by a new, unread row. Readers take
unread rows from the database in ID order, which is walk order, so a folder's files are read
together and photos found a minute ago are read while the walk goes on. Taking them from the
database rather than a queue keeps memory flat at 100k files and means an interrupted pass
resumes where it stopped. Results are stored 200 to a transaction, or once the oldest has waited
3 seconds: at NAS speed 200 take most of a minute, which quitting would lose and the progress in
the menu would lag by. On a network volume `ReadConcurrency`, the same controller as
music-player's, sets the reader count from measured throughput: it starts at 16 and stays within
2…32, half music-player's top, since the slideshow reads full photos from the same share. Local
volumes use one reader per core.

The safety rules carry over: rows are removed only after a walk that finished, with the folder
still on the same device and listing something, and never under a folder that couldn't be
listed, or that listed nothing while rows are known under it, which an SMB hiccup can cause. The
device check is a `stat` on the folder, made without holding the scan's lock, since on a hung
mount it blocks. A read that fails leaves the row unread for the next scan; a file with no image
in it is marked and not shown.

The app opens the database at launch and shows what it has, then rescans. New photos join the
feed when the walk finishes, before their details are read. The feed shuffles row IDs and looks
up each path as it loads, so 100k photos cost under a megabyte there.

## Alternatives considered

- **Keep the JSON cache and add the details to it** — rejected: rewriting a 30 MB file per batch
  to save progress, and loading it whole to filter by date, where SQLite does both in place.
- **Capture date as epoch seconds** — rejected: most photos have no offset, so the number would
  be a guess at an instant, and "this month" would shift with the Mac's time zone.
- **ImageIO's URL source** — rejected: how much it reads is the volume's paging and read-ahead,
  which `F_NOCACHE` and `F_RDAHEAD` can't reach, and its HEIC read was 512 KB locally.
- **An incremental source** — rejected: it gives a HEIC prefix no properties at all.
- **A fixed reader count** — rejected for the reasons in music-player's ADR 0010: it would be
  wrong on another NAS, or on this one while other clients load it.
- **One lister** — rejected: a rescan with no changes is only the walk, and listing one folder
  at a time over SMB makes that several minutes for this library.

## Consequences

- Changing any schema SQL costs one full rescan, details included.
- A JPEG whose header runs past 128 KiB, and a HEIC, PNG or TIFF without EXIF, is read whole,
  once. If the NAS shows many of those, a larger prefix or a second, larger read is the fix.
- A folder emptied but left in place keeps its photos' rows until it's deleted or gets a file
  again. The feed skips the missing files.
- The controller's numbers come from music-player's NAS, whose files are read for 16 KiB
  each. The scan's log line records the reader trace, to check them against this library.
- Photos whose details can't be read stay in the slideshow, unread, and like every photo
  without a capture date they are left out of any timeframe.
- The old `index.json` stays in Caches until removed by hand; nothing reads it.
