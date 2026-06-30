# Code Review — Phase 3, Round 2 (`feat/phase3-round2`)

- **Reviewer:** Independent code reviewer (did not author this code)
- **Date:** 2026-06-30
- **Scope:** STORY engine, ATB BATTLE engine + leveling, SAVE system
- **Contracts checked:** ADR-0003, ADR-0004, ADR-0005, ADR-0007 (referenced), ADR-0009; docs/story 03 & 04; ARCHITECTURE.md; PHASE2_OWNER_RULINGS.md

## Verdict: APPROVE WITH MINOR FIXES

The suite is green (`bash tools/run_tests.sh` → **122/122 passing, 1845 asserts, 8.5s**). The three systems are correct against their contracts on every focus item I checked: save crash-safety ordering is sound and proven by a torn-main test; battle turn order and RNG reproduction are deterministic and tested mid-fight; the story director applies effects exactly once, freezes gating state at lock, and resolves endings through the unmodified resolver.

**None of the findings below block the merge of PR #4.** They are documentation-accuracy, contract-completeness (two ADR-mandated guard tests), and one untested recovery path. Recommend filing them as Round-3 follow-ups. **PR #4 can merge.**

---

## Findings (ranked by severity)

### MEDIUM

#### M1 — `fsync` is promised by ADR-0005 but never performed (durability claim overstated)
- **File:** `game/src/save/atomic_file_io.gd:37-39, 53-57`
- **Defect:** Writes do `f.flush()` + `f.close()` only. ADR-0005 §b and §e explicitly promise `fsync` and a "completes-before-return **durable**" guarantee on native (Android). Godot 4 `FileAccess` exposes **no fsync**, so `close()` only hands bytes to the OS page cache; it does not force them to the platter.
- **Failure scenario:** On a true device **power-off** (DoD #13 names "phone being shut off") immediately after a lifecycle write, the renamed `save_main.sav` can reference unflushed blocks → a torn/corrupt main on next boot. (On an app *kill*/background — the more common DoD #13 case — the page cache survives and the guarantee holds.)
- **Mitigation already present:** The checksum + validate-before-backup + `.bak`/checkpoint recovery tier means the worst case is **recovery to a slightly older valid save, never a lost or corrupt game.** So "no corrupted saves" (the hard DoD requirement) is still met via recovery.
- **Fix:** Reconcile the ADR wording with reality — state "atomic rename + flush; durable on app-kill; power-off relies on OS flush + backup recovery since Godot exposes no `fsync`." Optionally investigate a platform `fsync` via JNI (Android) / `syncfs` already used on web. Non-blocking (engine limitation), but the contract should not claim more than the code can do.

#### M2 — ADR-0009 `test_no_nondeterminism` is missing, and `SaveManager` would trip it as written
- **Files:** guard test absent under `game/tests/unit/`; offending refs `game/src/save/save_manager.gd:64, 65, 260, 280, 281` (`OS.has_feature`, `JavaScriptBridge.eval`, `Time.get_ticks_msec`)
- **Defect:** ADR-0009 §2 mandates a guard that greps `battle/ story/ save/ inventory/ leveling/` for `Time.*`/`OS.*`/global `randi/randf`/`randomize`. `save/save_manager.gd` legitimately uses `Time` (debounce clock) and `OS`/`JavaScriptBridge` (web flush). The guard does not exist yet, so nothing fails today — but **implementing it per the ADR's literal scope will flag SaveManager.**
- **Assessment:** I manually grep-verified the **outcome-logic** modules (`battle/` incl. `enemy_ai.gd`, `story/`, `leveling/`, and `save/` serializer/migrator/atomic_io) are clean of any such reference. SaveManager's clock is injectable (`set_clock`) and its `Time`/`OS` use affects only *when* a write happens and *platform flush*, never save **content**, so it is functionally deterministic. This is a **contract-scope decision**, not a live bug.
- **Fix:** Add `test_no_nondeterminism.gd` scoped to outcome-logic files, explicitly excluding the SaveManager coordinator's clock/platform seam (or move those behind an injected interface) and document the exclusion in ADR-0009. The absence of this guard is **not a correctness blocker** given the manual verification, but it is an ADR-mandated item and carries this latent scope trap.

### MINOR

#### N1 — Checkpoint-tier recovery (`load_latest` last-ditch) is implemented but untested
- **File:** `game/src/save/save_manager.gd:147-153`; gap in `game/tests/unit/test_save_manager.gd`
- **Defect:** ADR-0005 §c's "if main **and** `.bak` both fail, recover from `checkpoint.sav` before fresh" path emits `save_recovered("checkpoint")`. Tests cover backup recovery and migration but **not** this tier (confirmed: no test asserts the `"checkpoint"` recovery source).
- **Fix:** Add a test that corrupts main + `.bak`, writes a checkpoint, then asserts `load_latest()` returns true, state matches the checkpoint, and `save_recovered("checkpoint")` fires. Recommended before the DoD #13 smoke test leans on it.

#### N2 — ADR-0009 `test_module_boundaries` is missing
- **Defect:** The mandated guard asserting logic modules don't reference autoloads/`ui/`/`overworld/` is absent. Manually verified clean: story/battle/leveling logic classes `extend RefCounted`, take deps by injection, and `story_director.gd` ships its own anti-scene-tree guard (`test_story_director.gd:168-182`). Low risk, but it is a contract item — add it.

#### N3 — Re-entering a resolved branch trigger can apply a second option's identity flags
- **File:** `game/src/story/story_director.gd:121-136`
- **Defect:** `choose()` applies option effects with no per-branch "already resolved" ledger; it is protected only because `_open_branch_id` is cleared after choosing. An explicit `goto_beat()` **back** to a trigger re-opens the branch, after which a *different* option could be chosen, setting a second branch-identity flag (`SET` never clears the first). UNITY cannot double-count (per-`source_id` idempotency holds).
- **Scenario:** Not reachable on the forward spine; only via deliberate back-navigation (lands in Round 3 with SceneRouter). 
- **Fix:** When back-nav exists, gate branch-identity SETs behind a per-branch resolution ledger (mirror `applied_beats`). Note for Round 3; not a current path.

### LOW / NIT (no action required to merge)

- **L1 — Windows rename non-atomicity:** `DirAccess.rename` on Windows is remove-then-rename (non-atomic); combined with the in-place `.bak` write, a crash in that narrow window could corrupt both on Windows. Shipping targets are Android (POSIX atomic rename) and web (IDBFS); the checkpoint tier still covers it. Out of scope for target platforms.
- **L2 — RNG seed derivation uses GDScript `hash()`** (`rng_service.gd:_derive_seed`). `hash()` stability across Godot versions/platforms is not contractually guaranteed; saves are not cross-platform-portable and only `master_seed`+cursors are stored (derived seeds recomputed locally), so within a platform reproduction is exact. Note for awareness.
- **L3 — `combatant.gd:56` `var defended = 1`** is dead/unused (defending is handled in `damage_formula`). Harmless; remove.
- **L4 — `enemy_ai.gd:75-83` `_biased_weight`** integer-floor can zero out an eligible entry; if *all* eligible entries floor to 0, `weighted_pick` falls back to index 0 (still deterministic, but the aggression bias is lost at the 0/1000 extremes). Cosmetic edge.
- **L5 — Simultaneous total-party + total-enemy death** resolves to WIN (`battle_engine.gd:371-374`, WIN checked first). No crash; reasonable default.

---

## Focus-item assessment

1. **Save crash-safety (DoD #13):** PASS (with M1 doc caveat). Write order is exactly tmp → validate-tmp → validate-current-before-promoting-to-`.bak` → atomic rename; a torn main is provably **not** promoted over a good backup (`test_atomic_file_io.gd:test_torn_main_does_not_clobber_good_backup`). Read recovery main → `.bak` → checkpoint is implemented (N1: checkpoint tier untested). Checksum scope = SHA-256 over `magic + version + payload-string`, key-order independent, detects any tamper (`save_serializer.gd:65`). `restore_checkpoint` reproduces RNG cursors via `import_state` → per-stream `set_cursor` replay, proven by `test_save_manager.gd:test_checkpoint_restore_reproduces_rng_cursors`. **Replay-mode write guard is enforced on ALL paths including `_notification`** (`save_manager.gd:75, 106, 221`), proven by `test_replay_mode_blocks_autosave_and_lifecycle`. No path overwrites the real save during replay.
2. **Battle determinism (DoD #4):** PASS. Turn order is integer ATB with a fully deterministic tie-break (atb desc → SPD desc → stable id asc, `turn_scheduler.gd:74-81`), no RNG. All draws come from the injected `battle`/`ai` streams; no hidden `Time`/`randf`/dict-order in outcomes (grep-verified). Mid-battle cursor save/restore reproduces subsequent draws (`test_battle_engine.gd:test_cursor_save_restore_mid_battle...`) and same-seed runs yield identical event streams. EnemyBrain is deterministic, retargets dead targets (picks from `living_opponents`, id-sorted), and `BattleEngine._resolve_targets` retargets-or-fizzles queued actions. Damage is `maxi(1, …)` (never negative), accuracy/crit boundaries via integer permille are correct (p=1000 always, p=0 never). Win/lose detection correct.
3. **Story director (matches 03/04):** PASS. Effects apply exactly once (`apply_beat_effects` gated by `mark_beat_applied`; UNITY also idempotent per `source_id`), proven by `test_entering_a_beat_applies_effects_exactly_once`. Branch open→choose→merge sets correct flags incl. `if_flag`-gated merge recruitment (`test_left/right_option...`). `if_flag` gating works on both `next` and branch options. `LOCK_ENDINGS` freezes gating SETs and INC_UNITY (`flag_store.gd:32, 51`; `test_lock_endings_freezes_gating_flags_and_unity`). `RECORD_ENDING` calls the unmodified `EndingResolver.resolve(store.view(), final_choice)` and yields the right letter on scripted paths to endings A and B.
4. **Test quality:** HIGH and behavioral, not superficial — they assert exact targets, exact flag/UNITY values, identical event streams, and recovery sources, with self-contained fixtures. Gaps: the two ADR-0009 guard tests (M2/N2) and the checkpoint recovery tier (N1). **Their absence is not a correctness blocker** (logic modules manually verified clean; boundaries respected), but they are mandated contract items and M2 carries a real scope subtlety that must be decided before that guard is written.
5. **Module boundaries / headlessness:** PASS. Story/battle/leveling/save-helper logic are `RefCounted`, dependency-injected, no scene-tree or autoload hard-deps. `BattleController` (Node) and `SaveManager` (Node) are the intended bridge/coordinator and are still unit-testable via injected stubs/clock. No leaks found.
6. **Documented deviations:** All sound. (a) EnemyBrain `intent` aggression tag — relative weights make the `/1000` harmless; correct (minor L4 extreme). (b) `growth_overrides` REPLACE semantics in `level_system.gd:63-72` — replaces that level's growth and may add new stats; matches the doc and is tested. (c) Save envelope nesting (`{magic, version, checksum, payload-string}`) — checksum scope is correct and tamper-detecting. (d) SaveManager not yet autoloaded — intentional for Round 3; fully exercised by injection. Note: until it is a tree-resident autoload, `_notification` lifecycle hooks won't actually fire in-game (expected this round).

---

## Bottom line
Solid, contract-faithful work with genuinely meaningful tests. Merge PR #4. File M1 (ADR durability wording), M2 + N2 (the two ADR-0009 guard tests, with the SaveManager-scope decision), and N1 (checkpoint-tier recovery test) as Round-3 follow-ups.
