# Code Review — Phase 3, R3a (`feat/phase3-r3a`) — the integration shell

- **Reviewer:** Independent code reviewer (did not author this code)
- **Date:** 2026-06-30
- **Scope:** Boot/Title/Overworld UI; SceneRouter; GameCoordinator; autoload wiring; New Game / Continue / autosave; the two ADR-0009 guard tests; the N1 checkpoint-recovery test; the N3 branch-ledger change; the SaveManager `class_name` removal.
- **Contracts checked:** ADR-0008 (scene flow / SceneRouter), ADR-0005 (save), ADR-0009 (determinism + guard tests), ARCHITECTURE.md; REVIEW_phase3_round2.md follow-ups M1/M2/N1/N2/N3.

## Verdict: APPROVE WITH MINOR FIXES

The suite is green: `bash tools/run_tests.sh` -> **132/132 passing, 2154 asserts, ~9.5s**. A headless import + a 120-frame headless boot both run **clean** (only `[INFO][Boot] Content loaded: 3 beats, 25 flags.`; no script errors, no push_error/push_warning). The integration shell is wired correctly: autoloads register in dependency order, SceneRouter listens before any `scene_intent` can fire, New Game resets state cleanly and round-trips through autosave -> Continue, and the headless logic modules stay pure. **All five Round-2 follow-ups (M1/M2/N1/N2/N3) are genuinely closed.**

**No blocking findings.** The items below are non-blocking minors/nits. **PR #5 can merge.**

---

## Are the 5 follow-ups genuinely closed?

- **M1 — ADR durability wording now honest: YES.** `ADR-0005` §native (lines ~51-60, ~164-170) and §web (~170-186) now state plainly that Godot 4 `FileAccess` exposes **no `fsync`**, that `close()` only reaches the OS page cache (durable against app-kill/background, not a true power-off), and that DoD-#13 "no corrupted saves" is met **via the checksum + `.bak`/checkpoint recovery tier**, never by a false durability claim. Code matches the contract.
- **M2 — `test_no_nondeterminism.gd` exists and is non-vacuous: YES.** It recurses `battle/`, `story/`, `leveling/` plus the three save serializer-tier files, strips comments, and flags `Time.`, `OS.`, `randomize(`, and *global* `randi(`/`randf(` (correctly excluding member calls like `stream.randi()` and identifiers like `_my_randi(`). Adding `Time.get_ticks_msec()` to any battle source **would** trip `code.contains("Time.")` -> the test fails. `assert_gt(files.size(), 0)` guarantees it is not vacuous, and it explicitly asserts `save_manager.gd` is **not** in scope. The exclusion is narrowly scoped (only `save_manager.gd`, not all of `save/`) and documented in **ADR-0009 §2 (lines ~77-85)** with the rationale (coordinator clock/web seam affects *when/where*, never save content).
- **N1 — checkpoint-tier recovery exercised incl. the signal: YES.** `test_save_manager.gd::test_load_latest_recovers_from_checkpoint_when_main_and_bak_corrupt` (lines 186-206) writes a valid checkpoint, corrupts BOTH `save_main.sav` and `save_main.sav.bak`, wipes live state, then asserts `load_latest()` returns true, the state is restored from the checkpoint, AND `save_recovered("checkpoint")` fired (`assert_signal_emitted_with_parameters(... ["checkpoint"], 0)`). This is the exact ADR-0005 §c last-ditch tier.
- **N2 — `test_module_boundaries.gd` exists and detects violations: YES.** It scans the logic dirs/files, and for each asserts (a) no whole-word reference to any of the 10 autoload names, (b) no `res://src/ui/` or `res://src/overworld/` preload/load, (c) `extends RefCounted`. A logic module that referenced `GameState` or preloaded a `ui/` script would fail (a)/(b). The two bridge Nodes (`battle_controller.gd`, `save_manager.gd`) are excluded, with a dedicated `test_excluded_bridges_are_not_in_scope` test, and the exclusion is documented in ADR-0009 §2/§module-boundary.
- **N3 — branch ledger prevents a second branch-identity flag: YES (in-session), with an acceptable persistence caveat.** `story_director.gd` adds `_resolved_branches` (branch_id -> chosen option_id). `choose()` (lines 138-149) refuses a *different* option once resolved (`err`), re-applies nothing on a *same-option* re-choose (idempotent), and only applies option effects when `prior == ""`. Two tests prove both arms (`test_reentering_resolved_branch_cannot_apply_second_option_identity_flags`, `test_rechoosing_same_resolved_option_is_idempotent_and_reroutes`). The logic is correct. See F1 for the in-memory-only caveat — it is acceptable for R3a because no back-navigation path ships this round.

