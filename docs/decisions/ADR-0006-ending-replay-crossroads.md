# ADR-0006: Ending-replay / Crossroads selector

- **Status:** Accepted
- **Date:** 2026-06-30
- **Deciders:** Architect, Owner

## Context

`DEFINITION_OF_DONE.md` **#14 (Owner requirement)**: after finishing the game once, the player can
replay **any** ending. From a post-game **Crossroads** selector they resume from the **story-divergence
point** that determines that ending and play forward to it — **without redoing the whole game**.
Verified by unit tests that the selector unlocks all reached/known endings and that resuming from each
divergence point reconstructs a **valid story-graph/flag state**. This must stay perfectly consistent
with `ADR-0003`'s resolver (`04 §5`).

## Options considered

1. **Full New Game+ replays.** Replaying an ending means replaying the whole game. Rejected — violates
   "without redoing the whole game."
2. **Save a snapshot at every branch and let the player rewind to any branch.** Powerful but heavy and
   confusing for a 10-year-old; many branches don't change the *ending*, only the journey.
3. **Single divergence point at the final choice (A4-06), with the earlier gating flags reconstructed
   to a valid state per ending.** Because all four endings are a pure function of the locked flag set
   plus `FINAL_CHOICE`, the *only* decision that distinguishes A/B/C/D is the A4-06 choice; the earlier
   branch flags merely decide which options are **offered**. Chosen.

## Decision

### Divergence-point mapping (the answer to "where do we resume?")

All four endings share **one divergence beat: `A4-06` — THE FINAL CHOICE.** That is the latest decision
that determines the ending. What differs per ending is the **availability gate** (earlier flags +
UNITY + the A4-03 Marrow outcome), which the replay reconstructs:

| Ending | Divergence beat | `FINAL_CHOICE` | Earlier gating flags that must hold to be *offered* |
|---|---|---|---|
| **A — Shared Dawn** | A4-06 | `SHARE` | `FACTIONS_UNITED` = `UNITY ≥ 5 AND KESTREL_RECRUITED AND (ORDER_ALLIED OR TRUTH_SHARED)` |
| **B — Long Quiet** | A4-06 | `SLEEP` | *(none — always offered)* |
| **C — Ascendant Throne** | A4-06 | `TAKE` | *(none — always offered)* |
| **D — Wandering Star** *(secret)* | A4-06 | `WAKE` | `WARDEN_TRUTH_WHOLE AND ROOKWISE_RECRUITED AND MARROW_REDEEMED` |

Replaying resumes at **A4-06** (the player re-sees the Warden's offer, picks the target choice, and
plays A4-06 → A4-06b → A4-07). The party/inventory/location for that scene come from the reconstructed
state. The deeper Act IV beats A4-01…A4-05 are deterministic given the locked flags, so their relevant
outcomes (`WARDEN_AWAKE`, `MARROW_REDEEMED`, `THANE_PERSUADED`) are already present in the reconstructed
state; the replay does **not** re-walk them unless flavor requires (a short recap cutscene is allowed).

### Unlocking the selector

- Reaching any `A4-07 ENDING` for the first time sets `GAME_COMPLETED = true` and unlocks the
  **Crossroads** screen (`ui/crossroads/`), reachable from the Title screen and post-credits.
- Unlocks are **cumulative across all completed runs**, persisted in the main save's
  `endings_unlocked` (Array) and `divergence_snapshots` (Dictionary keyed by ending id).

What unlocks, per completed run, at the moment `A4-06` is entered:

1. **The ending actually reached** (the chosen one) → unlocked, with a **faithful snapshot** stored.
2. **Every ending whose option was *offered* but not chosen** in that run (e.g. Share was available but
   the player chose Sleep) → unlocked, sharing that run's snapshot (the snapshot's flags already
   satisfy each offered gate, so the resolver returns the right letter for any offered choice).

This satisfies "unlocks all reached/known endings." Because Sleep and Take are always offered, finishing
the game **once** immediately unlocks B and C; A and D unlock as soon as a run reaches A4-06 with their
gate satisfied (whether or not chosen).

> **"Replay ANY ending" generosity (optional, behind completion):** `ReplayPlanner.build_state` can also
> synthesize a **canonical valid state** for an ending the player never had offered, from the ending's
> `requires` spec in `data/endings/`. The Crossroads UI may present these as "experience" entries
> (clearly marked, not "your" run). This guarantees literal "any ending" replay; the *required* unlock
> rule is still reached∪offered above.

### Reconstruction (how a valid state is rebuilt)

`story/replay_planner.gd` (pure, static):

```gdscript
static func divergence_beat_for(ending_id: int) -> String:
    return "A4-06"   # all endings

static func is_unlocked(ending_id: int, game_state) -> bool:
    return game_state.endings_unlocked.has(ending_id)

# Build a GameState dict positioned at A4-06 from which `ending_id` is offerable.
static func build_state(ending_id: int, stored_snapshot) -> Dictionary:
    var s: Dictionary
    if stored_snapshot != null:
        s = stored_snapshot.duplicate(true)          # faithful: the run that earned it
    else:
        s = _canonical_state_for(ending_id)          # synthesized: sets UNDERLYING flags only
    s.story.current_beat_id = "A4-06"
    s.story.endings_locked = true                    # UNITY frozen
    # Build the SAME FlagView a real run uses — derived flags are COMPUTED here, never stored:
    var v := FlagView.from_dict(s.story.flags, s.story.unity)
    # invariant (regression guard): the target option must be offered from this state
    assert(EndingResolver.offered_options(v).has(_choice_for(ending_id)))
    return s

# Synthesized canonical state: set the UNDERLYING flags from data/endings/<id>.requires, then let the
# derive step (FlagView) compute WARDEN_TRUTH_WHOLE / FACTIONS_UNITED. NEVER sets a derived flag.
static func _canonical_state_for(ending_id: int) -> Dictionary:
    var req := ContentDB.ending(_id_str(ending_id)).requires   # underlying flags + unity_min only
    var flags := {}
    for f in req.flags_all: flags[f] = true                    # e.g. ROOKWISE_RECRUITED, MARROW_REDEEMED
    if req.has("flags_any") and req.flags_any.size() > 0:
        flags[req.flags_any[0]] = true                          # e.g. one shard (DEPARTURE or PROMISE)
    var unity = max(req.get("unity_min", 0), 0)
    # ...default finale party/inventory/location loadout...
    return { "story": { "flags": flags, "unity": unity, "choices": {"final_choice":"NONE","ending":"NONE"} } }
```

