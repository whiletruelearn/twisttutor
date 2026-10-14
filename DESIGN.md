---
name: TwistTutor — Cube first
description: A native cube workspace with a navy stage and a light control drawer.
colors:
  stage: "rgb(7.5% 12% 19%)"
  stage-secondary: "rgb(72% 78% 86%)"
  primary: "rgb(6% 28% 72%)"
  on-primary: "#ffffff"
  drawer: "#ffffff"
  drawer-secondary: "rgb(35% 35% 35%)"
rounded:
  drawer: "28px"
  primary: "18px"
  entry-tool: "16px"
  swatch: "12px"
spacing:
  compact: "8px"
  control-gap: "14px"
  drawer-inset: "20px"
  heading-inset: "24px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.primary}"
  drawer:
    backgroundColor: "{colors.drawer}"
    rounded: "{rounded.drawer}"
    padding: "{spacing.drawer-inset}"
---

# Design System: TwistTutor

## Overview

**Creative North Star: “Cube first”**

The interactive cube leads. A continuous navy stage, compact guidance and light bottom drawer give first-time solvers one clear next action. Native navigation and edge tools keep the object visible. This is the user-approved direction from 14 October 2026, recorded from the implementation rather than the concept image.

Source of truth: `ContentView.swift` (including `CubeStyle`, `CubePrimaryButton` and `cubeDrawer`), `ManualEntryView.swift`, `ManualSolutionView.swift` and `CubeScene.swift`. See `PRODUCT.md` for product constraints and `Docs/Design/cube-first-brief.md` for the approved direction. Frontmatter dimensions use portable CSS syntax; their numeric values represent SwiftUI points in the app.

Verification boundary: physical-device, iPad and Dynamic Type visual checks remain pending. Final flow UI verification was interrupted because computer-use automation became unavailable. Screenshots of individual screens do not establish verification of other states or the complete solving flow.

## Colors

Use the shared strong primary blue (`CubeStyle.action`) for the main drawer action, navigation/drawer tint and current solution step. Primary buttons and the current step use white text.

The stage token is shared by SwiftUI and the RealityKit background so the viewport has no visible panel boundary. Use white stage headings and the pale blue-gray secondary token for instructions. Drawers explicitly use the light color scheme and `systemBackground`, with semantic primary text and the drawer-secondary token for secondary copy; the drawer token represents that current light surface.

Cube colors are functional data, defined by `CubeColorID.uiColor` in `CubeScene.swift`. Keep all six color names visible in the palette. Selection also uses a checkmark and a tinted container. Completion and errors pair semantic green/red with text or symbols; color alone must not carry status.

## Typography

Use system fonts and semantic SwiftUI text styles. The home headline uses bold rounded `largeTitle`; entry and solution stage headings use bold rounded `title2`. The large move notation also uses the rounded system design. Body instructions use `body` or `subheadline`; buttons and action descriptions use `headline`; palette labels and counts use `caption2`. Counts use monospaced digits and step notation uses a monospaced body style.

Preserve Dynamic Type through semantic text styles. Avoid replacing this hierarchy with fixed point sizes or a custom typeface.

## Layout

Center the workspace at a maximum width of 700 points. Home uses a flexible cube viewport between its heading and drawer. Entry and solution use vertical scrolling and geometry-dependent viewport heights, keeping a minimum visible cube area while allowing controls to extend below the fold.

Entry reserves 360 points for ordinary controls, 220 while inspecting, or 480 at accessibility text sizes; its viewport minimum is 240 points. Solution reserves 330 points, or 440 at accessibility text sizes, with a 220-point viewport minimum. These are current layout values, not proof of device coverage.

Use the established 20-point drawer inset and 24-point heading inset. The palette changes from six columns to three at accessibility text sizes. The solution strip scrolls horizontally, centers the current step and uses a scaled 72-point base height. Do not shrink text to force all controls into a single viewport.

## Elevation & Depth

Depth comes from the actual 3D cube and the tonal separation between stage and drawer. The UI uses no decorative drop-shadow system. Edge tools sit on translucent white fills at 10% opacity. Keep the live cube geometry; generated artwork is not a substitute for the interactive object.

## Shapes

Use the drawer and primary radii from the tokens. Entry edge tools are 58-point squares with the entry-tool radius; the solution reset control is a 48-point square with a 14-point radius. Swatches have softly rounded corners and a subtle dark outline. The six face-progress indicators use thin capsules; solution step tiles use a 10-point radius.

## Components

- **Primary action:** full available width, headline text, horizontal padding of 20 points and minimum height of 52 points. Pressed opacity is 80%. Disabled buttons use secondary text and a 16%-opacity gray fill. Keep the main action specific: “Continue,” “Review cube,” or “Show next move.”
- **Native navigation:** use `NavigationStack`, inline titles and a dark navigation bar matching the stage. Put help, examples and playback options in the trailing menu. Destructive clearing uses a confirmation dialog.
- **Entry workspace:** the face strip is both progress and navigation, with accessible filled counts and selected traits. Painting locks the view to the named face and accepts 3D sticker taps only on that face. Inspect and review allow orbit while disabling 3D painting. “Back to painting” restores the focused face. Keep Undo and Inspect/Reset on the edge rail.
- **Orientation guidance:** name the top neighbor using its entered center color when available, otherwise use the face name. Do not assume fixed center colors.
- **Accessible entry alternative:** “Help & sticker buttons” opens a native sheet with orientation instructions, a labeled 3×3 sticker grid, palette and validation feedback. Each sticker exposes face, position, color and painting/erasing hint. The viewport has directional accessibility actions that respect the orbit lock. These are implemented alternatives; assistive-technology usability still needs device verification.
- **Review and solving:** surface validation before enabling the solve action. Keep calculation progress and cancellation visible. During playback show the active or next move with a plain-language direction, previous-step control and next/pause action. The step strip distinguishes current, completed and upcoming steps through labels and checkmarks. Replay, slow motion, play all and restart remain in the menu. Turns animate over 0.42 seconds normally or 1 second in slow motion.

## Do's and Don'ts

- **Do** preserve one clear next action and readable physical-cube orientation guidance.
- **Do** retain undo, erase, review, validation, previous/next moves, replay and cancellation.
- **Do** retain accessible color names, non-color selection cues, native navigation and scrollable content.
- **Don't** introduce camera scanning into the current flow.
- **Don't** allow orbit gestures to move the painting view or paint an adjacent visible face.
- **Don't** imply that source inspection, a concept image or an isolated screenshot proves complete flow, accessibility or physical-device validation.
