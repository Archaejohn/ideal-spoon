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

- Each combatant has `atb: int` in `[0, ATB_MAX]` (`ATB_MAX = 10000`). Per tick, `atb += speed_rate`,
  where `speed_rate` is **pure integer**: `speed_rate = base_rate(SPD) * haste_permille / 1000`, with
  `haste_permille` the product of all active ATB-status modifiers in **permille** (1000 = ×1.00; SLOW
  might be 700, HASTE 1300). **All turn-order-affecting math is integer/fixed-point** (scale = 1000);
  there are no floats anywhere in ATB advancement — this guarantees identical turn order across
  Android/Chromebook/web (ADR-0009 §1).
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

### Enemy AI — `EnemyBrain` (pure, deterministic, RNG injected) — `battle/enemy_ai.gd`

Player actions are queued by the controller/UI; **enemy actions are produced by `EnemyBrain`**, a pure
headless component in the logic layer (no scene tree, no autoload access). When an **enemy** combatant
becomes ready, `BattleEngine` calls:

```gdscript
static func choose_action(self_c: Combatant, state: BattleState, rng_ai) -> BattleAction
```

and queues the returned action. Determinism comes from an injected **`ai` RNG stream** (separate from
the `battle` stream so AI rolls don't perturb damage reproducibility, ADR-0009).

**Selection algorithm (data-authored policy):**
1. Read `self_c.enemy_def.ai` — the per-enemy **AI policy block** (schema in ADR-0007).
2. From `ai.abilities`, keep entries whose `condition` evaluates true against `state` (e.g.
   `hp_below_permille`, `self_hp_below`, `ally_down`, `turn_gte`, `phase` for `boss_phased`). Conditions
   are pure functions of battle state — no RNG.
3. Pick one eligible entry by integer `weight` via `rng_ai.weighted_pick(weights)`.
4. Pick targets by the entry's `target_rule` (`lowest_hp`, `highest_threat`, `random`, `self`,
   `all_enemies`, `lowest_hp_ally`, …). All rules are deterministic functions of state except `random`,
   which draws from `rng_ai`. Ties in `lowest_hp`/`highest_threat` break by stable combatant index.
5. `ai.aggression_permille` (0..1000) biases the eligible-set weights toward offense vs. support when an
   entry is tagged accordingly.

