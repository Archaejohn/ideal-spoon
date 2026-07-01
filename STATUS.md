# STATUS

> Live project status and resume point. Updated continuously and committed often.

- **Project:** Aetherbound (working title) — offline single-player RPG, Godot 4.x, Android + Chromebook.
- **Original runtime start (Phase 0):** 2026-06-30T07:29:58Z
- **Timer RESET by Owner after story approval — new window start:** 2026-06-30T13:55:00Z
- **Hard checkpoint (4h30m of new window):** 2026-06-30T18:25:00Z (5h window ends ~18:55Z)
- **Current phase:** Phase 3 slice **COMPLETE & merged** (141 tests green, playable). Then **Phase 4 ART-PIPELINE R&D** (this session, 2026-07-01) → **pixel-art pipeline PROVEN** (full N/S/E/W walk), **pending formal lock** (pixel style guide + palette + ADR) before Phase 4 production proper.
- **➡️ FULL CONTEXT: see `docs/SESSION_HANDOFF.md` and `CLAUDE.md`.** Working branch: `feat/phase4-art-pipeline` (art tooling + this handoff). No open PRs.
- **Art direction (Owner):** pixel art, SNES / FF VI / Secret of Mana. Reliable pipeline = Flux.2 Klein (local ComfyUI :8000) generate + **edit** (ReferenceLatent, preserves character) + per-frame review + master-palette lock. Tools in `tools/art/`.
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

- **Phase 3 R2 — Core systems:** merged (PR #4). story (StoryGraph/StoryDirector), battle (TurnScheduler/DamageFormula/StatusEngine/EnemyBrain/BattleEngine + LevelSystem + BattleController), save (AtomicFileIO/SaveSerializer/SaveMigrator/SaveManager). Independent review APPROVE.
- **Phase 3 R3 — Vertical slice (COMPLETE):**
  - R3a (PR #5): autoloads + SceneRouter + GameCoordinator; Boot→Title→New/Continue→Overworld; autosave wiring; the 4 R2 follow-ups (incl. ADR-0009 guard tests).
  - R3b-1 (PR #6): playable ATB Battle UI (WAIT mode); pre-battle checkpoint + **lose→restore→retry** (never Title); Sleepless Crane encounter. Caught+fixed a real engine win-detection bug.
  - R3b-2 (PR #7): dialogue/cutscene UI, Location (town/dungeon) scenes, Crossroads stub; real slice micro-arc with **one diverging/merging branch**; fixed H1 (dialogue rendered blank — node-path bug found in review). **141 tests green; slice completable end-to-end on both branch arms.**

## In flight
- **Art-pipeline R&D (branch `feat/phase4-art-pipeline`):** pixel pipeline proven; **awaiting Owner go-ahead to LOCK it** (write pixel `STYLE_GUIDE.md` + master palette + art ADR, retire painterly guide, merge branch). Nothing else in flight; `main` releasable at 141 tests.

## Next steps (RESUME HERE)
**0. Lock the art pipeline (if Owner approves):** pixel `docs/art/STYLE_GUIDE.md` + `docs/art/PALETTE.*` + art ADR (pixel raster; Flux.2 gen+edit+review+palette-lock; no rigging; ComfyUI-local); fix North base pendant-on-back; merge `feat/phase4-art-pipeline`.

**Then Phase 4 — Full production.** The big loop — turn the locked story bible into the full game (use **`isolation:"worktree"`** for concurrent agents):
1. **Content authoring (data):** convert the whole story (03 beat ledger A1-01..A4-07 + heart/triumph/Piggy beats, 04 branches/endings, 05 side quests, 06 dialogue) into ContentDB data — beats, branches, dialogue, quests, items, enemies, abilities, encounters, level curves. Flip ContentDB to strict validation as each act closes.
2. **Art (pixel pipeline + Art Quality Loop):** per-asset via `tools/art/comfy_gen.py`+`comfy_edit.py` → review ≥8/10 → master-palette lock. Cast/enemies/tiles/portraits + the walk-set template; replace all placeholders; whole-game cohesion gate.
2b. **Skyway overworld map (Owner design intent):** progressively-opening FF-style map of skylands you pilot between (unlock via story flags; enter towns/dungeons; Second Sundering reshapes it). Write an ADR + build in Phase 4.
3. **Audio:** original soundtrack (the "Song" motif system + per-area/mood) + SFX; cohesive.
4. **Systems/UI completion:** full menus (inventory, party, equipment, status), world map/travel, settings (incl. ATB wait/active + timer), full Crossroads ending-replay (ADR-0006 reconstruction), credits.
5. **Loop:** implement→test→review→merge→integrate→playtest→fix; Architect repeatedly asks "is the game complete per DoD?" Keep looping while no.
Then **Phase 5 — Hardening & release:** full playthroughs of every path/ending, balance, zero-known-blockers, offline/no-network audit, Android `.aab/.apk` + Chromebook build, smoke test, release notes, DoD certification.

### Phase-4 polish items carried from the slice (non-blocking now)
- Replace all placeholder visuals with real art; dialogue typewriter/auto-advance/skip; closing → a real end card (currently → Title).
- Persist the N3 branch-resolved ledger into GameState if save+reload+back-nav becomes reachable.
- Validator: add `APPLY_STATUS`→status reference check (NOTE-2).

## Process notes / lessons (orchestration)
- **Parallel file-writing subagents MUST use `isolation:"worktree"`** (the engineering reviews/builds were run sequentially in the main tree to avoid the R2 shared-checkout race).
- **Never switch git branches while a subagent reads the shared working tree** — hold git ops until background readers finish.
- Every PR gets an independent review (author ≠ reviewer); reviews have repeatedly caught real bugs (engine win-detection, blank dialogue) — keep the discipline.

## Process notes / lessons (orchestration)
- **Parallel file-writing subagents MUST use `isolation:"worktree"`.** R2's three engineers shared one checkout (resolved cleanly into `feat/phase3-round2`, but risky).
- **Never switch git branches while a subagent reads the shared working tree** — hold git ops until background readers finish.

## Known setup notes
- Godot 4.3 in `tools/bin/` (git-ignored); GUT at `game/addons/gut`. Tests: `bash tools/run_tests.sh`.
- Branch protection on `main` not enabled (human-only, optional); workflow enforced by process + CI.
- **Currently checked out:** `feat/phase3-round2`.

## How to resume
On `feat/phase3-round2`, run `bash tools/run_tests.sh` (should show 122 passing), then follow "Next steps".
