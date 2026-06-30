# ADR-0004: ATB battle engine

- **Status:** Accepted
- **Date:** 2026-06-30
- **Deciders:** Architect, Owner

## Context

`DEFINITION_OF_DONE.md` #4 requires an FF-style **Active-Time-Battle** system: parties, enemies,
abilities, items, status effects, leveling, balanced encounters, win/lose handling. The battle math
must be **deterministic** (seeded RNG injected) and **headless-testable** (no scene-tree dependency in
the math), per `CONTRIBUTING.md` and `DEFINITION_OF_DONE.md` #9. Party battle roles are defined in
`02_CHARACTERS.md` (Wren = Resonant support with a **Breath** resource and **Songsickness** risk; Sable
gunner; Tam gadgets; Mira healer; Kestrel tank/counter; Bramble adaptive; Rookwise debuff-mage; Piggy
luck/morale with a **Pomp** resource and random **Penguin Dance**). Real enemies include the Sleepless
Crane (A1 boss), Hollow swarms, Tinplate patrols, and Marrow.

## Options considered

1. **Turn-based (no ATB gauge).** Simpler, but violates DoD #4's explicit "FF-style ATB" requirement.
2. **Real-time gauges tied to frame delta in the scene.** Authentic feel but couples battle timing to
   the render loop and wall clock → non-deterministic, hard to unit-test.
3. **Tick-based ATB simulation in a pure engine, with the scene merely a renderer of emitted events.**
   ATB gauges advance in integer "ticks"; the scene maps real time → ticks for feel but the engine is
   driven by an explicit `step(dt_ticks)` so tests run it deterministically with a fixed RNG. Chosen.

## Decision

Adopt **Option 3**: a pure `battle/battle_engine.gd` (`BattleEngine`) plus pure helpers
`turn_scheduler.gd`, `damage_formula.gd`, `status_engine.gd`, and runtime structs `combatant.gd`,
`battle_action.gd`. The autoload `battle_controller.gd` bridges this to the battle scene/HUD; it
contains **no math**.

### ATB gauge & turn ordering

- Each combatant has `atb: int` in `[0, ATB_MAX]` (`ATB_MAX = 10000`). Per tick, `atb += speed_rate`
  where `speed_rate` is derived from the combatant's `SPD` stat (`damage_formula.atb_rate(spd)`), and
  is scaled by haste/slow statuses.
- When `atb >= ATB_MAX` the combatant is **ready** and enters the ready-queue. ATB does not advance
  while a combatant is choosing/executing (classic "active" sub-mode) — the controller chooses
  ATB-pause for accessibility (low-end + 10-year-old audience); "wait vs. active" is a settings toggle
  handled by the controller's tick cadence, never by the engine.
- `TurnScheduler.next_ready(combatants)` returns the highest-`atb` ready combatant; ties broken by
  (a) higher `SPD`, then (b) stable combatant index — **fully deterministic, no RNG**.
- On acting, `atb -= ATB_MAX` (carry-over preserved) and the action resolves.

### Action selection & "time to choose"

- For player combatants the engine emits a `turn_ready(combatant_id)` event; the controller opens the
  command UI and (if "active" mode) keeps ticking *other* combatants. The player's choice becomes a
  `BattleAction` queued via `BattleEngine.queue_action(action)`.
- A per-turn **decision window** (`choose_ticks`, from settings) can auto-pass or auto-default if it
  elapses (kid-friendly: defaults to a basic Attack), but this is enforced by the controller; the
  engine just consumes queued actions, so tests are unaffected.

### `BattleAction` (intent struct)
```gdscript
class BattleAction extends RefCounted:
    var actor_id: int
    var kind: int           # ATTACK | ABILITY | ITEM | DEFEND | FLEE
    var ability_id: String  # or item_id
    var target_ids: Array
```

### Abilities & items (data, ADR-0007)

Abilities are data records (`data/abilities/`) keyed by ID (e.g. Wren's `LISTEN`, `STEADY`,
`KINDLING_CHORUS`, `QUIET_THE_HOLLOW`; Sable's `SNAPSHOT`). Fields: `cost` (resource + amount, where
resource ∈ `{NONE, BREATH, POMP, ITEM}`), `target_kind`, `power`, `element/resonance`, `effects`
(damage/heal/apply-status/buff), `accuracy`, and `tags` (e.g. `vs_machine`). Items are
`data/items/` records that reference an ability-like effect plus consumption rules. Wren's **Breath**
and Piggy's **Pomp** are per-combatant resources tracked in `Combatant`; overspending Breath applies the
`SONGSICK` status (mirrors the world rule). Piggy's `PENGUIN_DANCE` rolls a beneficial effect from a
**data-defined table** using the injected `dance` RNG stream — deterministic under test.

### Status effects (data + `StatusEngine`)

