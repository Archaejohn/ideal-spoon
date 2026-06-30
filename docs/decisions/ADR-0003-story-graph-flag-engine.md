# ADR-0003: Story-graph & flag/quest-state engine

- **Status:** Accepted
- **Date:** 2026-06-30
- **Deciders:** Architect, Owner

## Context

`03_MAIN_STORY.md` (the Beat Ledger A1-01…A4-07, incl. the new beats A1-06a, A1-06b, A2-10b, A3-02b/c,
A3-03b/c, A3-04b, A3-13b) and `04_BRANCHES_ENDINGS.md` (BR1–BR4, the flag model, the UNITY counter, the
derived flags, and `resolveEnding`) are the **locked content contract**. The engine must drive that
content as **data**, set the exact flags each beat declares, gate the branches, and compute endings
**exactly** as `04 §4–§5` specifies — deterministically and unit-testably. No story logic may be
hard-coded in scenes.

## Options considered

1. **Hard-code beats/branches in GDScript scenes (one scene script per beat).**
   - Pro: simple to start. Con: violates data/code separation; writers can't edit; untestable as a
     unit; renumbering or rewording forces code changes; resolver risks drifting from `04`.
2. **General-purpose third-party dialogue/quest plugin.**
   - Pro: ready-made. Con: external dependency, web/Android export risk, offline-only constraint, and
     it still wouldn't encode our exact UNITY/derived-flag resolver. Over-powered and under-precise.
3. **Purpose-built, data-driven story graph + pure flag store + a resolver that mirrors `04` verbatim.**
   - Pro: matches our determinism/testability/offline rules; writers own the JSON; the resolver is a
     ~20-line pure function we can pin to `04` with exhaustive tests. Con: we build it (small).

## Decision

Adopt **Option 3**. Three pure, headless logic classes plus one thin coordinator:

- `story/flag_store.gd` — `FlagStore` (booleans + the integer `UNITY`).
- `story/flag_ops.gd` — interprets the declarative effect ops a beat lists in data.
- `story/story_graph.gd` — beat traversal and branch gating, built from `ContentDB`.
- `story/ending_resolver.gd` — `resolveEnding` / `factions_united` / `offered_options`, **verbatim**
  from `04 §5`.
- `story/story_director.gd` — autoload coordinator that walks the graph, applies effects, fires
  `EventBus` signals, and calls `SaveManager`/`SceneRouter`.

### Beats as data (authored, not coded)

Each beat is a JSON record (schema in ADR-0007). The story-relevant fields:

```json
{
  "id": "A2-03",
  "act": 2,
  "location": "glasswastes",
  "scene": "dialogue",
  "branch": null,
  "effects": [
    { "op": "SET", "flag": "SAVED_GLASSWASTES_REFUGEES", "if_flag": "OBJ_GLASSWASTES_EVAC" },
    { "op": "INC_UNITY", "source_id": "u1_br1_refugees", "if_flag": "SAVED_GLASSWASTES_REFUGEES" }
  ],
  "next": ["A2-05"]
}
```

> Note the **single-owner split**: the BR1 *branch-identity* flags (`SAVED_GLASSWASTES`,
> `BRAMBLE_SHARD_DEPARTURE`, `MIRA_RECRUITED`) are owned by the **branch option** (below); the
> **in-scene UNITY sub-objective** (`SAVED_GLASSWASTES_REFUGEES`) and its `INC_UNITY` are owned by the
> **beat**. The two owners never set the same flag/source — see "Flag & UNITY ownership" below.
> `OBJ_*` is a transient in-scene objective flag the scene sets when the player meets the timing.

**Effect ops** (the only ones the interpreter accepts; unknown op = fatal validation error):

| Op | Meaning |
|---|---|
| `SET` | set `flag` true (optional `value:false` to clear); optional `if_flag` guard. |
| `INC_UNITY` | add `+1` to UNITY for a unique **`source_id`** (required), gated by `if_flag`. **Idempotent per `source_id`** (a `unity_sources_applied` set in `GameState` blocks re-application). Only applies while `!locked`. |
| `LOCK_ENDINGS` | freeze UNITY and the underlying flag set (only on beat `A3-13`). Derived flags are computed-on-read, never stored. |
| `SET_FINAL_CHOICE` | record `FINAL_CHOICE ∈ {SHARE,SLEEP,TAKE,WAKE}` into the **enum store** (only on `A4-06`). |
| `RECORD_ENDING` | derive + store `ENDING ∈ {A,B,C,D}` via `EndingResolver` into the **enum store** (only on `A4-07`). |

There is deliberately **no op to set `BRAMBLE_SACRIFICE`**: its rule (`FINAL_CHOICE ∈ {SHARE,SLEEP,TAKE}`)
is an enum-membership test the closed op vocabulary cannot express. It is therefore a **hard-coded
derived value** in `FlagStore.bramble_sacrifice()` (computed at A4-06b from the enum store) — and it is
**non-gating**, so hard-coding it touches no ending logic (the resolver lint proves it never appears in
`EndingResolver`). This is the one documented exception to "all story logic is data."

