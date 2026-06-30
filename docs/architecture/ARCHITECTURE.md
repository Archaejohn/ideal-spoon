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
   (pure,   │  FlagStore + FlagView │   │  TurnScheduler │  │
   testable)│  EndingResolver       │   │  DamageFormula │  │
            │  ReplayPlanner        │   │  StatusEngine  │  │
            └───────┬───────────────┘   │  EnemyBrain    │  │
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
│   ├── enemies/               # enemy stat blocks (incl. per-enemy `ai` policy block)
│   ├── encounters/            # battle definitions: enemy list/formation, rewards, flee/ambush
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
│   │   ├── flag_store.gd             # boolean flags + UNITY integer + enum choices (pure)
│   │   ├── flag_view.gd              # typed read facade over FlagStore (props the resolver reads)
│   │   ├── flag_ops.gd               # SET/INC_UNITY/LOCK/SET_FINAL_CHOICE/RECORD_ENDING interpreter (pure)
│   │   ├── ending_resolver.gd        # resolveEnding() — mirrors 04 EXACTLY (pure)
│   │   └── replay_planner.gd         # ADR-0006 divergence reconstruction (pure)
│   │
│   ├── battle/                # BATTLE LOGIC (headless) + coordinator
│   │   ├── battle_controller.gd      # autoload (scene/UI bridge)
│   │   ├── battle_engine.gd          # the ATB simulation (pure, RNG injected)
│   │   ├── turn_scheduler.gd         # ATB gauge + ready-queue ordering (pure, integer)
│   │   ├── damage_formula.gd         # deterministic damage/heal math (pure)
│   │   ├── status_engine.gd          # status apply/tick/expire (pure)
│   │   ├── enemy_ai.gd               # EnemyBrain: deterministic enemy action+target select (pure, RNG injected)
│   │   ├── combatant.gd              # runtime combatant state (RefCounted)
│   │   ├── battle_event.gd           # typed battle-event structs emitted by step() (RefCounted)
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

Battle                       ── BattleController.start(encounter_id)
  → SaveManager.write_checkpoint("pre_battle")        # ADR-0005 (c): lose → return here
  → builds Combatants from ContentDB.encounter(id) + GameState.party; gets RngService.stream("battle")
  → BattleEngine.step() runs deterministically; EnemyBrain queues enemy actions from the "ai" stream;
    UI animates purely from emitted typed BattleEvents
  → on win:  apply XP/loot (leveling + inventory) → GameState updated → resume story
  → on lose: SaveManager.restore_checkpoint("pre_battle") → never title, never restart

A3-13  ENDING_FLAGS_LOCKED   ── StoryDirector freezes UNITY (derived flags are computed-on-read, never stored)
A4-06  FINAL_CHOICE          ── stored in GameState.story.choices.final_choice (enum, NOT a boolean flag);
                                options offered = EndingResolver.offered_options(flags.view())   # view carries frozen unity
A4-06b BRAMBLE_SACRIFICE     ── computed = final_choice in {SHARE,SLEEP,TAKE} (hard-coded derived, non-gating)
A4-07  ENDING                ── ending = EndingResolver.resolve(flags.view(), final_choice)
  → GameState.record_ending(ending, divergence_snapshot)  # stored in story.choices.ending; unlocks replay
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
  exposes **read-only** typed accessors: `ContentDB.beat(id)`, `.enemy(id)`, `.encounter(id)`,
  `.ability(id)`, `.item(id)`, `.status(id)`, `.branch(id)`, `.quest(id)`, `.party_member(id)`,
  `.ending(id)`, `.level_curve(id)`.
- IDs are the contract and come straight from the story docs: beat IDs `A1-01…A4-07` (incl. `A1-06a`,
  `A1-06b`, `A2-10b`, `A3-02b`, `A3-02c`, `A3-03b`, `A3-03c`, `A3-04b`, `A3-13b`), branches `BR1–BR4`,
  quests `CQ-*/SQ-*/MA-*`, and the flag names in `04 §3`. The flag **registry** (`data/flags/`) is the
  single validation source: any flag a beat tries to set must exist there, and any flag the resolver
  reads must be marked gating; non-gating emotional/Piggy flags are marked `gating: false` so the
  resolver lint can prove they never feed it.
