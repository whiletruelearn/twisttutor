# TwistTutor: Cube Solver

An offline iOS cube solver and beginner tutor, under development. ENG-595–598 establish the cube foundation; ENG-599–601 add an offline two-phase solver and independently verified results. ENG-602–603 add an interactive RealityKit cube with animated turns. ENG-604 adds manual color entry with validation, verified solving and solution playback. The app opens the cube explorer; **Enter cube manually** opens the camera-independent test flow. ENG-605–607 add guided six-face camera capture and quality-gated raw samples. Color classification, scan-to-solve, full instructional solving and lessons remain subsequent milestones.

- Display name: `TwistTutor: Cube Solver`
- Bundle identifier: `com.serendipitylabs.twisttutor`
- Deployment target: iOS 17.0; iPhone and iPad
- Development: Xcode 16 or later with Swift 6; current local verification uses Xcode 26
- No external package dependencies, accounts or networking. Camera permission is requested only when opening the scanner.

Open `TwistTutor.xcodeproj`, select a simulator and run the `TwistTutor` scheme. For physical devices, select your Apple development team in Signing & Capabilities. App icons and release configuration are tracked separately.

## Architecture

| Boundary | Responsibility | Status |
| --- | --- | --- |
| `TwistTutor/App` | SwiftUI app composition and session ownership | Implemented |
| `TwistTutor/Features/Home` | Cube explorer and entry points to manual solving and scanning | Implemented |
| `TwistTutor/Features/ManualEntry` | 54-sticker entry, validation and verified solution playback | M4 integration harness implemented |
| `Packages/TwistTutorKit/Sources/CubeCore` | Models, notation, integer geometry, turns, conversion, capture orientation | Implemented; independent of UI and camera |
| `Packages/TwistTutorKit/Sources/CubeValidation` | Color checks, piece uniqueness and physical legality | Implemented; depends only on CubeCore |
| `Packages/TwistTutorKit/Sources/AppWorkflow` | Main-actor session, scan sampling/quality and cancellation | Implemented; core, validation and solver dependencies |
| `TwistTutor/Features/Scan` and AppWorkflow scan types | AVFoundation lifecycle, Vision/Core Image sampling, quality gates and six-face workflow | M5 capture implemented; physical-device validation and ENG-608 classification pending |
| `Packages/TwistTutorKit/Sources/CubeSolver` | Offline two-phase search, bundled tables and independent verification | Implemented; solution presentation is M7 |
| `TwistTutor/Features/Cube` | Non-AR RealityKit cubies, orbit, hit testing, highlights and slice animation | M3 implemented; correction UI remains M6 |
| Teaching / Features/Learn / Features/Practice | Beginner plans, explanations and practice | M8/M9; separate from quick solver |
| Persistence | Local preferences, learning progress and history | Later issue; no image storage introduced here |

Future boundaries are documented contracts, not empty modules or placeholder implementations. Implementations must preserve the dependency direction toward CubeCore. Camera state does not belong in a cubie, and view state does not belong in a camera adapter.

`AppSession` represents all specified phases from Idle to Completed. Accepted faces are ordered, duplicate completions are ignored, and validation gates cube readiness. Leaving/restarting cancels the owned task and invalidates its operation token. Even an adapter that ignores cancellation cannot overwrite a newer session. A failed capture returns to Scanning with retry feedback. Solve and Learn remain distinct modes. Solution calculation returns a `VerifiedSolution` bound to the exact initial cube. Its initializer is unavailable to callers: only independent facelet replay can create one. `AppSession.calculateSolution` exposes verified moves, handles retry/cancellation and rejects results from another scan. Solving uses a detached task and forwards cancellation into its bounded search. No solver work or table I/O runs on MainActor.

## Cube conventions

All facelets use **U, R, F, D, L, B** face order, each with nine row-major positions viewed **directly from outside that face**. Public array offsets are zero-based; conventional labels U1…B9 are one-based. Center offsets are 4, 13, 22, 31, 40, 49.

