## save_manager.gd — automatic, crash-safe save orchestration (ADR-0005, DoD #13).
##
## Designed to run as an autoload Node (Round 3 wires it; NOT registered here to avoid
## conflicts), but fully unit-testable by direct instantiation with injected deps
## (game_state, clock, io, dir, debounce). Pure helpers do the work:
##   * SaveSerializer  — GameState dict <-> validated on-disk envelope
##   * AtomicFileIO    — temp-write / validate / validate-before-backup / atomic rename
##   * SaveMigrator    — ordered pure version migrations
##
## Durability honesty (PHASE2_OWNER_RULINGS #3, ADR-0005 §e):
##   * Native (Android): a lifecycle write is synchronous — temp-write + flush + atomic
##     rename complete before _notification() returns, so progress is durable on kill.
##   * Web (Chromebook): the file write lands synchronously in the in-memory IDBFS, but the
##     durable flush (FS.syncfs) is ASYNC and cannot be awaited in a dying handler. We do
##     NOT claim "completes before return" on web. Instead we request a syncfs after every
##     write and on the reliable visibilitychange/pagehide events, accepting a small,
##     bounded residual-loss window. A prior committed beat/battle transition is never lost.
class_name SaveManager
extends Node

signal saved(reason: String)
signal loaded()
signal save_recovered(source: String)   # source in {"backup","checkpoint"}

## Lifecycle reasons BYPASS debounce and write immediately & synchronously.
const LIFECYCLE_REASONS := ["app_paused", "go_back", "window_close", "focus_out"]
const DEFAULT_DEBOUNCE_MS := 3000
const DEFAULT_CHECKPOINT_LABEL := "pre_battle"

const Serializer := preload("res://src/save/save_serializer.gd")
const AtomicIO := preload("res://src/save/atomic_file_io.gd")
const Migrator := preload("res://src/save/save_migrator.gd")

# --- injectable dependencies (defaults resolved lazily) ---
var _game_state: Node = null
var _io: RefCounted = null
var _dir: String = "user://"
var _clock: Callable = Callable()                 # () -> int milliseconds; default Time
var _debounce_ms: int = DEFAULT_DEBOUNCE_MS
var _migrator_target: int = Migrator.CURRENT_VERSION
var _migrator_steps: Dictionary = Migrator.STEPS

# --- debounce / state ---
var _last_write_ms: int = -2147483648
var _pending_reason: String = ""
var _replay_mode: bool = false
var _replay_stash: Dictionary = {}

# --- configuration (used by tests and by Round 3 wiring) ---
func set_game_state(gs: Node) -> void: _game_state = gs
func set_io(io: RefCounted) -> void: _io = io
func set_dir(dir: String) -> void: _dir = dir
func set_clock(c: Callable) -> void: _clock = c
func set_debounce_ms(ms: int) -> void: _debounce_ms = ms
func set_migrator(target: int, steps: Dictionary) -> void:
	_migrator_target = target
	_migrator_steps = steps

func _ready() -> void:
	_ensure_defaults()
	# Web: request a durable flush on the reliable lifecycle events (ADR-0005 §e). The data
	# is already in IDBFS memory from the synchronous write; this only asks for the async
	# IndexedDB flush. Best-effort, bounded residual window — not awaited.
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"try{var __sm=function(){if(typeof FS!=='undefined'&&FS.syncfs){FS.syncfs(false,function(){});}};" +
			"document.addEventListener('visibilitychange',function(){if(document.visibilityState==='hidden'){__sm();}});" +
			"window.addEventListener('pagehide',__sm);}catch(e){}", true)

# --- public API (ADR-0005 §SaveManager) ---

## Debounced unless `reason` is a lifecycle reason; honors the replay guard on EVERY path.
func autosave(reason: String) -> void:
	_ensure_defaults()
	if _replay_mode:
		return   # replay guard: never persist throwaway replay state over the real save
	if LIFECYCLE_REASONS.has(reason):
		_pending_reason = ""          # coalesce: the lifecycle write is the one that lands
		_write_main(reason)
		return
	# Debounced (trailing-edge): the first write in an idle window lands; rapid follow-ups
	# collapse into a single pending write that flushes once the interval elapses.
	if _now_ms() - _last_write_ms >= _debounce_ms:
		_write_main(reason)
	else:
		_pending_reason = reason