---

## Findings (ranked by severity)

### MINOR (non-blocking)

#### F1 — N3 ledger is in-memory only; not durable across save/Continue (latent for future back-nav)
- **Files:** `game/src/story/story_director.gd:41` (`_resolved_branches` never serialized); `game/src/core/game_coordinator.gd:37-38, 69` (`_build_director()` constructs a fresh director -> empty ledger on every New Game and every Continue).
- **Defect:** The per-branch resolution ledger lives only on the StoryDirector instance. `GameState.applied_beats` and `flags` persist across save/load, but `_resolved_branches` does not, and `continue_game()` rebuilds the director with an empty ledger.
- **Failure scenario:** Resolve a branch (LEFT, sets `FX_LEFT_TAKEN`) -> save/quit -> Continue (ledger now empty) -> *if* a future back-navigation re-enters the trigger, `choose("right")` sees `prior == ""` and applies `FX_RIGHT_TAKEN` — the exact double-identity-flag bug N3 closes. **Not reachable in R3a**: there is no back-nav UI/path (only `advance()` walks forward and `choose()` routes forward); the N3 tests reach the trigger via a direct `goto_beat` that gameplay cannot currently issue. The author explicitly documents the in-memory caveat in the `_resolved_branches` comment.
- **Fix (when back-nav ships):** Persist the resolved-branch ledger into `GameState` alongside `applied_beats` (serialize in `to_dict`/`from_dict`, restore in `snapshot`/`restore_snapshot`), and seed `StoryDirector._resolved_branches` from it on `_build_director()`. Acceptable to defer to the round that introduces back-navigation.

#### F2 — `_strip_comment` in the nondeterminism guard can mask a same-line violation after a `#` inside a string literal
- **File:** `game/tests/unit/test_no_nondeterminism.gd:99-103`.
- **Defect:** `_strip_comment` truncates at the FIRST `#`. If a scanned line ever contains a `#` inside a string literal followed by real code (e.g. `var s := "a#b"; OS.get_name()`), the `OS.` after it is dropped -> **false negative**. (The complementary case — a forbidden token *inside* a string literal, e.g. a log message containing `"Time."` — produces a harmless false *positive*, i.e. over-strict, which is safe.) No scanned file currently has such a pattern, so the guard is correct today.
- **Fix:** Either keep the documented "no `#` inside string literals in scanned files" assumption (currently true) or harden the stripper to ignore `#` within quotes. Low priority.

### NIT (no action required to merge)

- **N-1 — Heartbeat Timer runs for the whole test session.** `game_coordinator.gd:29-34` adds an autostart 45s `Timer` on the autoload. During tests the autoload is alive throughout; the integration test resets `SaveManager` debounce to 0 inside its window, so a heartbeat firing there could land one extra (identical-content) autosave. Harmless and test-only; the author's "cross-test debounce state" note is accurate. Real product uses the 3000ms default.
- **N-2 — New Game fires two autosaves back-to-back.** `goto_beat(START_BEAT)` emits `beat_entered` (-> GameCoordinator `autosave("beat")`) then `scene_intent` (-> SceneRouter `autosave("map")` for OVERWORLD). With the 3000ms debounce the first lands immediately and the second collapses to a single pending write flushed by `_process`. No re-entrancy, no save-during-load. Correct behavior; noted for awareness.

---

## Focused verification

