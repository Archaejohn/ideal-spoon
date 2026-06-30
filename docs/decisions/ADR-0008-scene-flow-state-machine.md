# ADR-0008: Scene flow & app state machine

- **Status:** Accepted
- **Date:** 2026-06-30
- **Deciders:** Architect, Owner

## Context

The game needs a clear, testable flow from Boot → Title → New/Continue → the playable world
(Overworld/Town/Dungeon) → Battle → Cutscene/Dialogue → Menu, and back. `DEFINITION_OF_DONE.md` #1
requires a working shell (Title, New Game, Continue, Settings, Credits) with automatic saving and a
"Continue" that resumes exactly where the player left off. The **story engine drives scene loads** (a
beat declares its scene type, ADR-0003/0007), and the **save/checkpoint hooks** (ADR-0005) must sit at
well-defined points in this flow. Scenes are presentation; the autoload coordinators own
transitions.

## Options considered

1. **Ad-hoc `change_scene_to_file` calls scattered through scripts.** Fast but untraceable; no single
   place to hook autosave/checkpoint; hard to test; easy to leave the game in a bad state.
2. **A central `SceneRouter` finite state machine that owns all transitions, with the
   `StoryDirector` telling it what each beat needs.** One place for transitions, save hooks, and
   overlays; states are explicit and testable. Chosen.

## Decision

`core/scene_router.gd` (autoload) is a finite **app state machine**. It is the only place that loads or
swaps top-level scenes and manages overlays. `StoryDirector` decides *which* state a beat needs;
`SceneRouter` performs the transition and fires the right save hook.

### States

```
enum AppState { BOOT, TITLE, OVERWORLD, TOWN, DUNGEON, BATTLE, CUTSCENE, MENU, CROSSROADS }
```

- **BOOT** — `ui/Boot`: `ContentDB.load_all()`, `SettingsService.load()`, `SaveManager.detect_save()`,
  then `goto(TITLE)`.
- **TITLE** — `ui/Title`: New Game, Continue (enabled iff `SaveManager.has_save()`), Settings, Credits,
  and Crossroads (enabled iff `GAME_COMPLETED`).
- **OVERWORLD / TOWN / DUNGEON** — `overworld/*`: explorable scenes; entering/leaving each fires an
  autosave (ADR-0005 "overworld map change").
- **BATTLE** — `ui/battle/*`: hosts `BattleController`; entered with an encounter context.
- **CUTSCENE** — `ui/dialogue/*`: plays a dialogue/cutscene set; covers both `scene:"dialogue"` and
  `scene:"cutscene"` beats and branch-choice presentation (`scene:"branch"`).
- **MENU** — pause/inventory/party/settings, pushed as an **overlay** over the current base scene; its
  close fires an autosave.
- **CROSSROADS** — `ui/crossroads/*`: post-game ending-replay selector (ADR-0006).

### Transition API

```gdscript
func goto(state: int, ctx: Dictionary = {}) -> void   # swap the base scene; ctx carries beat/encounter ids
func push_overlay(scene_path: String, ctx := {}) -> void  # MENU/dialogue over a base scene
func pop_overlay() -> void
signal state_changed(old_state, new_state)
```

`goto` runs a uniform sequence: emit `state_changed` → (optional fade) → free old base scene → load new
→ pass `ctx`. Overlays keep the base scene alive (paused) so returning is instant and stateful.

### How the story engine drives scene loads

The beat record's `scene` field (ADR-0007) maps to a state:

| `scene` | SceneRouter target |
|---|---|
| `dialogue`, `cutscene` | `CUTSCENE` |
| `branch` | `CUTSCENE` (presents `branch_options`, then `StoryDirector.choose`) |
| `battle` | `BATTLE` (with `encounter` id) |
| `overworld` | `OVERWORLD`/`TOWN`/`DUNGEON` (per `location`) |
| `ending` | `CUTSCENE` (epilogue), then `CROSSROADS` unlock |

Flow per beat:
```
StoryDirector.goto_beat(id)
  → apply_beat_effects(id)                     # flags/UNITY (ADR-0003)
  → EventBus.beat_entered(id)
  → SaveManager.autosave("beat_transition")    # ADR-0005 trigger
  → SceneRouter.goto(state_for(beat), {beat_id:id, encounter:beat.encounter, location:beat.location})
  → (scene finishes) → EventBus.scene_complete → StoryDirector.advance()/choose()
```

### Where save/checkpoint hooks sit (ADR-0005)

| Point in flow | Hook |
|---|---|
| Every `goto_beat` | `autosave("beat_transition")` |
| Enter/leave OVERWORLD/TOWN/DUNGEON | `autosave("map_change")` |
| `pop_overlay` of MENU | `autosave("menu_close")` |
| Enter BATTLE | `write_checkpoint("pre_battle")` **before** the engine starts |
| Battle LOSE | `restore_checkpoint("pre_battle")` → `goto` the pre-battle base state |
| Lifecycle (pause/back/close/focus-out) | `SaveManager._notification` immediate write (any state) |
| Reach `A4-07` ending | `autosave("ending_reached")` + record unlock (ADR-0006) |

### New Game / Continue / boot resume

- **Continue:** `SaveManager.load_latest()` restores `GameState` (incl. RNG cursors, current beat,
  location) then `StoryDirector.goto_beat(current_beat_id)` resumes exactly where the player left off.
  If a battle was interrupted mid-fight, the pre-battle checkpoint is the resume point (we never persist
  partial battle state), satisfying "resume exactly where you left off" without restarting the game.
- **New Game:** confirm-overwrite if a save exists → `GameState.new_run(seed)` (seed from
  `RngService.seed_run`) → `goto_beat("A1-01")`.

### Testability

`SceneRouter` logic (state-for-beat mapping, transition ordering, overlay stack, hook firing) is
exercised by integration tests with a **stub scene loader** (no real `.tscn` needed): assert that
entering an `A2-07` branch beat goes to CUTSCENE and emits `branch_opened`, that a `scene:"battle"`
beat fires `write_checkpoint` before BATTLE, and that MENU close fires `autosave("menu_close")`.

## Rationale

A single FSM coordinator makes the flow legible and gives exactly one home for the save/checkpoint hooks
that DoD #13 depends on; without it those hooks would be scattered and easy to miss. Letting beats
declare their scene type keeps the story (data) in charge of flow while the engine owns the mechanics —
consistent with ADR-0003/0007. Overlays (rather than scene swaps) for menus keep the base world state
intact, which is both faster on low-end devices and necessary for a clean autosave-on-close.

## Consequences

- Every base-scene change goes through `SceneRouter.goto`; direct `change_scene_*` calls are banned (a
  review rule + a grep guard test).
- Battle is always entered via a path that writes the pre-battle checkpoint, so the lose→retry contract
  is structurally guaranteed, not per-encounter remembered.
- Mid-battle state is intentionally not persisted; the checkpoint is the unit of battle resume, which
  keeps the save schema simple and the "Continue" semantics clear.
- Branch beats reuse the CUTSCENE state to present choices, so adding a branch needs only data, not a
  new state.