Status definitions live in `data/statuses/` (e.g. `SONGSICK`, `SHIELD/KINDLING`, `REGEN/VIGIL`,
`HASTE`, `SLOW`, `FEAR`, `STUN`, `MARK`, `MORALE`). Each has `duration` (turns or ticks), `stack_rule`
(`REFRESH | STACK | IGNORE`), `tick_effect`, `on_apply`, `on_expire`, and `atb_modifier`.
`StatusEngine.apply(combatant, status_id, source, rng)` and `StatusEngine.tick(combatant)` are pure;
ticking happens at the start of a combatant's turn (deterministic order). Crowd-control via Wren's
`QUIET_THE_HOLLOW` removes a Hollow from the fight non-violently (sets it `pacified`, not `dead`).

### Damage formula (deterministic, RNG injected)

`DamageFormula` is pure and static; all randomness comes from the injected `RngStream`:

```gdscript
# damage_formula.gd
static func compute(attacker, defender, ability, rng) -> int:
    var base := attacker.stat(ability.power_stat)        # ATK or MAG
    var raw  := maxi(1, (base * ability.power) / 100 - defender.stat(ability.defense_stat))
    var variance := rng.randi_range(95, 105)             # ±5%, the ONLY randomness
    var dmg := (raw * variance) / 100
    if _is_weakness(defender, ability): dmg = (dmg * 150) / 100
    if rng.chance(_crit_chance(attacker, ability)):  dmg = (dmg * 200) / 100
    return maxi(1, dmg)
```

- Integer math throughout (no float drift across platforms).
- Healing reuses the same shape with heal stats. Misses/crit/variance all draw from the **battle** RNG
  stream so a fixed seed reproduces a fight exactly (ADR-0009).
- `atb_rate(spd)` and `_crit_chance` are pure helpers; weakness/resonance lookups read the ability's
  element vs. the defender's tags (data).

### Leveling (delegated to `leveling/`)

On WIN, the engine returns XP + loot in its result; `BattleController` hands XP to `LevelSystem`
(`leveling/level_system.gd`) which applies the data-driven XP→level curve (`data/level_curves/`) and
stat growth, and loot to `Inventory`. Level/growth math is pure and unit-tested. The engine itself
does not mutate persistent party state — it works on battle-scoped `Combatant` copies built from
`GameState.party`.

### Win / lose handling

- `is_over()` true when all enemies are down (WIN) or all party members are down (LOSE). `result()`
  returns `BattleResult.WIN | LOSE`.
- WIN → apply XP/loot, emit `battle_won`, resume story.
- LOSE → `BattleController` calls `SaveManager.restore_checkpoint("pre_battle")` (ADR-0005 (c)):
  the player returns to **just before the battle**, never the title, never a restart.
- FLEE (where allowed by encounter data) ends the battle with a neutral result and no rewards.

### Data shapes (skeletons; full specs in ADR-0007)

```jsonc
// enemy
{ "id":"sleepless_crane", "name":"The Sleepless Crane", "is_boss": true,
  "stats": { "hp": 1200, "atk": 70, "def": 40, "mag": 30, "res": 50, "spd": 18 },
  "weaknesses": ["resonance"], "resistances": ["physical"],
  "abilities": ["crane_sweep", "hollow_screech"], "xp": 450, "loot": ["wellstone_shard"] }

// ability
{ "id":"steady", "name":"Steady", "owner":"wren", "kind":"ABILITY",
  "cost": { "resource":"BREATH", "amount": 2 }, "target_kind":"ALLY_SINGLE",
  "power_stat":"MAG", "power": 90, "effects":[ {"type":"HEAL"}, {"type":"CLEANSE","count":1} ],
  "accuracy": 100 }

// status
{ "id":"songsick", "name":"Songsickness", "duration_turns": 3, "stack_rule":"REFRESH",
  "tick_effect": { "type":"NONE" }, "atb_modifier": -0.30, "on_apply": {"block_resource":"BREATH"} }
```

## Rationale

A tick-based pure engine gives authentic FF-style ATB *feel* (gauges, active mode, time-to-choose) while
keeping every number reproducible and unit-testable headless — the only way to hit DoD #9 on combat and
to make battle checkpoints (DoD #13) meaningful. Integer math avoids cross-platform float divergence on
Android/Chromebook. Putting abilities/enemies/statuses in data lets designers balance encounters
(`02_CHARACTERS.md` roles) without engine edits.

## Consequences

- The scene layer must translate real seconds → ticks and animate purely from engine-emitted events; it
  may not compute outcomes. A guard test asserts no `randf`/`Time` use inside `battle/`.
- Balance is a data concern; encounter balance and the XP curve get their own tuning passes (Phase 3)
  but require no engine changes.
- "Active vs. wait" ATB and the decision-window timer are controller/settings concerns, keeping the
  engine timing-agnostic and tests stable.
- Character resources (Breath/Pomp) and Songsickness are first-class `Combatant` fields, so the world's
  "no free energy / overreach hurts" rule is modeled mechanically, not narrated only.
