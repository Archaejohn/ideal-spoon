# STATUS

> Live project status and resume point. Updated continuously and committed often.

- **Project:** Aetherbound (working title) — offline single-player RPG, Godot 4.x, Android + Chromebook.
- **Runtime start (Phase 0):** 2026-06-30T07:29:58Z
- **Hard checkpoint (4h30m):** 2026-06-30T11:59:58Z
- **Current phase:** Phase 1 — Story (awaiting human story sign-off)
- **Remote:** https://github.com/Archaejohn/ideal-spoon.git (origin) — push verified.

## Done
- **Phase 0 — Bootstrap:** complete.
  - Push/PR access verified (`gh` as `Archaejohn`, scopes repo+workflow).
  - Repo initialized as standalone git repo (separate from Desktop repo) → `ideal-spoon`.
  - Scaffold: README, .gitignore, DEFINITION_OF_DONE, CONTRIBUTING, DECISIONS, NEEDS_HUMAN, STATUS.
  - Godot 4.x project skeleton (`game/project.godot`, dev icon, dir layout).
  - CI workflow (`.github/workflows/ci.yml`) runs GUT headless on PRs.
  - Toolchain scripts (`tools/fetch_godot.sh`, `tools/run_tests.sh`).
  - ADR-0001 (tech stack), ADR-0002 (repo & remote).

## In flight
- **Phase 1 — Story bible** on branch `story/story-bible`: world, factions, cast, themes, main beats, branch map, side quests, multiple endings + 1-page summary.

## Next steps
1. Present 1-page story summary → **STOP for human "approved"** (the single human gate).
2. On approval: Phase 2 — Architect designs systems (story-graph engine, ATB, save format, content pipeline) with ADRs.
3. Phase 3 — vertical slice (title→town→dungeon→ATB battle→save/load→one branch), fully tested.

## Known issues / setup notes
- Godot not yet installed in this environment; `tools/fetch_godot.sh` will pull a pinned 4.3 binary + vendor GUT when test execution is needed (Phase 2/3). This is autonomous (no human action).
- Server-side branch protection on `main` not enabled (human-only, optional); workflow enforced by process + CI.

## How to resume
Read this file top-to-bottom, then `git log --oneline -15` and open PRs (`gh pr list`). Continue from "Next steps".
