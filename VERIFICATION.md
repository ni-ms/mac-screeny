# screeny verification

Measured November 8, 2026 on a MacBook Air, Apple M4 (10 cores), 16 GB RAM, macOS 26.3.1 (25D2128), arm64. Built with Swift 6.3.3, `-O`, whole-module optimization, symbol stripping, and local ad-hoc signing. No third-party dependencies.

## Release measurements

Launch and memory measurements precede the icon and universal-release packaging changes. Bundle size and source counts reflect the rebuilt universal screeny app.

| Measurement | Result |
| --- | ---: |
| Median process start to first window draw, 5 warm launches | 223.49 ms |
| Launch range | 207.72–289.55 ms |
| Idle physical footprint, final run, reported by Apple's `sample` | 47.1M |
| Median idle resident set, including resident system mappings | 117.64 MiB |
| Uncompressed app bundle, sum of file sizes | 1,434,857 bytes (1401.23 KiB), universal arm64 + x86_64 with icon |
| Swift implementation | 933 lines in five files |
| Regression test source | 264 lines, excluded from release |

Launch timing starts in the measurement process immediately before spawning screeny and ends when screeny reports that its native window has drawn. It includes executable startup and AppKit initialization. These are warm-cache measurements, not a reboot/cold-disk benchmark or input-to-screen latency measurement. Memory was sampled one second after window readiness with an empty 1600 × 1000 canvas, in the current desktop session. Physical footprint is one final-run reading; resident set is the median of five readings. These are different OS memory accounting measures. Large documents, undo, and opening the system color panel use additional memory.

Exact readings: `build/measurements.json`. Repeat with `python3 Tools/measure.py`.

## Automated verification

`./test.sh`: **75 checks passed, zero failures**. The final run took 0.36 seconds for the core checks, excluding compilation and preliminary dialog/picker checks. Fixtures are synthetic RGBA images at 3840 × 2160, 5000 × 4000, and 7000 × 5000 pixels, with asymmetric colors and transparent regions.

Verified:

- Pasted-image object erasure: whole-image deletion, undo/redo with preserved identity and pixel masks, overlapping elements, transparent hit-through, multi-image drag deletion, and single-action batch undo.
- General macOS pasteboard: PNG/TIFF alternatives produce one image, distinct items produce multiple images, original dimensions, image orientation, transparent PNG copy, and single-paste canvas sizing.
- Multiple image items have distinct identities and offsets, move independently, and undo/redo as one paste action.
- History: five-entry limit, 64 MiB eviction, oldest-first eviction, oversized-image insertion without retention, clearing without document deletion, disabled empty insertion, selection enabling insertion, and selected historical batch insertion/undo.
- Brush records and pixel erasure preserve identity and visible hit geometry. Pixel erasure clears screenshots and annotations to alpha zero; JPEG export flattens those pixels to white.
- Object erasure removes pasted images as whole items, ignores transparent and pixel-erased regions, removes the topmost visible item, handles images/shapes/text and multiple items during a drag, and restores identities and prior pixel erasures with undo.
- Pointer-anchored zoom and rotation, natural-scroll deltas, momentum start/end guarding, Fit/100% smart zoom, pan/rotation reset, transformed hit testing, unchanged export dimensions, blocked accidental edits, and cancellation of in-progress strokes.
- Exact-dimension cropping and undo without rasterizing editable objects.
- Undo action/memory bounds, including eviction of a redo image larger than 128 MiB.
- Full native color panel visibility and opacity support, and native JPEG format/extension updates.

Gesture tests call the actual NSView event handlers using test NSEvent subclasses; mouse tests deliver local AppKit mouse events. They do not synthesize physical multitouch input. Test code is not compiled into the release app.

Additional checks cover on-canvas native text entry, Return and click-away commit, Escape cancellation, multiline glyph geometry, text insertion undo, native text undo availability, automatic selection of Move after drawing, editor alignment under zoom/rotation, usable window layout, horizontal/vertical scrollbar panning, and Center preserving scale, angle, and document pixels.

## Live native-window verification

Inspected the compact dark-appearance window, icon tool grid, consistent button styling, inline typing and Return-to-Move behavior, scrollbar dragging and Center, canvas clipping, the former transparency checkerboard (now replaced with a solid white canvas display), accessible native controls, eraser mode visibility, hidden width in Object mode, empty history, thumbnails/dimensions/checkboxes, selection-enabled insertion, Copy/Paste keyboard shortcuts, native scrolling and Fit, the native save dialog, and PNG/JPEG choices. Exported a JPEG through the dialog and checked its actual file format and dimensions. The app's local code signature passes strict verification.

Physical trackpad pinch/rotation/smart-tap behavior still needs a hands-on hardware pass; automated handler checks and live scrolling do not establish that physical input has been tested. The large-image tests use synthetic fixtures rather than captured screenshots. Only the listed Mac and OS were tested.

## Storage and rendering

Clipboard reads occur only on explicit paste/drop. Image decoding produces an owned sRGB pixel buffer, so history does not retain an uncounted compressed source. Pixel cost is budgeted by bytes-per-row × height. History is session-only. Clearing it does not remove document references.

Rendering occurs on demand; brush and eraser movement invalidate affected view regions. There is no timer, polling, display link, permanent drawing loop, raster undo snapshot, or database. Snapshots share immutable paths and image buffers. Undo/redo is bounded to 50 retained actions and 128 MiB beyond the current scene, using conservative record/path estimates. The current document is not part of that cap. Editable data is session-only; PNG/JPEG exports retain composed pixels.

## Icon and release packaging

Added a complete ICNS app icon and a reproducible native vector generator. Verified both arm64 and x86_64 executable slices, version injection (1.0.0/build 1), native code signing, packaged icon metadata, ZIP extraction with preserved executable permissions, and SHA-256 checksum. The universal release ZIP was built successfully on the local M4 Mac. Intel execution was not tested.

The GitHub Actions workflow was checked for valid YAML, its job/permission structure, and embedded shell syntax. It builds and uploads an artifact on branches/PRs/manual runs, and publishes a GitHub Release for a pushed numeric version tag. Local validation does not establish GitHub-hosted build success. See the repository Actions page for the latest CI results; release publication occurs only when a version tag is pushed. Releases remain ad-hoc signed and unnotarized.
