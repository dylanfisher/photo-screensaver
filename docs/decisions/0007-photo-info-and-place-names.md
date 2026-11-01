# 0007. The info panel looks up place names only for the photo on screen, and caches them per 0.01°

- **Date:** 2026-11-01
- **Status:** accepted

## Context

A key (`info`, ↑ by default) opens a panel over the slideshow with what the library knows about
the photo on screen: where and when it was taken, the camera, lens and exposure, its size, and
its folder and file. The library database (ADR 0005) has the EXIF fields, but not for photos the
first scan hasn't read yet, and it has coordinates, not place names. Apple's `CLGeocoder` turns
coordinates into names for free, over the network, rate-limited per app. The library has over
100,000 photos.

## Decision

**Geocode only the photo on screen, only while the panel is open.** Each photo shown with the
panel open starts one lookup task and cancels the one before, which cancels its request, so a
lookup for an earlier photo never writes over a later one. Until a name arrives, or if the lookup
fails, the panel shows the coordinates, and the name replaces them in place. Only the coordinates
go to Apple. `CLGeocoder` doesn't use the Mac's location, so it needs no location permission and
no Info.plist key; the app isn't sandboxed, so it needs no network entitlement either.

**Wait a second before asking.** A lookup for a place not in the cache waits a second first, so
stepping quickly through photos with the panel open, which cancels each lookup, sends nothing
for the photos passed by. A cached name still shows at once, and the cache is checked again
after the wait, since a nearby photo may have filled it meanwhile.

**Cache names in `places`, keyed by coordinates rounded to 0.01°.** That's about 1.1 km north to
south, less east to west away from the equator. Photos from one trip cluster, so most of them
share a lookup, and at the level a short name shows (a park, a neighborhood, a city) a cell
rarely spans two names. The lookup sends the photo's own coordinates, not the cell's center,
which can be a kilometer off and outside the park the photo was taken in. The table outlasts a
change of library folder, since places don't depend on it.

**Cache "nothing there", not errors.** A geocoder that answers with no place, as at sea, is
stored as an empty name and not asked again: it's an answer, and asking again for every photo
from a ferry would spend the rate limit. A network error, a rate-limit refusal or a cancel isn't
stored, so the next time the photo shows tries again. A failed lookup is logged, not shown in the
menu, since offline it would be every photo with a location.

**Store the short name, not the placemark.** The name is the most specific area (an area of
interest, a landmark name, or a neighborhood), then the city, or the state when there's no city,
then the country: "Shibuya, Tokyo, Japan". `name` is used only when it isn't a street address,
told by starting with a digit or containing the street. A rule change keeps the old names until
`places` is cleared; changing the schema text, which clears it, also costs a full rescan.

**Read an unread photo's details on demand, and don't store them.** The panel shows the path at
once, then the details read from the file with `PhotoMetadata.read`, off the main thread. The
scan reads and stores the file in its turn; a second writer would race its batches.

**The date is the camera's clock.** `taken_at` is shown in the locale's words without moving it
into the Mac's time zone. With an offset, the time zone is that offset and is shown after the
time, like "18:30 GMT-4"; without one, nothing is added.

**The panel's open state isn't saved.** It stays open across photos and slideshows until its key
closes it or the app quits.

## Alternatives considered

- **Geocoding the whole library in the background** — rejected: tens of thousands of requests
  against a per-app rate limit, and every location sent to Apple, for photos no one may look at.
- **Caching errors for a while** — rejected: the common error is being offline, and a retry the
  next time the photo shows costs one request.
- **Rounding to 0.1° (about 11 km)** — rejected: a cell would hold several neighborhoods and parks
  under one name.
- **No delay before geocoding** — rejected: each step cancels the lookup before it, but a
  request already sent still counts against the rate limit. The wait holds up each new name by
  a second, which with the panel open is hardly noticed.
- **MapKit's `MKReverseGeocodingRequest`** — not on macOS 12. `CLGeocoder` is deprecated in the
  macOS 26 SDK but available on 12, which is what the app targets.

## Consequences

- With the panel open, each new photo with a location in a cell not yet looked up, and on screen
  for a second, costs one request. Stepping through such photos a second or more apart can still
  reach Apple's rate limit; the panel then shows coordinates until a later lookup succeeds.
- Place names are in the language of the Mac when they were looked up, and stay so.
- A photo removed by a rescan while on screen closes the panel's content until the next photo.
