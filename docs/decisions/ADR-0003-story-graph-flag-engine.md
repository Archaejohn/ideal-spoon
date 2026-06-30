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
    { "op": "SET", "flag": "SAVED_GLASSWASTES" },
    { "op": "SET", "flag": "BRAMBLE_SHARD_DEPARTURE" },
    { "op": "SET", "flag": "MIRA_RECRUITED" },
    { "op": "INC_UNITY", "amount": 1, "if_flag": "SAVED_GLASSWASTES_REFUGEES" }
  ],
  "next": ["A2-05"]
}
```

**Effect ops** (the only ones the interpreter accepts; unknown op = fatal validation error):

| Op | Meaning |
|---|---|
| `SET` | set `flag` true (optional `value:false` to clear). |
| `INC_UNITY` | add `amount` (default 1) to UNITY, gated by optional `if_flag`. Only applies while `!locked`. |
| `LOCK_ENDINGS` | freeze UNITY and compute derived flags (only on beat `A3-13`). |
| `SET_FINAL_CHOICE` | record `FINAL_CHOICE ∈ {SHARE,SLEEP,TAKE,WAKE}` (only on beat `A4-06`). |
| `RECORD_ENDING` | derive + store `ENDING ∈ {A,B,C,D}` via `EndingResolver` (only on `A4-07`). |

Effects are applied **in array order**, idempotently per beat entry (re-entering a beat does not
double-count UNITY because a beat's UNITY source is tied to a sub-objective flag that is itself
idempotent; the interpreter also guards with a per-beat `applied` ledger in `GameState`).

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
and `{ "op":"INC_UNITY","if_flag":"KESTREL_DOUBT" }`.

### Flag model (mirrors `04 §3`)

- **Booleans:** the full named set in `04 §3.1` (gating) and the non-gating emotional/Piggy flags in
  `04 §3.1` "Emotional-thread flags". The flag **registry** in `data/flags/` marks each `gating:
  true|false`. The resolver may only read `gating:true` flags — a lint test (ADR-0009) proves no
  non-gating flag (`PELL_*`, `FIRST_FLIGHT_WON`, `RELIGHTING_SHARED`, `HAVEN_RELIT`, `SABLE_RIFT`,
  `SABLE_RECONCILED`, `PIGGY_RECRUITED`, `PIGGY_JOINED_LATE`, `BRAMBLE_SACRIFICE`) appears in
  `EndingResolver`.
- **UNITY:** integer, starts 0, **monotonic** (only ever increments), **range 0–8**, **frozen at
  A3-13** by `LOCK_ENDINGS`. Eight sources exactly per `04 §3.2`, each `+1`, each gated by its flag.
- **Derived (computed at A3-13, never authored):**

```
WARDEN_TRUTH_WHOLE :=
     (BRAMBLE_SHARD_DEPARTURE and BRAMBLE_SHARD_PROMISE)
  or (ROOKWISE_RECRUITED and (BRAMBLE_SHARD_DEPARTURE or BRAMBLE_SHARD_PROMISE))

FACTIONS_UNITED :=
     unity >= 5
 and KESTREL_RECRUITED
 and (ORDER_ALLIED or TRUTH_SHARED)
```

- `BRAMBLE_SACRIFICE := FINAL_CHOICE in {SHARE,SLEEP,TAKE}` — computed at **A4-06b**, *after* the
  choice; an **outcome** flag only. It never appears in any availability check or in `resolveEnding`.

### The ending resolver (mirrors `04 §5` EXACTLY)

```gdscript
# story/ending_resolver.gd  (pure, static)
const SHARE := ids.FinalChoice.SHARE
const SLEEP := ids.FinalChoice.SLEEP
const TAKE  := ids.FinalChoice.TAKE
const WAKE  := ids.FinalChoice.WAKE

static func factions_united(f, unity: int) -> bool:
    return unity >= 5 and f.KESTREL_RECRUITED and (f.ORDER_ALLIED or f.TRUTH_SHARED)

static func can_wake(f) -> bool:
    return f.WARDEN_TRUTH_WHOLE and f.ROOKWISE_RECRUITED and f.MARROW_REDEEMED

static func offered_options(f, unity: int) -> Array:
    var opts := [SLEEP, TAKE]                 # always available
    if factions_united(f, unity): opts.append(SHARE)
    if can_wake(f):               opts.append(WAKE)
    return opts

static func resolve(f, unity: int, final_choice: int) -> int:
    if final_choice == SHARE and factions_united(f, unity): return ids.EndingId.A
    if final_choice == SLEEP:                                return ids.EndingId.B
    if final_choice == TAKE:                                 return ids.EndingId.C
    if final_choice == WAKE and can_wake(f):                 return ids.EndingId.D
    # SHARE/WAKE are never presented unless their gate is true, so this is unreachable:
    assert(false, "resolveEnding reached an unoffered choice")
    return ids.EndingId.B
```

This is line-for-line faithful to `04 §5`: Sleep→B and Take→C are always available; Share→A is gated by
`FACTIONS_UNITED`; Wake→D is gated by `WARDEN_TRUTH_WHOLE and ROOKWISE_RECRUITED and MARROW_REDEEMED`.

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
