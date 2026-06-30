# ADR-0009: Determinism, RNG & testing strategy

- **Status:** Accepted
- **Date:** 2026-06-30
- **Deciders:** Architect, Owner

## Context

`CONTRIBUTING.md` and `DEFINITION_OF_DONE.md` #9 require deterministic core logic (seeded RNG) and
thorough, meaningful unit tests — **≥80% on non-UI logic modules**, full GUT suite green in CI. Saves
(ADR-0005) and ending replays (ADR-0006) must be **reproducible**, which only works if all randomness
flows through a single seeded service whose state is saved. This ADR fixes the RNG design, the
determinism guarantees, and the concrete GUT test layout and must-test list.

## Options considered

1. **Ad-hoc `randi()`/`randf()` global calls wherever randomness is needed.** Non-deterministic, not
   restorable, impossible to reproduce a battle or replay; untestable. Rejected.
2. **One `RandomNumberGenerator` shared globally.** Better, but a single cursor shared across battle,
   loot, and UI flavor means unrelated draws perturb each other and break reproducibility when, say,
   an animation also rolls. Rejected.
3. **A single `RngService` that vends named, independently-seeded substreams, with per-stream cursors
   saved.** Deterministic, reproducible, isolates concerns, and is the injectable unit tests need.
   Chosen.

## Decision

### The RNG service

`core/rng_service.gd` (autoload) owns one `master_seed` (set at New Game, saved in `GameState`). It
derives **named substreams** so unrelated systems don't perturb each other:

```gdscript
func seed_run(master_seed: int) -> void
func stream(name: String) -> RngStream         # "battle", "loot", "dance", "story", "encounter"
func export_state() -> Dictionary              # { master_seed, cursors: { name: int } }
func import_state(d: Dictionary) -> void
```

Each `RngStream` (RefCounted) wraps a `RandomNumberGenerator` seeded by `hash(master_seed, name)` and
tracks a **cursor** (number of draws taken). Drawing increments the cursor; `set_cursor(n)` replays the
stream forward to draw `n` (or the implementation reseeds and fast-forwards) so a saved cursor
**exactly** reproduces subsequent draws.

```gdscript
class RngStream:
    func randi() -> int
    func randi_range(a: int, b: int) -> int
    func randf() -> float
    func chance(p: float) -> bool
    func get_cursor() -> int
    func set_cursor(n: int) -> void
```

- **Injection:** logic classes (`BattleEngine`, `DamageFormula`, loot, `PENGUIN_DANCE`) receive an
  `RngStream` as a constructor/parameter argument — never reach for a global. Tests pass a `FakeRng`
  (scripted sequence) or a fixed-seed real stream.
- **Saved with the run:** `export_state()` is stored in the save (ADR-0005) and in checkpoints/replay
  snapshots, so restoring a checkpoint or replaying an ending continues the exact same RNG.

### Determinism guarantees & rules

1. **Integer math** in all battle/leveling formulas (ADR-0004) — no float accumulation that can diverge
   across Android/Chromebook/web. Floats only for cosmetic/animation, never for outcomes.
2. **No wall-clock / OS entropy in logic.** Logic modules must not call `Time.*`, `OS.*`, global
   `randi/randf`, or `randomize()`. A **guard test** (`tests/unit/test_no_nondeterminism.gd`) greps the
   `battle/`, `story/`, `save/`, `inventory/`, `leveling/` sources and fails on any such reference.
3. **Stable ordering.** Turn ties and any iteration that affects outcomes use deterministic keys
   (stable indices), never `Dictionary` iteration order or unordered sets.
4. **Stream discipline.** Battle outcomes draw only from `"battle"`; loot from `"loot"`; Piggy's dance
   from `"dance"`; encounter selection from `"encounter"`. Cosmetic randomness (idle wobble, particle)
   uses a throwaway *unsaved* UI stream that never affects state.

### Module-boundary guard (supports ARCHITECTURE §3)

`tests/unit/test_module_boundaries.gd` asserts logic modules don't `preload`/reference autoload
coordinators, `ui/`, or `overworld/` — keeping the headless core pure and the ≥80% target attainable.

### GUT test layout

