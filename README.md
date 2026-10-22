# SidecarSide

A tiny macOS menu bar app that puts your Sidecar iPad on the correct side of your Mac.

When an iPad connects as a Sidecar display, a small glass panel asks whether it's on the **left** or **right**, then arranges the displays so your cursor moves across naturally. Tick "Don't ask again" and it just applies your side silently from then on.

- **← / →** pick a side, **Return** picks the highlighted (last used) side, **Esc** dismisses
- Menu bar item: switch sides instantly, toggle asking, launch at login
- Hide the menu bar icon entirely; the app keeps working, and opening SidecarSide again (Applications, Spotlight) brings the icon back
- Pure AppKit, no dependencies, idle until a display connects

## Install

```bash
./install.sh
```

This builds a universal (Apple silicon + Intel) app, copies it to `/Applications`, and launches it. On first launch from `/Applications` it adds itself as a login item (turn it off from the menu bar item).

Or download the zip from [Releases](../../releases), unzip, and drag `SidecarSide.app` to Applications. The app is ad-hoc signed, not notarized, so the first time either right-click → **Open**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/SidecarSide.app
```

## Build

Requires macOS 13+ and the Xcode Command Line Tools.

```bash
./build.sh                                                  # -> build/SidecarSide.app and build/SidecarSide-<version>.zip
build/SidecarSide.app/Contents/MacOS/SidecarSide --preview  # show the picker without moving any displays
```

The app icon is drawn from SF Symbols at build time by `tools/make-icon.swift`. The version lives in `VERSION`.

## How it works

- `CGDisplayRegisterReconfigurationCallback` notices when a display is added.
- A display counts as Sidecar if its name contains "Sidecar" or "iPad".
- `CGConfigureDisplayOrigin` places it flush against the main display's left or right edge, vertically centered, and the change is saved permanently.
