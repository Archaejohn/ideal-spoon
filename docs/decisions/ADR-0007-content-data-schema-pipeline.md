# ADR-0007: Content data schema & pipeline

- **Status:** Accepted
- **Date:** 2026-06-30
- **Deciders:** Architect, Owner

## Context

`CONTRIBUTING.md` mandates **data separated from code** (story graph, items, enemies, dialogue as
JSON/resources) so writers/designers can author content without touching engine code, and so logic
stays deterministic and testable. The story docs already define the **IDs that are the contract**: beat
IDs (`A1-01…A4-07`, incl. `A1-06a/b`, `A2-10b`, `A3-02b/c`, `A3-03b/c`, `A3-04b`, `A3-13b`), branches
`BR1–BR4`, quests `CQ-*/SQ-*/MA-*`, the flag names in `04 §3`, party member ids, and the canon
skylands. This ADR fixes the JSON schemas, the loader, validation, and the authoring pipeline.

## Options considered

1. **Godot `.tres`/`.res` resources only.** Native and typed, but binary/awkward to diff in PRs, and
   not friendly for non-engineer writers.
2. **Plain JSON under `game/data/`, validated on load into typed in-memory objects.** Diff-friendly,
   writer-friendly, engine-agnostic, easy to fixture in tests. Chosen.
3. **An external CMS/database.** Violates offline/no-network and is overkill.

## Decision

Adopt **Option 2**: human-authored **JSON** in `game/data/**`, loaded and validated by `ContentDB`
(autoload, `src/data/content_db.gd`) at boot into read-only typed catalogs. Each content kind has a
validator under `src/data/validators/` and a human-readable spec under `game/data/schema/`.

### Loader & validation

- `ContentDB.load_all()` walks each `data/<kind>/` directory, parses every `.json`, and runs the
  matching validator. It builds `Dictionary` catalogs keyed by `id` and exposes typed accessors
  (`ContentDB.beat(id)`, `.enemy(id)`, …). Files may be one-record-per-file or arrays of records.
- **Validation is layered:**
  1. **Schema** — required fields present, correct types, enums valid (per `data/schema/`).
  2. **Referential integrity** — every referenced id exists: a beat's `flag` is in the flag registry; a
     branch's `goto`/`merge_beat` is a real beat; an enemy's `abilities[]` and `ai.abilities[].ability`
     exist; an ability's `status` effects reference real statuses; a quest's `reward` items/abilities
     exist; an **encounter's** `enemies[].enemy` and reward `item`s exist; a beat's `encounter` is a
     real encounter; a party member's `growth` is a real **level_curve**.
  3. **Domain rules** — UNITY sources match `04 §3.2`; the resolver only reads `gating:true` flags;
     exactly **eight distinct `source_id`s** (`u1…u8`) exist, applied **at most once per playthrough**
     (a `source_id` may appear on **mutually-exclusive** beats such as `u1` on A2-03/A2-04, but never on
     two **co-reachable** locations; the per-source ledger guarantees ≤1 application); **no flag is
     `SET` by more than one owner-kind** (branch-option XOR beat — the single-owner / no-double-UNITY
     rule); every branch (`BR1–BR4`) merges at its named beat; beat `next[]`/branch graph is connected
     from `A1-01` and reaches `A4-07`; **`ending.requires` contains no `derived`-kind flag** (so the
     synthesized-replay path can never set a derived flag directly, ADR-0006); enum-kind flags
     (`final_choice`/`ending`) are never targeted by a `SET` op.
- **Failure policy:** in debug/CI, any validation error is **fatal** (fail-fast with a precise message:
  file, id, field, rule). In release, the loader logs and, where safe, skips a bad optional record;
  core spine errors remain fatal. Validators are pure and unit-tested with good/bad fixtures.

### Authoring pipeline (how writers work)

1. Writer edits/adds a `.json` under the right `data/<kind>/` folder, reusing canonical IDs from the
   story docs. No `.gd` changes.
2. Run the **content-lint** GUT test (`tests/unit/test_content_validation.gd`) locally — it loads all
   data through the validators and reports any schema/reference/domain error.
3. Open a `story/…` or `data/…` PR; CI runs the same lint + the full suite. Independent review checks
   that IDs/flags match the locked story (`03`/`04`).
4. Because flags, beats, branches, and the resolver are all data-driven against one flag registry,
   adding a beat or rewording dialogue **cannot** change engine code and cannot silently break the
   ending logic (the resolver only sees gating flags).

