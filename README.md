# TwistTutor: Cube Solver

An offline iOS cube solver and beginner tutor, under development. ENG-595–598 establish the cube foundation; scanning, solving algorithms, 3D rendering and lessons are subsequent milestones. The app currently displays its starter welcome screen.

- Display name: `TwistTutor: Cube Solver`
- Bundle identifier: `com.serendipitylabs.twisttutor`
- Deployment target: iOS 17.0; iPhone and iPad
- Development: Xcode 16 or later with Swift 6; current local verification uses Xcode 26
- No external package dependencies, accounts, networking or camera permissions in this foundation

Open `TwistTutor.xcodeproj`, select a simulator and run the `TwistTutor` scheme. For physical devices, select your Apple development team in Signing & Capabilities. App icons and release configuration are tracked separately.

## Architecture

| Boundary | Responsibility | Status |
| --- | --- | --- |
| `TwistTutor/App` | SwiftUI app composition and session ownership | Implemented |
| `TwistTutor/Features/Home` | Starter screen; future feature views consume state/services | Starter only |
| `Packages/TwistTutorKit/Sources/CubeCore` | Models, notation, integer geometry, turns, conversion, capture orientation | Implemented; independent of UI and camera |
| `Packages/TwistTutorKit/Sources/CubeValidation` | Color checks, piece uniqueness and physical legality | Implemented; depends only on CubeCore |
| `Packages/TwistTutorKit/Sources/AppWorkflow` | Main-actor observable session and cancellation | Implemented; depends on core and validation |
| Vision / Features/Scan | AVFoundation capture and local image analysis | M5; adapter supplies a captured face, owns camera lifecycle |
| Solver / Features/Solve | Offline solver plus independent solution verification | M2/M7; must validate input before solving |
| Renderer / Features/CubeReview | RealityKit geometry and correction UI | M3/M6; consumes core state, never owns cube truth |
| Teaching / Features/Learn / Features/Practice | Beginner plans, explanations and practice | M8/M9; separate from quick solver |
| Persistence | Local preferences, learning progress and history | Later issue; no image storage introduced here |

Future boundaries are documented contracts, not empty modules or placeholder implementations. Implementations must preserve the dependency direction toward CubeCore. Camera state does not belong in a cubie, and view state does not belong in a camera adapter.

`AppSession` represents all specified phases from Idle to Completed. Accepted faces are ordered, duplicate completions are ignored, and validation gates cube readiness. Leaving/restarting cancels the owned task and invalidates its operation token. Even an adapter that ignores cancellation cannot overwrite a newer session. A failed capture returns to Scanning with retry feedback. Solve and Learn remain distinct modes. The solution-completion seam currently accepts a verification flag; the later solver integration must supply this only after independent replay verification (ENG-601). No solving behavior is implemented in M1.

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
swift test --package-path Packages/TwistTutorKit --enable-code-coverage
```

Run the same test sources on iOS using Product → Test in the `TwistTutor` scheme, or choose an installed simulator:

```sh
xcodebuild -project TwistTutor.xcodeproj -scheme TwistTutor \
  -destination 'platform=iOS Simulator,name=iPhone 16e,OS=26.0' \
  CODE_SIGNING_ALLOWED=NO test
```

If command-line tools point at a different Xcode, set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for the command. CI runs package tests and a simulator app build.

The suite covers all 18 turns, fixed quarter-turn fixtures, move inverses, noncommuting moves, a known algorithm identity, 1,000 reproducible 30-turn scrambles, metadata-preserving conversions, capture rotations, invalid colors/centers, reflected/duplicate pieces, single flipped edges/twisted corners, permutation parity, correction revalidation and asynchronous cancellation races.

Support assumptions: iOS 17+ on iPhone/iPad; macOS 14+ is a **test host**, not a shipping app target. Minimum-OS device validation and older-device camera/solver/renderer benchmarks remain outstanding. Simulator/core tests do not establish physical scanning accuracy or release performance.
