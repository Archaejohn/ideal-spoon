# Independent Code Review — Phase 3 R3b-2 (Narrative Slice / Vertical-Slice Capstone)

- **Branch:** `feat/phase3-r3b-narrative`  (head `78b4f40`)
- **Reviewer role:** independent (did not author this code)
- **Scope:** the narrative slice that completes the vertical slice — beats/branch/flags, Dialogue + Location scenes, SceneRouter map, validator, the two R3b-1 follow-up fixes (MINOR-1/MINOR-2), regression surface, and test quality.

## Verdict: APPROVE WITH MINOR FIXES

The slice logic, data graph, branch semantics, save/checkpoint flow, both R3b-1 fixes, and the regression surface are **correct and well-tested**. There is **one real presentation defect** (Dialogue scene node paths) that does not crash, does not fail any test, and does not break the boot — but it makes the marquee R3b-2 deliverable (the on-screen narrative) render **blank**. It is a trivial 3-line fix and should land before PR #7 is called a *playable* narrative slice.

### Gate results
- `bash tools/run_tests.sh` → **139/139 passing** (2272 asserts, 23 scripts). Matches the expected 139.
- `--headless --path game --import` → clean.
- `--headless --path game --quit-after 120` → clean: `[INFO][Boot] Content loaded: 10 beats, 29 flags.` No script errors.

---

## Findings (ranked by severity)

### H1 — Dialogue scene never renders speaker/line/tint (wrong node paths) — REQUIRED FIX
**File:** `game/src/ui/dialogue/dialogue.gd:77,81,84`
**Defect:** `_show_line()` looks up the content nodes at `Panel/VBox/Speaker`, `Panel/VBox/Tint`, `Panel/VBox/Line`, but the actual scene tree in `Dialogue.tscn` nests them under a `MarginContainer`:
```
Panel → Margin (MarginContainer) → VBox → {Tint, Speaker, Line}
```
so the real paths are `Panel/Margin/VBox/Speaker` etc. (confirmed: `Dialogue.tscn` lines 36/43/47/52/57).

Because the lookups use `get_node_or_null(...)` and every write is guarded by `if x != null`, the three lookups silently return `null` and the speaker name, per-speaker tint, and **the line text are never set**. The scene shows its default authored `Speaker` label and an empty line for the entire sequence. The `Hint` node (`(n/m)` progress) is at the correct root path, so the box *looks* alive while showing no dialogue.

**Failure scenario:** Playing the slice for real, the Meadowmoor opening, the dockside fork prompt, the help/hurry beats, and the closing beat all display an empty dialogue panel. The narrative — the entire point of R3b-2 — is invisible. The branch *choice buttons* still work (`Panel`, `Hint`, `ChoiceBox` are at correct paths), and the spine still advances, so it is functionally navigable but narratively blank.

**Why no test caught it:** no test instantiates `Dialogue.tscn`. The `set_lines()` test seam is never exercised, and the slice e2e test injects a stub SceneRouter loader that only records the route path — the scene is never built, so `_show_line()` never runs under test. The bug is in a completely untested rendering path.

**Fix:** change the three paths to `Panel/Margin/VBox/Speaker`, `Panel/Margin/VBox/Tint`, `Panel/Margin/VBox/Line`. Recommend also adding a tiny headless test that `set_lines([...])`, adds the scene, and asserts `Panel/Margin/VBox/Line.text` matches the injected line — that closes the untested gap permanently.

### L1 — `dialogue_set` referenced but unused (cosmetic / latent)
**Files:** `slice_start.json`, `slice_docks.json`, `slice_help.json`, `slice_hurry.json`, `slice_after.json` (`"dialogue_set"` keys)
The beats carry both an inline `dialogue` array (what the scene reads via `ContentDB.beat_dialogue`) and a `dialogue_set` id that points at no `data/dialogue/` file. `dialogue_set` is optional in the schema and nothing reads it, so this is harmless today, but the dangling ids invite confusion about which is authoritative. Recommend dropping `dialogue_set` from these slice beats or documenting it as a non-loaded annotation.

### L2 — `after_battle()` FLEE comment is now stale
**File:** `game/src/core/game_coordinator.gd` (FLED branch comment)
The comment says "R3b-2 supplies real fleeable encounters" as a future tense; R3b-2 (this branch) already ships `hollow_skirmish` with `flee_allowed:true` and a test for the flee→OVERWORLD route. Comment only; no behavior impact.

---

## Detailed assessment against the review contract

### 1. Slice completeness & correctness — PASS
Graph (all `next`/`goto`/`merge` targets exist; no dead-ends, no unreachable beats):
```
SLICE-START (cutscene, SET SLICE_OPENING_SEEN)
  → SLICE-HOLLOWGATE (town)
    → SLICE-DOCKS (dialogue, trigger BR-SLICE; next→SLICE-WRECK)
        ├─ help  → SLICE-HELP  (SET SLICE_HELPED_DOCKHAND) → SLICE-WRECK
        └─ hurry → SLICE-HURRY (SET SLICE_HURRIED_WRECK)   → SLICE-WRECK
    → SLICE-WRECK (dungeon, MERGE) → SLICE-BATTLE
      → SLICE-BATTLE (battle, checkpoint:true, encounter sleepless_crane) → SLICE-AFTER
        → SLICE-AFTER (cutscene, SET SLICE_BOSS_CLEARED, next:[] terminal → Title)
```
This covers **title (new_game) → cutscene → town → branch → dungeon → ATB battle → pre-battle checkpoint/autosave → closing branch-aware beat**, satisfying the DEFINITION_OF_DONE slice demonstration. Both arms are completable; the e2e test proves both run start→finish. The branch genuinely **diverges** (distinct beats + distinct identity flags) and **merges** (both arms reconverge at `SLICE-WRECK`). No dangling references.

