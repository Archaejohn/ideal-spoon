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
don't stall I/O on low-end devices; lifecycle triggers **bypass debounce** and write immediately and
synchronously (the app may be about to die). On the lifecycle path the write must complete before the
handler returns (`OS` may suspend right after).

### (b) Atomic write strategy

`AtomicFileIO.write(path, bytes)`:

1. Write payload to `path.tmp`.
2. `flush` + close.
3. If a valid `path` already exists, copy it to `path.bak` (rotating backup) **before** replacing.
4. `DirAccess.rename(path.tmp, path)` — atomic replace on the platform FS.

`AtomicFileIO.read_validated(path)`:

1. Read `path`; verify header (magic + version) and a stored **checksum** (e.g. a hash of the payload).
2. On success → return dict.
3. On missing/corrupt/checksum-fail → try `path.bak` the same way.
4. If both fail → return `Err` (caller shows "couldn't load; starting fresh" only as a last resort).

Files (under `user://`): `save_main.sav`, `save_main.sav.bak`, `checkpoint.sav`,
`checkpoint.sav.bak`, and `settings.cfg` (settings persisted separately so a save problem never loses
audio/accessibility prefs, and vice-versa).

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

### (d) Save schema, versioning & migration

The save payload is a dict produced by `SaveSerializer.to_dict(GameState)`:

```jsonc
{
  "save_version": 1,
  "magic": "AETHER",
  "playtime_secs": 4123.5,
  "rng_state": { "master_seed": 123456789, "cursors": { "battle": 88, "loot": 12, "dance": 4, "story": 0 } },
  "story": {
    "current_beat_id": "A3-06",
    "flags": { "RESONANT_REVEALED": true, "KESTREL_RECRUITED": true, "...": "..." },
    "unity": 4,
    "endings_locked": false,
    "applied_beats": ["A1-01", "A1-02", "..."]      // idempotency ledger for effect ops
  },
  "party": [ { "id": "wren", "level": 14, "xp": 2310, "hp": 180, "breath": 4,
               "equipment": { "weapon": "masters_tuning_fork" }, "learned": ["listen","steady"] } ],
  "inventory": { "items": { "lamp_herb": 5, "wellstone_shard": 2 }, "key_items": ["keepers_lamp"] },
  "quests": { "SQ-PIGGY": "DONE", "CQ-MIRA": "ACTIVE" },
  "location": { "skyland": "thornholt", "entry": "junk_market" },
  "endings_unlocked": [],
  "divergence_snapshots": {},                          // ADR-0006
  "checksum": "…"                                      // computed over the above, appended last
}
```

- `save_version` is an integer bumped whenever the schema changes incompatibly.
- `SaveMigrator.migrate(dict)` applies ordered, pure `v(n)→v(n+1)` steps until `dict.save_version`
  equals the current `SAVE_VERSION`. Each migration is a small pure function with its own GUT test
  using a frozen old-version fixture. Loading a save newer than the build is refused safely.

### (e) Platform persistence

- **Android:** `user://` maps to the app's private storage; atomic `rename` is supported. Writes on the
  lifecycle hooks ensure progress survives backgrounding/kill/lock.
- **Chromebook / web export:** Godot's web export backs `user://` with a persistent browser FS
  (IDBFS over IndexedDB; OPFS on supporting builds). Because the in-memory FS is flushed to IndexedDB
  asynchronously, after every web write `SaveManager` calls the engine's FS-sync hook
  (`OS.has_feature("web")` → trigger `idbfs`/OPFS flush) so data reaches durable storage before the tab
  is hidden/closed. The lifecycle hooks (`FOCUS_OUT`, `WM_CLOSE_REQUEST`) drive this sync on web too.
- A small **integration test** (and the manual smoke test in #13) verifies a write-then-reload survives
  on each target.

### SaveManager public API
```gdscript
func autosave(reason: String) -> void          # debounced unless reason is a lifecycle reason
func write_checkpoint(label: String) -> void    # "pre_battle"
func restore_checkpoint(label: String) -> bool
func has_checkpoint(label: String) -> bool
func load_latest() -> bool                       # validate + recover-from-backup + migrate
func has_save() -> bool
func delete_all() -> void                        # used by "New Game over existing" confirm
func _notification(what: int) -> void            # lifecycle hooks
signal saved(reason)
signal loaded()
signal save_recovered_from_backup()              # surfaced for QA logs (no network)
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
- Web durability depends on the FS-sync call after writes; the web build's smoke test must confirm it.
- Debounce means the *very last* few seconds of pure overworld walking could be lost on a hard kill,
  but never a beat/battle/menu transition or a lifecycle event — acceptable and within #13.
- Checkpoints occupy a second pair of files; storage cost is trivial.