World axes are +X right, +Y up, +Z front. Face-local basis vectors fix orientation at the back, top and bottom:

| Face | Outward normal | Image right | Image down | Face at image top |
| --- | --- | --- | --- | --- |
| U | +Y | +X | +Z | B |
| R | +X | −Z | −Y | U |
| F | +Z | +X | −Y | U |
| D | −Y | +X | −Z | F |
| L | −X | +Z | −Y | U |
| B | −Z | −X | −Y | U |

Clockwise means looking directly at the turning face: a −90° rotation around its outward normal. `CubeMove` stores a typed face and turn amount; notation accepts only U/D/L/R/F/B with optional `'` or `2`. Unsupported tokens fail as a whole. Geometry generates the facelet permutation once. Cubie moves compose destination-to-source piece permutations and add orientations modulo three/two.

Corner order is `URF UFL ULB UBR DFR DLF DBL DRB`; edge order is `UR UF UL UB DR DF DL DB FR FL BL BR`. The ordered faces in each identifier define orientation. Component zero is the reference sticker; orientation is the destination component index occupied by that reference. Corner matching permits cyclic rotations, **not reflections**. These conventions match the mathematical descriptions in [Kociemba's facelet reference](https://kociemba.org/math/faceletlevel.htm) and [cubie reference](https://kociemba.org/math/cubielevel.htm). This project uses an original integer-geometry implementation, not third-party solver code.

Colors are relative to the six observed centers. No direction is permanently white, green or another named color. `CubeState.solved()` supplies a default color scheme for fixtures, but callers can supply any six distinct center colors.

### Capture-to-model mapping

Capture order is F → R → B → L → U → D. Preserve U at the top of the four side captures. For top/bottom capture, first return to the initial F-facing pose; tilt U toward the camera with B at the image top, or D toward the camera with F at the image top. These prescribed, upright images require no additional rotation. Capture guidance will implement these poses in M5.

Every `CapturedFace` explicitly declares its logical face and the clockwise image rotation needed to reach the canonical basis. `CaptureAssembly` reorders by identity, applies those rotations, and rejects duplicate or missing faces. It **does not infer** orientation from arbitrary photos. A future import review must supply the confirmed assignment/rotation. Source-image points remain normalized coordinates in the original image, even when the sticker moves logically.

### Validation and metadata

`CubeFace`/`CubeState` reject malformed lengths. `CubieState` rejects malformed lengths and out-of-range values but permits physically impossible states to be diagnosed. Validate raw observations with `validateColors`, then use `CubeValidator.validate` for unique corners/edges, orientation sums and matching permutation parity. Shape alone is never proof of legality. Structured diagnostics contain friendly messages; unknown-piece diagnostics identify implicated sticker indices.

`CubeConversion.cubies` is a mathematical projection and does not include scan metadata. Use `CubeEncoding` for a **lossless** bridge: it stores the observation catalog by physical sticker identity so UUID, confidence, alternate colors and source coordinates survive conversion and subsequent moves. `facelets(from:centerColors:)` constructs fresh observations for fixtures. Do not use that color-only helper to replace an actual scan.

## Verification

Run the portable XCTest suite without launching a simulator:

```sh
TWISTTUTOR_SOLVER_CASES=1000 swift test -c release --package-path Packages/TwistTutorKit --enable-code-coverage
```

Run the same test sources on iOS using Product → Test in the `TwistTutor` scheme, or choose an installed simulator:

```sh
xcodebuild -project TwistTutor.xcodeproj -scheme TwistTutor \
  -destination 'platform=iOS Simulator,name=iPhone 16e,OS=26.0' \
  CODE_SIGNING_ALLOWED=NO test
```

If command-line tools point at a different Xcode, set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for the command. CI runs the release package suite (including 1,000 solve/replay cases), regenerates and compares the bundled tables, and builds the simulator app.

The suite covers all 18 turns, fixed quarter-turn fixtures, move inverses, noncommuting moves, a known algorithm identity, 1,000 reproducible 30-turn scrambles, metadata-preserving conversions, capture rotations, invalid colors/centers, reflected/duplicate pieces, single flipped edges/twisted corners, permutation parity, correction revalidation asynchronous cancellation races, invalid solver output, resource corruption, concurrent solves, explicit search limits and stale solution results. Solver regression includes 1,000 seeded scrambles plus 50 directly sampled reachable cubie configurations, independent of scramble generation.

Support assumptions: iOS 17+ on iPhone/iPad; macOS 14+ is a **test host**, not a shipping app target. Minimum-OS device validation and older-device camera/solver/renderer benchmarks remain outstanding. Simulator/core tests do not establish physical scanning accuracy or release performance.


## Offline solver design and selection

`QuickSolver` validates the cube, searches for at most 12 moves to orient the pieces and put the four middle-slice edges in their slice, then searches at most 18 moves using U/D turns and R2/F2/L2/B2. It accepts the first verified solution rather than searching for global optimality. Typical lengths are approximately 20–30 face turns. The approach follows the published [two-phase algorithm](https://kociemba.org/math/twophase.htm) and [pruning-table principles](https://kociemba.org/math/pruning.htm); the Swift implementation, coordinate encoding, generator and tables are original to this repository.

Each search owns its mutable paths and counters; immutable tables are loaded once from the local SwiftPM resource bundle. The default bound is 50 million visited nodes or 10 seconds, checked with cooperative cancellation every 1,024 nodes. Limits are a safety bound, not the product's two-second latency target. Failure returns an error and never a partial solution. Solved input returns an empty verified sequence without loading tables. The final replay uses the existing facelet engine, independently of solver coordinates. Tests reject deliberately wrong output before it reaches guidance.

### Dependency/license decision (14 October 2026)

| Option / reviewed revision | License evidence | Decision |
| --- | --- | --- |
| Original Swift implementation / table format `TT2PH001` | No third-party implementation or table data copied; project source is governed by this repository's own distribution policy | Selected: native integration, explicit cancellation, small bundled tables, existing core conventions |
| cubejs / `6b3da493894d9aed54f4c8aafccadbe676e745b5` | [Full MIT license and copyright notice](https://github.com/ldez/cubejs/blob/6b3da493894d9aed54f4c8aafccadbe676e745b5/LICENSE); permits commercial use with notice retention | Not integrated: would require a JavaScript runtime bridge or a separately maintained port |
| RubiksCube-TwophaseSolver / `0c1ea6233cb2d4f294bc97077b60265ba76f3616` | [Full GPL-3.0 license](https://github.com/hkociemba/RubiksCube-TwophaseSolver/blob/0c1ea6233cb2d4f294bc97077b60265ba76f3616/LICENSE) | Not integrated: Python runtime/port plus GPL distribution obligations |
| min2phase / `4d183b9eff8119cac72bc50ef35a7d8990740e06` | [GPL notice in source header](https://github.com/cs0x7f/min2phase/blob/4d183b9eff8119cac72bc50ef35a7d8990740e06/src/Search.java) | Not integrated: Java runtime/port plus GPL distribution obligations |

These alternatives are not shipped, so their code, data and notices are not dependencies of the app. GPL is not a prohibition on commercial use; it was not selected as the licensing model for an embedded dependency. This decision does not add an open-source license to the app.

### Bundled data and regeneration

`CubeSolver/Resources/TwoPhaseTables.bin` contains six UInt16 transition tables and four UInt8 pairwise distance tables. Payload size including header/checksum is **5,815,285 bytes** (about 5.55 MiB). Its format has a magic/version, fixed dimensions, little-endian integers and SHA-256 checksum; the loader rejects wrong sizes, versions, checksums, transition ranges or distance bounds. Resources never come from the network or the user's filesystem.

SHA-256 of the complete version-one file:

```text
a44255f8ac90537c76c06893fb8c9d59594239b0abd2074ecb7d0590454b3a4b
```

Regenerate independently and compare before updating a table-format version:

```sh
swift run -c release --package-path Packages/TwistTutorKit SolverTools generate /tmp/TwoPhaseTables.bin
cmp Packages/TwistTutorKit/Sources/CubeSolver/Resources/TwoPhaseTables.bin /tmp/TwoPhaseTables.bin
```

Generation took approximately 0.32 seconds on the development Mac; it is a development/CI operation, never a first-launch requirement. The resource bundle is copied into the iOS build, so the first solve needs no downloads or generated cache. Table changes require a new format version if their coordinate meanings or layout change.

### Measured performance and limits

Fresh-process release benchmark on Apple M4 / macOS 15.6.1, 1,000 deterministic 30-turn scrambles (a simulator build was also running on the host):

| Measure | Result |
| --- | ---: |
| First solve, including table load | 39.13 ms |
| Warm median / p95 / maximum | 2.54 / 15.22 / 124.00 ms |
| Solution length, min / mean / max | 11 / 22.99 / 26 moves |
| Peak resident process memory | 16,924,672 bytes |

Fresh-process iPhone 16e **Simulator**, iOS 26.0 on the same Mac, Release XCTest with coverage enabled, 100 scrambles: first solve **16.78 ms**, warm median/p95/maximum **3.88/44.86/72.22 ms**, mean **23.03** moves (max 26). Peak resident memory **152,371,200 bytes** includes the simulator XCTest runner; it is not solver-only or physical-device memory.

Reproduce a cold host benchmark in a new process:

```sh
swift run -c release --package-path Packages/TwistTutorKit SolverTools benchmark 1000
```

For a cold simulator benchmark, run only `TwistTutorTests/SolverBenchmarkTests` in a fresh Release test process with `ENABLE_TESTABILITY=YES` and `ONLY_ACTIVE_ARCH=YES`. Running the benchmark after other tests is a warm-table measurement.

No physical iPhone was available during this slice. The approximately two-second target is comfortably met on the measured host/simulator; it remains **unverified on supported physical iPhones**, especially the oldest supported devices. The solver is now connected through the M4 manual-entry route. Full instructional solving remains M7.


## Interactive cube (ENG-602–603)

The explorer is a working renderer demonstration, with solved and deterministic mixed examples. It does not yet capture or solve a physical cube.

On an iPhone or iPad:

1. Drag the cube to orbit it; **Reset view** restores the front/right/up instructional angle. Camera movement never changes notation or logical state. VoiceOver users can use the cube’s Rotate view left/right/up/down custom actions.
2. Tap a sticker to see its color and canonical face/position. Turn on **Highlight selected piece** to outline that cubie's stickers. Face buttons select the corresponding face; center letters identify it on the model.
3. Choose Clockwise, Counterclockwise or Half turn, then **Turn**. The highlighted face and curved arrow indicate the turn, viewed from outside that face. Normal animation is 420 ms; **Slow motion** uses 1,000 ms.
4. **Replay** animates the same last turn from its original starting state and leaves the result unchanged. All mutating controls are disabled during playback. Leaving the app cancels an unfinished turn and restores the last committed state.
5. Use **Examples** in the navigation bar to load a solved or mixed cube. This clears replay history. Scroll the controls on small screens or with large text; the Turn button stays visible at the bottom.

`CubeRenderLayout` exposes the core's canonical positions and face bases without duplicating facelet conventions. Each of 26 visible cubies owns its body, sticker meshes and center label. Nine cubies are reparented to a pivot for each turn. The renderer samples a signed axis-angle over time (including a clockwise 180° path), then rebuilds the exact canonical endpoint to avoid floating-point accumulation. Non-AR rendering never requests camera access.

`CubePlayback` owns logical state and issues unique turn tokens. It rejects overlapping starts, commits only completed tokens, rejects stale completion after reset/cancel, and stores the source/target for replay. `CubeScene` owns rendering and camera state, cancels its task on background/detach, and never changes cube state from hit testing or orbit. The component accepts any `CubeState`, including nonstandard center colors.

Verification: 48 package tests passed on macOS and 48 native tests passed on iPhone 16e Simulator / iOS 26. Geometry tests transform every sticker with the same signed quaternion used for rendering across all 18 turns and a mixed sequence, checking both position and outward normal against core permutation results. Playback tests cover repeated replay, overlaps, cancellation, replacement and stale completion. Simulator UI checks cover actual rendering, turns, replay, sticker/piece selection, example loading, camera orbit through accessibility actions and instructional-angle reset; physical-iPhone performance and gestures remain to be verified because paired devices were unavailable. Simulator automation delivered attempted drags as taps, so drag-orbit is implemented but not counted as a verified gesture.

Simulator captures: [iPhone mixed cube](Docs/Renderer/iphone.png) · [iPad solved cube](Docs/Renderer/ipad.png).


## Manual entry → verified solve → animation (ENG-604)

Open **Enter cube manually** below the explorer. This is the explicit M4 test route, available in normal builds; it needs no camera or developer settings.

1. Choose the physical cube's Up and Front faces and keep those names fixed. Pick a face tab, look straight at that face and keep the indicated neighboring face at its top edge. The top-edge hints use the core's canonical orientation, including Back above Up and Front above Down. Expand **How to orient the cube** for the holding reminder.
2. Select a named color and tap stickers in the 3×3 grid. All 54 stickers, including centers, are editable. Entries start empty, and **Erase** returns a sticker to empty. Six counters track the color totals; centers are not tied to a preset color scheme.
3. Finish all six faces. Validation checks counts, unique centers, real piece identities, edge flips, corner twists and permutation parity. Invalid input cannot reach the solver. Details identify suspect pieces where possible; the screen distinguishes incomplete entries from impossible states.
4. Tap **Validate & solve**. A verified solution opens the rendered cube with **Next move**, **Play solution**, **Pause**, **Slow motion**, **Replay last** and **Restart**. Completion requires consuming every verified move and a logically solved endpoint. An already-solved input needs zero moves.
5. Pause/backgrounding cancels the in-flight turn and restores the last committed endpoint. Resume retries that move. Replay does not advance the move counter. Returning to entry preserves the colors and discards the old result; editing, clearing or loading an example invalidates pending solver work.

The entry options menu provides solved/mixed fixtures and confirmed clearing for testing. The mixed fixture is `R U R' U' F2 D L2 B`. For a quick rejection check, load the solved example and recolor one sticker: the counts become invalid and solving is disabled. Restore it to verify the zero-move path, or load the mixed example to play a complete solve.

`ManualCubeEntry` holds optional stickers, preserving unfilled state and stable identities. `AppSession.enterManually` validates a supplied snapshot and cancels previous operations without pretending it came from camera captures. `CubePlayback(solution:)` accepts only verified plans and disallows arbitrary face turns while following a plan. Renderer completion tokens advance the plan; stale or cancelled completions cannot skip moves. No camera recognition, physical-cube recovery guidance, persistence or teaching is introduced by this slice.

Validation: **55 package tests and 55 native iPhone simulator tests passed**. New coverage includes all 54 manually entered colors with a nonstandard center scheme, invalid colors/centers/flipped edges rejected before solver invocation, stale results after edit/clear, pause/restart/replay/overlap, canonical orientation hints and zero-move completion. Physical-iPhone gesture and performance checks remain pending; paired devices were unavailable.

Native simulator checks exercised painting a sticker, invalid-count rejection and correction, the zero-move path, and a 19-move mixed-cube solve to the visibly solved endpoint. A navigation-time blank viewport found during testing was fixed by maintaining camera pose during RealityKit scene updates.

Screenshots: [manual editor](Docs/ManualEntry/entry.png) · [verified solution ready to play](Docs/ManualEntry/solution.png).

## Guided camera capture (ENG-605–607)

Open **Scan your cube** from Home. Hold the device in portrait and show one complete face. Once the detected face passes the quality checks and remains stable for 0.85 seconds, it is captured automatically. Follow the rotation diagram, then tap **I’m ready** for each next face. The order is Front → Right → Back → Left → Top → Bottom. After six captures, review the sampled nine-color grids or retake from any face (which discards that face and all later captures).

This slice ends at raw sampled colors. It does **not** classify the 54 colors, reconstruct a validated cube or solve a camera scan; those belong to ENG-608 and the review/correction slice. Manual entry remains available for verified solving.

### Orientation and camera lifecycle

Keep the original top upward through the four side faces. Before each top/bottom capture, return to the original front. Tip the top toward the camera with the original **back edge at the image top**, or tip the bottom toward the camera with the original **front edge at the image top**. These exact holds produce canonical outside-view row order, so both top and bottom use an identity sample mapping. Tests verify these rotations against `CubeRenderLayout`; arbitrary photo orientations are not supported here.

The rear camera supplies upright, unmirrored portrait frames. Session setup, throttled analysis (at most roughly 8 frames/second) and shutdown run on a serial background queue; late video frames are discarded. Generation tokens reject results from before a retake, pause or navigation. Capture pauses between faces and requires orientation confirmation before any retake. Backgrounding, landscape layout, cancelling and session interruptions invalidate stability; resuming after a background/permission interruption is explicit. Permission denial provides a Settings link, and unavailable cameras retain the manual-entry alternative. Images are neither saved nor uploaded; only six sets of RGB samples and geometric/quality metadata remain in memory until leaving the screen.

### Detector and quality gates

`FaceImageAnalyzer` uses Vision rectangle observations, Core Image perspective correction, and median sRGB samples from the inner 40% of each cell in a 180×180 normalized face. Samples retain normalized original-image coordinates through a projective mapping. All four internal seams need image support across all three cells, preventing a plain rectangle or surrounding background rectangle from masquerading as a 3×3 grid. Samples are provisional measurements, never cube-color assignments.

`ScanCapture` checks completeness, image edges, area, side-length ratio, sharpness, underexposure, clipping, cell variation, and temporal geometry/color stability. CIELAB center distance distinguishes a confident repeated center from an ambiguous near-match; both block automatic advancement and explain how to recover. Balanced sticker counts and physical cube validity are intentionally not inferred here. `ScanThresholds` holds the initial tunable thresholds; they are not calibrated accuracy claims.

### Verification and device test checklist

Synthetic stickered and stickerless fixtures exercise the actual Vision/Core Image path, perspective correction, source-coordinate mapping, row order, blur/exposure measurement and plain-rectangle rejection. Workflow tests exercise all six faces, quality rejections, duplicate/ambiguous centers, interrupted stability, late frames, and retakes. Synthetic fixtures do not establish real-world recognition accuracy.

Physical-device validation is **pending**: no connected iPhone was available during implementation. Before treating this scanner as release-ready:

- Scan real stickered and stickerless cubes in daylight and warm indoor light; inspect every sampled cell, especially Top and Bottom.
- Try blur, partial faces, glare, low light, fingers covering cells and red/orange centers. Confirm bad frames never advance and stable good faces do.
- Deny permission, enable it in Settings, background during capture, rotate the device, interrupt the camera, retake and cancel. Confirm no duplicate or stale advancement.
- Measure capture latency and preview responsiveness on the oldest supported iPhone. Tune thresholds against a retained, consented test corpus of real cube images.

The simulator can verify navigation and the unavailable-camera path, but cannot validate physical camera capture.

Local verification: 67 host tests and 67 native iPhone simulator tests passed. Simulator and unsigned iPhone device builds succeeded. Simulator UI checks covered denial guidance, cancellation and navigation into manual entry. [Permission-denied screen](Docs/Scanner/permission-denied.png). Real camera capture and threshold calibration remain pending.
