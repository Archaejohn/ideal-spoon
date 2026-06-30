# Phase 2 Architecture Review — "Aetherbound"

> **Reviewer role:** Independent Architecture Reviewer (did not author this design).
> **Date:** 2026-06-30
> **Scope:** ARCHITECTURE.md, PHASE2_OWNER_RULINGS.md, ADR-0003…ADR-0009, against the locked
> contracts in `docs/story/03_MAIN_STORY.md`, `04_BRANCHES_ENDINGS.md`, `DEFINITION_OF_DONE.md`
> (#4, #9, #13, #14), and the example schemas under `game/data/`.
> **Verdict:** **NEEDS WORK** (strong foundation; concrete blocking gaps in battle AI, two missing
> schemas, web durability correctness, and the synthesized-replay path).

---

## Summary

This is a genuinely good design. The determinism-first, data-driven, headless-core philosophy is
coherent and consistently applied; the module boundaries are clean; the resolver is faithful to the
story; and the test plan maps tightly to the Definition of Done. The problems are not philosophical —
they are **specific omissions and a few internal inconsistencies** that will stop an engineer from
building a complete, correct game against this spec as written. None require redesign; all are
bounded fixes. But several block DoD clauses (#4 battle buildability, #13 web durability, #14 replay
validity), so this cannot be approved as-is.

| # | Area | Score |
|---|------|------:|
| 1 | Contract fidelity (resolver / flags / UNITY / derived) | **8/10** |
| 2 | Crash-safe saving (DoD #13) | **6/10** |
| 3 | Ending replay (DoD #14) | **6/10** |
| 4 | ATB battle design (DoD #4) | **5/10** |
| 5 | Module boundaries & testability | **8/10** |
| 6 | Schema & pipeline completeness | **6/10** |

---

## 1. Contract fidelity — **8/10**

**What is exactly right.** `EndingResolver` (ADR-0003 §"The ending resolver") is line-for-line
faithful to `04 §5`:
- `factions_united = unity >= 5 and KESTREL_RECRUITED and (ORDER_ALLIED or TRUTH_SHARED)` — identical
  to `04 §3.3` and the `factionsUnited` reference.
- `can_wake = WARDEN_TRUTH_WHOLE and ROOKWISE_RECRUITED and MARROW_REDEEMED` — identical to `04 §4`
  Wake gate.
- `offered_options` always lists `[SLEEP, TAKE]`, adds `SHARE` iff factions united, `WAKE` iff
  can_wake — matches the `04 §4` availability table ("Sleep and Take are always available… Share and
  Wake are *earned*").
- `resolve` mapping SHARE→A / SLEEP→B / TAKE→C / WAKE→D with the same gates — matches.

`WARDEN_TRUTH_WHOLE` (ADR-0003) `(SHARD_DEPARTURE and SHARD_PROMISE) or (ROOKWISE_RECRUITED and
(SHARD_DEPARTURE or SHARD_PROMISE))` is verbatim `04 §3.3`. UNITY is correctly specified as integer,
monotonic, 0–8, frozen at A3-13 by `LOCK_ENDINGS`, eight sources. Beat IDs in ADR-0007 (`A1-01…A4-07`
incl. `A1-06a/b, A2-10b, A3-02b/c, A3-03b/c, A3-04b, A3-13b`) match the ledger in `03`. The
non-gating set (`PELL_*`, `FIRST_FLIGHT_WON`, `RELIGHTING_SHARED`, `HAVEN_RELIT`, `SABLE_*`,
`PIGGY_*`, `BRAMBLE_SACRIFICE`) matches `04 §3.1` "Emotional-thread flags," and the resolver-lint
(gating:false ⇒ provably absent from resolver) is the right mechanism. The pin-to-`04` golden test
(Owner Ruling #5) is the correct safeguard.

**Drift / gaps found:**

- **Enum-valued story state has no home.** `FINAL_CHOICE ∈ {SHARE,SLEEP,TAKE,WAKE}` and
  `ENDING ∈ {A,B,C,D}` are listed in the flag registry (`data/flags/example_flags.json`,
  `kind: final_choice`/`ending`) and the ledger (A4-06, A4-07), but `FlagStore` is defined as
  "**booleans + UNITY integer**" (ARCHITECTURE §7.3, ADR-0003). There is no boolean representation of
  a 4-way enum, and the save schema (ADR-0005 §d) shows `story.flags` as a boolean dict with **no
  `final_choice` or `ending` field**. So the two most important story outputs are unmodelled in both
  the flag store and the save payload. This is a real contract hole, not cosmetic.
- **`BRAMBLE_SACRIFICE` cannot be authored with the closed op vocabulary.** Its rule is
  `FINAL_CHOICE in {SHARE,SLEEP,TAKE}` (`04 §3.3`, ledger A4-06b). The only ops are
  `SET / INC_UNITY / LOCK_ENDINGS / SET_FINAL_CHOICE / RECORD_ENDING`, and `if_flag` tests a boolean,
  not an enum membership. There is no way in data to express "set this flag iff FINAL_CHOICE ∈ a set."
  It is non-gating so low-stakes, but as written it must be hard-coded — violating the data/code
  separation the whole design rests on.
- **UNITY sub-objective flags are invented and unregistered.** The BR1 data
  (`branches/example_branch.json`) and ADR-0003 examples gate `INC_UNITY` on
  `SAVED_GLASSWASTES_REFUGEES` / `SAVED_VERDANCE_VILLAGERS`, but those names appear **nowhere** in
  `04 §3` and **are not in** `flags/example_flags.json`. ADR-0007's referential-integrity rule
  ("every referenced id exists… a beat's `flag` is in the flag registry") would make this **fail
  validation**. Either register them (with `04` updated) or change the gate.
- **Branch-option vs beat flag ownership is ambiguous → double-UNITY risk.** `04 §2` and the `03`
  ledger both attribute BR1's flags to A2-03/04 (the beat), while ADR-0007's branch example sets them
  in the **option**. If both the option's `effects` and the destination/merge beat's `effects` apply
  the same `INC_UNITY`, the per-beat `applied` idempotency ledger (ADR-0003) will **not** catch it
  (different sources), and UNITY double-counts — directly corrupting `FACTIONS_UNITED`. The contract
  must state exactly one owner per flag/UNITY source.
- **`FACTIONS_UNITED` stored vs computed inconsistency.** The registry marks it `kind: derived`
  (implying it is stored at lock), but the resolver **recomputes** it live and reads only
  `WARDEN_TRUTH_WHOLE` as a stored flag. Two potential sources of truth for the same value. Pick one
  (recommend: derived flags are computed, never stored, except where the resolver reads them).
- **Minor doc drift:** ARCHITECTURE §6 abbreviates the new-beat list (omits `A1-06b, A3-02b/c,
  A3-03b/c`); §7.1 lists 4 RNG streams while ADR-0009 lists 5 (adds `encounter`); GameState §7.2 omits
  the `quests` field that the save schema §d carries.

---

## 2. Crash-safe saving (DoD #13) — **6/10**

**What is right.** The temp-write → flush → backup → atomic `rename` pattern (ADR-0005 §b) is the
correct primitive. Checksum+header validation on read with `.bak` fallback (§b read_validated),
separate `checkpoint.sav` pair, lifecycle-hook writes bypassing debounce (§a, Owner Ruling #4),
settings persisted separately, and version+migration (§d) are all sound and complete on **Android**.
The pre-battle-checkpoint = unit-of-resume model (Owner Ruling #2) is clean and makes the
lose→retry contract structurally guaranteed (ADR-0008 §"Where save/checkpoint hooks sit").

**Holes:**

- **The web async-flush gap is real and the design overstates it (BLOCKING for #13 "done").**
  ADR-0005 §e says the lifecycle hooks "drive this sync on web" and §a says lifecycle writes "must
  complete before the handler returns." On the browser this is **not achievable**: IDBFS/OPFS
  `syncfs` is **asynchronous with a callback**; you cannot synchronously block a `_notification`
  handler until IndexedDB has durably committed, and the tab can be hidden/killed before the async
  flush resolves. Owner Ruling #3 makes durable web survival a **hard requirement gating "done"**, so
  the design as written cannot meet its own bar. The fix is a different strategy, not hand-waving:
  flush on `visibilitychange→hidden`/`pagehide` (fires reliably and earlier than close), run a
  periodic `syncfs` so the durable lag is bounded, and **document the residual small-loss window**.
  Also: "OPFS on supporting builds" is optimistic — confirm what the actual Godot 4.x web export
  provides before depending on it.
- **"Both save and backup corrupt" ignores the checkpoint.** §b read_validated falls main→`.bak`→
  `Err` ("starting fresh"). But `checkpoint.sav`(+`.bak`) is a separate, often very recent, valid
  pair. On total main-save loss the design discards a perfectly good recovery source and sends the
  player to a new game. Add checkpoint as a last-ditch recovery tier before "start fresh."
- **Backup promotion can destroy the last good backup.** §b step 3 says "If a valid `path` already
  exists, copy it to `path.bak`." If "valid" means *exists* (not *checksum-validates*), then a torn
  main from a prior failed write gets copied over a **good** `.bak`, losing the only recoverable copy.
  Must be explicit: validate the current main **before** promoting it to `.bak`; never overwrite a
  good backup with a bad main.
- **No pre-migration backup.** §d migrates in place, then normal autosave will overwrite
  `save_main.sav` with the migrated state. If a migration step is buggy, the original v(n) save is
  gone. Keep a one-shot `save_main.v{n}.bak` before the first write of migrated data, and re-validate
  the dict **after** migration (currently only validated before).
- **Debounce/lifecycle interaction unspecified.** A pending debounced autosave plus an immediate
  lifecycle write should be coalesced (cancel the pending timer) — single-threaded GDScript prevents a
  true race, but the spec should say the lifecycle write flushes/cancels the pending one.

---

## 3. Ending replay (DoD #14) — **6/10**

**What is right.** The single-divergence-point insight (ADR-0006 §"Divergence-point mapping") is
correct: because A/B/C/D are a pure function of locked flags + `FINAL_CHOICE`, **A4-06 is the only
beat that distinguishes endings**, so resuming there with a reconstructed state is sufficient. The
**faithful path** — store `GameState.snapshot()` *on entry to A4-06* and replay it — is sound and
deterministic (RNG cursors captured, ADR-0009). Capturing at A4-06 entry (not A3-13) is the right
call: `MARROW_REDEEMED` (A4-03), `WARDEN_AWAKE` (A4-04), `THANE_PERSUADED` (A4-05) are all set by
then, so `offered_options` has every input. The reach∪offered unlock rule and reuse of the **same**
resolver (no duplicated ending rules) are exactly right. The build_state `assert(offered_options …
has target)` invariant is a good guard.

**Holes:**

- **The synthesized/canonical path risks an INVALID flag combination — specifically for Ending D
  (the question's central concern).** `_canonical_state_for` (ADR-0006 §"Reconstruction") reads the
  ending's `requires` block and "sets exactly those gating flags + UNITY." But Wake's gate includes
  **`WARDEN_TRUTH_WHOLE`, which is *derived*, not authored** (`04 §3.3`). If the builder sets
  `WARDEN_TRUTH_WHOLE = true` directly while leaving the underlying shards false, then either (a) it
  contradicts the derive rule, or (b) `lock_endings`/recompute flips it back to false and the
  `assert` fails. The `requires` schema (ADR-0007: `unity_min` / `flags_all` / `flags_any`) **cannot
  express a derived flag** — it can only list raw flags. The fix: canonical reconstruction must set
  the **underlying** flags (e.g. `flags_all:[ROOKWISE_RECRUITED, MARROW_REDEEMED]`,
  `flags_any:[BRAMBLE_SHARD_DEPARTURE, BRAMBLE_SHARD_PROMISE]`) and then **run the same derive step**
  to compute `WARDEN_TRUTH_WHOLE` — never set the derived flag directly. This must be stated, and the
  `data/endings/D` `requires` must be authored against underlying flags, or the "play any ending"
  generosity feature produces contradictory states.
- **Sandbox protection hinges on a guard that must cover the lifecycle path.** ADR-0006 §"Sandboxed
  replay" says SaveManager "will not autosave over `save_main.sav` while in replay mode." But
  ADR-0005's lifecycle `_notification` writes immediately and is the most likely thing to fire
  unexpectedly (player backgrounds the app mid-replay). If the replay-mode guard is only on the
  normal `autosave()` path and not on `_notification`, a lifecycle write **clobbers the real save with
  replay state**. The guard must be enforced on *every* write path including lifecycle.
- **Singleton GameState vs "separate throwaway GameState."** `GameState` is an autoload singleton
  (ARCHITECTURE §2); you cannot trivially instantiate a second one. "Replay runs in a separate
  throwaway GameState" therefore means overwriting the live singleton and relying entirely on the
  never-save guard. That is fragile and couples replay safety to the guard above. Spell out the
  mechanism (e.g. stash the real `to_dict()`, restore on exit, hard-block all writes meanwhile).

---

## 4. ATB battle design (DoD #4) — **5/10**

**What is right.** The tick-based pure engine with `step(dt_ticks)→events` + `queue_action`
(ADR-0004 §"ATB gauge", §"Action selection") is the correct way to get FF-style feel while staying
headless and deterministic. Integer damage math with the single ±5% variance + crit on the injected
`battle` stream (§"Damage formula") is reproducible. Deterministic tie-break (higher SPD, then stable
index — no RNG) is exactly right. Breath/Pomp/Songsickness as first-class `Combatant` fields,
Penguin Dance on the `dance` stream, leveling delegated to `LevelSystem`, loot to `Inventory`,
win/lose/flee with checkpoint-restore on LOSE — all present and testable. Wait/active mode and the
decision window correctly pushed to the controller so the engine stays timing-agnostic.

**Holes — this is the weakest area because a battle is not buildable as specified:**

- **Enemy AI / action-selection is entirely missing (BLOCKING for #4).** The enemy schema has
  `ai: basic|caster|boss_phased` (ADR-0007), but **no module, class, or interface anywhere** selects
  an enemy's ability and targets. The engine "consumes queued actions"; for players the controller/UI
  queues them — **but nothing queues enemy actions.** There is no `AIController`/`EnemyBrain` in the
  module list (ARCHITECTURE §2–§4) or the dependency graph, and no description of where AI lives,
  how it stays deterministic (it must draw from a seeded stream), or how it is tested. You cannot
  build a single fight without this. It needs a home, an injected RNG, and tests.
- **No `encounter` schema (BLOCKING for #4).** `BattleController.start(encounter, …)` and
  `beat.encounter` (ADR-0007 beat schema) reference an encounter id, but **there is no
  `data/encounters/` schema** (no folder in ARCHITECTURE §4, no schema in ADR-0007) defining which
  enemies, how many, formation, flee-allowed, rewards override, battle context. You can author an
  enemy but not a fight. This is exactly the "complete enough to author the whole game" bar ADR-0007
  sets for itself.
- **No `level_curve` schema (BLOCKING for #4 leveling).** `party.growth` references a curve id
  (`"support_curve"`) and `data/level_curves/` exists in the layout, but ADR-0007 provides **no
  schema** for the XP→level table or stat-growth curve. Leveling math can't be authored or
  unit-tested against an undefined shape.
- **Float `atb_modifier` contradicts the integer-determinism rule.** Statuses carry
  `atb_modifier: float` (`-0.30`, ADR-0004/0007) and ATB advance is "scaled by haste/slow." But
  ADR-0009 §1 mandates **integer math for all outcome-affecting formulas**, and **turn order is an
  outcome**. Multiplying integer `speed_rate` by a float invites cross-platform truncation
  divergence. Express the modifier as integer permille (e.g. `-300/1000`) and keep ATB advance in
  integer space.
- **Ability economy for 6 of 8 members is unspecified.** `cost.resource ∈ {NONE,BREATH,POMP,ITEM}`
  means everyone except Wren (Breath) and Piggy (Pomp) has either free abilities or item-cost ones,
  and there is **no cooldown/charge field** in the ability schema. Either that is intentional
  (kid-friendly, fine) or a generic resource/cooldown is missing — but the design should say which,
  because it determines whether encounters can be balanced at all.
- **No retargeting rule for dead/invalid targets** when an action resolves after an ATB delay, and
  `DamageFormula.compute` shows variance+crit but not the `accuracy`/miss roll the schema implies.
  Minor relative to the above, but needed for a complete engine.

---

## 5. Module boundaries & testability — **8/10**

**What is right.** The downward-only dependency rule, the headless logic core with RNG/ContentDB
**injected** (never global), the god-object guard on `GameState` (data only; rules live in
`EndingResolver`/`BattleEngine`/`StoryGraph`), and the two enforcement guard-tests
(`test_module_boundaries.gd`, `test_no_nondeterminism.gd`) are textbook and exactly what makes the
≥80% logic-coverage target (ADR-0009) realistic. The must-test list maps cleanly onto DoD
#4/#9/#13/#14. This is the strongest part of the design.

**Gaps engineers will trip on:**

- **`FlagStore` access contract is inconsistent with the resolver.** The resolver reads attributes —
  `f.KESTREL_RECRUITED`, `f.ORDER_ALLIED`, `f.WARDEN_TRUTH_WHOLE` (ADR-0003) — but `FlagStore`'s
  public API is `get_flag(name)` plus a few named methods (§7.3). GDScript won't resolve
  `f.KESTREL_RECRUITED` unless those are real properties or `f` is a plain `Dictionary`. Pick one
  (dict-backed resolver, or generated properties) and make the signature honest; otherwise the
  resolver as written does not compile against `FlagStore`.
- **Missing enemy-AI component** (see §4) is also a boundary gap: it needs a defined place in the
  dependency graph and the no-nondeterminism guard's grep list.
- **Event vocabulary from `BattleEngine.step()` is undefined.** "Returns events… small structs" —
  but the presentation layer must animate purely from them (ADR-0004 §Consequences), so the event
  types (`damage`, `heal`, `status_applied`, `turn_ready`, `down`, `battle_over`, …) are a real public
  contract and should be enumerated/typed for engineers to build the HUD against.
- **GameState public API drift** (omits `quests`, `final_choice`, `ending`, `applied_beats`) — see §1.
- **Replay vs singleton GameState tension** — see §3.

---

## 6. Schema & pipeline completeness — **6/10**

**What is right.** Plain validated JSON, one validator per kind, layered validation
(schema → referential integrity → domain rules), fail-fast in debug/CI, and the flag registry as the
single authoritative gate-source (ADR-0007) are the right calls and align with CONTRIBUTING. The
provided example files **match the ADR schemas**: `abilities/`, `beats/`, `branches/`, `endings/`,
`enemies/`, `flags/`, `items/` all conform (ability adds optional `element`/`tags`, both allowed;
enemy `loot` is `arr<obj>` with `chance`; ending `requires` matches the A-gate). Domain rules
(exactly eight UNITY sources, every branch merges at its named beat, graph connected A1-01→A4-07,
resolver reads only gating flags) are the right things to assert.

**Gaps (what you cannot author yet):**

- **No `encounter` schema** (BLOCKING — see §4).
- **No `level_curve` schema** (BLOCKING — see §4).
- **No representation for enum-valued state** `FINAL_CHOICE` / `ENDING` (see §1) — registry calls
  them flags but they are not booleans and have no save slot.
- **No op to author `BRAMBLE_SACRIFICE`** (see §1).
- **Unregistered UNITY sub-objective flags** would fail referential integrity (see §1).
- **Dialogue `condition` is a single truthy flag** (ADR-0007 dialogue schema). Real dialogue needs
  negation and compound conditions ("show iff NOT `KESTREL_RECRUITED`", "iff A and B"). As specified,
  branch-aware lines can't all be authored.
- **`encounter` RNG stream not saved.** ADR-0009 defines an `encounter` stream, but the save schema
  `rng_state.cursors` example (ADR-0005 §d) lists only `battle/loot/dance/story`. If encounter
  selection isn't cursor-saved, encounters aren't reproducible across save/load — a determinism
  promise (#13/#14) quietly broken.

---

## Overall verdict: **NEEDS WORK**

The architecture is well-conceived and ~80% of the way to an approvable design. It is held back by a
small number of **concrete, bounded** problems that each block a DoD clause: an ATB system with no
enemy AI and two missing data schemas (#4), a web-durability claim the platform can't honor as written
(#13), and a synthesized-replay path that can manufacture an invalid Ending-D state (#14). Fix the
MUST-FIX list and this is approvable.

### MUST-FIX (blocking)

1. **Add the enemy AI / action-selection component.** Define a pure, deterministic
   `battle/enemy_ai.gd` (or equivalent) that maps `enemy.ai ∈ {basic,caster,boss_phased}` to a
   `BattleAction`, draws only from an injected stream (`battle` or a new `ai` stream), lives in the
   dependency graph, is covered by the no-nondeterminism guard, and is unit-tested. Without it no
   fight runs.
2. **Add a `data/encounters/` schema (and folder).** Enemies list, counts/formation, flee-allowed,
   reward overrides, battle context; referenced by `beat.encounter` and `BattleController.start`.
   Add referential-integrity validation (every enemy id exists).
3. **Add a `data/level_curves/` schema.** XP→level table and per-stat growth shape, referenced by
   `party.growth`; integer-only; with good/bad fixtures and a `LevelSystem` test.
4. **Re-specify web durability correctly (Owner Ruling #3 / #13).** Acknowledge that `syncfs` is
   async and cannot be awaited in a dying `_notification` handler; flush on
   `visibilitychange→hidden`/`pagehide`, run a bounded periodic `syncfs`, document the residual
   loss window, and verify the chosen Godot 4.x web FS (don't assume OPFS).
5. **Model enum-valued story state.** Give `FINAL_CHOICE` and `ENDING` real homes in `GameState`/
   `SaveSerializer` (explicit fields, not the boolean flag dict) and the save schema; and add a way to
   author `BRAMBLE_SACRIFICE` (a new op such as `SET_IF_CHOICE`, or a documented derived computation)
   so no story logic is hard-coded.
6. **Fix the synthesized-replay derived-flag path.** Canonical `build_state` must set the
   **underlying** flags and **re-run the derive step** to compute `WARDEN_TRUTH_WHOLE` (never set the
   derived flag directly); author each `data/endings/*.requires` against underlying flags
   (D needs `flags_all:[ROOKWISE_RECRUITED, MARROW_REDEEMED]`, `flags_any:[shards]`). Keep the
   `offered_options` assert as the regression guard.
7. **Make the `FlagStore` access contract honest.** Resolve the `f.FLAG` vs `get_flag("FLAG")`
   mismatch (dict-backed resolver or generated properties) so `EndingResolver` actually compiles
   against `FlagStore`. While here, change status `atb_modifier` to integer permille so turn order
   stays integer-deterministic per ADR-0009 §1.
8. **Lock down flag ownership and backup safety.**
   (a) State that exactly one place (branch option **or** beat, not both) owns each flag/UNITY source,
   and add a domain-rule test that no UNITY source can be applied twice — prevents `FACTIONS_UNITED`
   corruption. Register the UNITY sub-objective flags (`SAVED_*_REFUGEES`/`_VILLAGERS`) or change the
   gate. (b) In `AtomicFileIO`, validate the current main **before** promoting it to `.bak` (never
   overwrite a good backup with a torn main); and enforce the replay-mode no-save guard on the
   **lifecycle** write path too, not just `autosave()`.

### NICE-TO-HAVE (non-blocking)

- Add checkpoint(`+.bak`) as a final recovery tier before "start fresh" when both main saves fail.
- Keep a pre-migration `save_main.v{n}.bak` and re-validate the dict **after** migration.
- Define the `BattleEngine.step()` event vocabulary explicitly (typed event structs) for the HUD.
- Decide and document the ability economy for non-Breath/Pomp members (free vs. cooldown vs. generic
  resource); add a cooldown field if needed for balance.
- Specify retargeting when a queued action's target dies before resolution, and implement the
  `accuracy`/miss roll in `DamageFormula`.
- Save the `encounter` RNG cursor (add to `rng_state.cursors`) for reproducible encounter selection.
- Extend dialogue `condition` to support negation/compound expressions.
- Reconcile the minor doc drift: ARCHITECTURE §6 beat-list abbreviation, §7.1 stream list (add
  `encounter`), §7.2 GameState fields (`quests`, `final_choice`, `ending`, `applied_beats`), and the
  stored-vs-computed status of `FACTIONS_UNITED`.

---

*Reviewed independently against the locked story contracts and DoD. Sign-off withheld pending the
MUST-FIX list.*

---

## Architect resolution (2026-06-30) — all 8 MUST-FIX addressed (re-review requested)

All eight blocking items were fixed in place on `feat/phase2-architecture`. The resolver logic is
**unchanged** — only its flag-access syntax is now honest (typed `FlagView`). Summary with file pointers:

1. **Enemy AI added.** New pure, RNG-injected `EnemyBrain` (`battle/enemy_ai.gd`): ARCHITECTURE §3
   (dep graph), §4 (layout), §7.6b (interface), §8 (tests); ADR-0004 new "Enemy AI" section + wired into
   `BattleEngine` flow; per-enemy `ai` policy block in ADR-0007 *Enemy* + `enemies/example_enemy.json`.
   Draws from a separate injected `ai` RNG stream; on the no-nondeterminism guard list (ADR-0009).
2. **`encounter` schema added.** ADR-0007 new *Encounter* schema (enemies/formation/flee/ambush/rewards/
   victory-defeat/`seed_salt`); `data/encounters/` in ARCHITECTURE §4; `beat.encounter` +
   `BattleController.start(encounter_id)` (ARCHITECTURE §5, ADR-0004, ADR-0008); example
   `encounters/example_encounter.json` (A1-11 Crane) + `beats/example_beat_battle.json`.
3. **`level_curve` schema added.** ADR-0007 new *Level curve* schema (integer XP formula + growth +
   overrides); `party.growth` reference; `level_curves/example_level_curve.json`; `LevelSystem` tests
   (ADR-0009).
4. **Web durability re-specified honestly.** Dropped the "completes before return" claim for web. ADR-0005
   §a/§e now: native Android = synchronous before-return guarantee; web = flush on
   `visibilitychange→hidden`/`pagehide` + bounded periodic `syncfs`, **documented residual-loss window**,
   no OPFS assumption. PHASE2_OWNER_RULINGS #3 revised to match.
5. **Enum state has a home.** `FINAL_CHOICE`/`ENDING` are scalars in a `FlagStore` **enum store**, saved
   under `story.choices` (ARCHITECTURE §7.2/§7.3, ADR-0003, ADR-0005 §d). `BRAMBLE_SACRIFICE` documented
   as a **hard-coded derived, non-gating** value (the closed op vocab can't express enum membership) —
   ADR-0003 op table + flag model.
6. **Synthesized-replay validity fixed.** ADR-0006 `_canonical_state_for` sets **underlying** flags then
   re-runs the derive step via `FlagView` (never sets derived flags); `data/endings/*.requires` authored
   in underlying flags only (validator rejects derived); `endings/example_ending_d.json` shows D's
   underlying requires. Test asserts synthesized states pass the same validation + yield the intended
   ending via the unmodified resolver.
7. **FlagStore access honest + integer ATB.** New `FlagView` typed facade (ARCHITECTURE §7.3a); resolver
   rewritten to `v.PROP`/`v.warden_truth_whole()` against it (ADR-0003) — **logic identical to 04**.
   Status `atb_modifier` → integer `atb_modifier_permille`; all ATB/turn-order math integer permille
   (ADR-0004, ADR-0007, ADR-0009 §1; `statuses/example_status.json`).
8. **Flag ownership + backup + replay guard.** Single-owner rule (branch-option XOR beat) + per-
   `source_id` idempotent `INC_UNITY` + registered UNITY sub-objective flags (ADR-0003; `flags/`
   examples + `example_unity_sources.json`; ADR-0007 domain rules). `AtomicFileIO` write order spelled
   out with **validate-current-main-before-`.bak`** (ADR-0005 §b). Replay no-save guard enforced on
   **every** write path incl. lifecycle `_notification` (ADR-0005 §b/API, ADR-0006 sandbox section).

Nice-to-haves also folded in: checkpoint as last recovery tier, pre-migration backup + post-migration
re-validate, typed `BattleEvent` vocabulary, ability `cooldown_turns` economy, retarget/accuracy rules,
`encounter` RNG cursor saved, compound/negation dialogue conditions, and the §6/§7 doc-drift reconciled.

*Architect requests re-review for sign-off.*

---

## Re-review (2026-06-30, independent verification) — **APPROVE**

I re-read every changed file and the new data, and verified each of the 8 must-fixes against the
actual source (not the addendum's claims). All eight are genuinely resolved; the resolver logic is
unchanged and still line-for-line with `04 §5`; no new blocking issues were introduced.

### Per-item verification

1. **Enemy AI — RESOLVED.** New pure `EnemyBrain` (`battle/enemy_ai.gd`) is *wired into the turn
   flow*: ADR-0004 §"Enemy AI" states "When an **enemy** combatant becomes ready, `BattleEngine` calls
   `EnemyBrain.choose_action(...)` and queues the returned action" (mirrored in ARCHITECTURE §7.6b
   line 410). It draws from a **separate injected `ai` stream** (not `battle`), is on the
   no-nondeterminism guard (ADR-0009 line 74, `battle/ incl. enemy_ai.gd`), and has a test
   (`test_enemy_ai.gd`, ADR-0009 line 97). Data-authored policy (`basic|caster|boss_phased`,
   weights, conditions, target_rules) in `enemies/example_enemy.json`. Enemy turns are now produced.

2. **`encounter` schema — RESOLVED.** ADR-0007 §"Encounter" (line 331) defines enemies/formation/
   flee/ambush/victory/defeat/rewards/`seed_salt`; `data/encounters/` in layout; referential
   integrity added ("a beat's `encounter` is a real encounter," line 41). `encounters/example_
   encounter.json` + `beats/example_beat_battle.json` (A1-11) conform; `BattleController.start(
   encounter_id)` wired (ADR-0004 line 171, ARCHITECTURE §5).

3. **`level_curve` schema — RESOLVED.** ADR-0007 §"Level curve" (line 358): integer `xp_to_next`
   formula + `growth_per_level` + `growth_overrides`. `party.growth` integrity-checked (line 41).
   `level_curves/example_level_curve.json` conforms.

4. **Web durability — RESOLVED (now physically honest).** ADR-0005 §a explicitly **drops the
   "completes-before-return" claim for web** and states `FS.syncfs` "is asynchronous with a callback
   that cannot be awaited inside a dying `_notification` handler." §e replaces it with: flush on DOM
   `visibilitychange→hidden`/`pagehide`, a bounded periodic `syncfs` (~10–15s), an explicitly
   **documented residual-loss window** (≤ the interval), and **no OPFS assumption** (IDBFS confirmed
   for Godot 4.x web). Native Android retains the synchronous before-return guarantee. The
   physically-impossible claim is gone.

5. **Enum state — RESOLVED.** `FINAL_CHOICE`/`ENDING` are scalars in a dedicated **enum store** on
   `FlagStore` (ADR-0003 flag model; ARCHITECTURE §7.3), serialized under `story.choices` ("ENUM
   store — NOT booleans", ADR-0005 §d line 123), never in the boolean dict. `BRAMBLE_SACRIFICE` is
   documented as the single, deliberate **hard-coded derived non-gating** exception with the reason
   stated (the closed op vocab cannot express enum membership) and proven harmless by the resolver
   lint (ADR-0003 lines 75–79).

6. **Synthesized replay — RESOLVED (cannot produce an invalid Ending-D state).** ADR-0006
   `_canonical_state_for` sets **only underlying flags** from `requires`, then the builder **re-runs
   the derive step via `FlagView`** to compute `WARDEN_TRUTH_WHOLE`/`FACTIONS_UNITED` — it "NEVER
   sets a derived flag." `endings/example_ending_d.json` `requires` is authored in underlying flags
   (`flags_all:[ROOKWISE_RECRUITED, MARROW_REDEEMED]`, `flags_any:[BRAMBLE_SHARD_DEPARTURE,
   BRAMBLE_SHARD_PROMISE]`), and the ADR-0007 validator **rejects a derived flag name in `requires`**
   (line 49), so the contradiction "WARDEN_TRUTH_WHOLE=true but no shards" is structurally
   impossible. **Real save protected on the lifecycle path:** `enter_replay_mode()` hard-blocks all
   `save_main` writes, and the guard is enforced in `autosave()`, `write_checkpoint()` **and**
   `_notification()` (ADR-0005 §b "Replay-mode guard (every write path)", ADR-0006 sandbox section).

7. **FlagStore access + integer ATB — RESOLVED.** New typed `FlagView` (ARCHITECTURE §7.3a) exposes
   the gating flags as **real bool properties** and the derived flags as computed methods, so
   `EndingResolver` compiles against it. I checked the rewritten resolver (ADR-0003 lines 177–196)
   against `04 §5`: `factions_united`, `can_wake`, `offered_options`, and the SHARE→A / SLEEP→B /
   TAKE→C / WAKE→D mapping are **identical in logic** — only the access syntax changed (`v.PROP`).
   ATB is integer: `speed_rate = base_rate(SPD) * haste_permille / 1000` (ADR-0004 line 36) and
   status `atb_modifier_permille` is an integer (ADR-0007 line 236; `statuses/example_status.json`
   `700`). No float touches turn order.

8. **No double-count UNITY + backup safety — RESOLVED.** `INC_UNITY` now **requires a unique
   `source_id`** and is **idempotent per source** via a `unity_sources_applied` set (ADR-0003 op
   table + §"Flag & UNITY ownership"); single-owner rule (branch option XOR beat) with a validator
   that forbids the same `source_id` on **co-reachable** beats. `branches/example_branch.json`
   correctly **moved `INC_UNITY` out of the option to the destination beat**, and the previously
   unregistered sub-objective flags (`SAVED_*_REFUGEES`/`_VILLAGERS`, etc.) are now in
   `flags/example_flags.json` (`kind: unity_source`) with `flags/example_unity_sources.json` listing
   `u1…u8`. `AtomicFileIO.write` (ADR-0005 §b) **validates the current main before promoting it to
   `.bak`** (step 4: "Only if it validates, copy it to `path.bak`") — a torn main can no longer
   destroy a good backup.

### Nice-to-haves (all folded in)

Verified present: checkpoint as last recovery tier (ADR-0005 §c), pre-migration `save_main.v{n}.bak`
+ post-migration re-validate (§d), typed `BattleEvent` vocabulary, ability `cooldown_turns` economy
(ADR-0004/0007), retarget/fizzle + `accuracy` miss roll (ADR-0004 §"Damage formula"), all six RNG
cursors incl. `ai`/`encounter` saved (ADR-0005 §d), compound/negation dialogue conditions, and the
§6/§7 doc-drift reconciled (stream list, GameState fields, computed-not-stored derived flags).

### Final verdict: **APPROVE**

All 8 blocking must-fixes are genuinely resolved at the source, the nice-to-haves are incorporated,
and the high-stakes resolver remains faithful to `04 §5`. I found **no remaining blocking issues and
no minor fixes that need to gate the merge** — the design is internally consistent and buildable
against. **PR #2 is approved to merge.**

*Re-reviewed independently against the locked story contracts and DoD. Sign-off granted.*
