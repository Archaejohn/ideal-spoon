# ADR-0001: Engine, language, testing, and toolchain

- **Status:** Accepted
- **Date:** 2026-06-30
- **Deciders:** Owner, Architect

## Context
We must ship a single-player, fully offline RPG to Android phones and Chromebooks, with detailed original art, an ATB battle system, a branching story, and thorough unit tests. No paid/external APIs. The stack is fixed by the studio charter; this ADR records the rationale and the concrete toolchain.

## Decision
- **Engine:** Godot 4.x (latest stable 4.x).
- **Language:** GDScript for game logic and tooling.
- **Unit testing:** GUT (Godot Unit Test), vendored under `game/addons/gut/`, run headless in CI and locally.
- **Art:** Original SVG authored in `art/`, imported into Godot and rasterized at import; richly layered (gradients, shading, lighting). No external image API.
- **Audio:** Original soundtrack/SFX produced by headless, committable tooling that outputs `.ogg`/`.wav`. No copyrighted material.
- **Build targets:** Android `.aab`/`.apk` via Godot export; Chromebook via Android runtime and/or web export.
- **CI:** GitHub Actions runs the GUT suite on every PR.

## Rationale
- Godot 4 exports cleanly to Android and the web, is free/open-source, fully scriptable, and supports headless unit testing — directly satisfying the offline, low-end-device, and testability requirements.
- GDScript keeps logic, tests, and tooling in one language with fast iteration.
- SVG source art gives crisp scaling across phone/Chromebook DPIs and supports the layered detail the Art Quality Loop demands.

## Consequences
- A Godot binary (and Android export templates) must be available to the build/test environment. We download a pinned Godot version into `tools/bin/` (git-ignored) via `tools/`; this is not a human-only action.
- SVG import settings (scale, anti-alias) must be standardized in the style guide for consistent rasterization.
- Deterministic logic (seeded RNG) is required so battle/quest/save systems are unit-testable.
