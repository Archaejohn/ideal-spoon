# Aetherbound — System Architecture

> **Status:** Accepted · **Date:** 2026-06-30 · **Phase:** 2 (design only — no gameplay code yet).
> This is the binding system overview for the whole game. It is implemented per the ADRs in
> `docs/decisions/ADR-0003 … ADR-0009`. It honors `DEFINITION_OF_DONE.md` (esp. #4 battle, #9
> tests, #13 saving, #14 ending replay), `CONTRIBUTING.md`, and the locked story in
> `docs/story/03_MAIN_STORY.md` + `04_BRANCHES_ENDINGS.md`. Engine/language are fixed by
> `ADR-0001` (Godot 4.x, GDScript, GUT).

---

## 1. Design north stars (non-negotiable)

1. **Deterministic, headless core.** All game *logic* — battle math, turn order, status ticks,
   story-flag transitions, branch gating, the ending resolver, save serialization, inventory and
   leveling — lives in plain `RefCounted`/`Resource` classes with **no scene-tree dependency** and
   **no direct access to global singletons**. They take their inputs (including a seeded RNG) by
   injection. This is what makes ≥80% GUT coverage on logic modules achievable (`ADR-0009`).
2. **Strict data/code separation.** Content (beats, branches, items, enemies, abilities, statuses,
   party, dialogue, quests) is authored as JSON under `game/data/` and validated on load. Engineers
   change *code*; writers/designers change *data*. No story IDs or balance numbers are hard-coded in
   `.gd` files (`ADR-0007`).
3. **One source of truth for run state.** `GameState` holds the entire savable run; `SaveManager`
   serializes exactly that. Nothing savable lives anywhere else (`ADR-0005`).
4. **Single seeded RNG.** Exactly one `RngService` produces all randomness, in named streams, and its
   seed/cursors are saved so replays and checkpoints are reproducible (`ADR-0009`).
5. **Offline & quiet.** No network, telemetry, or ads — ever. Nothing in the architecture opens a
   socket. (`DEFINITION_OF_DONE` #8.)
6. **Performance budget for low-end Android + Chromebook** (see §9).

---

## 2. Autoloads / singletons

Autoloads are **thin coordinators**: they own lifecycle, wire signals, and delegate to headless
logic classes. They never contain battle math or resolver logic directly. Registered in
`project.godot [autoload]` in this order (dependencies first):

| # | Autoload | File | One-line responsibility |
|---|----------|------|--------------------------|
| 1 | `Log` | `src/core/log.gd` | Leveled, ring-buffered local logging (no network); asserts in debug. |
| 2 | `RngService` | `src/core/rng_service.gd` | The single seeded RNG; named deterministic streams; seed/cursor save+restore. |
| 3 | `EventBus` | `src/core/event_bus.gd` | Global typed signal hub so modules stay decoupled (no cross-module hard refs). |
| 4 | `ContentDB` | `src/data/content_db.gd` | Loads + validates all `game/data/**` at boot into read-only typed catalogs. |
| 5 | `SettingsService` | `src/core/settings_service.gd` | Volume, text speed, accessibility; persisted separately from the save. |
| 6 | `GameState` | `src/core/game_state.gd` | The entire savable run: flags, UNITY, party, inventory, position, RNG cursors, current beat. Single source of truth. |
| 7 | `StoryDirector` | `src/story/story_director.gd` | Drives the beat ledger: advances beats, applies flag/UNITY ops, opens/gates branches, asks `EndingResolver`. |
| 8 | `SaveManager` | `src/save/save_manager.gd` | Fully automatic, atomic, crash-safe saving + battle checkpoints + load/migrate/recover. |
| 9 | `BattleController` | `src/battle/battle_controller.gd` | Bridges the battle scene/UI to the headless `BattleEngine`; emits results. |
| 10 | `SceneRouter` | `src/core/scene_router.gd` | App state machine: boot→title→overworld→battle→cutscene→menu transitions and scene loads. |
| 11 | `AudioDirector` | `src/audio/audio_director.gd` | Music layers (incl. the diegetic Song-fragment stems) + SFX bus. Stub in Phase 2. |

> **God-object guard:** `GameState` holds data but contains *no* rules — it cannot decide an ending,
> roll damage, or pick a branch. Those live in `EndingResolver`, `BattleEngine`, and `StoryGraph`.

---

## 3. Module boundaries & dependency diagram

Modules are folders under `game/src/`. **Dependencies point downward only**; a lower module never
imports an upper one. The headless logic core (bottom) knows nothing about Godot scenes.

```
                         ┌───────────────────────────────────────────┐
   PRESENTATION          │  ui/  overworld/  (scenes, screens, HUD)   │
   (scene tree)          └───────────────┬───────────────────────────┘
                                         │ calls / listens to signals
                         ┌───────────────▼───────────────────────────┐
   COORDINATORS          │ SceneRouter  StoryDirector  BattleController│
   (autoloads, thin)     │ SaveManager  AudioDirector                  │
                         └───────┬───────────────┬──────────┬─────────┘
                                 │               │          │
            ┌────────────────────▼──┐   ┌────────▼───────┐  │
   HEADLESS │ story/ (logic)        │   │ battle/ (logic)│  │
   LOGIC    │  StoryGraph           │   │  BattleEngine  │  │
   (pure,   │  FlagStore            │   │  TurnScheduler │  │
   testable)│  EndingResolver       │   │  DamageFormula │  │
            │  ReplayPlanner        │   │  StatusEngine  │  │
            └───────┬───────────────┘   │  LevelCurve    │  │
                    │                   └───────┬────────┘  │
            ┌───────▼───────┐   ┌───────────────▼────────┐  │
   SAVE     │ save/ (logic) │   │ inventory/ leveling     │  │
            │  SaveSerializer│  │ (logic)                 │  │
            │  SaveMigrator  │  └───────────┬─────────────┘  │
            │  AtomicFileIO  │              │                │
            └───────┬────────┘              │                │
                    │                       │                │
                    └───────────┬───────────┴────────────────┘
                                │ all read from
                    ┌───────────▼──────────────────────────────────┐
   FOUNDATION       │ core/  : RngService EventBus GameState Log     │
   (no game rules)  │ data/  : ContentDB + schema validators         │
                    │ types/ : shared structs (RefCounted/Resource)  │
                    └───────────────────────────────────────────────┘
```

**Allowed-dependency rules (enforced by review + a lint test in `tests/unit/test_module_boundaries.gd`):**

- `core/`, `types/`, `data/` depend on nothing else (engine only).
- `battle/`, `story/`, `save/`, `inventory/`, `leveling/` logic depend on `core/types/data` only —
  **never** on autoload coordinators, `ui/`, or `overworld/`.
- Coordinators (`StoryDirector`, `BattleController`, `SaveManager`, `SceneRouter`) may use the logic
  modules and `core/`. They talk to each other only through `EventBus` signals or explicit method
  calls, never via global mutable state in another coordinator.
- `ui/` and `overworld/` are the only modules allowed to touch the scene tree for gameplay; they call
  coordinators and read (never mutate directly) `GameState`.

---

## 4. `game/src/` directory layout (concrete)

```
game/
├── project.godot
├── data/                      # CONTENT (writers/designers) — see game/data/README.md
│   ├── beats/                 # one JSON per beat (A1-01 … A4-07), or grouped per act
│   ├── branches/              # BR1–BR4 definitions
│   ├── flags/                 # flag registry + UNITY source table (validation source of truth)
│   ├── items/                 # consumables, gear, key items
│   ├── enemies/               # enemy stat blocks
│   ├── abilities/             # party + enemy abilities
│   ├── statuses/              # status-effect definitions
│   ├── party/                 # playable members (Wren, Sable, …) base stats + growth
│   ├── dialogue/              # dialogue line sets, keyed by beat/scene
│   ├── quests/                # CQ-/SQ-/MA- quest definitions
│   ├── endings/               # ending metadata + divergence-point map (ADR-0006)
│   ├── level_curves/          # XP→level tables, stat growth curves
│   ├── schema/                # JSON-schema-style spec docs (human + validator reference)
│   └── README.md              # the content pipeline
│
├── src/
│   ├── core/                  # FOUNDATION (no game rules)
│   │   ├── log.gd
│   │   ├── rng_service.gd            # autoload
│   │   ├── event_bus.gd              # autoload
│   │   ├── game_state.gd             # autoload (data only)
│   │   ├── settings_service.gd       # autoload
│   │   └── scene_router.gd           # autoload (app state machine)
│   │
│   ├── types/                 # shared immutable-ish structs (RefCounted / Resource)
│   │   ├── stats.gd                  # combatant stat block
│   │   ├── ids.gd                    # ID constants & enums (FinalChoice, EndingId, BattleResult…)
│   │   └── result.gd                 # Result/Ok/Err helper for loaders & validators
│   │
│   ├── data/                  # data loaders + validation
│   │   ├── content_db.gd             # autoload
│   │   ├── json_loader.gd            # read + parse + locate
│   │   └── validators/               # one validator per schema (beat, enemy, ability, …)
│   │
│   ├── story/                 # STORY LOGIC (headless) + coordinator
│   │   ├── story_director.gd         # autoload (coordinator)
│   │   ├── story_graph.gd            # beat traversal + branch gating (pure)
│   │   ├── flag_store.gd             # boolean flags + UNITY integer (pure)
│   │   ├── flag_ops.gd               # SET/INC/DERIVE op interpreter (pure)
│   │   ├── ending_resolver.gd        # resolveEnding() — mirrors 04 EXACTLY (pure)
│   │   └── replay_planner.gd         # ADR-0006 divergence reconstruction (pure)
│   │
│   ├── battle/                # BATTLE LOGIC (headless) + coordinator
│   │   ├── battle_controller.gd      # autoload (scene/UI bridge)
│   │   ├── battle_engine.gd          # the ATB simulation (pure, RNG injected)
│   │   ├── turn_scheduler.gd         # ATB gauge + ready-queue ordering (pure)
│   │   ├── damage_formula.gd         # deterministic damage/heal math (pure)
│   │   ├── status_engine.gd          # status apply/tick/expire (pure)
│   │   ├── combatant.gd              # runtime combatant state (RefCounted)
│   │   └── battle_action.gd          # action intent struct (RefCounted)
│   │
│   ├── inventory/             # inventory + equipment logic (headless)
│   │   └── inventory.gd
│   ├── leveling/              # XP/level/growth logic (headless)
│   │   └── level_system.gd
│   │
│   ├── save/                  # SAVE LOGIC (headless) + coordinator
│   │   ├── save_manager.gd           # autoload (triggers, lifecycle hooks, checkpoints)
│   │   ├── save_serializer.gd        # GameState <-> dict (pure)
│   │   ├── save_migrator.gd          # version N→N+1 migrations (pure)
│   │   └── atomic_file_io.gd         # temp-write + rename + backup + validate (thin IO)
│   │
│   ├── audio/
│   │   └── audio_director.gd         # autoload (stub Phase 2)
│   │
│   ├── ui/                    # PRESENTATION (scenes)
│   │   ├── Boot.tscn / boot.gd
│   │   ├── Title.tscn / title.gd
│   │   ├── menu/                     # pause, settings, party, inventory screens
│   │   ├── dialogue/                 # dialogue/cutscene player
│   │   ├── battle/                   # battle scene + HUD (drives BattleController)
│   │   └── crossroads/               # ending-replay selector (ADR-0006)
│   │
│   └── overworld/             # PRESENTATION (maps)
│       ├── overworld.gd / .tscn      # sky-map / region travel
│       ├── town.gd
│       └── dungeon.gd
│
├── tests/                     # GUT (ADR-0009)
│   ├── unit/                  # headless logic tests (the ≥80% target lives here)
│   ├── integration/           # coordinator + scene-light tests
│   └── helpers/               # fixtures, fake RNG, in-memory FS, sample content
│
├── addons/gut/                # vendored test runner
└── assets/                    # imported art/audio (out of scope for Phase 2)
```

---

## 5. App data flow

```
Boot (ui/Boot)               ── SceneRouter.boot()
  → ContentDB.load_all()     ── parse + validate game/data/**  (fail-fast on schema error in debug)
  → SettingsService.load()
  → SaveManager.detect_save()
  → SceneRouter.goto(TITLE)

Title                        ── Continue?  → SaveManager.load_latest() → GameState restored
                                New?       → GameState.new_run(seed) → StoryDirector.goto_beat("A1-01")

StoryDirector.advance(beat)  ── reads ContentDB.beat(id)
  → applies flag/UNITY ops to GameState.flag_store (via FlagStore/FlagOps)
  → emits EventBus.beat_entered(id)
  → tells SceneRouter what scene the beat needs (dialogue / battle / overworld / branch-choice)
  → SaveManager.autosave("beat_transition")           # ADR-0005 trigger

Branch choice (e.g. BR1)     ── ui presents options → player picks
  → StoryDirector.choose(branch_id, option_id) → sets flags → routes to chosen beat

Battle                       ── BattleController.start(encounter, rng_stream)
  → SaveManager.write_checkpoint("pre_battle")        # ADR-0005 (c): lose → return here
  → BattleEngine.run() steps deterministically; UI animates from emitted events
  → on win:  apply XP/loot (leveling + inventory) → GameState updated → resume story
  → on lose: SaveManager.restore_checkpoint("pre_battle") → never title, never restart

A3-13  ENDING_FLAGS_LOCKED   ── StoryDirector freezes UNITY + computes derived flags
A4-06  FINAL_CHOICE          ── options offered = EndingResolver.offered_options(flags, unity)
A4-07  ENDING                ── ending = EndingResolver.resolve(flags, unity, final_choice)
  → GameState.record_ending(ending, divergence_snapshot)  # unlocks replay (ADR-0006)
  → SaveManager.autosave("ending_reached")

Post-game                    ── Crossroads selector (ui/crossroads) lists unlocked endings
  → ReplayPlanner.build_state(ending) → GameState restored to that divergence point
  → StoryDirector.goto_beat(divergence_beat) → play forward
```

Lifecycle autosave hooks (always-on, see ADR-0005): `SaveManager` connects to
`NOTIFICATION_APPLICATION_PAUSED`, `NOTIFICATION_WM_GO_BACK_REQUEST`, `NOTIFICATION_WM_CLOSE_REQUEST`,
`NOTIFICATION_APPLICATION_FOCUS_OUT`, plus a periodic timer and the explicit beat/map/menu triggers.

---

## 6. Data ↔ code separation

- **Code** (`src/`) contains rules and shapes; **data** (`data/`) contains content and numbers.
- `ContentDB` loads every `data/**` file at boot, runs each through its `validators/` validator, and
  exposes **read-only** typed accessors: `ContentDB.beat(id)`, `.enemy(id)`, `.ability(id)`,
  `.item(id)`, `.status(id)`, `.branch(id)`, `.quest(id)`, `.party_member(id)`, `.ending(id)`.
- IDs are the contract and come straight from the story docs: beat IDs `A1-01…A4-07` (incl. `A1-06a`,
  `A2-10b`, `A3-04b`, `A3-13b`), branches `BR1–BR4`, quests `CQ-*/SQ-*/MA-*`, and the flag names in
  `04 §3`. The flag **registry** (`data/flags/`) is the single validation source: any flag a beat
  tries to set must exist there, and any flag the resolver reads must be marked gating; non-gating
  emotional/Piggy flags are marked `gating: false` so the resolver lint can prove they never feed it.
- In debug/CI, schema or unknown-ID errors are **fatal** (fail-fast); in release the loader logs and
  degrades gracefully where safe. Validation rules live in `ADR-0007`.

---

## 7. Public interfaces (GDScript-style pseudosignatures)

> These are the contracts engineers build against in Phase 3. Types use Godot conventions
> (`Dictionary`, `Array`, typed where helpful). Pure-logic classes take their dependencies by
> injection; coordinators wrap them.

### 7.1 `RngService` (autoload) — `core/rng_service.gd`
```gdscript
func seed_run(master_seed: int) -> void          # set at New Game; saved to GameState
func stream(name: String) -> RngStream            # named substream: "battle","loot","dance","story"
# RngStream (RefCounted) — the injectable unit:
class RngStream:
    func randi() -> int
    func randi_range(a: int, b: int) -> int
    func randf() -> float
    func chance(p: float) -> bool                  # p in [0,1]
    func get_cursor() -> int                        # # of draws taken (saved)
    func set_cursor(n: int) -> void                 # restore for replay/checkpoint
func export_state() -> Dictionary                   # {master_seed, cursors:{stream:int}}
func import_state(d: Dictionary) -> void
```

### 7.2 `GameState` (autoload, data only) — `core/game_state.gd`
```gdscript
var flags: FlagStore                  # booleans + UNITY
var party: Array                       # PartyMemberState (id, level, xp, equipment, learned)
var inventory: Inventory
var current_beat_id: String
var location_id: String
var rng_state: Dictionary              # from RngService.export_state()
var endings_unlocked: Array            # [EndingId] for the Crossroads selector
var divergence_snapshots: Dictionary   # ending_id -> snapshot (ADR-0006)
var playtime_secs: float
var save_version: int

func new_run(master_seed: int) -> void
func to_dict() -> Dictionary           # delegated to SaveSerializer
func from_dict(d: Dictionary) -> void
func snapshot() -> Dictionary          # deep copy for checkpoints
```

### 7.3 `FlagStore` (pure) — `story/flag_store.gd`
```gdscript
func get_flag(name: String) -> bool
func set_flag(name: String, value: bool = true) -> void
func unity() -> int                                 # 0..8, monotonic non-decreasing
func add_unity(n: int = 1) -> void                  # only when not locked
func lock_endings() -> void                         # called at A3-13; freezes UNITY, computes derived
func is_locked() -> bool
# derived (computed, never authored):
func warden_truth_whole() -> bool
func factions_united() -> bool
func to_dict() -> Dictionary
func from_dict(d: Dictionary) -> void
```

### 7.4 `EndingResolver` (pure, static) — `story/ending_resolver.gd`
```gdscript
# Mirrors 04 §5 EXACTLY. flags: FlagStore (or dict), final_choice: ids.FinalChoice
static func factions_united(flags, unity: int) -> bool
static func offered_options(flags, unity: int) -> Array   # subset of [SLEEP,TAKE,SHARE,WAKE]
static func resolve(flags, unity: int, final_choice: int) -> int   # returns EndingId A/B/C/D
```

### 7.5 `StoryGraph` + `StoryDirector`
```gdscript
# StoryGraph (pure) — story/story_graph.gd
func next_beats(beat_id: String, flags: FlagStore) -> Array   # gated successors
func is_branch_node(beat_id: String) -> bool
func branch_options(branch_id: String) -> Array

# StoryDirector (autoload) — story/story_director.gd
func goto_beat(beat_id: String) -> void
func advance() -> void                                # to next non-branch beat
func choose(branch_id: String, option_id: String) -> void
func apply_beat_effects(beat_id: String) -> void      # runs flag/UNITY ops from data
signal beat_entered(beat_id)
signal branch_opened(branch_id, options)
signal flags_locked()
```

### 7.6 `BattleEngine` (pure) — `battle/battle_engine.gd`
```gdscript
# Constructed headless; rng is an RngStream; defs come from ContentDB (passed in, not global).
func _init(party: Array, enemies: Array, defs: BattleDefs, rng) -> void
func step(dt_ticks: int) -> Array                     # advance ATB; returns events
func queue_action(action: BattleAction) -> void       # actor, ability_id, targets
func is_over() -> bool
func result() -> int                                  # BattleResult.WIN / LOSE
func snapshot() -> Dictionary                          # full deterministic state (for tests)
# helpers used internally and unit-tested directly:
#   TurnScheduler.next_ready(combatants) -> Combatant
#   DamageFormula.compute(attacker, defender, ability, rng) -> int
#   StatusEngine.tick(combatant) -> Array
```

### 7.7 `SaveManager` (autoload) — `save/save_manager.gd`
```gdscript
func autosave(reason: String) -> void                 # debounced; reason for telemetry-free logging
func write_checkpoint(label: String) -> void          # "pre_battle"
func restore_checkpoint(label: String) -> bool
func load_latest() -> bool                             # validate; recover from backup on corruption
func has_save() -> bool
func _notification(what: int) -> void                  # lifecycle hooks (pause/back/close/focus-out)
# uses SaveSerializer (pure), SaveMigrator (pure), AtomicFileIO (thin)
```

### 7.8 `ReplayPlanner` (pure) — `story/replay_planner.gd`  (ADR-0006)
```gdscript
static func divergence_beat_for(ending_id: int) -> String
static func build_state(ending_id: int, unlocked_snapshot: Dictionary) -> Dictionary
                                                       # returns a valid GameState dict at the
                                                       # divergence point that can reach that ending
static func is_unlocked(ending_id: int, game_state) -> bool
```

### 7.9 `SceneRouter` (autoload) — `core/scene_router.gd`
```gdscript
enum AppState { BOOT, TITLE, OVERWORLD, TOWN, DUNGEON, BATTLE, CUTSCENE, MENU, CROSSROADS }
func goto(state: int, ctx: Dictionary = {}) -> void
func push_overlay(scene_path: String) -> void         # menu/dialogue over a base scene
func pop_overlay() -> void
signal state_changed(old_state, new_state)
```

---

## 8. Testing strategy (GUT) — summary (full detail in ADR-0009)

- **Where:** `game/tests/unit/` (headless logic), `tests/integration/` (coordinators), `tests/helpers/`
  (fixtures, `FakeRng`, in-memory FS, sample content under `tests/helpers/content/`).
- **Coverage target:** **≥80%** on non-UI logic modules: `battle/`, `story/`, `save/`, `inventory/`,
  `leveling/`, `data/validators/`. UI/scene code is exercised by lighter integration tests, not held
  to 80%.
- **Determinism enforcement:** every test that touches randomness injects a `FakeRng` or a fixed-seed
  `RngStream`; no test reads the wall clock or `OS`-level entropy. A guard test asserts that no logic
  module references `randi()`/`randf()` global functions or `Time`/`OS` directly (they must go through
  `RngService`).
- **Must-test list (DoD #9, #13, #14):** battle damage/heal math, status apply/tick/expire, ATB turn
  ordering & ties, level-up/XP curves, inventory add/remove/equip, **save↔load round-trip**,
  **migration N→N+1**, **battle-checkpoint restore**, **corruption→backup recovery**, every story-flag
  transition in the ledger, each branch's flag outcomes, UNITY accumulation & freeze at A3-13, derived
  flags (`WARDEN_TRUTH_WHOLE`, `FACTIONS_UNITED`), **`resolveEnding` for all four endings + gating**,
  and **ending-replay reconstruction** for each divergence point.
- **CI:** `.github/workflows/ci.yml` runs the full GUT suite headless on every PR; red blocks merge
  (`CONTRIBUTING.md`).

---

## 9. Performance budget (low-end Android + Chromebook)

| Concern | Budget / rule |
|---|---|
| Target frame | 30 FPS floor on a low-end phone; 60 where free. Battle math is O(combatants) per tick and runs off the render path. |
| Boot content load | `ContentDB.load_all()` ≤ ~1.5s on low-end; JSON parsed once, cached as typed dicts. Large data may be sharded per act and lazy-loaded. |
| Memory | Keep loaded textures modest; SVGs rasterized at import (ADR-0001). No giant atlases held for unused acts. |
| Allocation in battle loop | No per-tick `Dictionary`/`Array` churn in `BattleEngine.step`; reuse buffers; events are small structs. |
| Save writes | Atomic write of a compact JSON (or binary `var_to_bytes`) save; autosave debounced (≥ a few seconds between writes) to avoid I/O stalls; periodic timer ~30–60s. |
| Renderer | `gl_compatibility` (already set in `project.godot`) for broad device support. |
| No background work | No threads doing network/telemetry; the only timer is the autosave heartbeat. |

---

## 10. Open items handed to the ADRs

- Story-graph & flag/quest engine → **ADR-0003**
- ATB battle engine → **ADR-0004**
- Save & persistence (incl. checkpoints, Chromebook/web OPFS) → **ADR-0005**
- Ending-replay / Crossroads selector → **ADR-0006**
- Content data schema & pipeline → **ADR-0007**
- Scene flow & app state machine → **ADR-0008**
- Determinism, RNG & testing strategy → **ADR-0009**
```
