# Developing screeny

A native macOS paint app in Swift, AppKit, and Core Graphics. No packages, networking, clipboard polling, continuous rendering loop, or persistent clipboard database.

## Build and run

Requires macOS 14 or later and Apple's Command Line Tools (`xcode-select --install`). Full Xcode is unnecessary.

```sh
./build.sh
open build/screeny.app
```

The script produces an optimized, stripped, locally signed app for the current Mac's architecture. The app bundle is self-contained apart from system frameworks and the system Swift runtime. It is not a notarized distribution build.

```sh
./test.sh
python3 Tools/measure.py
```

Run tests and measurements from a logged-in macOS desktop session. Tests temporarily replace, then restore, the general clipboard. Test code is excluded from the release executable. Build outputs are in `build/`.

## Release builds and GitHub Actions

Create a universal app for Apple Silicon and Intel Macs:

```sh
SCREENY_VERSION=1.0.0 ./release.sh
```

Outputs are `build/screeny-macos-universal.zip` and its `.sha256` checksum. The ZIP preserves the app bundle and executable permissions. The app requires macOS 14 or later. `./build.sh` still defaults to the current Mac's architecture; `SCREENY_ARCHS='arm64 x86_64'` builds both.

`.github/workflows/release.yml` builds the universal ZIP on branch pushes, pull requests, and manual runs, then uploads it as the `screeny-macos-universal` Actions artifact for 30 days. Push a numeric version tag to publish the same ZIP and checksum on a GitHub Release:

```sh
git tag v1.0.0
git push origin v1.0.0
```

The workflow uses the repository's automatic `GITHUB_TOKEN`; no personal token is needed. Only the tag-triggered release job has permission to write releases. The tag sets the version shown in About screeny, and the workflow run number becomes the bundle build number. Re-running a version tag replaces that release's generated assets. Commit the source, icon assets, scripts, and workflow to your GitHub repository first; generated `build/` files stay excluded.

The build is ad-hoc signed and verified, but is not Apple Developer ID signed or notarized. Distributing it without macOS trust prompts requires a Developer ID certificate and Apple's notarization service; those credentials are not configured by this workflow.

The app icon lives in `Assets/AppIcon.icns`, with a 1024px preview at `Assets/AppIcon.png`. It is vector artwork drawn by the project, matching the app's violet accent. To regenerate the complete macOS icon set with Apple's tools:

```sh
xcrun swift -module-cache-path build/ModuleCache Tools/make-icon.swift .
iconutil -c icns build/AppIcon.iconset -o Assets/AppIcon.icns
```

Workflow references: [GitHub artifact uploads](https://github.com/actions/upload-artifact), [GitHub CLI release creation](https://cli.github.com/manual/gh_release_create).

## Use

The canvas displays a solid white background. Copy and PNG export still preserve transparent pixels.

- Brush, arrow, rectangle, ellipse, and text create separate editable records. Completing a stroke, shape, or text item automatically selects it and switches to Move. Move drags items; Shift-click selects several. Arrow keys nudge selected items; Shift nudges by ten pixels. Delete removes selected items.
- Text is entered directly on the canvas at the current font size and color. Return or clicking away commits it; Shift-Return adds a line; Escape cancels. Text stays aligned under zoom and rotation.
- Click the color well for the full native macOS color panel, including RGB sliders and opacity. Hex accepts `RRGGBB` and `RRGGBBAA`, with an optional `#`.
- Eraser reveals Pixel/Object. Pixel clears all covered image and annotation pixels to transparency, preserving record identity. Object removes the topmost visible stroke, shape, text, or pasted image. A pasted image is erased as one whole item; transparent and pixel-erased regions do not intercept hits. Screenshot contents are never interpreted as separate objects.
- Select / Crop draws a rectangle; press Return or click Crop to apply. Escape cancels a selection or pending edit.
- Copy and ⌘C copy the complete composition as transparent PNG at document pixel dimensions. Paste and ⌘V insert all readable image items, once per pasteboard item. Alternative formats in one pasteboard item are decoded once. Images and image file URLs are supported, including drag-and-drop.
- Paste's arrow shows only images copied or pasted through this screeny session. Select one or more checkboxes, then Insert selected. Clear releases history references without changing the document. History retains at most five images and 64 MiB of pixel storage; oversized images still paste but are not retained. Reinserted images become recent again.
- A paste batch is one undo step and creates separate, offset, movable items. A single image pasted into an empty document sets the original canvas dimensions.
- Pinch zooms around the pointer. Two-finger scrolling pans using native natural-scroll and momentum deltas. Two-finger rotation rotates the view. Smart zoom toggles Fit/100%. Fit resets pan and rotation. These transforms never change document pixels.
- Horizontal and vertical scrollbars pan the workspace. Center (⇧⌘0) centers the image while preserving zoom and rotation; Fit also resets zoom and rotation.
- Mouse/keyboard navigation: Space-drag or middle-drag to pan; unselected arrow keys pan; ⌘+/⌘− zoom; ⌘0 fits; ⌘1 shows 100%; ⌥⌘[/] rotates. Command-scroll zooms at the pointer. Tools are also available through the Tools menu with ⌥⌘1–8.
- ⌘N creates a canvas, ⌘O opens an image, ⌘Z/⇧⌘Z undo/redo, and ⌘S or ⇧⌘E exports. Native PNG/JPEG dialogs are used. PNG preserves transparency; JPEG composites on white. Closing, quitting, replacing a canvas, and opening an image protect unexported changes.

Exports contain pixels, not editable object records. Editability and history last for the session. The application currently uses one document window.

## Implementation

`Sources/App.swift` contains native controls, menus, dialogs, and lifecycle handling. `Sources/Canvas.swift` handles drawing, hit testing, and native input events. `Sources/Document.swift` contains image I/O, clipboard parsing, editable records, history, and bounded undo. `Sources/main.swift` starts AppKit. `Sources/Chrome.swift` gives native buttons and dividers a compact, consistent appearance with system fonts, SF Symbols, and a restrained violet accent.

Drawing invalidates affected view regions and renders on demand. No full-image snapshots are made while drawing. Images and immutable paths are shared by scene snapshots. Erased records use clipped transparency groups and geometric masks instead of a permanent raster buffer per object. Undo retains at most 50 actions and 128 MiB of conservatively estimated retained record/path/image storage beyond the current document. History's 64 MiB budget is independent. Current document contents themselves have no fixed memory cap.

See `VERIFICATION.md` for measured results and verification limits.