Effects are applied **in array order**. Idempotency is enforced at two grains: a per-beat `applied_beats`
ledger (re-entering a beat re-runs nothing) **and** the per-`source_id` `unity_sources_applied` set (so a
UNITY source can never be counted twice even if reached by two paths) — see ownership rules below.

### Branches as data

A branch (BR1–BR4) is its own JSON record listing its trigger beat, options, the per-option flags, and
the beat each option routes to. Example (BR2):

```json
{
  "id": "BR2",
  "trigger_beat": "A2-07",
  "merge_beat": "A2-10",
  "options": [
    { "id": "show_truth", "effects": [{ "op": "SET", "flag": "KESTREL_DOUBT" }], "goto": "A2-08" },
    { "id": "resist",     "effects": [{ "op": "SET", "flag": "KESTREL_PURSUER" }], "goto": "A2-08" }
  ]
}
```

`StoryDirector.choose(branch_id, option_id)` applies the option's effects then routes to `goto`.
Recruitment that depends on an earlier fork (e.g. `KESTREL_RECRUITED` requires `KESTREL_DOUBT`) is
itself a data effect on the **merge beat** with an `if_flag` guard, so the rule lives in data and is
testable: beat `A2-10` carries `{ "op":"SET","flag":"KESTREL_RECRUITED","if_flag":"KESTREL_DOUBT" }`
and `{ "op":"INC_UNITY","source_id":"u3_kestrel","if_flag":"KESTREL_DOUBT" }`.

### Flag & UNITY ownership (single owner — prevents double-count)

To make `FACTIONS_UNITED` impossible to corrupt by a flag/UNITY being applied twice, ownership is **one
place, never two**:

- A **branch option** owns its branch-identity/outcome flags (`SAVED_GLASSWASTES`, `KESTREL_DOUBT`, …).
  **No beat may `SET` a flag that a branch option sets**, and vice-versa.
- A **beat** owns its own story flags and its in-scene UNITY sub-objective(s).
- Every UNITY `+1` is keyed to a unique **`source_id`** (the eight ids `u1…u8`, listed in
  `data/flags/unity_sources.json`), applied in exactly one location, and **idempotent per `source_id`**.
- The validator (ADR-0007 domain rule) asserts: (a) each registered flag is `SET` by ≤1 owner-kind, (b)
  exactly the eight distinct `source_id`s (`u1…u8`) exist and **each is applied at most once on any
  single playthrough** — a `source_id` may legitimately be authored on **mutually-exclusive** beats
  (e.g. `u1` on both A2-03 and A2-04, only one of which is ever visited), and the per-`source_id`
  `unity_sources_applied` ledger guarantees ≤1 actual application regardless; the validator forbids the
  same `source_id` on two **co-reachable** locations, (c) every UNITY sub-objective gate flag (e.g.
  `SAVED_GLASSWASTES_REFUGEES`, `SAVED_VERDANCE_VILLAGERS`, `CONSCRIPTS_FREED`, `HUSH_SURVIVORS_SAVED`,
  `ALLIES_RALLIED`, `ROOKWISE_RECRUITED`, `KESTREL_RECRUITED`, and the BR3 unifying gate) is
  **registered** in `flags.json`. A GUT domain test walks every path and asserts no `source_id` is
  applied twice on a path and UNITY never exceeds 8.

### Flag model (mirrors `04 §3`)

- **Booleans:** the full named set in `04 §3.1` (gating) and the non-gating emotional/Piggy flags in
  `04 §3.1` "Emotional-thread flags". The flag **registry** in `data/flags/` marks each `gating:
  true|false`. The resolver may only read `gating:true` flags — a lint test (ADR-0009) proves no
  non-gating flag (`PELL_*`, `FIRST_FLIGHT_WON`, `RELIGHTING_SHARED`, `HAVEN_RELIT`, `SABLE_RIFT`,
  `SABLE_RECONCILED`, `PIGGY_RECRUITED`, `PIGGY_JOINED_LATE`, `BRAMBLE_SACRIFICE`) appears in
  `EndingResolver`.
- **Enum-valued story state (NOT booleans):** `FINAL_CHOICE ∈ {SHARE,SLEEP,TAKE,WAKE}` and
  `ENDING ∈ {A,B,C,D}` are scalars, so they live in a small **enum store** on `FlagStore`
  (`final_choice()/set_final_choice()`, `ending()/set_ending()`), **separate** from the boolean dict,
  and are serialized under `story.choices` in the save (ADR-0005 §d). They are never represented as
  booleans. The registry lists them with `kind: final_choice`/`ending` for documentation/integrity, but
  they are stored and read through the enum API, not `get_flag`.
