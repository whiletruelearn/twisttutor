# Cube first

Approved by the user on 14 October 2026: “let's go with cube first approach”.

Audience: first-time solvers; clear guidance and one action at a time. The approved image is a directional reference, not a functional screen. Live geometry, legible color labels, fixed painting orientation and accessible controls take precedence over its decorative cube icons and placeholder text.

## Approved direction

- Navy object stage across Solve and Learn, entry and playback.
- Cube centered with an unobtrusive edge tool rail.
- Native navigation with secondary commands in menus.
- Compact instruction and light control trays; playback actions stay fixed at the bottom while lesson guidance scrolls.
- Paint mode fixes orientation; Inspect allows orbit and blocks painting.
- Solver, validation, undo, previous/next moves, replay and cancellation remain available.

No camera entry point. No generated image is used in place of the interactive cube.

## Current surfaces and behavior

The four root tabs are **Solve cube**, **Learn**, **Time solving** and **Settings**. Root tab bars have an explicit white background and light color scheme. There is no separate “Just explore” action. Solve and Learn share one `ManualCubeEntry` instance for the current app session; this is not a claim of saved cube restoration after relaunch.

**Solve cube** opens manual color entry. The face strip selects a face and reports its completion. Painting stays locked to that face; Inspect provides an orbitable preview and a “Back to painting” action. The painting hint explicitly points to Inspect. For top and bottom faces, four labeled neighboring-color groups show the adjacent three-sticker row from Front, Right, Back and Left. The Help sheet retains labeled sticker buttons as an alternative to 3D painting. Review validates the entered state before calculating a quick solution.

**Learn** offers the shared valid cube, color entry/editing, and a practice cube; replacing existing colors requires confirmation. Its introduction establishes holding position from the actual center colors, explains the piece types and move notation, and identifies an already-solved cube. `BeginnerSolver` generates a deterministic layer-by-layer teaching plan for the entered cube. It searches stage-specific move patterns, verifies each milestone and the final solution, and skips stages already satisfied. Its seven stages are:

1. Make the first cross.
2. Finish the first layer.
3. Fill the middle layer.
4. Make the top cross.
5. Finish the top color.
6. Place the top corners.
7. Place the last edges.

Teaching playback shows the stage goal, the current named pattern, an expandable explanation, the pattern’s moves and a plain-language instruction tied to the actual center color. A stage checkpoint asks the learner to compare the physical cube with the model. Previous step, replay, reset view, holding help and restart support recovery. “Try without animation” lets the learner confirm each physical move. Quick solving additionally offers Play all.

**Piece inspection stays inline on the same 3D cube.** The Find action hides the turn guide, outlines the current piece in white and its destination in blue, and replaces lesson copy with current-position and destination guidance. It identifies a piece already in its home position but still needing orientation. The fixed bottom action becomes “Back to the moves.” Piece inspection does not open a separate sheet; holding help and milestone checkpoints still do.

**Time solving** stores up to 100 completed times locally, displays the latest ten, preserves the all-time best separately, prevents automatic screen sleep while running, and supports discarding an active attempt. Navigating away or backgrounding interrupts the attempt without saving it. **Settings** offers the slow-animation preference (on by default), local-processing information and confirmation before clearing saved solve times and personal best. Both Solve and Learn initialize playback from that preference.

## Validation record and limits

The final implementation handoff reports **78 release package tests passing**, including 500 seeded 25-turn scrambles, stage preservation, piece metadata, remapped centers, solved input, deterministic output, invalid input, cancellation and an early-finish fixture. The final iPhone 16e simulator build passed after all edits. See `Docs/BeginnerLearning.md` for the detailed method and QA record.

Simulator interaction verified the practice-cube Learn route, lesson generation, introduction, first pattern and inline piece/destination rendering. Manual top-face selection showed all four adjacent-color groups and the Inspect hint. `Screens/learn/lesson.png` and `Screens/learn/piece-inline.png` are live simulator captures; the latter replaces the rejected blank-sheet evidence. `Screens/learn/top-entry.png` predates the final viewport-height adjustment and establishes reference groups and orientation, not final spacing.

The finish review’s disposition is **ship**: blank inspection was resolved visually, top-cross wording was corrected in source, and early completion was corrected in source with a model test. This clears the identified defects without claiming full flow or device validation.

Final orbit/return interaction, a complete solve, timer/settings interactions, physical-device, iPad, Dynamic Type and VoiceOver verification remain pending. Simulator control intermittently failed, limiting interactive coverage. Automated solver checks, compilation and individual simulator screenshots are separate evidence layers; none substitutes for following the teaching flow with a physical cube.