- **Derived flags are computed-on-read, never stored** (`WARDEN_TRUTH_WHOLE`, `FACTIONS_UNITED`):
  `FlagView` recomputes them from the underlying flags + the frozen UNITY each time the resolver asks,
  so there is exactly one source of truth. `LOCK_ENDINGS` at A3-13 freezes only UNITY and the
  underlying flag set; it does not snapshot derived values.
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
func stream(name: String) -> RngStream            # named substreams: "battle","ai","loot","dance",
                                                   #   "encounter","story" (all cursor-saved)
# RngStream (RefCounted) — the injectable unit:
class RngStream:
    func randi() -> int
    func randi_range(a: int, b: int) -> int
    func chance_permille(p: int) -> bool           # p in 0..1000 (integer; outcome logic uses this)
    func weighted_pick(weights: Array) -> int       # integer-weighted index (for EnemyBrain)
    func randf() -> float                           # COSMETIC-only (unsaved UI stream); never for outcomes
    func get_cursor() -> int                        # # of draws taken (saved)
    func set_cursor(n: int) -> void                 # restore for replay/checkpoint
func export_state() -> Dictionary                   # {master_seed, cursors:{stream:int}}
func import_state(d: Dictionary) -> void
```

### 7.2 `GameState` (autoload, data only) — `core/game_state.gd`
```gdscript
var flags: FlagStore                  # booleans + UNITY + enum choices (final_choice, ending)
var party: Array                       # PartyMemberState (id, level, xp, equipment, learned)
var inventory: Inventory
var quests: Dictionary                 # quest_id -> state {LOCKED,AVAILABLE,ACTIVE,DONE}
var current_beat_id: String
var applied_beats: Array               # idempotency ledger for effect ops (ADR-0003)
var location_id: String
var rng_state: Dictionary              # from RngService.export_state() (all stream cursors)
var endings_unlocked: Array            # [EndingId] for the Crossroads selector
var divergence_snapshots: Dictionary   # ending_id -> snapshot (ADR-0006)
var playtime_secs: float
var save_version: int

# Enum-valued story state lives on FlagStore (NOT in the boolean dict), reached via:
#   flags.final_choice() -> ids.FinalChoice    # SHARE|SLEEP|TAKE|WAKE|NONE
#   flags.ending()       -> ids.EndingId        # A|B|C|D|NONE

