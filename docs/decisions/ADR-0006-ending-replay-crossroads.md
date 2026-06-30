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
        s = _canonical_state_for(ending_id)          # synthesized minimal valid locked state
    s.story.current_beat_id = "A4-06"
    s.story.endings_locked = true                    # UNITY frozen; derived flags computed
    # invariant: the target option must be offered from this state
    assert(EndingResolver.offered_options(_flags(s), s.story.unity).has(_choice_for(ending_id)))
    return s
```

- **Faithful path** (tiers 1–2): the stored `divergence_snapshots[ending_id]` is the exact
  `GameState.snapshot()` captured **on entry to A4-06** in the completed run — full flags, UNITY (locked),
  party, inventory, location, and RNG cursors. Replaying it reproduces that run's finale precisely
  (RNG-deterministic, ADR-0009).
- **Canonical path** (synthetic, optional): `_canonical_state_for` reads `data/endings/<id>.json`'s
  `requires` block and sets exactly those gating flags + UNITY (and the implied A4-03/A4-05 outcomes)
  to the minimum that makes the option offered, plus a default party/inventory loadout for the finale.

In **both** paths the builder asserts (and tests verify) that
`EndingResolver.offered_options(flags, unity)` contains the target choice — i.e. the reconstructed
state is a **valid** story-graph/flag state for that ending. The resolver used is the *same one* from
ADR-0003; replay never has its own copy of the ending rules.

### Sandboxed replay session

Replay runs in a **separate, throwaway `GameState`** (a "replay session"); the player's real save is
**never overwritten** by a replay. On finishing the replayed ending the game returns to Crossroads and
discards the replay state. (`SaveManager` will not autosave over `save_main.sav` while in replay mode;
it may use a distinct `replay.sav` for crash-safety within the replay only.)

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
  unlocks A/D; `build_state` (faithful and canonical) always yields an offerable, valid state; and the
  resolver returns A/B/C/D correctly for each reconstructed state.