## Flush a coalesced debounced autosave if the interval has elapsed. Driven by _process at
## runtime; tests call it directly after advancing the injected clock.
func flush_pending() -> void:
	if _replay_mode or _pending_reason == "":
		return
	if _now_ms() - _last_write_ms >= _debounce_ms:
		var r := _pending_reason
		_pending_reason = ""
		_write_main(r)

func _process(_delta: float) -> void:
	if _pending_reason != "":
		flush_pending()

## Pre-battle (and other risky-point) checkpoint = the battle resume unit (ADR-0005 §c,
## PHASE2_OWNER_RULINGS #2). Captures a deep GameState.snapshot() INCLUDING RNG cursors.
func write_checkpoint(label: String = DEFAULT_CHECKPOINT_LABEL) -> bool:
	_ensure_defaults()
	if _replay_mode:
		return false   # replay guard blocks all real-save writes, checkpoints included
	if _game_state == null:
		return false
	var payload: Dictionary = _game_state.snapshot()
	var bytes := Serializer.encode(payload)
	var res: Result = _io.write(_checkpoint_path(label), bytes)
	if res.is_ok():
		_request_web_flush()
	return res.is_ok()

## Restore the checkpoint into GameState (reproduces RNG draws — ADR-0009). True on success.
func restore_checkpoint(label: String = DEFAULT_CHECKPOINT_LABEL) -> bool:
	_ensure_defaults()
	if _game_state == null:
		return false
	var res: Result = _io.read_validated(_checkpoint_path(label))
	if res.is_err():
		return false
	var payload := _decode_and_migrate((res.value as Dictionary)["bytes"])
	if payload.is_empty():
		return false
	_game_state.restore_snapshot(payload)
	return true

func has_checkpoint(label: String = DEFAULT_CHECKPOINT_LABEL) -> bool:
	_ensure_defaults()
	return _io.exists(_checkpoint_path(label))

## Load tier: main -> main.bak (auto, inside read_validated) -> checkpoint(+bak) -> fresh.
## Validates, recovers, migrates (pre-migration file backup + post re-validate). True if a
## save was loaded into GameState; false means the caller should start a new game.
func load_latest() -> bool:
	_ensure_defaults()
	var bytes := PackedByteArray()
	var res: Result = _io.read_validated(_main_path())
	if res.is_ok():
		var info: Dictionary = res.value
		bytes = info["bytes"]
		if str(info.get("source", "main")) == "backup":
			_emit_recovered("backup")
	else:
		# Last-ditch recovery tier: try the checkpoint pair before "start fresh".
		var cp: Result = _io.read_validated(_checkpoint_path(DEFAULT_CHECKPOINT_LABEL))
		if cp.is_err():
			return false
		bytes = (cp.value as Dictionary)["bytes"]
		_emit_recovered("checkpoint")

	var decoded: Result = Serializer.decode(bytes)
	if decoded.is_err():
		return false
	var payload: Dictionary = decoded.value

	# Migration with a pre-migration backup of the ORIGINAL file + post re-validate.
	if Migrator.payload_version(payload) != _migrator_target:
		var v := Migrator.payload_version(payload)
		if v < _migrator_target:
			_io.copy_raw(_main_path(), "%s.premigrate.v%d.bak" % [_main_path(), v])
		var migrated: Result = Migrator.migrate(payload, _migrator_target, _migrator_steps)
		if migrated.is_err():
			return false   # newer-than-build or failed re-validation: refuse, keep original
		payload = migrated.value

	if _game_state != null:
		_game_state.from_dict(payload)
	loaded.emit()
	_mirror_to_event_bus("loaded")
	return true

func has_save() -> bool:
	_ensure_defaults()
	return _io.exists(_main_path())

