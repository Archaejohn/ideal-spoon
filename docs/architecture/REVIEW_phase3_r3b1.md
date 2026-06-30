# Code Review — Phase 3 R3b-1 (playable ATB battle + pre-battle checkpoint/lose loop)

- **Branch:** `feat/phase3-r3b-battle`  (commit `837b320`, PR #6)
- **Reviewer:** Independent (did not author the code)
- **Date:** 2026-06-30
- **Contracts checked:** ADR-0004 (ATB), ADR-0005 (checkpoint/save), ADR-0009 (determinism), PHASE2_OWNER_RULINGS #1 (WAIT mode) / #2 (pre-battle checkpoint = resume unit), DEFINITION_OF_DONE #4 & #13.

## Verdict: APPROVE WITH MINOR FIXES (non-blocking) — mergeable

The win-detection change is correct, determinism is preserved, the Owner-#13
checkpoint/lose loop is implemented and tested correctly, the UI is logic-free,
and the new content is valid and referentially consistent. The two minor items
below are non-blocking (no divergence with the shipped data) and may be merged
as-is or landed as quick follow-ups.

### Evidence
- `bash tools/run_tests.sh` → **135/135 passing**, 2183 asserts, 22 scripts.
- Headless import: clean.
- Headless boot (`--headless --path game --quit-after 120`): **no script errors**;
  `[INFO][Boot] Content loaded: 5 beats, 25 flags.`

---

## 1. BattleEngine win-detection change — CORRECT

`_post_turn()` now calls `_is_decided()` instead of `is_over()`
(`battle_engine.gd:206-225`).

- **Fires at the right moment.** `_post_turn()` runs `_sweep_downs()` first, then
  `_is_decided()`, so a side-wipe is detected immediately after the deciding
  turn resolves (and also after the status-tick death path at
  `battle_engine.gd:186-189`). This is exactly what the old code missed: the
  previous `is_over()` check only returned true once `_result` was already set,
  so a turn-by-turn driver (`process_next_turn`) never terminated on a side-wipe
  — only `run_until_over`'s trailing `_finish()` did. The new code makes the
  playable `advance()`/`peek` path terminate correctly.
- **No turn-order / determinism regression.** `_is_decided()` reads only
  `is_alive()`; it consumes no RNG and emits no events. `run_until_over` reaches
  an identical final `_result` (it now just calls `_finish()` one iteration
  earlier). The existing engine unit tests
  (`test_battle_engine.gd`) remain *semantically* valid, not merely green:
  `run_until_over` WIN/LOSE, the same-seed identical-stream test, retarget, and
  the mid-battle cursor save/restore all still assert the same observable
  outcomes.
- **`peek_next_actor()` preserves determinism (`battle_engine.gd:150-160`).** It
  mirrors `process_next_turn`'s time-advance (`ticks_until_next_ready` +
  `advance`) but resolves nothing. After a peek advances ATB, the following
  `process_next_turn` finds a ready actor and does **not** advance again, so the
  same actor resolves with the same RNG draws. The peek-driven UI path and the
  `run_until_over` test path are therefore equivalent for a given seed. Peek is
  idempotent (a second peek returns the same actor with no further advance) and
  consumes no RNG.
- **Edge cases.** Simultaneous both-side wipe → `_finish()` evaluates
  `not enemies_alive` first → WIN; this is effectively unreachable in one turn
  because an action only damages one side and the only self-inflicted death
  (DoT) is the actor's own. FLEE short-circuits via `_result != ONGOING` and
  `_finish()`'s FLED branch returns before computing a win/lose side count. No
  mis-fire found.

## 2. Checkpoint / lose-restore (Owner #13) — CORRECT and robust

Trace: `start_battle` (`game_coordinator.gd:119`) records `_pre_battle_beat`
→ `BattleController.start` emits `checkpoint_requested("pre_battle")`
(`battle_controller.gd:42`) → `_on_checkpoint_requested`
(`game_coordinator.gd:166`) → `SaveManager.write_checkpoint`
(`save_manager.gd:107`) → `GameState.snapshot()` → `to_dict()` which refreshes
`rng_state = rng.export_state()`.