func new_run(master_seed: int) -> void
func to_dict() -> Dictionary           # delegated to SaveSerializer
func from_dict(d: Dictionary) -> void
func snapshot() -> Dictionary          # deep copy for checkpoints
```

### 7.3 `FlagStore` (pure) — `story/flag_store.gd`
```gdscript
# Boolean flags (string-keyed), the UNITY integer, AND the two enum-valued story outputs.
func get_flag(name: String) -> bool
func set_flag(name: String, value: bool = true) -> void
func unity() -> int                                 # 0..8, monotonic non-decreasing
func add_unity_source(source_id: String, n: int = 1) -> void  # idempotent per UNITY-source-id; no-op if locked
func lock_endings() -> void                         # A3-13: freezes UNITY + underlying flag set
func is_locked() -> bool
# enum-valued story state (NOT booleans):
func set_final_choice(choice: int) -> void          # ids.FinalChoice; only at A4-06 (pre-lock invariant)
func final_choice() -> int                          # ids.FinalChoice or NONE
func set_ending(e: int) -> void                     # ids.EndingId; only at A4-07
func ending() -> int                                # ids.EndingId or NONE
# bramble_sacrifice is a hard-coded derived, non-gating value (see ADR-0003):
func bramble_sacrifice() -> bool                    # == final_choice() in {SHARE,SLEEP,TAKE}
func view() -> FlagView                              # typed read facade for the resolver (below)
func to_dict() -> Dictionary
func from_dict(d: Dictionary) -> void
```

### 7.3a `FlagView` (pure, typed read facade) — `story/flag_view.gd`
```gdscript
# Built by FlagStore.view(). Exposes the gating flags the resolver reads as REAL typed properties
# (so EndingResolver compiles against it) and computes the derived flags on read from the underlying
# flags + the frozen UNITY — derived values are never stored. Construct from a FlagStore OR from a
# plain dict (used by ReplayPlanner's synthesized states).
var KESTREL_RECRUITED: bool
var ORDER_ALLIED: bool
var TRUTH_SHARED: bool
var ROOKWISE_RECRUITED: bool
var MARROW_REDEEMED: bool
var BRAMBLE_SHARD_DEPARTURE: bool
var BRAMBLE_SHARD_PROMISE: bool
var unity: int
# computed-on-read (never stored):
func warden_truth_whole() -> bool      # (DEPARTURE and PROMISE) or (ROOKWISE and (DEPARTURE or PROMISE))
func factions_united() -> bool         # unity>=5 and KESTREL_RECRUITED and (ORDER_ALLIED or TRUTH_SHARED)
static func from_store(store: FlagStore) -> FlagView
static func from_dict(flags: Dictionary, unity: int) -> FlagView
```

### 7.4 `EndingResolver` (pure, static) — `story/ending_resolver.gd`
```gdscript
# Mirrors 04 §5 EXACTLY. `v` is a FlagView; final_choice: ids.FinalChoice. Uses real typed property
# access (v.KESTREL_RECRUITED, v.warden_truth_whole()) so it compiles against the facade. LOGIC
# UNCHANGED from 04 — only the access syntax is honest now.
static func factions_united(v: FlagView) -> bool          # v.factions_united()
static func can_wake(v: FlagView) -> bool                 # v.warden_truth_whole() and v.ROOKWISE_RECRUITED and v.MARROW_REDEEMED
static func offered_options(v: FlagView) -> Array         # subset of [SLEEP,TAKE,SHARE,WAKE]
static func resolve(v: FlagView, final_choice: int) -> int  # returns EndingId A/B/C/D
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
# Constructed headless; defs come from ContentDB (passed in, not global). Two injected RngStreams:
# `battle` (damage/crit/accuracy/loot-rolls) and `ai` (EnemyBrain selection) — kept separate so AI
# choices don't perturb damage reproducibility.
func _init(party: Array, encounter: Dictionary, defs: BattleDefs, rng_battle, rng_ai) -> void
func step(dt_ticks: int) -> Array                     # advance ATB (integer); returns typed BattleEvents
func queue_action(action: BattleAction) -> void       # player intent: actor, ability_id, targets
func is_over() -> bool
func result() -> int                                  # BattleResult.WIN / LOSE / FLED
func snapshot() -> Dictionary                          # full deterministic state (for tests)
# When an ENEMY becomes ready, the engine asks EnemyBrain for its action (no UI involved):
#   var act := EnemyBrain.choose_action(self_combatant, battle_state, rng_ai); queue_action(act)
# helpers used internally and unit-tested directly:
#   TurnScheduler.next_ready(combatants) -> Combatant            # integer ATB; ties: SPD then index
#   DamageFormula.compute(attacker, defender, ability, rng_battle) -> int
#   StatusEngine.tick(combatant) -> Array
# Retargeting: if a queued action's target is down/invalid at resolution, the engine retargets to the
# next valid target of the same side (deterministic order); if none, the action fizzles (a "fizzle"
# event). DamageFormula rolls accuracy (miss → "miss" event) before variance/crit.
```

### 7.6a `BattleEvent` vocabulary (typed) — `battle/battle_event.gd`
The HUD animates purely from these (no outcome logic in the scene). Event `type ∈`:
`turn_ready` (combatant id), `action_started` (actor, ability, targets), `damage` (target, amount,
is_crit, is_weak), `heal` (target, amount), `miss` (target), `fizzle` (actor), `status_applied`
(target, status), `status_expired` (target, status), `resource_changed` (combatant, resource, value),
`pacified` (target), `down` (combatant), `revived` (combatant), `atb_full` (combatant),
`battle_over` (result, xp, loot). Each is a small `RefCounted` with typed fields.

### 7.6b `EnemyBrain` (pure) — `battle/enemy_ai.gd`
```gdscript
# Headless, deterministic, RNG injected. No scene tree, no autoload access. Maps an enemy's `ai`
# policy (from ContentDB.enemy(id).ai) + the live battle state to a BattleAction.
static func choose_action(self_c: Combatant, state, rng_ai) -> BattleAction
# Policy resolution (data-authored, see ADR-0004/0007 enemy `ai` block):
#   1. Evaluate ability entries whose `condition` passes (e.g. hp_below, ally_down, turn>=N, phase).
#   2. From the eligible set, pick by integer `weight` via rng_ai.weighted_pick(weights).
#   3. Choose target by the ability/policy `target_rule` (lowest_hp, highest_threat, random, self,
#      all) — `random` uses rng_ai; the rest are deterministic functions of state.
#   4. `aggression` (0..1000 permille) biases attack-vs-support weighting.
# `basic`/`caster`/`boss_phased` are the same engine driven by different authored policy blocks
# (boss_phased adds phase conditions keyed to hp thresholds).
```

### 7.7 `SaveManager` (autoload) — `save/save_manager.gd`
```gdscript
func autosave(reason: String) -> void                 # debounced; reason for telemetry-free logging
func write_checkpoint(label: String) -> void          # "pre_battle"
func restore_checkpoint(label: String) -> bool
func load_latest() -> bool                             # validate; recover (backup→checkpoint) on corruption
func has_save() -> bool
func enter_replay_mode() -> void                       # stashes real save; blocks ALL writes to save_main
func exit_replay_mode() -> void                        # restores real save
func _notification(what: int) -> void                  # lifecycle hooks; honors replay-mode guard too
# every write path (autosave, checkpoint, AND _notification) checks _replay_mode before touching
# save_main.sav, so a focus-out mid-replay never persists the sandbox over the real save (ADR-0005/0006).
# uses SaveSerializer (pure), SaveMigrator (pure), AtomicFileIO (thin, validate-before-backup)
```

### 7.8 `ReplayPlanner` (pure) — `story/replay_planner.gd`  (ADR-0006)
```gdscript
static func divergence_beat_for(ending_id: int) -> String   # always "A4-06"
# Faithful path: pass the stored A4-06 snapshot. Canonical path: pass null → synthesize from
# data/endings/<id>.requires by setting UNDERLYING flags + UNITY, then RE-RUN the derive step
# (FlagView) to compute WARDEN_TRUTH_WHOLE/FACTIONS_UNITED — never sets derived flags directly.
static func build_state(ending_id: int, stored_snapshot) -> Dictionary
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
- **Must-test list (DoD #9, #13, #14):** battle damage/heal math, status apply/tick/expire, **integer
  ATB turn ordering & ties**, **EnemyBrain action/target selection (deterministic under fixed `ai`
  seed; condition/weight/target rules; boss phases)**, **encounter loading & validation**,
  **level-up/XP curve math (data-authored)**, inventory add/remove/equip, **save↔load round-trip**,
  **migration N→N+1**, **battle-checkpoint restore**, **corruption→backup recovery (incl. validate-
  before-backup; checkpoint as last recovery tier)**, **replay-mode guard blocks all write paths
  incl. lifecycle**, every story-flag transition in the ledger, each branch's flag outcomes,
  **single-owner UNITY (no double-count) & freeze at A3-13**, enum choices (`final_choice`/`ending`)
  round-trip, derived flags computed-on-read (`WARDEN_TRUTH_WHOLE`, `FACTIONS_UNITED`),
  **`resolveEnding` for all four endings + gating (golden, pinned to 04)**, and **ending-replay
  reconstruction (faithful + synthesized) yielding valid, offerable states** for each divergence point.
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
