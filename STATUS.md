# STATUS

> Live project status and resume point. Updated continuously and committed often.

- **Project:** Aetherbound (working title) — offline single-player RPG, Godot 4.x, Android + Chromebook.
- **Original runtime start (Phase 0):** 2026-06-30T07:29:58Z
- **Timer RESET by Owner after story approval — new window start:** 2026-06-30T13:55:00Z
- **Hard checkpoint (4h30m of new window):** 2026-06-30T18:25:00Z (5h window ends ~18:55Z)
- **Current phase:** Phase 3 — Vertical slice (autonomous). Phase 2 architecture merged (PR #2, ADR-0003..0009, independent review APPROVE).
- **Story gate:** ✅ APPROVED by Owner. Story is locked; it is the game we build.
- **Remote:** https://github.com/Archaejohn/ideal-spoon.git (origin) — push verified. Story merged to main (PR #1).

## Owner functional requirements added at approval (baked into Definition of Done #13, #14)
1. **Automatic, crash-safe saving + battle checkpoints** — no manual saves; survives phone shutoff/lock/app-kill; losing a battle resumes from a pre-battle checkpoint, not a restart.
2. **Replayable endings** — after finishing, replay any ending from its story-divergence point (post-game selector).

## Done
- **Phase 0 — Bootstrap:** complete.
  - Push/PR access verified (`gh` as `Archaejohn`, scopes repo+workflow).
  - Repo initialized as standalone git repo (separate from Desktop repo) → `ideal-spoon`.
  - Scaffold: README, .gitignore, DEFINITION_OF_DONE, CONTRIBUTING, DECISIONS, NEEDS_HUMAN, STATUS.
  - Godot 4.x project skeleton (`game/project.godot`, dev icon, dir layout).
  - CI workflow (`.github/workflows/ci.yml`) runs GUT headless on PRs.
  - Toolchain scripts (`tools/fetch_godot.sh`, `tools/run_tests.sh`).
  - ADR-0001 (tech stack), ADR-0002 (repo & remote).

## Done
- **Phase 1 — Story:** COMPLETE & APPROVED. Full bible in `docs/story/` (incl. heart pass, light & triumph pass, and mascot Piggy). Merged to main via PR #1.

## Done
- **Phase 2 — Architecture:** COMPLETE & merged (PR #2). ARCHITECTURE.md + ADR-0003..0009 + data schemas. Independent review APPROVE after one NEEDS-WORK round (8 must-fixes resolved). Godot 4.3 + GUT toolchain installed (`tools/bin/`, `game/addons/gut`).

## In flight
- **Phase 3 — Vertical slice.** Build order:
  - R1 Foundation (in progress): `core/` (RngService, EventBus, Log), `types/`, `data/` (ContentDB + validators), `GameState`, `FlagStore`+`FlagView`, `EndingResolver` + golden test, autoload wiring, runnable Boot/Title, green GUT suite. Branch `feat/phase3-foundation`.
  - R2 (parallel after R1): `story/` engine, `battle/` engine (+EnemyBrain), `save/` system — each with GUT tests.
  - R3: scene/UI layer (Title→Town→Dungeon→Battle→Dialogue), slice content (Meadowmoor→Hollowgate wreck→Sleepless Crane→autosave/checkpoint→one branch), integration playtest.

## Next steps
1. Present 1-page story summary → **STOP for human "approved"** (the single human gate).
2. On approval: Phase 2 — Architect designs systems (story-graph engine, ATB, save format, content pipeline) with ADRs.
3. Phase 3 — vertical slice (title→town→dungeon→ATB battle→save/load→one branch), fully tested.

## Known issues / setup notes
- Godot not yet installed in this environment; `tools/fetch_godot.sh` will pull a pinned 4.3 binary + vendor GUT when test execution is needed (Phase 2/3). This is autonomous (no human action).
- Server-side branch protection on `main` not enabled (human-only, optional); workflow enforced by process + CI.

## How to resume
Read this file top-to-bottom, then `git log --oneline -15` and open PRs (`gh pr list`). Continue from "Next steps".
