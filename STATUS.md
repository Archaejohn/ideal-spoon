# STATUS

> Live project status and resume point. Updated continuously and committed often.

- **Project:** Aetherbound (working title) — offline single-player RPG, Godot 4.x, Android + Chromebook.
- **Original runtime start (Phase 0):** 2026-06-30T07:29:58Z
- **Timer RESET by Owner after story approval — new window start:** 2026-06-30T13:55:00Z
- **Hard checkpoint (4h30m of new window):** 2026-06-30T18:25:00Z (5h window ends ~18:55Z)
- **Current phase:** Phase 3 — Vertical slice. R1 (foundation) + R2 (story+battle+save) MERGED to main (122 tests green, releasable). R3 (autoload wiring + scene/UI + slice content) is next.
- **Paused:** by Owner at ~75% context usage. Safe pause: main builds + 122 tests green; nothing in flight; next session starts Round 3 from a clean main.
- **Story gate:** ✅ APPROVED by Owner. Story is locked; it is the game we build.
- **Remote:** https://github.com/Archaejohn/ideal-spoon.git (origin) — push verified. Story merged to main (PR #1).

## Owner functional requirements added at approval (baked into Definition of Done #13, #14)
1. **Automatic, crash-safe saving + battle checkpoints** — no manual saves; survives phone shutoff/lock/app-kill; losing a battle resumes from a pre-battle checkpoint, not a restart.
2. **Replayable endings** — after finishing, replay any ending from its story-divergence point (post-game selector).

## Done
- **Phase 0 — Bootstrap:** standalone repo → `ideal-spoon`; governance docs; Godot project skeleton; CI (GUT headless); toolchain; ADR-0001/0002.
- **Phase 1 — Story:** COMPLETE & APPROVED (the single human gate). Full bible in `docs/story/` (+ heart pass, light & triumph pass, mascot Piggy). Merged via PR #1.
- **Phase 2 — Architecture:** COMPLETE & merged (PR #2). ARCHITECTURE.md + ADR-0003..0009 + data schemas. Independent review APPROVE (after 8 must-fixes). Godot 4.3 + GUT installed (`tools/bin/`, `game/addons/gut`).
- **Phase 3 R1 — Foundation:** COMPLETE & merged (PR #3). `core/` (Log, RngService, EventBus, GameState, SettingsService), `story/` (FlagStore, FlagView, FlagOps, EndingResolver + golden test pinning all 256 ending combos), `data/` (ContentDB + validators), runnable Boot/Title. Independent review APPROVE + fast-follow (freeze gating flags after lock; FlagOps tests). 42 tests green.

## In flight
- **Nothing in flight.** R1+R2 merged to main; clean pause.

## Phase 3 R2 — DONE (merged via PR #4)
Three core systems, **122 tests / 1845 asserts green**, independent review **APPROVE WITH MINOR FIXES** (`docs/architecture/REVIEW_phase3_round2.md`):
- story: `StoryGraph` + `StoryDirector`
- battle: `TurnScheduler`/`DamageFormula`/`StatusEngine`/`EnemyBrain`/`BattleEngine` + `LevelSystem` + thin `BattleController`
- save: `AtomicFileIO`/`SaveSerializer`/`SaveMigrator`/`SaveManager`

## Next steps (RESUME HERE — Phase 3 R3: integrate + make playable)
**First, the carried-over R2 review follow-ups (non-blocking, do early in R3):**
- M1: soften ADR-0005 fsync wording (Godot 4 has no `fsync`; durability on app-kill holds, power-off relies on backup recovery — no data loss, worst case slightly stale save).
- M2 + N2: add the ADR-0009 guard tests `test_no_nondeterminism.gd` (scope to outcome-logic modules; exclude SaveManager's injectable clock/platform seam — document the exclusion) and `test_module_boundaries.gd`.
- N1: add a test for `SaveManager.load_latest` checkpoint-recovery tier (corrupt main+`.bak`, recover from checkpoint, assert `save_recovered("checkpoint")`).
- N3: add a per-branch "already resolved" ledger in `story_director.choose()` so back-nav can't set a second branch-identity flag.

**Then R3 proper:**
1. Register autoloads in `game/project.godot`: `SaveManager` (after GameState) + a thin StoryDirector/`SceneRouter` coordinator + `BattleController`.
2. Scene/UI layer per ADR-0008: Boot→Title(New/Continue)→Overworld/Town/Dungeon→Battle UI→Dialogue→Crossroads (ending replay). SceneRouter listens to `EventBus.scene_intent`.
3. Wire autosave triggers (beat_entered, map change, menu close, heartbeat) + pre-battle checkpoint in BattleController; wrap ending replay in `enter/exit_replay_mode`.
4. Author vertical-slice CONTENT (real data; flip ContentDB to strict for this closed set): Meadowmoor → Hollowgate wreck → Sleepless Crane ATB battle → autosave + lose-a-battle checkpoint → one story branch.
5. Integration playtest (desktop/headless); fix; Phase 3 slice done. Use `isolation:"worktree"` if dispatching parallel engineers.

## Process notes / lessons (orchestration)
- **Parallel file-writing subagents MUST use `isolation:"worktree"`.** R2's three engineers shared one checkout (resolved cleanly into `feat/phase3-round2`, but risky).
- **Never switch git branches while a subagent reads the shared working tree** — hold git ops until background readers finish.

## Known setup notes
- Godot 4.3 in `tools/bin/` (git-ignored); GUT at `game/addons/gut`. Tests: `bash tools/run_tests.sh`.
- Branch protection on `main` not enabled (human-only, optional); workflow enforced by process + CI.
- **Currently checked out:** `feat/phase3-round2`.

## How to resume
On `feat/phase3-round2`, run `bash tools/run_tests.sh` (should show 122 passing), then follow "Next steps".