- **Checkpoint written BEFORE any battle RNG is consumed.** In
  `BattleController.start` the `checkpoint_requested` signal is emitted *first*
  (line 42, synchronous handler), then `setup()` runs (consumes no RNG), then
  events. The first RNG draw happens later in `process_next_turn` (driven by the
  UI `_pump`). So the checkpoint captures the pre-battle `battle`/`ai` cursors.
  Confirmed by `test_battle_flow.gd:70,86`.
- **Restore truly rolls back everything.** `restore_checkpoint` →
  `GameState.restore_snapshot` → `from_dict` restores party (HP/level/XP),
  inventory, `current_beat_id`, `applied_beats`, flags, location, **and** RNG
  cursors via `rng.import_state` → `set_cursor` (reseed + replay-N, exact per
  ADR-0009). The LOSE test drifts `party=[]` and `current_beat_id="DRIFTED"`
  and asserts all are restored and the battle cursor equals the pre-battle
  cursor (`test_battle_flow.gd:77-86`). A retry is therefore consistent and
  non-exploitable.
- **LOSE never routes to Title.** `after_battle()` LOSE branch
  (`game_coordinator.gd:141-151`) restores and re-enters the pre-battle beat
  (→ BATTLE). There is no Title path anywhere in `after_battle`. Even if
  `restore_checkpoint` returned false, it still falls back to `_pre_battle_beat`
  → `goto_beat` → BATTLE. Asserted: `assert_false(_routed.has(TITLE_SCENE))`.
- **WIN rewards applied exactly once.** `_on_battle_over` (`game_coordinator.gd:172`)
  applies XP→LevelSystem and loot→inventory once; `battle_over` is emitted once
  (`battle_controller.advance` guards on `is_over()` before re-emitting), and WIN
  does not re-enter the fight, so there is no double-grant. `_apply_rewards` is
  pure GameState mutation; the engine never touched persistent state.

## 3. UI is logic-free — CONFIRMED

`battle_ui.gd` holds no battle math. It drives the controller via
`start`/`queue_action`/`advance`/`peek_next_actor` and renders the BattleEvent
stream from `battle_started`/`events_emitted`/`battle_over`. It reads only
`hp_cur`/`atb`/`is_alive()`/`side` and `target_kind` (a data lookup), and uses
the scene tree / autoloads legitimately. WAIT mode is honored (gauges pause while
the action menu is open; `peek` decides player-menu vs. auto-resolve). The
module-boundary and no-nondeterminism guard tests pass (135 green). All
`get_node` paths in `battle_ui.gd` match `Battle.tscn` node names (verified
ActionMenu/VBox/{Attack,Ability,Item,Defend,Flee}, ChoiceList, VictoryPanel,
DefeatPanel, EnemyRow, PartyRow, Log).

## 4. Content validity — VALID and referentially consistent

- `SLICE-BATTLE` beat carries `encounter: "sleepless_crane"` and
  `checkpoint: true`; StoryDirector propagates it via `_scene_ctx`
  (`story_director.gd:160-166`) → `SceneRouter.current_ctx()` → `battle_ui`
  reads it in `_ready`. Verified end-to-end by the smoke test
  (`scene._encounter_id == "sleepless_crane"`).
- All references resolve: encounter → enemies `sleepless_crane`, `hollow_husk`;
  reward item `lamp_herb` (data/items/example_item.json, id `lamp_herb`);
  enemy-AI abilities `crane_sweep`, `hollow_screech`, `husk_peck`; ability
  `APPLY_STATUS` → `rattled`, `songsick` (data/statuses/example_status.json, id
  `songsick`); party abilities `song_lash`, `steady`, `tam_bolt`, `tinker_mend`.
  Beat spine `SLICE-START → SLICE-BATTLE → SLICE-AFTER` all exist.
- Schema validation passes at boot (non-strict for the shipped sampler, per
  ContentDB.load_all design); the new beat fields `encounter`/`checkpoint` are
  accepted as optional extras.

---

## Findings (ranked by severity)

### MINOR-1 (low, pre-existing) — `rewards()` is non-idempotent and rolled twice on WIN
- **Files:** `battle_engine.gd:408` (`_finish` embeds `rewards()` in the
  BATTLE_OVER event) and `battle_controller.gd:63`
  (`emit_signal("battle_over", _engine.result(), _engine.rewards())`).
