# Beginner learning and four-section navigation

## Method

Learn uses the user's manually entered cube, shared with Solve during the current app session. The introductory screen shows the actual front/top center colors and lets learners select Centers, Edges or Corners to highlight an example directly on their cube. A practice cube is explicit and replacement of entered colors requires confirmation.

`BeginnerSolver` is independent of `QuickSolver`. It builds the bottom cross, bottom corners, middle edges, top cross, top color, top corner positions and top edge positions. Bottom/top refer to the user's established orientation, never hardcoded white/yellow faces.

- Cross: outer face turns, searched on the four bottom edges.
- First corners: top alignment and rotated three-move corner insertions (including inverse variants), preserving the cross at pattern boundaries.
- Middle edges: top alignment and rotated eight-move insertion patterns (including inverses), preserving the first layer.
- Top cross: rotated six-move edge-orientation patterns.
- Top color: rotated seven-move corner-orientation patterns.
- Top corners: rotated corner-swap patterns, preserving orientation and the bottom two layers.
- Top edges: rotated edge cycles, preserving corners.

The first three stages use bidirectional searches over projected piece positions and orientations. Last-layer searches choose from stage-specific patterns. Search is deterministic, runs off the main actor, checks cancellation and a 30-second overall deadline, and has a state-count limit. Failure remains an error; it never silently substitutes a quick-solver plan.

Every milestone is checked on the complete cubie state. The full sequence then passes the independent facelet replay verifier before presentation. Completed stages are skipped. Metadata groups moves by pattern and tracks an actual piece through its physical sticker identities, with destination indices derived from canonical geometry.

## Experience

Four native tabs: Solve cube, Learn, Time solving and Settings. The standalone Just explore entry is removed. Top/bottom painting uses the existing oblique 3D view. The separate neighboring-color strip was removed at the user’s request. The main hint directs users to Inspect.

Learning starts with an interactive 3D goal preview computed from the end of the current stage in the verified plan. This is explicitly labeled as a preview and does not advance playback. Returning to the current cube shows one color-based turn instruction and progress through the stage. “See goal,” “Find piece,” “Why?” and “All moves” reveal supporting information on demand; the main screen does not require reading notation. The move sequence remains available with its current/completed indicators. The fixed bottom tray holds previous/next controls. At stage boundaries the user checks their physical cube. A cube finished during an early stage gets the full completion message. Piece inspection reuses the existing live cube, with white source and blue destination outlines. Replay, slow motion and an optional “I did this move” mode support practice without first watching an animation.

The manual timer stores the most recent 100 times locally, displays 10 recent results, and keeps an all-time personal best separately. It prevents automatic screen sleep while timing. Backgrounding or leaving the timer discards an unfinished attempt, with an explanation on return. Settings stores slow-animation preference and confirms clearing timer history/best. Cube entry and lesson progress are not yet persisted across app termination (ENG-621 remains broader follow-up scope).

## Verification — 14 October 2026

- 78 release Swift-package tests passed. New teaching coverage includes 500 seeded 25-turn scrambles, stage preservation, piece metadata, remapped centers, solved input, deterministic output, invalid-input rejection, cancellation, and a cube solved before later stages begin.
- iOS simulator build passed with Xcode 26, iPhone 16e / iOS 26 destination.
- Simulator interaction verified the Learn practice-cube route, actual-cube lesson generation, introduction, first pattern, and inline piece/destination rendering. Manual top-face selection showed all four adjacent-color reference groups and the Inspect hint.
- `Docs/Design/Screens/learn/lesson.png` and `piece-inline.png` are live simulator captures. `top-entry.png` is historical and includes the neighboring-color strip that has since been removed.
- No final full solve, timer/settings interaction, iPad, Dynamic Type, VoiceOver or physical-device verification is claimed. Simulator control intermittently returned noWindowsAvailable/empty accessibility state; orbit and return from the final inline inspection remain unverified interactively.
- Native source detector reported no findings. This is not a substitute for UI testing.

