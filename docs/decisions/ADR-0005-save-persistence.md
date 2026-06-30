# ADR-0005: Save & persistence (automatic, crash-safe)

- **Status:** Accepted
- **Date:** 2026-06-30
- **Deciders:** Architect, Owner

## Context

`DEFINITION_OF_DONE.md` #1 and **#13 (Owner requirement)** demand saving that is **fully automatic**
(no manual slots, no manual action), **crash-safe** (survives the phone being shut off, locked, or the
app killed/backgrounded, including by a parent), with **atomic writes** (no corrupted saves) and
**battle checkpoints** so losing a battle returns the player to just before it — never the title, never
a restart. It must work on Android (`user://`) and on Chromebook/web export (where `user://` is backed
by the browser's persistent FS — OPFS/IndexedDB). Verified by save/load + checkpoint round-trip unit
tests and a manual kill/relaunch + lose-a-battle smoke test.

## Options considered

1. **Manual save slots (classic JRPG).** Rejected outright by the Owner requirement.
2. **Single autosave file, overwritten in place.** Simple but **not crash-safe**: a kill mid-write
   corrupts the only save.
3. **Automatic, atomic write (temp + rename) with a rotating backup, validation on load, backup
   recovery, plus a separate pre-battle checkpoint.** Chosen — meets every clause of #13.

## Decision

Adopt **Option 3**. `SaveManager` (autoload) orchestrates; pure helpers do the work:
`save/save_serializer.gd` (GameState↔dict), `save/save_migrator.gd` (version migrations), and
`save/atomic_file_io.gd` (the temp-write/rename/backup/validate primitive).

### (a) Autosave triggers

`SaveManager.autosave(reason)` is called on **all** of:

- **Beat transitions** — `StoryDirector.beat_entered` (every ledger advance).
- **Overworld map changes** — entering/leaving a skyland, town, or dungeon (`SceneRouter`).
- **Menu close** — when the pause/inventory/party menu is dismissed.
- **Godot lifecycle signals** (`SaveManager._notification`):
  - `NOTIFICATION_APPLICATION_PAUSED` (Android backgrounded),
  - `NOTIFICATION_WM_GO_BACK_REQUEST` (Android back button),
  - `NOTIFICATION_WM_CLOSE_REQUEST` (window close),
  - `NOTIFICATION_APPLICATION_FOCUS_OUT` (focus lost / lock screen).
- **Periodic timer** — a heartbeat every ~30–60s as a backstop.

Autosaves are **debounced** (a minimum interval, default ~3s, between disk writes) so rapid triggers
don't stall I/O on low-end devices; lifecycle triggers **bypass debounce**. A lifecycle write first
**cancels any pending debounced autosave** (coalescing — single-threaded GDScript means no true race,
but the pending timer is explicitly cleared so the lifecycle write is the one that lands), then writes.

**Durability guarantee differs by platform (stated honestly):**
- **Native (Android):** Godot 4's `FileAccess` exposes **no `fsync`**, so a lifecycle write does
  temp-write + `flush` + `close` + atomic `rename`, all **synchronously before the `_notification`
  handler returns**. `close()` hands the bytes to the OS **page cache**; the atomic rename is durable
  against an **app kill / background / lock** (the page cache survives the process — the common DoD-#13
  case). On a true **power-off** immediately after the write, durability depends on the OS flushing the
  page cache to storage; if it has not, the renamed `save_main.sav` may reference unflushed blocks. The
  hard DoD-#13 requirement — **"no corrupted saves"** — still holds **via recovery**, never as a lost or
  corrupt game: the checksum + validate-before-backup + `.bak`/checkpoint recovery tier (§b/§c) means the
  worst case is recovery to a slightly older *valid* save. A platform `fsync` via JNI is a possible
  future hardening; it is not required to meet #13 given the recovery tier.
- **Web (Chromebook):** the file write is synchronous to the in-memory FS, but the flush to durable
  storage (IndexedDB via `syncfs`, or OPFS) is **asynchronous and cannot be awaited inside a dying
  handler** — see §(e). Web durability is therefore **best-effort with a small, bounded residual-loss
  window**, achieved via earlier/more-reliable lifecycle events and a periodic flush, not a
  "completes-before-return" promise. This is called out in PHASE2_OWNER_RULINGS #3.

### (b) Atomic write strategy

`AtomicFileIO.write(path, bytes)` — **exact, ordered** (a good backup is never overwritten by a torn
main):

1. Write payload + header + checksum to `path.tmp`.
2. `flush` + `close` `path.tmp`. (Godot 4 `FileAccess` has no `fsync`; `close` flushes to the OS page
   cache. Durability against a power-off then relies on the OS flush + the recovery tier below, not on a
   forced sync — see §(a)/§(e).)
3. **Validate `path.tmp`** (re-read header + checksum). If invalid → abort, keep everything as-is, return `Err`.
4. **Validate the *current* `path`** (header + checksum). **Only if it validates**, copy it to `path.bak`.
   (A torn/corrupt main is *not* promoted — so the last good `.bak` survives.)
5. `DirAccess.rename(path.tmp, path)` — atomic replace on the platform FS.

`AtomicFileIO.read_validated(path)`:

1. Read `path`; verify header (magic + version) and the stored **checksum** (hash of the payload).
2. On success → return dict.
3. On missing/corrupt/checksum-fail → try `path.bak` the same way.
4. If both fail → return `Err` (the *caller* then tries the checkpoint pair before "start fresh" — see
   §c recovery tier).

Files (under `user://`): `save_main.sav`, `save_main.sav.bak`, `checkpoint.sav`,
`checkpoint.sav.bak`, and `settings.cfg` (settings persisted separately so a save problem never loses
audio/accessibility prefs, and vice-versa).

**Replay-mode guard (every write path):** `AtomicFileIO`/`SaveManager` refuse to write `save_main.sav`
(or its `.bak`) while `SaveManager` is in replay mode. This guard is checked in `autosave()`,
`write_checkpoint()`, **and** `_notification()` — so a focus-out/close during a sandboxed ending replay
can never persist the throwaway replay state over the real save (see ADR-0006).

### (c) Battle checkpoints

- On **battle start**, `BattleController` calls `SaveManager.write_checkpoint("pre_battle")`, which
  serializes a `GameState.snapshot()` (deep copy incl. RNG cursors) to `checkpoint.sav` atomically.
- On **battle LOSE**, `BattleController` calls `SaveManager.restore_checkpoint("pre_battle")`, which
  loads the checkpoint back into `GameState` and routes (via `SceneRouter`) to the pre-battle overworld
  context — the player retries from just before the fight.
- The checkpoint is separate from the main autosave so a checkpoint write never clobbers normal
  progress, and a normal autosave never erases a still-relevant checkpoint. Checkpoints are also
  "risky-point" general: bosses, the gate-relay set-piece, the descent.
- Because RNG cursors are captured, a restored battle is **reproducible** — the same encounter seed
  plays out identically unless the player acts differently (ADR-0009).
- **Checkpoint as last-ditch recovery tier:** if `load_latest()` finds both `save_main.sav` and its
  `.bak` corrupt, `SaveManager` next tries `checkpoint.sav`(+`.bak`) — a valid, usually very recent
  state — before ever falling back to "start fresh." Players are sent to a new game only if *all four*
  files fail validation.

### (d) Save schema, versioning & migration

The save payload is a dict produced by `SaveSerializer.to_dict(GameState)`:

```jsonc
{
  "save_version": 1,
  "magic": "AETHER",
  "playtime_secs": 4123.5,
  // all six cursors saved so battle/ai/loot/dance/encounter selection + story are reproducible:
  "rng_state": { "master_seed": 123456789,
                 "cursors": { "battle": 88, "ai": 41, "loot": 12, "dance": 4, "encounter": 7, "story": 0 } },
  "story": {
    "current_beat_id": "A3-06",
    "flags": { "RESONANT_REVEALED": true, "KESTREL_RECRUITED": true, "...": "..." },  // booleans only
    "unity": 4,
    "unity_sources_applied": ["u1_br1_refugees", "u3_kestrel"],  // per-source idempotency (ADR-0003)
    "choices": { "final_choice": "NONE", "ending": "NONE" },     // ENUM store — NOT booleans
    "endings_locked": false,
    "applied_beats": ["A1-01", "A1-02", "..."]      // per-beat idempotency ledger for effect ops
  },
  "party": [ { "id": "wren", "level": 14, "xp": 2310, "hp": 180, "breath": 4,
               "cooldowns": { "kindling_chorus": 0 },
               "equipment": { "weapon": "masters_tuning_fork" }, "learned": ["listen","steady"] } ],
  "inventory": { "items": { "lamp_herb": 5, "wellstone_shard": 2 }, "key_items": ["keepers_lamp"] },
  "quests": { "SQ-PIGGY": "DONE", "CQ-MIRA": "ACTIVE" },
  "location": { "skyland": "thornholt", "entry": "junk_market" },
  "endings_unlocked": [],
  "divergence_snapshots": {},                          // ADR-0006
  "checksum": "…"                                      // computed over the above, appended last
}
```

> Derived flags (`WARDEN_TRUTH_WHOLE`, `FACTIONS_UNITED`) are **not** stored — they are computed-on-read
> from the underlying flags + frozen UNITY (ADR-0003), so there is one source of truth and replays can't
> desync. `final_choice`/`ending` live under `story.choices` as enum strings, never in the boolean dict.

- `save_version` is an integer bumped whenever the schema changes incompatibly.
- `SaveMigrator.migrate(dict)` applies ordered, pure `v(n)→v(n+1)` steps until `dict.save_version`
  equals the current `SAVE_VERSION`. Each migration is a small pure function with its own GUT test using
  a frozen old-version fixture. **Before** migrating, `SaveManager` writes a one-shot
  `save_main.v{n}.bak` (the pre-migration original), and **after** migrating it **re-validates** the
  resulting dict against the current schema before the first write of migrated data — so a buggy
  migration cannot silently destroy the original save. Loading a save newer than the build is refused
  safely.

### (e) Platform persistence

- **Android (native):** `user://` maps to the app's private storage; atomic `rename` is supported.
  Godot 4 `FileAccess` exposes **no `fsync`**, so lifecycle-hook writes are synchronous (temp-write +
  flush + close + atomic rename complete before the handler returns) and the rename is durable against
  **backgrounding / kill / lock** via the OS page cache. A true **power-off** mid-flush falls back to the
  checksum + `.bak`/checkpoint recovery tier (§b/§c), so the result is at worst recovery to an older
  *valid* save — **never a corrupt save**. This satisfies DoD-#13 ("no corrupted saves") via recovery
  rather than a forced-sync before-return promise.
- **Chromebook / web export — honest strategy (the async-flush reality):** Godot 4.x's web export backs
  `user://` with **Emscripten IDBFS over IndexedDB**. (We **do not assume OPFS** — the build verifies
  what the pinned Godot 4.x web export actually provides before relying on anything beyond IDBFS.) The
  file write lands synchronously in the in-memory FS, but the durable flush is
  `FS.syncfs(false, cb)` — **asynchronous with a callback that cannot be awaited inside a dying
  `_notification` handler**. We therefore do **not** claim "completes before return" on web. Instead:
  1. **Flush on the reliable web lifecycle events.** Hook the DOM `visibilitychange→hidden` and
     `pagehide` events (these fire earlier and far more reliably than tab `close`, including when a
     Chromebook is locked or the tab is backgrounded) and request a `syncfs` flush there, in addition to
     Godot's `FOCUS_OUT`/`WM_CLOSE_REQUEST`.
  2. **Bounded periodic flush.** Run a `syncfs` on a short timer (e.g. every ~10–15s) and immediately
     after each gameplay write, so the durable lag — the window of state that exists in memory but not
     yet in IndexedDB — is **bounded** to at most that interval.
  3. **Document the residual-loss window.** Because the final flush before an abrupt tab-kill may not
     complete, web durability is **best-effort with a bounded residual window** (≤ the periodic
     interval, typically a few seconds), not a hard before-return guarantee. In practice the
     visibilitychange flush captures nearly all real lock/close/background cases; only an instant
     hard-kill mid-flush can lose the last few seconds — and never a *prior* committed beat/battle
     transition. This residual window is recorded in PHASE2_OWNER_RULINGS #3.
- A small **integration test** plus the manual smoke test in #13 verify a write-then-reload survives
  tab-hide/close/reload on the web build, and a synchronous kill/relaunch on Android.

### SaveManager public API
```gdscript
func autosave(reason: String) -> void          # debounced unless reason is a lifecycle reason; honors replay guard
func write_checkpoint(label: String) -> void    # "pre_battle"; honors replay guard
func restore_checkpoint(label: String) -> bool
func has_checkpoint(label: String) -> bool
func load_latest() -> bool                       # validate; recover main→.bak→checkpoint→fresh; migrate
func has_save() -> bool
func delete_all() -> void                        # used by "New Game over existing" confirm
func enter_replay_mode() -> void                 # stash real save dict; hard-block all save_main writes
func exit_replay_mode() -> void                  # restore real save dict
func _notification(what: int) -> void            # lifecycle hooks; coalesces pending debounce; honors replay guard
signal saved(reason)
signal loaded()
signal save_recovered(source)                    # source ∈ {backup, checkpoint} — QA logs, no network
```

### Data captured

Everything in §(d): RNG state, full story flags + UNITY + applied-beats ledger + current beat, the
whole party (levels/xp/hp/resources/equipment/learned abilities), inventory + key items, quest states,
location, unlocked endings, and divergence snapshots. Settings are **not** in the save (separate
`settings.cfg`).

## Rationale

Temp-write + rename is the standard atomic-replace pattern and is the only way to guarantee "no
corrupted saves" across an abrupt kill; the rotating backup + checksum-validated load turns a rare
torn write into a recoverable event rather than a lost game. A dedicated checkpoint file makes
"lose-a-battle → just before it" trivially correct and decoupled from normal autosave. Capturing RNG
cursors makes both checkpoint restores and ending replays reproducible. Driving writes off Godot's
own lifecycle notifications is the engine-blessed way to catch background/lock/close on Android and web.

## Consequences

- Every savable piece of state must live in `GameState` and be handled by `SaveSerializer`; adding a
  new persistent field requires a serializer update and, if incompatible, a `save_version` bump +
  migration + test. This is enforced by a round-trip test that serializes a fully-populated state and
  asserts equality after `from_dict(to_dict(...))`.
- Web durability is **best-effort with a bounded residual window** (≤ the periodic `syncfs` interval),
  not a before-return guarantee — an honest consequence of IDBFS's async flush. Native Android keeps the
  full before-return guarantee. The web smoke test must confirm survival across visibilitychange/hide.
- Debounce means the *very last* few seconds of pure overworld walking could be lost on a hard kill,
  but never a beat/battle/menu transition or a lifecycle event — acceptable and within #13.
- The replay-mode guard is enforced on **all** write paths (autosave, checkpoint, lifecycle), so an
  ending replay can never overwrite the real save even if the player backgrounds the app mid-replay.
- Checkpoints occupy a second pair of files; storage cost is trivial.
