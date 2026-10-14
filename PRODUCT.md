# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users
First-time solvers holding a physical 3×3 cube. The user confirmed clear guidance and one action at a time take priority over fast notation-heavy workflows.

## Product Purpose
Help users enter their cube's colors and follow a verified solution with an interactive 3D cube.

## Capabilities and Constraints
Native SwiftUI and RealityKit, iOS 17+, iPhone and iPad. Offline validation and solver already work. Preserve correctness, previous/next solution steps, replay and cancellation. Camera scanning is deferred and must not appear in the user flow. Support manual entry, undo, erase, orientation guidance and review before solving. Do not assume fixed center colors. Existing Xcode signing changes are user-owned.

## Brand Commitments
TwistTutor: Cube Solver. The user requests a substantial visual and UX redesign; the current implementation is not the visual reference to preserve.

## Evidence on Hand
The user's physical-device screenshot shows cluttered entry, duplicate progress and a visible face that differs from the selected painting face. The repository includes model tests and a reusable interactive cube renderer. Device validation must be distinguished from simulator checks.

## Product Principles
- One clear action at a time.
- Keep physical and virtual orientation understandable.
- Make recovery easy without losing work.
- Color entry and solving share a coherent visual language.

## Accessibility & Inclusion
Keep color names and non-color selection cues, accessible sticker controls, Dynamic Type and native navigation.