### Finish-review verdict: ship

| Material fix | Verdict |
| --- | --- |
| Blank piece-inspection viewport | Resolved visually: existing live cube, source/destination outlines and fixed return action visible |
| Rotated top-cross explanation | Resolved in source: orientation-neutral wording |
| Completion after an early stage | Resolved in source and covered by early-finish planner fixture |

The review clears these defects; it does not establish end-to-end or device validation.

## Device check

1. Enter a real mixed cube in Solve, then open Learn and reuse those colors.
2. Check Up/Down orientation using the 3D view. Inspect, return to painting, and confirm the colors stay unchanged.
3. Start the lesson, inspect a piece, orbit, return, advance and go back. Confirm the displayed face/arrow and physical moves agree.
4. Follow a complete lesson and compare at every milestone. Also try a cube one bottom turn from solved to check the early completion message.
5. Start/stop the timer, relaunch to check saved times, interrupt an attempt, and verify clearing history and animation-speed settings.

## Visual learning refinement — 15 October 2026

Removed the seven-row roadmap from Learn home, the dense notation/definition introduction, and the always-visible pattern explanation and move strip. Their jobs are now handled by the interactive introduction, stage goal preview, optional explanation and optional stage sequence. The underlying beginner solver and move playback engine are unchanged.

The stage preview uses a separate cube scene replayed from the verified solution’s initial state through the last move of that stage. Showing and dismissing it cannot change the learner’s current cube. At checkpoints, confirming or dismissing advances to a preview of the next available stage; choosing to check the last moves keeps the playback screen.

Validation: simulator build and all 3 focused playback regression tests passed. `Docs/Design/Screens/visual-learning/move.png` records the compact move screen. Simulator checks covered the practice-cube route, centers/edge highlighting, first-stage preview, returning without advancing, next move and previous move. Full lesson completion, later-stage transitions, iPad, accessibility sizes, VoiceOver and physical-device learning remain manual checks.

## Teacher-style lessons — 15 October 2026

Learn now follows how a person would teach the cube across a table.

- **Meet your cube (lesson 0):** five short pages. Hold the cube (centers never move), edges have two colors, corners have three, how turns are described (with the on-cube arrow), and the plan: bottom, middle and top layers.
- **Goal briefing:** each of the seven goals opens with what we're making and why, one tip for the mistake beginners usually make, and "you're done when…" written for the cube in your hands. All wording uses the learner's own center colors.
- **One piece per lesson:** the solver now groups turns by teaching intent (`BeginnerLesson.setupMoveCount`, `placesPiece`). Cross and first-layer corners get one lesson per piece placed, including repeated corner triggers. Middle edges get one lesson per pattern, and a pattern that frees a stuck edge is taught as "Lift out the … edge". Last-layer stages get one lesson per pattern, with leading top-layer alignment shown as "Get ready".
- **Turns in hand words:** `CubeMove.spokenInstruction` / `handHint` / `shortLabel` ("Turn the right side up", "Top ←"). `testSpokenDirectionsMatchGeometry` checks them against the cube geometry. Notation is still available from the ⋯ menu.
- **Checkpoints:** celebrate, ask the learner to check the physical cube, preview the next goal, and give recovery advice when it doesn't match.
- Copy lives in `CubeSolver/BeginnerCoaching.swift`.

Validation: 81 package tests passed, including coaching tests and a check that the practice cube exercises all seven goals. The simulator build passed. Static simulator screenshots (via a temporary debug launch hook, since removed) covered intro pages, goal briefing, corner and middle lessons, and the checkpoint, plus the checkpoint, "How it works" and holding-help sheets in dark mode (sheets now follow the system appearance on a solid background, and the checkpoint sheet is driven by its stage item). Tapping through a full lesson, VoiceOver, Dynamic Type and physical-device checks were not done.
