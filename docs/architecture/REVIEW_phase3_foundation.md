# Independent Code Review — Phase 3 Foundation (`feat/phase3-foundation`)

- **Reviewer:** Independent (did not author the code)
- **Date:** 2026-06-30
- **Scope:** `game/src/**` + `game/tests/**` against ARCHITECTURE §7/§8, ADR-0003, ADR-0005 §d, ADR-0009, story `04_BRANCHES_ENDINGS.md` §4–§5.
- **Suite:** `bash tools/run_tests.sh` → **28/28 passing, 1565 asserts, 0 failures** (Godot 4.3, headless). Confirmed green by the reviewer.

## Verdict: APPROVE WITH MINOR FIXES

No hard blockers. The EndingResolver is **exactly** correct against story 04 §4–§5, the golden test is genuinely exhaustive (not superficial), RNG is deterministic and round-trips, and GameState matches ADR-0005 §d. The findings below are localized and none are exploitable by any code path that exists today, so they do **not** block merging PR #3 — but Findings 1 and 2 should be fast-followed.

---

## Area-by-area

### 1. EndingResolver + FlagView derived logic — CORRECT (verified line-by-line)
- `offered_options` (ending_resolver.gd:24-30): Sleep/Take always; Share iff `factions_united`; Wake iff `can_wake`. Matches 04 §4 table.
- `can_wake` (ending_resolver.gd:21-22): `warden_truth_whole() AND ROOKWISE_RECRUITED AND MARROW_REDEEMED`. Matches 04 §4 / §5.
- `resolve` (ending_resolver.gd:32-43): SHARE+united→A, SLEEP→B, TAKE→C, WAKE+can_wake→D, else assert. Matches 04 §5 reference pseudocode verbatim.
- `warden_truth_whole` (flag_view.gd:24-26): `(DEP AND PROM) OR (ROOKWISE AND (DEP OR PROM))` — verbatim 04 §3.3.
- `factions_united` (flag_view.gd:30-31): `unity>=5 AND KESTREL AND (ORDER OR TRUTH)` — verbatim 04 §3.3.
- Non-gating flags (Piggy/emotional/BRAMBLE_SACRIFICE) never reach the resolver — `FlagView` only carries the 7 gating booleans + unity. Confirmed.

**No deviation from story 04.**

### 2. Golden test — STRONG
`test_ending_resolver.gd::test_golden_exhaustive` crosses `unity ∈ {4,5}` (the only boundary that matters) with all `2^7 = 256` gating-flag combinations and asserts both `offered_options` (sorted set equality) and the resolved ending. Crucially, expected values come from **independent reference reimplementations** (`_ref_wtw`, `_ref_factions`, `_ref_canwake`) rather than from the same `FlagView` methods — so a bug in `FlagView.warden_truth_whole`/`factions_united` would be caught, not masked. It correctly only resolves *offered* options (never exercises the unreachable assert path). The could-the-resolver-be-wrong-and-the-test-miss-it answer is effectively **no** for the boolean gating space.
- Minor gap (acceptable): `FinalChoice.NONE` and the unoffered-resolution fallback are intentionally not asserted.