- **Faithful path** (tiers 1–2): the stored `divergence_snapshots[ending_id]` is the exact
  `GameState.snapshot()` captured **on entry to A4-06** in the completed run — full flags, UNITY (locked),
  party, inventory, location, and RNG cursors. Replaying it reproduces that run's finale precisely
  (RNG-deterministic, ADR-0009).
- **Canonical path** (synthetic): `_canonical_state_for` reads `data/endings/<id>.requires` — which is
  authored **entirely in underlying flags** (never derived ones) — sets exactly those underlying flags +
  `unity_min`, and then the builder **re-runs the derive step via `FlagView`** to compute
  `WARDEN_TRUTH_WHOLE`/`FACTIONS_UNITED`. This is the critical fix: a derived flag is **never set
  directly**, so a synthesized Ending-D state cannot contain the contradiction "WARDEN_TRUTH_WHOLE=true
  but no shards." `data/endings/D.requires` is therefore
  `{ flags_all:[ROOKWISE_RECRUITED, MARROW_REDEEMED], flags_any:[BRAMBLE_SHARD_DEPARTURE,
  BRAMBLE_SHARD_PROMISE] }` — from which the derive step computes `WARDEN_TRUTH_WHOLE=true` exactly as a
  real run would.

In **both** paths the builder asserts (and tests verify) that `EndingResolver.offered_options(v)`
contains the target choice — i.e. the reconstructed state passes the **same** validation a real run does
and the **same** ADR-0003 resolver returns exactly the intended ending. Replay never has its own copy of
the ending rules, and the `requires` schema cannot express a derived flag (ADR-0007), so the only way to
satisfy a derived gate is to set its underlying flags and recompute — by construction.

### Sandboxed replay session

`GameState` is an autoload **singleton**, so a replay does not instantiate a second one. The mechanism:

```
StoryDirector.start_replay(ending_id):
  SaveManager.enter_replay_mode()          # 1) stash the REAL save dict in memory; HARD-BLOCK all
                                            #    writes to save_main.sav on EVERY path (autosave,
                                            #    checkpoint, AND _notification lifecycle) — ADR-0005
  GameState.from_dict(ReplayPlanner.build_state(ending_id, snapshot_or_null))
  SceneRouter.goto(CUTSCENE, {beat: "A4-06"})   # play A4-06 → A4-06b → A4-07
on replay exit (ending shown or player quits):
  SaveManager.exit_replay_mode()           # restore the stashed REAL save dict into GameState
  SceneRouter.goto(CROSSROADS)
```

The player's real save is **never overwritten** by a replay because the no-save guard covers **every**
write path — crucially the **lifecycle `_notification` path** (a focus-out/background mid-replay is the
most likely unexpected write, and it is blocked). For crash-safety *within* a replay, SaveManager may use
a distinct `replay.sav`; it never touches `save_main.sav`(+`.bak`) while in replay mode. Exiting replay
restores the stashed real-save dict, so the live singleton is returned to the player's true progress.

### Persistence

`endings_unlocked` and `divergence_snapshots` live in the main save (ADR-0005 §d) and migrate with it.
Snapshots are compact (they reuse the save serializer). Unlocks only ever grow.

## Rationale

Because `04`'s endings are a pure function of locked flags + the final choice, a **single divergence
point (A4-06)** is sufficient and correct: nothing between A4-06 and A4-07 changes which ending you get
except the choice itself, and everything that gates *availability* is captured in the snapshot or
synthesized from data. This is the minimal, least-confusing design that fully meets #14, reuses the
ADR-0003 resolver verbatim (no rule duplication, no drift), and is trivially unit-testable: for each
ending, assert `build_state` yields a state where the option is offered and `resolve` returns the right
letter. A sandboxed replay protects the player's real progress.

## Consequences

- We must capture a `GameState.snapshot()` exactly **on entry to A4-06** and store it per offered/chosen
  ending — a small, well-defined hook in `StoryDirector`.
- The Crossroads UI needs to distinguish "your" unlocked endings (faithful snapshots) from optional
  synthesized "experience" entries, if the latter are enabled.
- Adding a new ending later would mean a new `data/endings/` entry, a resolver update (ADR-0003), and a
  replay test — but the divergence-point machinery is unchanged.
- Tests (ADR-0009) must cover: completing once unlocks B+C; reaching A4-06 with each gate satisfied
  unlocks A/D; `build_state` (faithful and canonical) always yields an offerable, valid state with
  derived flags **computed** (a synthesized Ending-D state has real shards/Rookwise/Marrow, never a
  directly-set `WARDEN_TRUTH_WHOLE`); the resolver returns A/B/C/D correctly for each reconstructed
  state; and the replay-mode guard blocks a simulated lifecycle write from clobbering the real save.
- `data/endings/*.requires` is authored **only in underlying flags** (the validator rejects a derived
  flag name there), so the synthesized path can never manufacture a contradictory state — the derive
  step is the single way a derived gate becomes true.