> ID conventions (validated): beats `A<act>-<nn>[letter]`; branches `BR1–BR4`; quests
> `CQ-<NAME>` / `SQ-<NN|NAME>` / `MA-<NN>`; flags `UPPER_SNAKE_CASE`; content ids `lower_snake_case`.

---

## Schemas (field-by-field) with examples

> Types: `str`, `int`, `float`, `bool`, `enum(...)`, `id` (cross-reference), `arr<T>`, `obj`. `?` = optional.

### Beat — `data/beats/`
| Field | Type | Notes |
|---|---|---|
| `id` | str | canonical beat id (`A1-04`). |
| `act` | int | 1–4. |
| `location` | id | skyland/location id. |
| `scene` | enum(`dialogue`,`battle`,`overworld`,`cutscene`,`branch`,`ending`) | which scene type to route to. |
| `branch?` | id | branch id if this beat is a branch node (`BR1`…). |
| `effects` | arr<obj> | ordered effect ops (ADR-0003): `SET`/`INC_UNITY`/`LOCK_ENDINGS`/`SET_FINAL_CHOICE`/`RECORD_ENDING`. |
| `next` | arr<id> | successor beat ids (single-element on the linear spine). |
| `dialogue_set?` | id | dialogue lines to play. |
| `encounter?` | id | enemy encounter for `scene:"battle"`. |
| `checkpoint?` | bool | force a save checkpoint on entry (bosses/set-pieces). |

```json
{ "id": "A1-04", "act": 1, "location": "meadowmoor", "scene": "cutscene",
  "effects": [ { "op": "SET", "flag": "RESONANT_REVEALED" }, { "op": "SET", "flag": "TUT_STEADY" } ],
  "next": ["A1-05"], "dialogue_set": "a1_04_lamp_relit" }
```

### Branch — `data/branches/`
| Field | Type | Notes |
|---|---|---|
| `id` | str | `BR1`–`BR4`. |
| `trigger_beat` | id | beat that opens the branch. |
| `merge_beat` | id | beat both options converge on. |
| `options` | arr<obj> | each: `id`, `label_key`, `effects[]`, `goto` (beat id). |

```json
{ "id": "BR1", "trigger_beat": "A2-02", "merge_beat": "A2-05",
  "options": [
    { "id": "glasswastes", "label_key": "br1.glasswastes",
      "effects": [ {"op":"SET","flag":"SAVED_GLASSWASTES"}, {"op":"SET","flag":"BRAMBLE_SHARD_DEPARTURE"} ],
      "goto": "A2-03" },
    { "id": "verdance", "label_key": "br1.verdance",
      "effects": [ {"op":"SET","flag":"SAVED_VERDANCE"}, {"op":"SET","flag":"BRAMBLE_SHARD_PROMISE"} ],
      "goto": "A2-04" } ] }
```

### Flag registry — `data/flags/flags.json`
| Field | Type | Notes |
|---|---|---|
| `name` | str | `UPPER_SNAKE_CASE`. |
| `gating` | bool | `true` = the resolver/UNITY/derived flags may read it; `false` = emotional/flavor only. |
| `kind` | enum(`story`,`branch`,`unity_source`,`derived`,`final_choice`,`ending`,`emotional`) | category. |
| `set_at?` | arr<id> | beats/quests that set it (doc + integrity check). |

```json
[ { "name": "KESTREL_RECRUITED", "gating": true, "kind": "story", "set_at": ["A2-10"] },
  { "name": "TRUTH_SHARED", "gating": true, "kind": "branch", "set_at": ["A3-09"] },
  { "name": "SAVED_GLASSWASTES_REFUGEES", "gating": true, "kind": "unity_source", "set_at": ["A2-03"] },
  { "name": "WARDEN_TRUTH_WHOLE", "gating": true, "kind": "derived" },
  { "name": "PIGGY_RECRUITED", "gating": false, "kind": "emotional", "set_at": ["SQ-PIGGY","A3-13b"] } ]
```

- **UNITY sub-objective flags are first-class registry entries.** Every flag a UNITY source gates on —
  `SAVED_GLASSWASTES_REFUGEES`, `SAVED_VERDANCE_VILLAGERS`, `CONSCRIPTS_FREED`, `KESTREL_RECRUITED`,
  `HUSH_SURVIVORS_SAVED`, `ROOKWISE_RECRUITED`, the BR3 unifying gate, `ALLIES_RALLIED` — is registered
  (`kind: unity_source` or `story`/`branch`), so the referential-integrity rule passes and there are no
  invented, unregistered flags.