- **Defect:** `rewards()` rolls loot on the `battle` RNG stream
  (`rewards()` → `chance_permille`, `battle_engine.gd:423/430`). It is called
  twice per WIN: once to embed in the in-stream BATTLE_OVER event, once for the
  signal the coordinator actually grants from. This consumes the loot rolls
  twice and the granted set (call #2) can differ from the set reported in the
  event stream (call #1).
- **Failure scenario:** With the shipped slice data (`chance_permille: 1000`)
  both calls yield `[lamp_herb]`, so there is **no current divergence** — hence
  non-blocking. But the battle cursor double-advances (then gets persisted by the
  `battle_win` autosave), and as soon as any loot item has `chance < 1000`, the
  victory event's reported loot will not match what is granted to the inventory.
- **Fix:** Compute rewards once inside `_finish()` into a cached field (e.g.
  `_final_rewards`) and have `rewards()` return the cached dict when the battle
  is over. (Pre-dates this PR but now sits on the live playable path.)

### MINOR-2 (medium for a "playable" milestone) — player action-menu path has zero test coverage
- **Files:** `battle_ui.gd` handlers `_open_action_menu`/`_on_attack`/
  `_on_ability`/`_choose_ability`/`_on_item`/`_consume_lamp_herb`/
  `_begin_target_select`/`_pick_target`/`_submit`; tests
  `test_battle_flow.gd`, `test_battle_scene_smoke.gd`.
- **Defect:** Neither integration test drives a turn *through the UI*.
  `test_battle_flow` drives the **controller** directly (attack-only / defend-
  only); `test_battle_scene_smoke` calls `BattleController.advance()` directly
  and never opens the action menu. So the entire player-input surface
  (ability-use, item-use/herb consumption, target selection, FLEE-success) is
  unexercised — a wrong node path or signature in those handlers would not be
  caught. The smoke test only covers `_ready` + the event-render path.
- **Failure scenario:** A regression in a menu handler ships green. (I traced
  the handlers manually and found no current bug — node paths and signatures are
  correct — so this is a coverage gap, not a known defect.)
- **Fix:** Add a headless test that, via the scene, opens the menu for a ready
  player actor and submits at least one Attack/Ability/Item action
  (queue + submit), plus a flee-enabled encounter test asserting FLED →
  overworld route.

### NOTE-1 (low) — item consumed before engine resolution
- **File:** `battle_ui.gd:239-243` (`_pick_target` calls `_consume_lamp_herb`
  before `_submit`).
- The herb is decremented from GameState inventory before the engine resolves;
  if the ITEM action FIZZLEs (e.g. no valid target) the herb is lost with no
  effect. Acceptable for the slice (a LOSE rolls it back via checkpoint; a WIN
  legitimately consumes it), but consider deducting on confirmed resolution.

### NOTE-2 (low, not this PR's scope) — validator does not check ability→status refs
- `ContentValidator.validate_references` checks encounter→enemy/item and
  enemy-AI→ability, but not `APPLY_STATUS` `status` references. `songsick`/
  `rattled` happen to exist, so the slice is consistent; flagging the blind spot
  for a future strict-content pass.

---

## Contract compliance summary
- **ADR-0004 (ATB / retarget-or-fizzle / WAIT):** met. Engine owns all math;
  controller and UI are bridges; WAIT mode honored via `peek_next_actor`.
- **ADR-0005 §c (pre-battle checkpoint) / Owner #13:** met. Checkpoint = resume
  unit, written before battle RNG, restored on LOSE, retry routes to BATTLE,
  never Title.
- **ADR-0009 (determinism):** met. Peek/advance equivalent to `run_until_over`;
  cursors export/import bit-exact; only `rewards()`'s double loot-roll is a
  non-idempotent smell (MINOR-1).
- **PHASE2_OWNER_RULINGS #1/#2:** met.
- **DoD #4 (battle) & #13 (resilient save/checkpoint):** met (with the
  player-input test gap, MINOR-2, recommended before calling the battle fully
  "verified by tests").
