# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users
First-time solvers holding a physical 3×3 cube. The user confirmed clear guidance and one action at a time take priority over fast notation-heavy workflows.

## Product Purpose
Help users enter their cube's colors, follow a verified solution and learn a repeatable beginner method with their own interactive 3D cube.

## Capabilities and Constraints
Native SwiftUI and RealityKit, iOS 17+, iPhone and iPad. Offline validation and solver already work. Preserve correctness, previous/next solution steps, replay and cancellation. Camera scanning is deferred and must not appear in the user flow. Support manual entry, undo, erase, orientation guidance and review before solving. Do not assume fixed center colors. Existing Xcode signing changes are user-owned.

## Brand Commitments
TwistTutor: Cube Solver. Preserve the user-approved Cube first direction: navy 3D stage, light control drawer, rounded system headings and clear blue actions. Four primary sections: Solve cube, Learn, Time solving and Settings. Remove standalone Just explore; keep inspection inside the task.

## Evidence on Hand
The user's physical-device screenshot shows cluttered entry, duplicate progress and a visible face that differs from the selected painting face. The repository includes model tests and a reusable interactive cube renderer. Device validation must be distinguished from simulator checks.

## Product Principles
- One clear action at a time.
- Keep physical and virtual orientation understandable.
- Make recovery easy without losing work.
- Color entry and solving share a coherent visual language.

## Accessibility & Inclusion
Keep color names and non-color selection cues, accessible sticker controls, Dynamic Type and native navigation.