### 3. RNG determinism — SOUND
- Single master seed; per-stream `RngStream` seeded by `hash("%d:%s" % [master,name])` (Godot's String hash is content-deterministic, not per-process randomized) → reproducible.
- Every high-level draw funnels through `_next_u32()` (one `randi`, cursor +1), so `set_cursor(n)` reseed-and-replay reproduces subsequent draws bit-for-bit (test_cursor_save_restore + export/import round-trip prove it).
- `export_state` iterates the ordered `SAVED_STREAMS` const; `import_state` per-stream order is irrelevant (independent). No `Time`, `OS`, global `randi/randf`, or `randomize()`. No Dictionary-iteration-order dependence in outcomes.
- Per-stream cursor model is correct and isolation is tested (ai draws don't perturb battle).
- Nit (Finding 7): `randi_range`/`chance_permille`/`weighted_pick` use modulo → slight modulo bias. Deterministic (contract holds) but not perfectly uniform.

### 4. GameState — DATA-ONLY, faithful round-trip, matches §d
- No rules leak: `record_ending` only *stores* a pre-resolved ending; resolution lives in `FlagOps.RECORD_ENDING`→`EndingResolver`.
- `to_dict`/`from_dict` `story` shape = `{current_beat_id, flags, unity, unity_sources_applied, choices, endings_locked, applied_beats}` — matches ADR-0005 §d exactly; `choices` serialized as enum strings.
- Deep copies throughout (`duplicate(true)`); `snapshot()` is a faithful deep copy incl. RNG cursors; no shallow-aliasing bug found.
- `to_dict()` refreshes `rng_state` (a documented side-effect) — acceptable.
- Finding 6 (minor): `endings_unlocked` stored as enum ints while `choices` are enum strings; after the (future) JSON SaveSerializer round-trip the ints reload as floats. `Array.has` still matches (`1.0==1`), so benign today, but inconsistent with the "enum-as-string for JSON safety" rationale.

### 5. FlagStore — mostly correct; one contract gap (Finding 1)
- UNITY idempotency per `source_id`, monotonic, capped 0..8, frozen after lock: **UNITY** behavior is correct and tested.
- Enum choice store (`final_choice`/`ending`) correct; `bramble_sacrifice` derived correctly and proven non-gating.
- **Gap:** `lock_endings()` is documented (flag_store.gd:6-8, 56-57; flag_ops.gd:8) to "freeze UNITY **and the underlying flag set**," but `set_flag` (flag_store.gd:28-33) has **no `_locked` guard** — only UNITY is actually frozen. See Finding 1.

### 6. ContentDB / validators — reasonable & safe
- Schema validation (layer 1) always runs and is fatal; proven to catch unknown ops, bad enums, missing required fields, malformed shapes.
- Reference/domain validation (layer 2) is opt-in `strict` and well-tested with good/bad fixtures (unregistered flag, derived-in-`requires`, 8-source domain rule).
- The `strict=false` default for the shipped Phase-3 sampler is a documented, defensible decision (the sampler has intentional dangling refs). Caveat in Finding 5: this means shipped `game/data` is never reference-validated, which diverges from ADR-0009's "all shipped game/data passes schema/reference/domain validation." Track flipping strict on once content is closed.
- `_type_ok` correctly accepts integral floats for `int`/`float` (JSON parses numbers as float) — good.

### 7. Code quality / module boundaries — GOOD
- Core logic (`ids`, `result`, `flag_store`, `flag_view`, `flag_ops`, `ending_resolver`, `content_validator`, `json_loader`) is `RefCounted`, headless, no scene-tree deps. Autoloads (`game_state`, `rng_service`, `event_bus`, `log`, `settings`, `content_db`) extend `Node`. GameState reaches RngService via `get_node_or_null` (documented autoload coupling, guarded for headless). No god-objects. Typing is consistent; error handling via `Result`. Naming clear and doc-commented.

---

## Findings (ranked by severity)

### HIGH — 1. `lock_endings()` does not freeze the underlying flag set
- **Where:** `game/src/story/flag_store.gd:28-33` (`set_flag`), against the contract in `flag_store.gd:6-8,56-57` and `flag_ops.gd:8`.
- **Defect:** The module repeatedly promises that A3-13 lock freezes UNITY **and the underlying flag set**, and the ending is "a pure function of the *locked* flag set." But `set_flag` ignores `_locked`. Only UNITY is frozen.
- **Failure scenario:** Any Act IV beat (or a re-applied/duplicated beat effect) that `SET`s a gating flag after `LOCK_ENDINGS` — e.g. `SET ROOKWISE_RECRUITED` or `SET TRUTH_SHARED` — silently changes the computed-on-read `WARDEN_TRUTH_WHOLE`/`FACTIONS_UNITED`, altering which endings are offered and the resolved letter *after* the flags were supposed to be sealed. Not exploitable today (no post-lock SET exists), and **not covered** by any test (`test_lock_freezes_unity` only checks UNITY).
- **Fix:** Guard `set_flag` with `if _locked: return` (or `push_error` + return) so SETs are no-ops once locked; add a test asserting `set_flag` is inert after `lock_endings()`.

### MEDIUM — 2. `FlagOps` has zero unit tests
- **Where:** `game/src/story/flag_ops.gd` (no `game/tests/unit/test_flag_ops.gd`).
- **Defect:** ADR-0009's test layout lists `test_flag_ops.gd` ("effect ops; per-beat + per-source-id idempotency"), but it is absent. `apply_effect`/`apply_effects`, the `if_flag` guard, the unknown-op error, `SET_FINAL_CHOICE` invalid-choice handling, and the `RECORD_ENDING`→`EndingResolver` wiring are all unverified. Idempotency is tested only at the FlagStore level, not through the op interpreter that beats actually use.
- **Failure scenario:** A regression in op dispatch (e.g. `if_flag` inverted, `RECORD_ENDING` reading the wrong choice) would ship green.
- **Fix:** Add `test_flag_ops.gd` covering each op, the guard, unknown-op error, and a SET→INC_UNITY→SET_FINAL_CHOICE→RECORD_ENDING sequence resolving the expected ending.

### MEDIUM — 3. `INC_UNITY` `n` is unconstrained (can break monotonic/+1 invariant)
- **Where:** `game/src/story/flag_ops.gd:35` + `flag_store.gd:45-51`; validator `content_validator.gd:159-161`.
- **Defect:** `n` comes from authored data (`int(effect.get("n",1))`) and is applied via `clampi(_unity + n, 0, 8)`. The design says "+1 each." Authored `n<=0` would consume the `source_id` while adding nothing — or decrement UNITY — violating the "only ever increments" invariant the module claims to enforce. The validator never checks `n`.
- **Failure scenario:** A data typo `"n": -1` (or `0`) silently lowers/no-ops UNITY and burns the source idempotency slot.
- **Fix:** Either ignore `n` and always add exactly 1 per source, or clamp `n = maxi(1, n)` / validate `n >= 1` in the schema.

### LOW — 4. Resolving an unoffered/NONE final choice silently yields Ending B in release builds
- **Where:** `game/src/story/ending_resolver.gd:42-43`, reached via `flag_ops.gd:47-50` `RECORD_ENDING`.
- **Defect:** The safety `assert(false, ...)` is stripped from exported builds, so `resolve(v, NONE)` or `resolve(v, SHARE)` without the gate returns `EndingId.B` silently. UI gates choices, so unreachable in normal flow, but `RECORD_ENDING` doesn't verify a final choice was actually offered/set.
- **Fix (optional):** Have `RECORD_ENDING` early-return an error (or guard) when `final_choice` is NONE or not in `offered_options`.

### LOW — 5. Shipped `game/data` is never reference/domain-validated
- **Where:** `game/src/data/content_db.gd:41` (`load_all(strict=false)`).
- **Defect:** Deliberate, documented Phase-3 sampler decision, but it diverges from ADR-0009 ("all shipped game/data passes schema/reference/domain validation"). Dangling refs in shipped data ship silently.
- **Fix:** Flip `strict=true` for the boot load once the content set is closed; track as a phase exit-criterion.

### LOW — 6. `endings_unlocked` enum-int vs `choices` enum-string inconsistency
- **Where:** `game/src/core/game_state.gd:21,57-62,90`. Benign today (`Array.has` matches int/float), but inconsistent with the JSON-safety rationale; worth normalizing to strings when SaveSerializer lands.

### NIT — 7. Modulo bias in `randi_range`/`chance_permille`/`weighted_pick`
- **Where:** `game/src/core/rng_service.gd:43-67`. Deterministic (contract intact) but not perfectly uniform. Acceptable for a game; note for awareness.

---

## Test-quality note
The golden resolver test is the standout: exhaustive over the full boolean gating space at the unity boundary, with independent reference oracles, and it asserts both the offered set and the resolved letter — it would catch a `FlagView` derivation bug, not just a resolver bug. FlagStore, FlagView, RNG, and ContentDB tests are meaningful and assertion-rich. The one real coverage hole is **FlagOps** (Finding 2) — the op interpreter beats actually execute is untested. Overall test quality is high; closing the FlagOps gap would make it complete for this foundation.