func delete_all() -> void:
	_ensure_defaults()
	_io.delete(_main_path())
	_io.delete(_checkpoint_path(DEFAULT_CHECKPOINT_LABEL))

## Sandbox an ending replay: stash the real run state and HARD-BLOCK every real-save write
## (autosave, write_checkpoint, AND _notification) until exit_replay_mode (ADR-0005 §b/§a).
func enter_replay_mode() -> void:
	_ensure_defaults()
	if _replay_mode:
		return
	if _game_state != null:
		_replay_stash = _game_state.snapshot()
	_replay_mode = true

func exit_replay_mode() -> void:
	if not _replay_mode:
		return
	_replay_mode = false
	if _game_state != null and not _replay_stash.is_empty():
		_game_state.restore_snapshot(_replay_stash)
	_replay_stash = {}

func is_in_replay_mode() -> bool:
	return _replay_mode

## Godot lifecycle hooks (ADR-0005 §a). Immediate, synchronous main writes — EXCEPT while
## in replay mode, where they are blocked so a focus-out during a sandboxed replay can never
## persist over the real save.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			_lifecycle_save("app_paused")
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_lifecycle_save("go_back")
		NOTIFICATION_WM_CLOSE_REQUEST:
			_lifecycle_save("window_close")
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_lifecycle_save("focus_out")

func _lifecycle_save(reason: String) -> void:
	if _replay_mode:
		return   # replay guard on the lifecycle path too
	autosave(reason)   # lifecycle reasons bypass debounce -> immediate synchronous write

# --- internals ---

func _write_main(reason: String) -> bool:
	if _game_state == null:
		return false
	var payload: Dictionary = _game_state.to_dict()
	var bytes := Serializer.encode(payload)
	var res: Result = _io.write(_main_path(), bytes)
	if res.is_ok():
		_last_write_ms = _now_ms()
		_request_web_flush()
		saved.emit(reason)
		_mirror_to_event_bus("saved", reason)
		return true
	return false

func _decode_and_migrate(bytes: PackedByteArray) -> Dictionary:
	var decoded: Result = Serializer.decode(bytes)
	if decoded.is_err():
		return {}
	var payload: Dictionary = decoded.value
	if Migrator.payload_version(payload) != _migrator_target:
		var migrated: Result = Migrator.migrate(payload, _migrator_target, _migrator_steps)
		if migrated.is_err():
			return {}
		payload = migrated.value
	return payload

func _emit_recovered(source: String) -> void:
	save_recovered.emit(source)
	_mirror_to_event_bus("save_recovered", source)

func _now_ms() -> int:
	if _clock.is_valid():
		return int(_clock.call())
	return Time.get_ticks_msec()

func _main_path() -> String:
	return _dir.path_join("save_main.sav")

func _checkpoint_path(label: String) -> String:
	return _dir.path_join("checkpoint_%s.sav" % label)

func _ensure_defaults() -> void:
	if _io == null:
		_io = AtomicIO.new()
	if _dir == "":
		_dir = "user://"
	if _game_state == null:
		var tree := get_tree() if is_inside_tree() else null
		if tree != null and tree.root != null:
			_game_state = tree.root.get_node_or_null("GameState")

## Request the async web durable flush (no-op on native). Not awaited — see header.
func _request_web_flush() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(typeof FS!=='undefined'&&FS.syncfs){FS.syncfs(false,function(){});}", true)

## Mirror local signals onto the EventBus autoload when present (Round 3 wiring). Guarded so
## unit-instantiated managers without the autoload don't error.
func _mirror_to_event_bus(kind: String, arg: String = "") -> void:
	var tree := get_tree() if is_inside_tree() else null
	if tree == null or tree.root == null:
		return
	var bus := tree.root.get_node_or_null("EventBus")
	if bus == null:
		return
	match kind:
		"saved": bus.saved.emit(arg)
		"loaded": bus.loaded.emit()
		"save_recovered": bus.save_recovered.emit(arg)
