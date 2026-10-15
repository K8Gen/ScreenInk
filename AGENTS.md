# ScreenInk

A menu-bar app for drawing on the screen during presentations. SwiftPM only (no Xcode project), Swift 6 strict concurrency, macOS 14+, arm64 only.

`PLAN.md` holds the product scope, the decisions (with their reasons), the phase roadmap and its current **Status**. Read it before you start a new feature or phase. When you finish one, update its Status block, including any deviations from the plan.

## Verify

- Unit tests: `scripts/test.sh`. Run this instead of plain `swift test`. This machine has only the Command Line Tools, and `swift test` can't find Swift Testing without the extra flags the script adds (CI has Xcode, so it runs `swift test` directly).
- App bundle: `scripts/build-app.sh` builds `build/ScreenInk.app` and fails unless the binary is arm64-only.
- Rendering: `build/ScreenInk.app/Contents/MacOS/ScreenInk --self-test <dir>` drives the real canvas and tools off-screen, writes PNGs to `<dir>`, and exits non-zero if a check fails. Look at the PNGs when you change how something draws. When you add a tool or rendering path, add a check to `Sources/ScreenInk/SelfTest.swift`. The live UI usually can't be driven from here.

A change is done when all three pass, as they do in CI (`.github/workflows/ci.yml`).

## Layering

- `ScreenInkCore` is pure model and geometry: Foundation, CoreGraphics and CoreText only, no AppKit. All of its logic is covered by `Tests/ScreenInkCoreTests`. Put new logic here whenever it doesn't need a view.
- `ScreenInk` is the AppKit app: overlay panels, input, CALayer rendering.
- Data flows one way: input → tool → `Document` mutation, which records the previous annotation array with its `UndoManager` → the canvas syncs one sublayer per annotation. Tools only touch the live stroke bitmap. Committed annotations are always rebuilt from the model.
- Coordinates are screen-local points with a top-left origin (the views are flipped).