```
game/tests/
├── unit/                         # headless logic — the ≥80% coverage target
│   ├── battle/
│   │   ├── test_damage_formula.gd
│   │   ├── test_turn_scheduler.gd      # ordering, ties, haste/slow
│   │   ├── test_status_engine.gd       # apply/tick/expire/stack rules; Songsickness
│   │   └── test_battle_engine.gd       # full fights with fixed seed; win/lose/flee
│   ├── story/
│   │   ├── test_flag_store.gd          # set/get; UNITY monotonic + freeze at A3-13
│   │   ├── test_flag_ops.gd            # effect-op interpreter; idempotency ledger
│   │   ├── test_story_graph.gd         # every branch merges at its named beat; spine reachable
│   │   ├── test_derived_flags.gd       # WARDEN_TRUTH_WHOLE, FACTIONS_UNITED truth tables
│   │   ├── test_ending_resolver.gd     # GOLDEN: resolve + offered_options for all gating combos
│   │   └── test_replay_planner.gd      # divergence reconstruction validity (ADR-0006)
│   ├── save/
│   │   ├── test_save_serializer.gd     # round-trip equality on a fully-populated state
│   │   ├── test_save_migrator.gd       # v(n)->v(n+1) with frozen fixtures
│   │   └── test_atomic_io.gd           # temp+rename; corruption→backup recovery
│   ├── inventory/  test_inventory.gd
│   ├── leveling/   test_level_system.gd
│   ├── data/       test_content_validation.gd   # loads ALL game/data through validators
│   ├── test_no_nondeterminism.gd
│   └── test_module_boundaries.gd
├── integration/
│   ├── test_scene_router.gd            # beat→state mapping, hook firing (stub loader)
│   ├── test_checkpoint_roundtrip.gd    # start battle → lose → restored to pre-battle
│   ├── test_story_playthrough.gd       # walk the ledger headless along a chosen branch
│   └── test_save_lifecycle.gd          # autosave triggers fire on the right events
└── helpers/
    ├── fake_rng.gd                     # scripted RngStream for exact control
    ├── mem_fs.gd                       # in-memory file IO for atomic-write tests
    ├── fixtures.gd                     # sample party/enemies/states
    └── content/                        # tiny validated content set for tests
```

### Must-test list (maps to DoD #4/#9/#13/#14)

- **Battle math** — damage/heal with weakness/crit/variance under fixed seed; min-1 floor; integer
  stability.
- **Status & turn ordering** — apply/tick/expire, stack rules, Songsickness ATB penalty; ready-queue
  ordering and tie-breaks; haste/slow.
- **Leveling & inventory** — XP→level curve, stat growth; add/remove/equip/stack limits.
- **Save/load + checkpoint** — full round-trip equality; **battle-checkpoint restore** returns to
  pre-battle; **migration** N→N+1; **corruption → backup recovery**.
- **Story graph & flags** — every ledger beat's flag/UNITY effects; UNITY monotonic + frozen at A3-13;
  each branch's outcomes and merge; Kestrel-recruit dependency on `KESTREL_DOUBT`.
- **Derived flags** — `WARDEN_TRUTH_WHOLE` (both-shards OR Rookwise+one-shard); `FACTIONS_UNITED`
  (unity≥5 AND Kestrel AND (Order OR truth)).
- **`resolveEnding` (GOLDEN, exhaustive)** — for the relevant flag/UNITY/choice combinations: Sleep→B
  and Take→C always; Share→A iff `FACTIONS_UNITED`; Wake→D iff
  `WARDEN_TRUTH_WHOLE AND ROOKWISE_RECRUITED AND MARROW_REDEEMED`; `offered_options` never lists an
  ungated option; non-gating flags (Piggy/emotional/`BRAMBLE_SACRIFICE`) provably never change a result.
- **Ending replay** — completing once unlocks B+C; reaching A4-06 with each gate satisfied unlocks A/D;
  `ReplayPlanner.build_state` (faithful and canonical) yields an **offerable, valid** A4-06 state and
  `resolve` returns the correct letter from it.
- **Determinism guards** — no `Time/OS/randi/randf` in logic; module boundaries respected.
- **Content validation** — all shipped `game/data` passes schema/reference/domain validation.

### Coverage & CI

- ≥80% line coverage on the `unit/` target modules, measured by GUT's coverage option (or a coverage
  pass over the logic dirs); reported in the PR body per `CONTRIBUTING.md`.
- `.github/workflows/ci.yml` runs the full suite headless on every PR; **red blocks merge**. If Actions
  minutes are unavailable, the suite is run locally (headless Godot) and the result pasted into the PR.

## Rationale

A single seeded service with named, cursor-saved substreams is the smallest design that makes battles
reproducible, checkpoints/replays exact, and every randomized system unit-testable via injection — the
backbone of DoD #9/#13/#14. Integer math and the no-clock/no-global-RNG guards prevent the subtle
cross-platform nondeterminism that would otherwise make "reproducible" untrue on one of our three
targets. The golden resolver test pins the highest-stakes logic to `04` so it can never silently drift.

## Consequences

- All randomized logic must accept an injected `RngStream`; constructing one's own RNG inside logic is a
  review-blocked anti-pattern (and caught by the guard test).
- Saving RNG cursors slightly enlarges the save and requires `set_cursor` to be exact; the
  implementation is covered by its own determinism test (same seed+cursor ⇒ same next draws).
- The 80% target is scoped to logic modules by design; UI/scene code is covered by lighter integration
  tests, keeping the bar meaningful rather than padded.
- Cosmetic randomness must use the unsaved UI stream; using a saved stream for flavor would desync
  replays and is disallowed.
