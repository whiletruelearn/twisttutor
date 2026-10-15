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

Verification boundary: this document records the current source. Package tests and simulator builds establish different evidence from rendered UI checks. Physical-device, iPad, Dynamic Type and complete flow verification remain pending; screenshots of individual screens do not establish coverage of other states. See the surface brief for the current validation record.

## Colors

Use the shared strong primary blue (`CubeStyle.action`) for the main drawer action, navigation/drawer tint and current solution step. Primary buttons and the current step use white text.

The stage token is shared by SwiftUI and the RealityKit background so the viewport has no visible panel boundary. Use white stage headings and the pale blue-gray secondary token for instructions. Drawers explicitly use the light color scheme and `systemBackground`, with semantic primary text and the drawer-secondary token for secondary copy; the drawer token represents that current light surface.

Cube colors are functional data, defined by `CubeColorID.uiColor` in `CubeScene.swift`. Keep all six color names visible in the palette. Selection also uses a checkmark and a tinted container. Completion and errors pair semantic green/red with text or symbols; color alone must not carry status.

## Typography

Use system fonts and semantic SwiftUI text styles. Solve and Learn home headlines use bold rounded `largeTitle`; entry, solution and timer stage headings use bold rounded `title2`. The large move notation also uses the rounded system design. Body instructions use `body` or `subheadline`; buttons and action descriptions use `headline`; palette labels and counts use `caption2`. Counts use monospaced digits and step notation uses a monospaced body style.

Preserve Dynamic Type through semantic text styles. Avoid replacing this hierarchy with fixed point sizes or a custom typeface.

## Layout

Center the workspace at a maximum width of 700 points. Home uses a flexible cube viewport between its heading and drawer. Entry and solution use vertical scrolling and geometry-dependent viewport heights, keeping a minimum visible cube area while allowing guidance to extend below the fold. Solution playback controls occupy a fixed bottom safe-area tray, outside the scrolling lesson content. Learn home, its introduction and the timer use scrollable content; Settings uses a native Form.

Entry reserves 360 points for painting controls on every face, 220 while inspecting, or 480 at accessibility text sizes; its viewport minimum is 240 points. Solution uses a 220-point viewport minimum, subtracting 260 points for quick solving, 430 for teaching, or 500 at accessibility text sizes from the available geometry height. These are current layout values, not proof of device coverage.

Use the established 20-point drawer inset and 24-point heading inset. The palette changes from six columns to three at accessibility text sizes. The solution strip scrolls horizontally, centers the current step and uses a scaled 72-point base height. Do not shrink text to force all controls into a single viewport.

## Elevation & Depth

Depth comes from the actual 3D cube and the tonal separation between stage and drawer. The UI uses no decorative drop-shadow system. Edge tools sit on translucent white fills at 10% opacity. Keep the live cube geometry; generated artwork is not a substitute for the interactive object.

## Shapes

Use the drawer and primary radii from the tokens. Entry edge tools are 58-point squares with the entry-tool radius; the solution reset control is a 48-point square with a 14-point radius. Swatches have softly rounded corners and a subtle dark outline. The six face-progress indicators use thin capsules; solution step tiles use a 10-point radius.

## Components

- **Primary action:** full available width, headline text, horizontal padding of 20 points and minimum height of 52 points. Pressed opacity is 80%. Disabled buttons use secondary text and a 16%-opacity gray fill. Keep the main action specific: “Continue,” “Review cube,” or “Show next move.”
- **Native navigation:** the four root tabs are “Solve cube,” “Learn,” “Time solving” and “Settings.” Each owns a `NavigationStack`; root tab bars explicitly use a white background and light color scheme. Cube workspaces use inline titles and a dark navigation bar matching the stage; entry, lesson introduction and playback hide the tab bar. Settings retains the native Form presentation. Put help, examples and playback options in the trailing menu. Destructive clearing uses a confirmation dialog.
- **Entry workspace:** the face strip is both progress and navigation, with accessible filled counts and selected traits. Painting locks the view to the named face and accepts 3D sticker taps only on that face. Inspect and review allow orbit while disabling 3D painting. “Back to painting” restores the focused face. Keep Undo and Inspect/Reset on the edge rail.
- **Orientation guidance:** painting copy directs users to Inspect to understand how to hold the cube. Top and bottom painting retain the oblique 3D view and Inspect control. The separate neighboring-color strip was removed at the user’s request because it was confusing. Holding instructions in Learn and playback use the actual front and top center colors; do not assume fixed center colors.
- **Accessible entry alternative:** “Help & sticker buttons” opens a native sheet with orientation instructions, a labeled 3×3 sticker grid, palette and validation feedback. Each sticker exposes face, position, color and painting/erasing hint. The viewport has directional accessibility actions that respect the orbit lock. These are implemented alternatives; assistive-technology usability still needs device verification.
- **Review and solving:** surface validation before enabling the solve action. Keep calculation progress and cancellation visible. During playback show the active or next move with a plain-language direction, previous-step control and next/pause action in the fixed bottom tray. The step strip distinguishes current, completed and upcoming steps through labels and checkmarks. Replay, holding help, slow motion and restart remain in the menu; Play all is available for quick solving. Turns animate over 0.42 seconds normally or 1 second in slow motion. The saved slow-motion preference defaults to on and initializes both Solve and Learn playback.
- **Learn:** reuse the entered cube from Solve during the current app session. Offer color entry/editing, “Learn with this cube” for a valid cube, and a practice cube with replacement confirmation when colors already exist. The introduction explains holding position, centers/edges/corners and notation before playback. Teaching shows the stage goal, a named pattern, expandable “Why this pattern works” guidance and only the current pattern’s move strip. Stage boundaries open a comparison checkpoint. “Try without animation” changes the primary action to “I did this move.”
- **Inline piece inspection:** “Find the … edge/corner” keeps the same 3D cube visible and replaces the lesson drawer with piece guidance. White outlines identify the piece’s current stickers; blue outlines identify its destination. Explain the current faces and matching centers in text, including when the piece is home but incorrectly oriented. Hide the normal turn guide during inspection and replace playback controls with “Back to the moves.” Checkpoints and holding help use sheets; piece inspection stays inline.
- **Timer and settings:** Time solving uses a large monospaced timer, a single Start/Stop action, optional discard, all-time personal best and the ten most recent solves. Store up to 100 recent times locally and retain the all-time best separately. Prevent automatic screen sleep during an active attempt. Leaving the screen or backgrounding interrupts and discards the active attempt. Settings exposes the default slow-animation preference and confirmed clearing of saved times and personal best.

## Do's and Don'ts

- **Do** preserve one clear next action and readable physical-cube orientation guidance.
- **Do** keep the cube visible while explaining a teaching piece and keep playback actions reachable in the bottom tray.
- **Do** retain undo, erase, review, validation, previous/next moves, replay and cancellation.
- **Do** retain accessible color names, non-color selection cues, native navigation and scrollable content.
- **Don't** introduce camera scanning into the current flow.
- **Don't** allow orbit gestures to move the painting view or paint an adjacent visible face.
- **Don't** imply that source inspection, a concept image or an isolated screenshot proves complete flow, accessibility or physical-device validation.
