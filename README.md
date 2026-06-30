# Aetherbound (working title)

A single-player, offline fantasy/sci-fi RPG for Android and Chromebook, built in **Godot 4.x** (GDScript) with an **Active-Time-Battle** system, a branching/merging storyline, side quests, and multiple endings. Original art, music, and writing throughout. Age-appropriate for a 10-year-old reading at a 6th-grade level.

This repository is built and operated by an autonomous game studio (orchestrated AI team). See `ORCHESTRATOR_PROMPT.md` for the operating charter.

## Repo map

| Path | Purpose |
|---|---|
| `game/` | Godot 4.x project (project.godot lives here) |
| `game/addons/gut/` | GUT — Godot Unit Test framework (vendored) |
| `game/src/` | GDScript source, organized by system |
| `game/data/` | Content data (JSON/resources): story graph, items, enemies, dialogue |
| `game/assets/` | Imported art (SVG) and audio (.ogg) |
| `game/tests/` | GUT unit tests |
| `art/` | Authoring source for SVG art before import |
| `audio/` | Authoring source / generation scripts for music + SFX |
| `docs/decisions/` | ADRs (Architecture Decision Records) |
| `docs/story/` | Story bible, beat sheets, branch map |
| `docs/art/` | Art style guide + critique records |
| `tools/` | Headless build/test helper scripts |

## Governance
- `DEFINITION_OF_DONE.md` — the bar for "complete".
- `CONTRIBUTING.md` — mandatory git/PR/review workflow.
- `STATUS.md` — live project status (resume point).
- `DECISIONS.md` — running decision log (index into ADRs).
- `NEEDS_HUMAN.md` — anything blocked on a human-only action.
