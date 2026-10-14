# Beginner learning and four-section navigation

## Method

Learn uses the user's manually entered cube, shared with Solve during the current app session. The introductory screen explains centers, edges, corners, notation and the actual front/top center colors. A practice cube is explicit and replacement of entered colors requires confirmation.

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

Learning introduces one pattern at a time, with a stage goal, expandable reason, move notation and plain-language color-based instruction. The fixed bottom tray holds previous/next controls. At stage boundaries the user checks their physical cube. A cube finished during an early stage gets the full completion message. Piece inspection reuses the existing live cube, with white source and blue destination outlines. Replay, slow motion and an optional “I did this move” mode support practice without first watching an animation.

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