- **Enum-valued state is NOT a boolean flag.** `FINAL_CHOICE` (`kind: final_choice`) and `ENDING`
  (`kind: ending`) are registered for documentation/integrity but live in the **enum store**
  (`story.choices`, ADR-0003/0005), set via `SET_FINAL_CHOICE`/`RECORD_ENDING`, never via `SET`/`get_flag`.
- **Derived flags** (`WARDEN_TRUTH_WHOLE`, `FACTIONS_UNITED`; `kind: derived`) are **computed-on-read**,
  never stored and never `SET` by data.

The **UNITY source table** (`data/flags/unity_sources.json`) lists the eight `+1` sources from `04 §3.2`,
each with a unique `source_id` (`u1…u8`), its gate flag, and its single authoring location (branch
option **or** beat — see ADR-0003 ownership). The validator asserts: exactly eight `source_id`s; each
appears in exactly one `INC_UNITY`; each gate flag is registered; and no flag is `SET` by more than one
owner-kind (the single-owner / no-double-UNITY rule).

### Item — `data/items/`
| Field | Type | Notes |
|---|---|---|
| `id` | id | `lamp_herb`. |
| `name` | str | display. |
| `category` | enum(`consumable`,`weapon`,`armor`,`accessory`,`key`) | |
| `effect?` | obj | for consumables: an ability-like effect (`HEAL`/`CLEANSE`/`BUFF`/…). |
| `equip?` | obj | for gear: `slot` + stat modifiers. |
| `stack_max?` | int | default 99 for consumables, 1 for gear/key. |
| `value?` | int | shop/sell value. |
| `tags?` | arr<str> | e.g. `vs_machine`. |

```json
{ "id": "lamp_herb", "name": "Lamp-herb", "category": "consumable",
  "effect": { "type": "HEAL", "power": 120, "target_kind": "ALLY_SINGLE" }, "stack_max": 99, "value": 30 }
```

### Enemy — `data/enemies/`
| Field | Type | Notes |
|---|---|---|
| `id` | id | `sleepless_crane`. |
| `name` | str | display. |
| `is_boss?` | bool | |
| `stats` | obj | `hp,atk,def,mag,res,spd` (ints). |
| `weaknesses?` / `resistances?` | arr<str> | element/resonance tags. |
| `abilities` | arr<id> | enemy ability ids (each must exist). |
| `xp` | int | awarded on defeat. |
| `loot?` | arr<obj> | each: `item` id, `chance_permille` (0–1000, rolled on **loot** RNG stream). |
| `ai` | obj | **AI policy block** consumed by `EnemyBrain` (ADR-0004). See below. |

**`ai` block** (data-authored enemy behavior; no code per enemy):
| Field | Type | Notes |
|---|---|---|
| `policy` | enum(`basic`,`caster`,`boss_phased`) | preset shape (all run the same engine). |
| `aggression_permille` | int | 0–1000; biases offense vs. support weighting. |
| `abilities` | arr<obj> | candidate entries (below). |

Each `ai.abilities[]` entry: `ability` (id, must exist), `weight` (int ≥0, for
`rng_ai.weighted_pick`), `target_rule` (enum `lowest_hp`/`highest_threat`/`random`/`self`/
`all_enemies`/`lowest_hp_ally`/…), and optional `condition` (obj): `type ∈ {self_hp_below_permille,
ally_down, turn_gte, phase}` + `value`. Conditions are pure functions of battle state; only `random`
target_rule and the weighted pick draw from the injected `ai` stream — fully deterministic.

```json
{ "id": "sleepless_crane", "name": "The Sleepless Crane", "is_boss": true,
  "stats": { "hp": 1200, "atk": 70, "def": 40, "mag": 30, "res": 50, "spd": 18 },
  "weaknesses": ["resonance"], "resistances": ["physical"], "xp": 450,
  "loot": [ { "item": "wellstone_shard", "chance_permille": 1000 } ],
  "ai": { "policy": "boss_phased", "aggression_permille": 700,
    "abilities": [
      { "ability": "crane_sweep",    "weight": 60, "target_rule": "all_enemies" },
      { "ability": "hollow_screech", "weight": 40, "target_rule": "lowest_hp",
        "condition": { "type": "self_hp_below_permille", "value": 300 } } ] } }
```