### 1. Autoload ordering & `class_name` removal
- **Order is correct (`project.godot:17-28`):** `Log, RngService, EventBus, ContentDB, SettingsService, GameState` then the R3 coordinators `SaveManager, SceneRouter, GameCoordinator, BattleController`. Godot runs autoload `_ready` in registration order, so by the time `SceneRouter._ready` connects to `EventBus.scene_intent`, EventBus exists; by the time `GameCoordinator._ready` builds the director from ContentDB/GameState/EventBus and connects `beat_entered`/`content_loaded`, all three exist. **No init-order race:** the first `scene_intent` originates from `GameCoordinator.new_game()`/`continue_game()`, both user-driven from the Title screen — long after every autoload is ready. `Boot` is the main scene and runs after all autoloads, so its `content_loaded` emission reaches the already-connected GameCoordinator (which correctly rebuilds the director that was first built over an empty ContentDB at autoload time).
- **`class_name` removal is correct.** No `class_name SaveManager` remains anywhere. Runtime uses the `/root/SaveManager` autoload (e.g. `scene_router.gd:100`, `game_coordinator.gd:123`, `overworld.gd:30`); unit tests use `preload(".../save_manager.gd")` as `SaveManagerScript` (`test_save_manager.gd:5,42`); the integration test uses the `SaveManager` autoload global. No remaining type-annotation/`SaveManager.new()` references that the removal would break. The header comment documents exactly why (a global class would hide the autoload singleton).

### 2. New Game / Continue / autosave correctness
- **New Game resets cleanly.** `GameState.new_run()` (game_state.gd:31-48) re-instantiates `flags`, empties `party`/`inventory`/`quests`/`applied_beats`, clears `current_beat_id`, and reseeds RNG. A second New Game therefore carries **no stale flags, applied-beats, or branch ledger** (the latter because `_build_director()` makes a fresh StoryDirector). Verified by `test_integration_shell::test_new_game_initializes_run_at_start_beat_with_party`.
- **Continue is correctly gated and resumes the saved beat.** `continue_game()` returns false when `sm == null || !has_save()` or load fails; otherwise it rebuilds the director and re-enters `GameState.current_beat_id` (falling back to START_BEAT only if empty). Re-entry does **not** double-apply effects (`apply_beat_effects` is gated by the restored `applied_beats`), it only re-emits presentation + `scene_intent` to re-route to the saved scene. Proven by `test_continue_game_loads_and_routes` and `test_new_game_autosaves_and_continue_round_trips`.
- **No save-during-load / re-entrancy.** `load_latest()` performs no writes; the replay guard blocks every write path (autosave/checkpoint/`_notification`). The post-load `beat_entered` autosave writes the just-loaded (identical) content — benign. Debounce/heartbeat cross-test concerns are real but test-only (see N-1); product defaults are sound.

### 3. Headlessness still holds
- `test_no_nondeterminism` and `test_module_boundaries` both pass, confirming `battle/` (incl. `battle_controller.gd`, which is in nondeterminism scope), `story/`, `leveling/`, and the save serializer-tier are free of clock/OS/global-RNG and of autoload/ui coupling. `story_director.gd` remains `RefCounted`, injects all deps, and never touches the scene tree (its own anti-scene-tree guard still passes). The coordinators (`SceneRouter`, `GameCoordinator`, `SaveManager`, `BattleController`) legitimately use autoloads/`get_tree`, and are excluded from the boundary guard with documented rationale.

### 4. Boot / Title UI
- Headless boot loads content and hands off to `SceneRouter.goto("TITLE")` (deferred), with a resilient `change_scene_to_file` fallback if the router is somehow absent. No script errors.
- `Title.tscn` node paths (`Center/Menu/NewGame|Continue|Settings|Quit`) match `title.gd`; `Overworld.tscn` paths (`HUD/OpenMenu`, `PauseMenu/Panel/Margin/VBox/Close`) match `overworld.gd`. **Continue is disabled when no save exists** (`title.gd:16`). No dead ends: New Game routes to OVERWORLD, the pause-menu close fires `autosave("menu")`, Settings is a logged stub, Quit exits. R3b-only states (BATTLE/CUTSCENE/DIALOGUE/CROSSROADS) are mapped and **gracefully skipped with an info log** when their `.tscn` doesn't exist yet (the "not built yet — staying put (R3b)" path), which is the expected transitional behavior this round.

---

## Bottom line
A clean, contract-faithful integration shell. The five Round-2 follow-ups are all genuinely closed; the two ADR-0009 guard tests are real and non-vacuous; New Game/Continue/autosave are correct; headlessness holds; boot is error-free. The only notes are the in-memory N3 ledger (latent only once back-navigation ships — acceptable and documented for R3a) and a low-risk comment-stripper edge in the nondeterminism guard. **APPROVE WITH MINOR FIXES — merge PR #5.**
