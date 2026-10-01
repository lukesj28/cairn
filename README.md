# Cairn

A menu bar app for macOS that remembers how you like your windows arranged, and puts them back that way with one click.

![Platform](https://img.shields.io/badge/platform-macOS%2012%2B-blue)
![Swift](https://img.shields.io/badge/swift-6.0-orange)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

## What it does

If you switch between different work contexts (coding, writing, research, whatever) you probably open roughly the same set of apps in roughly the same spots every time. Cairn lets you save that arrangement as a **stack**, then restore it later from the menu bar instead of dragging six windows back into place by hand.

A stack is a named list of apps and where their windows should sit, stored as fractions of the screen rather than pixels. That's what lets a layout saved on one monitor still make sense on a different one.

- **Capture** your current window layout into a new stack with one click, or build one from scratch by adding apps manually.
- **Arrange** windows on a visual canvas with drag-to-move, edge/corner resize, and a 12x8 snap grid with edge and sibling-window magnetism (hold Shift to place freely instead).
- **Apply** a stack from the menu bar: Cairn launches whatever isn't already running, waits for windows to appear, and tiles everything into position.
- **Two displays.** A stack can span a main and secondary monitor, independently editable.
- **Auto-updates** via Sparkle, so you're not manually checking for new DMGs.

## Installation

Download the latest `Cairn.dmg` from [Releases](https://github.com/lukesj28/cairn/releases) and drag Cairn into Applications.

On first launch, Cairn will ask for Accessibility permission. It needs this to read and move other apps' windows. Updates after that are automatic via Sparkle.

## Building from source

Cairn is a Swift Package Manager project; there's no Xcode project file to open.

```bash
git clone https://github.com/lukesj28/cairn.git
cd cairn
make dev     # builds and ad-hoc signs a debug Cairn.app
make run     # launches it
```

**Requirements:** macOS 12+, Xcode (for the Swift toolchain), Python's `dmgbuild` package if you want to build a release DMG yourself.

Other useful targets:

```bash
make test           # run the CairnKit test suite
make app-release     # release build, signed with a Developer ID
make dmg            # app-release + packaged into a signed DMG
make clean           # remove build artifacts
```

## How it works, briefly

macOS's accessibility API is the only way to move another app's windows around, and it's not especially cooperative; some apps clamp window sizes to their own minimums and ignore a resize request outright. Cairn sets a window's frame, checks what actually happened, and adjusts its request if the app pushed back, repeating until the window settles or it gives up. The same logic launches apps that weren't running yet, waits for their windows to appear, and opens extra windows for apps that need more than one. None of this blocks the UI; it all runs on a background queue.

Stacks are stored as JSON at `~/Library/Application Support/Cairn/stacks.json`, using fractional (0-1) coordinates rather than pixels. If that file ever becomes unreadable, Cairn quarantines the broken copy instead of silently wiping your data or crashing on launch.

## License

MIT