### Ability — `data/abilities/`
| Field | Type | Notes |
|---|---|---|
| `id` | id | `steady`. |
| `name` | str | |
| `owner?` | id | party member / enemy (doc). |
| `kind` | enum(`ATTACK`,`ABILITY`,`ITEM`) | |
| `cost` | obj | `{ resource: NONE|BREATH|POMP|ITEM, amount: int }`. |
| `cooldown_turns?` | int | default 0; charge-gate for members without a unique resource (ADR-0004). |
| `target_kind` | enum(`SELF`,`ALLY_SINGLE`,`ALLY_ALL`,`ENEMY_SINGLE`,`ENEMY_ALL`,`ANY`) | |
| `power_stat?` | enum(`ATK`,`MAG`) | for damage/heal scaling. |
| `defense_stat?` | enum(`DEF`,`RES`) | which defense it checks. |
| `power` | int | percent multiplier (100 = baseline). |
| `element?` | str | resonance/physical/etc. for weakness checks. |
| `effects` | arr<obj> | `DAMAGE`/`HEAL`/`APPLY_STATUS`/`CLEANSE`/`BUFF`/`PACIFY`/`RANDOM_TABLE`. |
| `accuracy` | int | 0–100. |
| `tags?` | arr<str> | |

```json
{ "id": "steady", "name": "Steady", "owner": "wren", "kind": "ABILITY",
  "cost": { "resource": "BREATH", "amount": 2 }, "target_kind": "ALLY_SINGLE",
  "power_stat": "MAG", "defense_stat": "RES", "power": 90,
  "effects": [ { "type": "HEAL" }, { "type": "CLEANSE", "count": 1 } ], "accuracy": 100 }
```

### Status effect — `data/statuses/`
| Field | Type | Notes |
|---|---|---|
| `id` | id | `songsick`. |
| `name` | str | |
| `duration_turns?` / `duration_ticks?` | int | one of them. |
| `stack_rule` | enum(`REFRESH`,`STACK`,`IGNORE`) | |
| `tick_effect?` | obj | applied each turn (`DAMAGE`/`HEAL`/`NONE`). |
| `atb_modifier_permille?` | int | **integer permille** ATB-rate multiplier (1000 = ×1.00; SLOW `700`, HASTE `1300`). **No floats** — turn order is an outcome (ADR-0009 §1). |
| `on_apply?` / `on_expire?` | obj | hooks (e.g. `block_resource`). |
| `category` | enum(`buff`,`debuff`,`control`,`ailment`) | |

```json
{ "id": "songsick", "name": "Songsickness", "category": "ailment", "duration_turns": 3,
  "stack_rule": "REFRESH", "tick_effect": { "type": "NONE" }, "atb_modifier_permille": 700,
  "on_apply": { "block_resource": "BREATH" } }
```

### Party member — `data/party/`
| Field | Type | Notes |
|---|---|---|
| `id` | id | `wren`. |
| `name` | str | |
| `role` | enum(`support`,`gunner`,`gadget`,`healer`,`tank`,`adaptive`,`lore`,`whimsy`) | from `02`. |
| `base_stats` | obj | `hp,atk,def,mag,res,spd`. |
| `resource?` | enum(`BREATH`,`POMP`,`NONE`) | unique resource. |
| `growth` | id | level-curve id (`data/level_curves/`). |
| `abilities` | arr<obj> | each: `id`, `learn_level`. |
| `recruit_flag?` | str | flag that adds them to the roster. |

```json
{ "id": "wren", "name": "Wren", "role": "support", "resource": "BREATH",
  "base_stats": { "hp": 90, "atk": 12, "def": 14, "mag": 28, "res": 22, "spd": 20 },
  "growth": "support_curve",
  "abilities": [ { "id": "listen", "learn_level": 1 }, { "id": "steady", "learn_level": 1 },
                 { "id": "kindling_chorus", "learn_level": 6 }, { "id": "quiet_the_hollow", "learn_level": 10 } ] }
```

### Dialogue line set — `data/dialogue/`
| Field | Type | Notes |
|---|---|---|
| `id` | id | matches a beat's `dialogue_set`. |
| `lines` | arr<obj> | each: `speaker` (party/npc id), `text_key` or `text`, optional `condition` (expr), optional `portrait`. |

