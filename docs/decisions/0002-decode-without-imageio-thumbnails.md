# 0002. Decode photos without ImageIO thumbnails or CoreGraphics drawing

- **Date:** 2026-10-30
- **Status:** accepted

## Context

Photos are decoded at 2× their shown size (0001). The obvious API for that is
`CGImageSourceCreateThumbnailAtIndex`, which scales and applies EXIF rotation in one call. In the
running app, memory grew by one decoded photo per slide (~88 MB for a 24 MP original) and
plateaued near 2.9 GB on a 16 GB Mac. Allocation stacks showed the pixels held by CoreGraphics'
process-wide image cache (`RIPImageCache`), not by app code. Autorelease pools didn't help.
Drawing a full-size decode into our own `CGContext` to scale it fills the same cache.

## Decision

`ImageFile.decode` decodes with `CGImageSourceCreateImageAtIndex` (no cache growth measured), and
when the photo is larger than wanted or not upright, scales, rotates and mirrors it with vImage.
Photos that are already upright and small enough skip vImage entirely.

## Alternatives considered

- **ImageIO thumbnails**: rejected; they fill the CoreGraphics cache, as above.
- **Scaling with `CGContext.draw`**: rejected; it fills the same cache.
- **Rotating with layer transforms instead of pixels**: rejected; every size calculation
  (framing, Ken Burns, decode size) would have to account for rotation.

## Consequences

- `ImageFileTests.testAllExifOrientationsMatchImageIO` checks all eight EXIF orientations against
  ImageIO's own output, so a change to the vImage steps can't silently mirror photos.
- Decoding is roughly twice as fast as the thumbnail path on this Mac (~0.45 s for 24 MP).
- Steady-state memory is about the preload buffer plus the photos on screen, ~450 MB with the
  starter settings on a 2880×1800 screen.
