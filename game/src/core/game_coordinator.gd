## game_coordinator.gd — thin top-level run coordinator (ARCHITECTURE §3, ADR-0008).
##
## Autoload Node. It constructs and OWNS the headless StoryDirector (which itself is
## RefCounted and stays scene-tree-free), and exposes the high-level run verbs the Title menu
## drives: new_game / continue_game / has_save. It wires the save hooks that are not owned by
## the SceneRouter: a per-beat autosave (EventBus.beat_entered) and a periodic heartbeat
## backstop (ADR-0005 §a). Scene transitions themselves are NOT done here — the StoryDirector
## emits `scene_intent` and the SceneRouter performs the swap.
extends Node

const StoryDirectorScript := preload("res://src/story/story_director.gd")

## The integration-shell start beat (R3a slice bootstrap; real Act-1 opening lands in R3b).
const START_BEAT := "SLICE-START"
## Periodic autosave backstop interval (ADR-0005 §a "~30–60s heartbeat").
const HEARTBEAT_SECS := 45.0

var _director                              # StoryDirector (RefCounted, owned here)
var _heartbeat: Timer

func _ready() -> void:
	_build_director()
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.beat_entered.connect(_on_beat_entered)
		# Content loads asynchronously at Boot; rebuild the director's graph once it is ready.
		bus.content_loaded.connect(_build_director)
	# Heartbeat backstop autosave (debounced by SaveManager).
	_heartbeat = Timer.new()
	_heartbeat.name = "Heartbeat"
	_heartbeat.wait_time = HEARTBEAT_SECS
	_heartbeat.autostart = true
	_heartbeat.timeout.connect(_on_heartbeat)
	add_child(_heartbeat)

## (Re)build the StoryDirector over the current ContentDB catalogs + GameState + EventBus.
func _build_director() -> void:
	_director = StoryDirectorScript.new(_content(), _game_state(), _event_bus())

func director():
	return _director

# --- public run API (driven by the Title menu) ---

## Start a fresh run: reset GameState, install the starting party (incl. Wren), rebuild the
## director over loaded content, then enter the START beat (which emits a scene_intent the
## SceneRouter turns into the opening scene).
func new_game() -> void:
	var gs := _game_state()
	gs.new_run(int(Time.get_unix_time_from_system()))
	_set_starting_party(gs)
	_build_director()
	var r: Result = _director.goto_beat(START_BEAT)
	if r != null and r.is_err():
		_log("error", "new_game: %s" % r.error)
	else:
		_log("info", "New Game started at beat '%s'." % START_BEAT)

## Resume the last run: load the latest save into GameState, then re-enter the saved beat so
## the player lands exactly where they left off (ADR-0008 §"New Game / Continue"). Returns
## false if there is nothing to continue.
func continue_game() -> bool:
	var sm := _save_manager()
	if sm == null or not sm.has_save():
		return false
	if not sm.load_latest():
		_log("warn", "continue_game: load_latest failed.")
		return false
	_build_director()
	var beat: String = _game_state().current_beat_id
	if beat == "":
		beat = START_BEAT
	var r: Result = _director.goto_beat(beat)
	if r != null and r.is_err():
		_log("error", "continue_game: %s" % r.error)
		return false
	_log("info", "Continued at beat '%s'." % beat)
	return true

func has_save() -> bool:
	var sm := _save_manager()
	return sm != null and sm.has_save()

# --- ending replay (ADR-0006) — thin wrapper around SaveManager's sandbox (stub for R3b) ---

func begin_ending_replay() -> void:
	var sm := _save_manager()
	if sm != null:
		sm.enter_replay_mode()

func end_ending_replay() -> void:
	var sm := _save_manager()
	if sm != null:
		sm.exit_replay_mode()

# --- internals ---

func _set_starting_party(gs) -> void:
	# Minimal R3a party: Wren at level 1. Full roster + stats land with R3b slice content.
	gs.party = [ { "id": "wren", "level": 1, "xp": 0 } ]

func _on_beat_entered(_beat_id: String) -> void:
	_autosave("beat")

func _on_heartbeat() -> void:
	_autosave("heartbeat")

func _autosave(reason: String) -> void:
	var sm := _save_manager()
	if sm != null:
		sm.autosave(reason)

func _content() -> Node:
	return get_node_or_null("/root/ContentDB")

func _game_state() -> Node:
	return get_node_or_null("/root/GameState")

func _event_bus() -> Node:
	return get_node_or_null("/root/EventBus")

func _save_manager() -> Node:
	return get_node_or_null("/root/SaveManager")

func _log(level: String, msg: String) -> void:
	var log := get_node_or_null("/root/Log")
	if log == null:
		return
	match level:
		"error": log.error(msg, "GameCoordinator")
		"warn": log.warn(msg, "GameCoordinator")
		_: log.info(msg, "GameCoordinator")