**`condition`** is a small boolean **expression** (not just one flag) so branch-aware lines can be
authored: a string flag name (truthy test), or an object `{ all: [...] }`, `{ any: [...] }`, or
`{ not: <expr> }`, nestable, with leaf terms being flag names or `{ flag, value }`. The evaluator is
pure and reads only registered flags. Example: `{ "all": ["MIRA_TRUST", { "not": "KESTREL_RECRUITED" }] }`.

```json
{ "id": "a1_04_lamp_relit",
  "lines": [
    { "speaker": "pell", "text": "Steady, Wren. Two taps, a breath…" },
    { "speaker": "wren", "text": "…the lamp is lit. We're aloft. All's well." },
    { "speaker": "officer", "text": "A Resonant. The Ascendancy claims her.", "condition": "ASCENDANCY_SEEN" },
    { "speaker": "kestrel", "text": "I have the line.", "condition": { "all": ["KESTREL_RECRUITED"] } } ] }
```

### Quest — `data/quests/`
| Field | Type | Notes |
|---|---|---|
| `id` | str | `CQ-*/SQ-*/MA-*`. |
| `name` | str | |
| `type` | enum(`companion`,`world`,`recruitment`,`mastery`) | |
| `skyland` | id | location. |
| `act` | str | e.g. `"II–III"`. |
| `unlock` | obj | `{ flags_required: [...], beat_after?: id }`. |
| `steps?` | arr<obj> | optional step records (objective + completion flag). |
| `effects_on_complete` | arr<obj> | effect ops (sets quest flags, e.g. `PIGGY_RECRUITED`). |
| `reward?` | obj | `items[]`, `abilities[]`, `gear[]`. |

```json
{ "id": "SQ-PIGGY", "name": "The Crate That Said Hwonk", "type": "recruitment",
  "skyland": "thornholt", "act": "II–III",
  "unlock": { "beat_after": "A1-12" },
  "effects_on_complete": [ { "op": "SET", "flag": "PIGGY_RECRUITED" } ],
  "reward": { "abilities": ["penguin_dance"], "gear": ["emperors_sash"] } }
```

### Ending — `data/endings/`
| Field | Type | Notes |
|---|---|---|
| `id` | enum(`A`,`B`,`C`,`D`) | |
| `name` | str | "The Shared Dawn" etc. |
| `final_choice` | enum(`SHARE`,`SLEEP`,`TAKE`,`WAKE`) | the A4-06 choice that leads here. |
| `divergence_beat` | const `"A4-06"` | per ADR-0006. |
| `requires` | obj | gating spec for `ReplayPlanner` canonical reconstruction (ADR-0006). `{ unity_min?, flags_all?, flags_any? }`. **Authored in UNDERLYING flags ONLY** — a domain rule rejects any `derived`-kind flag here. The replay builder sets these underlying flags and **re-runs the derive step** to compute `WARDEN_TRUTH_WHOLE`/`FACTIONS_UNITED` (never sets a derived flag directly). |
| `epilogue_set` | id | dialogue/cutscene for A4-07. |

```json
// Ending A: requires are underlying (Kestrel + an aligned faith + UNITY); FACTIONS_UNITED is derived.
{ "id": "A", "name": "The Shared Dawn", "final_choice": "SHARE", "divergence_beat": "A4-06",
  "requires": { "unity_min": 5, "flags_all": ["KESTREL_RECRUITED"], "flags_any": ["ORDER_ALLIED","TRUTH_SHARED"] },
  "epilogue_set": "ending_a_shared_dawn" }

// Ending D (secret): requires are underlying (Rookwise + Marrow + at least one shard); the builder
// then DERIVES WARDEN_TRUTH_WHOLE=true from the shard + Rookwise — it is NEVER set directly.
{ "id": "D", "name": "The Wandering Star", "final_choice": "WAKE", "divergence_beat": "A4-06",
  "requires": { "flags_all": ["ROOKWISE_RECRUITED","MARROW_REDEEMED"],
                "flags_any": ["BRAMBLE_SHARD_DEPARTURE","BRAMBLE_SHARD_PROMISE"] },
  "epilogue_set": "ending_d_wandering_star" }
```

