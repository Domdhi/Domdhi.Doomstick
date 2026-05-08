# Maps · Offline OpenStreetMap

This folder ships an OpenStreetMap regional `.pbf` file. The `.pbf` is
the bulk format: every road, building, POI, and trail in the region,
in one file, around 1–700 MB depending on region size.

`build-usb.{sh,ps1}` downloads a small placeholder (Monaco, ~700 KB)
by default. Swap it for your real region from
[Geofabrik](https://download.geofabrik.de/) or the [BBBike extract
tool](https://extract.bbbike.org/) for arbitrary bounding boxes.

## Why no desktop launcher?

There is no "open this `.pbf` and chat with it" desktop app the way
there is for chat (llamafile) or wiki (kiwix-serve). OSM data is the
fuel; you bring the engine.

The kit is built around the assumption that the **engine for offline
maps lives on a phone**:

- **Organic Maps** (Android, iOS, F-Droid) — recommended. FOSS, no
  ads, no telemetry, exact same architecture goal as Doomstick.
  https://organicmaps.app/
- **OsmAnd** (Android, iOS) — more features, more complex. Free with
  paid pro tier for vector renders.
- **Maps.me** (older fork of what became Organic Maps; still works
  but has ads and unclear future).

## Sideload protocol

1. Plug the phone into the host that has the USB.
2. Copy `maps/<region>-latest.osm.pbf` from the USB to the phone:
   - Android: `Internal storage/Android/data/app.organicmaps/files/`
     (Organic Maps imports it on next launch)
   - iOS: open Files → On My iPhone → Organic Maps → drop in.
3. Launch Organic Maps. It indexes the `.pbf` and you have offline
   maps + routing for the region.

## Swapping regions

Geofabrik provides per-continent / -country / -state extracts. Edit
the `PBF_URL` constant in `build-usb.{sh,ps1}` to point at your region:

```
# Default placeholder
PBF_URL=https://download.geofabrik.de/europe/monaco-latest.osm.pbf

# Examples
PBF_URL=https://download.geofabrik.de/north-america/us/california-latest.osm.pbf
PBF_URL=https://download.geofabrik.de/europe/great-britain/england-latest.osm.pbf
PBF_URL=https://download.geofabrik.de/asia/japan-latest.osm.pbf
```

Bigger regions take longer to download and longer for Organic Maps
to import. A US-state .pbf is typically 100–700 MB; a US-region (e.g.
`us-northeast`) is 1–4 GB; the whole `north-america` is ~12 GB.

## Why .pbf instead of pre-rendered tiles?

Tiles (PNG/MVT) are visually instant but only cover the zoom levels
you generated. `.pbf` is the source data — Organic Maps re-renders
on the device at any zoom and supports search + routing. One file,
one source of truth. The trade-off is the import step takes a few
minutes on the phone.

## License

OSM data is licensed under the
[Open Database License](https://opendatacommons.org/licenses/odbl/1-0/).
TL;DR: redistribute freely, attribute "© OpenStreetMap contributors",
share derived data under the same license.
