# Design: copy the screen to the clipboard as PNG

Status: approved by the project owner on 2026-10-15.
Implementation plan: [`plan.md`](plan.md).

## Goal

The presenter can put a PNG of the screen, with the drawings on top, on the clipboard.
The presenter can copy the whole screen or a region that they drag.
This feature is the first part of PLAN.md Phase 5. PNG is the only format.

## Behavior

### Copy Screen (⌘C)

- The menu-bar menu has the item **Copy Screen**. ⌘C does the same thing while the overlay is active.
- The app uses the same screen rule as Undo: the overlay with keyboard focus, else the screen under the pointer.
- The clipboard gets a PNG of that whole screen with its annotations on top.
- If the overlay is visible, a short white flash covers the screen after the copy.

### Copy Region… (⇧⌘C)

- The menu-bar menu has the item **Copy Region…**. ⇧⌘C does the same thing while the overlay is active.
- The overlay shows on all screens, also when drawing was off. The palette hides. The cursor is a crosshair.
- The presenter drags a rectangle on one screen. The rectangle stays inside that screen.
- When the presenter releases the mouse, the region goes to the clipboard and flashes.
- Then the overlay goes back to its earlier state: hidden, or visible with the palette.
- Esc cancels. A click without a drag (smaller than 4 pt on a side) also cancels.
- During the pick, all other keys and tool shortcuts do nothing.

### PNG content

- The PNG has the screen content and all annotations of that screen.
- The annotations are rebuilt from the `Document` model. They are in the PNG also when drawing is off.
- The PNG does not have the palette, selection boxes, the marquee, the copy flash, the cursor or the dimming veil.
- The pixel size is the screen size times its backing scale (for example 2x on Retina).
- The clipboard type is `public.png` (`NSPasteboard.PasteboardType.png`).

### Permission

The capture needs the Screen Recording permission (ScreenCaptureKit).

1. First use without permission: the overlay hides. The app shows its own alert that explains the reason. On **Continue**, the app calls `CGRequestScreenCaptureAccess()`, and macOS shows its prompt. Nothing goes to the clipboard.
2. Later uses without permission: the overlay hides. An alert offers **Open System Settings** (Privacy & Security › Screen & System Audio Recording).
3. With permission: the copy runs. If the capture fails, the overlay hides and an alert shows the error.

The overlay window level (`.screenSaver`) is above alert windows, and the overlay takes the clicks.
For this reason, the app always hides the overlay before it shows an alert.

## Architecture

The design follows `AGENTS.md`: pure geometry goes in `ScreenInkCore`, and the annotations always come from the model.

| Part | Module | Job |
|---|---|---|
| `ExportRegion` (new) | ScreenInkCore | Drag → rect in points (clipped, minimum size). Rect in points → crop in pixels. Unit-tested. |
| `ScreenCapturer` (new) | ScreenInk | ScreenCaptureKit: one `SCScreenshotManager` image of a display. The filter excludes all ScreenInk windows. |
| `ExportRenderer` (new) | ScreenInk | Draws the capture, then the annotation layers from `AnnotationLayerFactory`, then crops. |
| `ScreenExporter` (new) | ScreenInk | Capture → render → PNG → pasteboard. Permission and failure alerts. |
| `RegionTool` (new) | ScreenInk (`CanvasTools.swift`) | A `CanvasTool` that shows the marquee and reports the dragged rect. |
| `CanvasView` | ScreenInk | `beginRegionPick` / `endRegionPick`, ⌘C / ⇧⌘C, Esc during a pick. |
| `OverlayLayerView` | ScreenInk | `flash(_:)` for the copy confirmation. |
| `ScreensController` | ScreenInk | Chooses the screen. Runs the region pick on all screens. Restores the state. |
| `StatusItemController` | ScreenInk | The two menu items. |

### Data flow

```
menu item / ⌘C / ⇧⌘C
  → ScreensController.copyScreen() / copyRegion()
      copyRegion: every CanvasView swaps in RegionTool → drag → ExportRegion.rect → finishRegionPick
  → ScreenExporter.copy(screen:annotations:rect:)
      → ScreenCapturer.capture (ScreenCaptureKit, own app excluded)
      → ExportRenderer.render (capture + annotation layers, crop with ExportRegion.pixelRect)
      → NSPasteboard.general (.png)
  → OverlayLayerView.flash → restore the overlay state
```

### Why this approach

- PLAN.md §3 already chose ScreenCaptureKit with our own app excluded by `SCContentFilter`.
- The capture does not see our windows. Thus the app does not need to hide the palette, the marquee or the dimming before the capture, and there is no race with the window server.
- The annotations come from the model, as `AGENTS.md` requires. The export does not depend on what the overlay shows at that moment.

Rejected options: capture with our overlay window included (needs hide/show of UI parts and a wait for the window server), and running `screencapture -i -c` (the palette gets into the image, and an external process is hard to control).

## Known limits

- The highlighter uses `multiplyBlendMode` on screen. `CALayer.render(in:)` ignores compositing filters, so in the PNG the highlighter blends normally. Over other windows this looks the same as on screen.
- ⌘C and ⇧⌘C work only while the overlay has keyboard focus. There is no global hotkey for the copy.
- The app is ad-hoc signed by default. macOS can forget the Screen Recording permission after each rebuild.

## Tests

- Unit tests (`Tests/ScreenInkCoreTests/ExportRegionTests.swift`): drag direction, clipping to the screen, click cancels, pixel rounding, crop inside the image.
- Self-test (`Sources/ScreenInk/SelfTest.swift`, checks 8 and 9): render over a solid blue "capture" with the dimming on. The test checks the size, the background pixel, the annotation position (orientation) and the crop. It also checks that the region tool returns the dragged rect, that a click cancels, and that the earlier tool comes back.
- Manual test on a Mac: see the checklist at the end of `plan.md`. The ScreenCaptureKit capture cannot run in CI, because CI has no Screen Recording permission.

## Out of scope

Snapshots (⌘S), the gallery, PDF, saving to a file, a global copy hotkey, and regions across two screens.