### Encounter — `data/encounters/`
The fight definition referenced by `beat.encounter` and `BattleController.start(encounter_id)`.
| Field | Type | Notes |
|---|---|---|
| `id` | id | `enc_a1_11_crane`. |
| `enemies` | arr<obj> | each: `enemy` (id, must exist), `count` (int), optional `slot`/position. |
| `formation?` | enum(`single_back`,`line`,`spread`,`flank`) | layout for the scene. |
| `flee_allowed` | bool | gates the FLEE action (bosses usually `false`). |
| `ambush?` | enum(`none`,`player_first_strike`,`enemy_ambush`) | who gets the opening ATB advantage. |
| `victory` | enum(`all_enemies_down`,`survive_turns`,`target_down`) | win condition. |
| `defeat` | enum(`all_party_down`) | lose condition. |
| `rewards?` | obj | `xp` (int) + `items[]` (`{item, chance_permille}`); overrides enemy defaults if present. |
| `seed_salt?` | int | mixed into the `encounter` RNG stream so distinct encounters differ deterministically. |

Encounter RNG: enemy/loot/AI rolls draw from the `battle`/`ai`/`loot`/`encounter` streams (cursors
saved, ADR-0009/0005), so a save→load reproduces the same fight. Referential-integrity: every `enemy`
id and reward `item` id must exist.

```json
{ "id": "enc_a1_11_crane",
  "enemies": [ { "enemy": "sleepless_crane", "count": 1, "slot": "center" } ],
  "formation": "single_back", "flee_allowed": false, "ambush": "none",
  "victory": "all_enemies_down", "defeat": "all_party_down",
  "rewards": { "xp": 450, "items": [ { "item": "wellstone_shard", "chance_permille": 1000 } ] },
  "seed_salt": 1111 }
```

### Level curve — `data/level_curves/`
The XP→level table and per-level stat growth that `party.growth` references; **integer-only**, so
`LevelSystem` is deterministic and unit-testable.
| Field | Type | Notes |
|---|---|---|
| `id` | id | `support_curve`. |
| `max_level` | int | cap (e.g. 50). |
| `xp_to_next` | obj | how the XP needed for level L→L+1 is computed (below). |
| `growth_per_level` | obj | integer added to each stat per level (`hp,atk,def,mag,res,spd`). |
| `growth_overrides?` | obj | optional `{ "<level>": { stat: value } }` for hand-tuned breakpoints. |

`xp_to_next` is a **formula descriptor** evaluated with integer math (no floats), e.g.
`{ "type": "poly", "base": 50, "factor": 25, "exp": 2 }` →
`xp(L) = base + factor * L^exp` (integer). `LevelSystem.level_for_total_xp(total, curve)` and
`stats_at_level(member, curve)` are pure and tested with good/bad fixtures (monotonic XP thresholds,
caps respected, overrides applied).

```json
{ "id": "support_curve", "max_level": 50,
  "xp_to_next": { "type": "poly", "base": 50, "factor": 25, "exp": 2 },
  "growth_per_level": { "hp": 6, "atk": 1, "def": 1, "mag": 3, "res": 2, "spd": 1 },
  "growth_overrides": { "10": { "mag": 5 }, "25": { "hp": 12 } } }
```

## Rationale

Plain validated JSON is diff-friendly in PRs, editable by writers without engine knowledge, trivial to
fixture in GUT, and engine-agnostic — while layered validation (schema → references → domain rules)
catches the dangerous mistakes (a typo'd flag, a branch that doesn't merge, a UNITY source that drifts
from `04`) at boot/CI instead of in play. Keying everything to the story docs' canonical IDs makes the
data the single contract between writers and engineers.

## Consequences

- A new content kind needs a folder, a `schema/` doc, and a validator with good/bad fixtures. This ADR
  now covers all kinds an engineer needs to author a whole fight and the leveling: **enemy (+`ai`),
  encounter, ability (+`cooldown`), status (integer permille), level_curve**.
- The flag registry is authoritative: no beat/quest may set a flag that isn't registered, and the
  resolver lint depends on the `gating` field — keeping non-gating flags (Piggy, emotional threads,
  `BRAMBLE_SACRIFICE`) provably out of the ending math. Enum state (`final_choice`/`ending`) and derived
  flags are registered but handled through the enum store / derive step, never as boolean `SET` targets.
- JSON has no comments; the `schema/` docs and this ADR carry the explanations (examples here use
  `jsonc` only for annotation).
- Large data can be sharded per act and lazy-loaded for the performance budget (ARCHITECTURE §9) without
  changing the schemas.