The three schema policies `basic | caster | boss_phased` are **the same engine** driven by different
authored `ai` blocks: `basic` = a couple of weighted attacks; `caster` = ability-heavy with low-hp
conditions; `boss_phased` = phase conditions keyed to hp thresholds that swap the eligible ability set
(e.g. the Sleepless Crane's enrage below 30% hp). New behaviors are **authored in the enemy JSON**, not
coded. `EnemyBrain` is on the no-nondeterminism guard list (ADR-0009) and unit-tested with a `FakeRng`
to assert exact action+target choices per condition/weight, and boss phase transitions.

### Abilities & items (data, ADR-0007)

Abilities are data records (`data/abilities/`) keyed by ID (e.g. Wren's `LISTEN`, `STEADY`,
`KINDLING_CHORUS`, `QUIET_THE_HOLLOW`; Sable's `SNAPSHOT`). Fields: `cost` (resource + amount, where
resource ∈ `{NONE, BREATH, POMP, ITEM}`), optional `cooldown_turns` (default 0), `target_kind`,
`power`, `element/resonance`, `effects` (damage/heal/apply-status/buff), `accuracy`, and `tags` (e.g.
`vs_machine`). Items are `data/items/` records that reference an ability-like effect plus consumption
rules. Wren's **Breath** and Piggy's **Pomp** are per-combatant resources tracked in `Combatant`;
overspending Breath applies the `SONGSICK` status (mirrors the world rule). Piggy's `PENGUIN_DANCE`
rolls a beneficial effect from a **data-defined table** using the injected `dance` RNG stream —
deterministic under test.

**Ability economy (decided):** basic attacks are free; signature/ultimate abilities gate on **either** a
unique resource (Wren=Breath, Piggy=Pomp), an **item** (Tam's gadgets/items), or a **`cooldown_turns`**
charge (the kid-friendly default for Sable/Mira/Kestrel/Bramble/Rookwise, who otherwise have no special
resource). The `Combatant` tracks per-ability cooldown counters ticked at turn start. This keeps every
member balanceable in data without a universal MP bar (intentional: simpler for a 10-year-old).

### Status effects (data + `StatusEngine`)

Status definitions live in `data/statuses/` (e.g. `SONGSICK`, `SHIELD/KINDLING`, `REGEN/VIGIL`,
`HASTE`, `SLOW`, `FEAR`, `STUN`, `MARK`, `MORALE`). Each has `duration` (turns or ticks), `stack_rule`
(`REFRESH | STACK | IGNORE`), `tick_effect`, `on_apply`, `on_expire`, and **`atb_modifier_permille`**
(integer; e.g. SLOW `700`, HASTE `1300`, SONGSICK `700` — applied as `rate * permille / 1000`). The
modifier is **integer permille, never a float**, because turn order is an outcome (ADR-0009 §1).
`StatusEngine.apply(combatant, status_id, source, rng)` and `StatusEngine.tick(combatant)` are pure;
ticking happens at the start of a combatant's turn (deterministic order). Crowd-control via Wren's
`QUIET_THE_HOLLOW` removes a Hollow from the fight non-violently (sets it `pacified`, not `dead`).

### Damage formula (deterministic, RNG injected)

`DamageFormula` is pure and static; all randomness comes from the injected `RngStream`:

```gdscript
# damage_formula.gd  (all integer; rng is the injected "battle" RngStream)
static func compute(attacker, defender, ability, rng) -> Dictionary:
    # 1. accuracy/miss roll FIRST (chance_permille: 0..1000)
    if not rng.chance_permille(ability.accuracy * 10):   # accuracy is 0..100 → permille
        return { "hit": false }                          # → "miss" event
    var base := attacker.stat(ability.power_stat)        # ATK or MAG
    var raw  := maxi(1, (base * ability.power) / 100 - defender.stat(ability.defense_stat))
    var variance := rng.randi_range(95, 105)             # ±5%
    var dmg := (raw * variance) / 100
    if _is_weakness(defender, ability): dmg = (dmg * 150) / 100
    var is_crit := rng.chance_permille(_crit_permille(attacker, ability))   # 0..1000
    if is_crit: dmg = (dmg * 200) / 100
    return { "hit": true, "amount": maxi(1, dmg), "crit": is_crit, "weak": _is_weakness(defender, ability) }
```

- **Integer math throughout** (no float drift across platforms); all probabilities are integer permille.
- Healing reuses the same shape with heal stats. Accuracy/variance/crit all draw from the **battle** RNG
  stream so a fixed seed reproduces a fight exactly (ADR-0009).
- `base_rate(spd)` and `_crit_permille` are pure helpers; weakness/resonance lookups read the ability's
  element vs. the defender's tags (data).
- **Retargeting:** because actions resolve after an ATB delay, if a queued action's target is
  down/`pacified`/invalid at resolution, `BattleEngine` retargets to the next valid target on the same
  side (deterministic stable-index order); if none remain, the action **fizzles** (a `fizzle` event, no
  effect). This rule is unit-tested.

### Leveling (delegated to `leveling/`)

On WIN, the engine returns XP + loot in its result; `BattleController` hands XP to `LevelSystem`
(`leveling/level_system.gd`) which applies the data-driven XP→level curve (`data/level_curves/`) and
stat growth, and loot to `Inventory`. Level/growth math is pure and unit-tested. The engine itself
does not mutate persistent party state — it works on battle-scoped `Combatant` copies built from
`GameState.party`.

### Win / lose handling

- `is_over()` true when all enemies are down (WIN), all party members are down (LOSE), or a FLEE
  succeeded (FLED). `result()` returns `BattleResult.WIN | LOSE | FLED`.
- The fight is launched from an **encounter** (ADR-0007 `data/encounters/`): `BattleController.start(
  encounter_id)` reads `ContentDB.encounter(id)` for the enemy list/formation, flee-allowed,
  ambush/first-strike, and reward overrides. The encounter's RNG is the `encounter` stream cursor +
  the `battle`/`ai` streams (ADR-0009), so a save/load reproduces the same fight.
- WIN → apply XP/loot (from the encounter's reward block, else enemy defaults), emit `battle_over`,
  resume story.
- LOSE → `BattleController` calls `SaveManager.restore_checkpoint("pre_battle")` (ADR-0005 (c)):
  the player returns to **just before the battle**, never the title, never a restart.
- FLEE (only where `encounter.flee_allowed`) ends the battle with a neutral result and no rewards.

### Data shapes (skeletons; full specs in ADR-0007)

```jsonc
// enemy (note the per-enemy `ai` policy block consumed by EnemyBrain)
{ "id":"sleepless_crane", "name":"The Sleepless Crane", "is_boss": true,
  "stats": { "hp": 1200, "atk": 70, "def": 40, "mag": 30, "res": 50, "spd": 18 },
  "weaknesses": ["resonance"], "resistances": ["physical"], "xp": 450,
  "loot": [ { "item":"wellstone_shard", "chance_permille": 1000 } ],
  "ai": { "policy":"boss_phased", "aggression_permille": 700,
    "abilities": [
      { "ability":"crane_sweep",    "weight": 60, "target_rule":"all_enemies" },
      { "ability":"hollow_screech", "weight": 40, "target_rule":"lowest_hp",
        "condition": { "type":"self_hp_below_permille", "value": 300 } } ] } }

// ability (cooldown_turns optional; accuracy 0..100; cost.resource ∈ {NONE,BREATH,POMP,ITEM})
{ "id":"steady", "name":"Steady", "owner":"wren", "kind":"ABILITY",
  "cost": { "resource":"BREATH", "amount": 2 }, "cooldown_turns": 0, "target_kind":"ALLY_SINGLE",
  "power_stat":"MAG", "defense_stat":"RES", "power": 90,
  "effects":[ {"type":"HEAL"}, {"type":"CLEANSE","count":1} ], "accuracy": 100 }

// status (integer permille ATB modifier — never a float)
{ "id":"songsick", "name":"Songsickness", "duration_turns": 3, "stack_rule":"REFRESH",
  "tick_effect": { "type":"NONE" }, "atb_modifier_permille": 700, "on_apply": {"block_resource":"BREATH"} }

// encounter (data/encounters/) — what BattleController.start(encounter_id) loads
{ "id":"enc_a1_11_crane", "enemies":[ {"enemy":"sleepless_crane","count":1,"slot":"center"} ],
  "formation":"single_back", "flee_allowed": false, "ambush":"none",
  "victory":"all_enemies_down", "defeat":"all_party_down",
  "rewards": { "xp": 450, "items":[ {"item":"wellstone_shard","chance_permille":1000} ] } }
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
- Enemy behavior is **authored in the enemy `ai` block** and executed by the pure, RNG-injected
  `EnemyBrain` — so a designer can tune a boss's phases or a Hollow's aggression in JSON without engine
  changes, and every enemy decision is reproducible under a fixed `ai` seed.
- All turn-order math (ATB advance, status modifiers) is integer permille; floats are confined to
  cosmetic animation, guaranteeing identical turn order on Android/Chromebook/web.