- **UNITY:** integer, starts 0, **monotonic** (only ever increments), **range 0–8**, **frozen at
  A3-13** by `LOCK_ENDINGS`. Exactly eight `source_id`s per `04 §3.2`, each `+1`, each gated by its flag,
  each idempotent per source.
- **Derived flags are computed-on-read, never authored and never stored.** `FlagView` (built from
  `FlagStore` or a dict) computes them each time from the underlying flags + the frozen UNITY, so there
  is exactly one source of truth:

```
WARDEN_TRUTH_WHOLE :=
     (BRAMBLE_SHARD_DEPARTURE and BRAMBLE_SHARD_PROMISE)
  or (ROOKWISE_RECRUITED and (BRAMBLE_SHARD_DEPARTURE or BRAMBLE_SHARD_PROMISE))

FACTIONS_UNITED :=
     unity >= 5
 and KESTREL_RECRUITED
 and (ORDER_ALLIED or TRUTH_SHARED)
```

- `BRAMBLE_SACRIFICE := final_choice() in {SHARE,SLEEP,TAKE}` — a **hard-coded derived, non-gating**
  value computed at **A4-06b** from the enum store (see the op table above for why it cannot be
  authored). It never appears in any availability check or in `resolveEnding`.

### The ending resolver (mirrors `04 §5` EXACTLY)

```gdscript
# story/ending_resolver.gd  (pure, static)
# `v` is a FlagView (story/flag_view.gd) — a typed facade with REAL bool properties and computed
# derived methods, built via FlagStore.view() (or FlagView.from_dict for synthesized states). This
# makes the access honest (it compiles against FlagStore) while the LOGIC stays line-for-line with 04.
const SHARE := ids.FinalChoice.SHARE
const SLEEP := ids.FinalChoice.SLEEP
const TAKE  := ids.FinalChoice.TAKE
const WAKE  := ids.FinalChoice.WAKE

static func factions_united(v: FlagView) -> bool:
    return v.unity >= 5 and v.KESTREL_RECRUITED and (v.ORDER_ALLIED or v.TRUTH_SHARED)

static func can_wake(v: FlagView) -> bool:
    return v.warden_truth_whole() and v.ROOKWISE_RECRUITED and v.MARROW_REDEEMED

static func offered_options(v: FlagView) -> Array:
    var opts := [SLEEP, TAKE]                 # always available
    if factions_united(v): opts.append(SHARE)
    if can_wake(v):        opts.append(WAKE)
    return opts

static func resolve(v: FlagView, final_choice: int) -> int:
    if final_choice == SHARE and factions_united(v): return ids.EndingId.A
    if final_choice == SLEEP:                         return ids.EndingId.B
    if final_choice == TAKE:                          return ids.EndingId.C
    if final_choice == WAKE and can_wake(v):          return ids.EndingId.D
    # SHARE/WAKE are never presented unless their gate is true, so this is unreachable:
    assert(false, "resolveEnding reached an unoffered choice")
    return ids.EndingId.B
```

This is line-for-line faithful to `04 §5` — **the logic is unchanged; only the flag-access syntax is
now honest** (typed `FlagView` properties instead of bare `f.FIELD` against a `get_flag` store). Sleep→B
and Take→C are always available; Share→A is gated by `FACTIONS_UNITED`; Wake→D is gated by
`WARDEN_TRUTH_WHOLE and ROOKWISE_RECRUITED and MARROW_REDEEMED`. `FlagView.factions_united()` and
`warden_truth_whole()` use the exact `04 §3.3` expressions; the golden test (ADR-0009) pins all of this
to `04`.

### Quest state

Quests (`CQ-*/SQ-*/MA-*`) are data records (ADR-0007) with `state ∈ {LOCKED, AVAILABLE, ACTIVE,
DONE}` tracked in `GameState`. Quest completion sets ordinary flags (e.g. `PIGGY_RECRUITED` from
SQ-PIGGY) via the same effect ops, so quests and beats share one flag pipeline. Quests never bypass the
resolver: SQ-PIGGY, MA-01, MA-02 only set their own (mostly non-gating) flags.

## Rationale

A purpose-built data-driven graph keeps the locked story as **content**, lets writers edit beats and
branches without engine changes, and reduces the high-stakes logic (the resolver) to a tiny pure
function we can pin to `04` with exhaustive truth-table tests. It satisfies determinism (no RNG in the
story graph at all), testability, and offline constraints with no external dependency.

## Consequences

- `EndingResolver` and `04 §5` are now coupled by a **golden test** that enumerates every gating
  combination; any divergence fails CI. If `04` ever changes, the test and resolver change together.
- The effect-op vocabulary is closed and validated; adding an op is a code+ADR change, keeping data
  safe for non-engineers.
- UNITY's monotonic/locked invariants are enforced in `FlagStore`, not trusted to data authors.
- Branch routing, merges, and recruitment-dependency live in data, so the single-track-spine rule from
  `04 §1` is verifiable by walking the graph in a test (every branch merges at its named beat).