### 2. Branch correctness — PASS
- `GameCoordinator.choose_branch` resolves only the open branch (`current_branch_id()` guard) and delegates to `StoryDirector.choose`, which applies the option's effects then `goto_beat(goto)`.
- Linear advance is blocked while a branch is open: `StoryDirector.advance()` returns err if `_open_branch_id != ""`; verified by `test_branch_blocks_advance_until_choice`.
- N3 double-resolve guard intact: `_resolved_branches[branch_id]` records the chosen option; a *different* option after resolution is refused, the *same* option is idempotent (re-route only, no second flag). The two flags are therefore mutually exclusive in practice — exactly one is ever set. `slice_flags.json` marks both `gating:false, kind:"branch"`, single-owner per ADR-0003. The e2e test asserts the non-chosen arm's flag stays false on both arms.

### 3. Dialogue UI + scenes — PASS with H1
- **Spine continuation:** `dialogue.gd` correctly continues — branch trigger → presents `offered_branch_options()` buttons → `choose_branch`; otherwise `advance_story()`, and routes to TITLE at a terminal beat. Choice/continue node paths (`Panel`, `Hint`, `ChoiceBox`) are correct. No script errors.
- **Rendering:** broken by H1 (speaker/line/tint paths miss the `Margin` container).
- **Location.tscn:** correct for both TOWN and DUNGEON — paths (`CenterLabel`, `SubLabel`, `HUD/Look`, `HUD/Continue`) match the scene; themes off `current_state()`; continue calls `advance_story()`; `Look` fires an autosave hook.
- **SceneRouter map:** every routed state has a scene — `TOWN`/`DUNGEON`→`Location.tscn` (was `Overworld.tscn`), `CUTSCENE`/`DIALOGUE`→`Dialogue.tscn`, `CROSSROADS`→`Crossroads.tscn` (real stub). No routed-but-missing scene remains.
- **Validator:** scene enum extended with `town`,`dungeon`; new `_validate_dialogue` requires an array of `{speaker:non-empty str, line:non-empty str}` and would reject malformed dialogue (wrong type, missing/empty speaker or line). Matches ADR-0007.

### 4. The two R3b-1 fixes — PASS
- **MINOR-1 (rewards once):** `battle_engine.gd:418` rolls rewards exactly once in `_finish()` into `_final_rewards` (`_rewards_rolled` flag), and `rewards()` returns the cache post-finish. The `BATTLE_OVER` event and the controller's `battle_over` signal share that single roll — no double advance of the `battle` RNG stream. `test_rewards_are_rolled_exactly_once_on_win` proves it with `enc_loot_chance` (`chance_permille: 500`, i.e. <100%, so a re-roll *would* diverge): it asserts the `battle` stream cursor is unchanged across two `rewards()` calls, `r1 == r2`, and `BATTLE_OVER.rewards == r1`. Genuine proof.
- **MINOR-2 (menu/flee handlers):** `test_battle_menu_paths.gd` drives the real `battle_ui.gd` handlers (`_open_action_menu`, `_on_ability`+`_choose_ability`, `_on_item`, `_on_flee`, `_pick_target`, `_submit`) and asserts (a) the menu/choice nodes become visible, (b) the correct ABILITY/ITEM `action` event with the right ability id reaches the engine, (c) item consumption decrements inventory, (d) flee on a `flee_allowed:true` encounter yields `FLED` and routes to OVERWORLD. Any handler script error would surface as a test error. Solid coverage of the previously-untested menu surface.

### 5. Regressions — PASS
- StoryDirector remains RefCounted and scene-tree-free; it emits `scene_intent` and never touches the tree (module-boundary guard test still green).
- UI scripts are presentation-only: they read router/coordinator state and call coordinator verbs; no game logic embedded.
- Determinism, save/checkpoint, and existing battle/story tests remain semantically valid; the rewards change is a pure caching refactor with identical first-roll values.

### 6. Test quality — STRONG
`test_slice_integration.gd` asserts real state at every step: exact beat ids on each transition, identity-flag set/clear on both arms, the open branch id, the merge beat, the offered option set, the recorded routes (Dialogue/Location/Battle scene paths), the pre-battle checkpoint existence, a deterministic battle WIN, the closing flag, and terminal-beat behavior. Not superficial. The only gap is that no test instantiates the Dialogue scene itself (the cause H1 slipped through) — recommend the small set_lines render test noted in H1.

---

## Is the Phase-3 vertical slice DONE?

**Functionally / architecturally: yes.** The vertical slice is logically complete and correct end-to-end on both branch arms — title→town→dungeon→ATB battle→checkpoint/autosave→a real diverge-then-merge story branch — with 139/139 tests, a clean headless boot, the two R3b-1 fixes verified, and no regressions or contract violations.

**As a demonstrable narrative slice: not quite, until H1 is fixed.** The Dialogue scene currently renders an empty speaker/line, so the actual playable build shows no story text. This is a trivial 3-path correction with zero architectural impact and no test/boot effect.

**Recommendation:** apply the H1 node-path fix (and ideally the accompanying render test), then merge PR #7. With H1 fixed, this is a clean APPROVE and the Phase-3 vertical slice can be declared DONE. L1/L2 are non-blocking cleanups.
