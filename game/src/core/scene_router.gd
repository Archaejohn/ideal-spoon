## scene_router.gd — the single owner of ALL top-level scene transitions (ADR-0008).
##
## Autoload Node (Round 3 wiring). It is the ONLY place that loads or swaps base scenes:
## StoryDirector decides *which* state a beat needs and emits `EventBus.scene_intent(state_key,
## ctx)`; this router listens and performs the transition, then fires the right save hook
## (ADR-0005). Scenes are presentation; this coordinator owns the flow.
##
## Testability (ADR-0008): the actual scene swap goes through an injectable `_loader` Callable
## (default `change_scene_to_file`). Integration tests inject a stub loader so they can assert
## the state_key->scene mapping and hook firing WITHOUT a real scene tree swap (which would tear
## down a running test scene).
extends Node

## App state machine (ADR-0008). String state keys (from StoryDirector.state_for / the task's
## map) resolve to these for the `state_changed` signal.
enum AppState { BOOT, TITLE, OVERWORLD, TOWN, DUNGEON, BATTLE, CUTSCENE, MENU, CROSSROADS }

## state_key -> base scene path (ADR-0008 §"how the story engine drives scene loads").
## TITLE + OVERWORLD/TOWN/DUNGEON are real this round; BATTLE/CUTSCENE/DIALOGUE/CROSSROADS are
## declared here for R3b and routed gracefully (skipped with a warning) until their scenes exist.
const STATE_TO_SCENE := {
	"TITLE": "res://src/ui/Title.tscn",
	"OVERWORLD": "res://src/ui/overworld/Overworld.tscn",
	"TOWN": "res://src/ui/overworld/Location.tscn",
	"DUNGEON": "res://src/ui/overworld/Location.tscn",
	"BATTLE": "res://src/ui/battle/Battle.tscn",
	"CUTSCENE": "res://src/ui/dialogue/Dialogue.tscn",
	"DIALOGUE": "res://src/ui/dialogue/Dialogue.tscn",
	"CROSSROADS": "res://src/ui/crossroads/Crossroads.tscn",
}

## Entering one of these (an explorable map) fires an autosave (ADR-0005 "map change").
const MAP_STATES := ["OVERWORLD", "TOWN", "DUNGEON"]

const STATE_KEY_TO_ENUM := {
	"BOOT": AppState.BOOT, "TITLE": AppState.TITLE, "OVERWORLD": AppState.OVERWORLD,
	"TOWN": AppState.TOWN, "DUNGEON": AppState.DUNGEON, "BATTLE": AppState.BATTLE,
	"CUTSCENE": AppState.CUTSCENE, "DIALOGUE": AppState.CUTSCENE, "MENU": AppState.MENU,
	"CROSSROADS": AppState.CROSSROADS,
}

var _loader: Callable = Callable()         # injectable scene-swap seam; default change_scene_to_file
var _current_state: int = AppState.BOOT
var _last_scene_path: String = ""          # last path the router asked to load (for tests/QA)
var _last_ctx: Dictionary = {}             # ctx of the last transition (beat/encounter/location)

func _ready() -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.scene_intent.connect(_on_scene_intent)

## Inject a stub loader (tests). The stub receives the scene path and records/loads as it likes.
func set_loader(c: Callable) -> void:
	_loader = c

func current_state() -> int:
	return _current_state

func last_scene_path() -> String:
	return _last_scene_path

## The ctx of the most recent transition. Scenes that need their entry payload (e.g. the
## Battle scene reading its `encounter` id) read it here, since change_scene_to_file cannot
## pass arguments to the incoming scene.
func current_ctx() -> Dictionary:
	return _last_ctx

# --- transition API (ADR-0008) ---

## Perform a base-scene transition for `state_key` (e.g. "TITLE", "OVERWORLD", "BATTLE").
## Resolves the scene path, swaps (via the injected loader or change_scene_to_file), emits
## `state_changed`, and fires the map autosave hook when entering an explorable map.
func goto(state_key: String, ctx: Dictionary = {}) -> void:
	var key := state_key.to_upper()
	var path := str(STATE_TO_SCENE.get(key, ""))
	if path == "":
		_warn("SceneRouter.goto: no scene mapped for state '%s'" % key)
		return
	# With a real loader we require the resource to exist; a stub loader bypasses this so R3b
	# states can be exercised before their .tscn ships. A not-yet-built scene is an EXPECTED
	# transitional state this round, so it is logged at info level (not a warning).
	if not _loader.is_valid() and not ResourceLoader.exists(path):
		_info("SceneRouter.goto: scene '%s' (state '%s') not built yet — staying put (R3b)" % [path, key])
		return
	var old := _current_state
	_current_state = int(STATE_KEY_TO_ENUM.get(key, AppState.OVERWORLD))
	_last_scene_path = path
	_last_ctx = ctx.duplicate(true)
	_change_scene(path)
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.state_changed.emit(old, _current_state)
	if MAP_STATES.has(key):
		_autosave("map")

func _on_scene_intent(state_key: String, ctx: Dictionary) -> void:
	goto(state_key, ctx)

# --- internals ---

func _change_scene(path: String) -> void:
	if _loader.is_valid():
		_loader.call(path)
		return
	get_tree().change_scene_to_file(path)

func _autosave(reason: String) -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null:
		sm.autosave(reason)

func _warn(msg: String) -> void:
	var log := get_node_or_null("/root/Log")
	if log != null:
		log.warn(msg, "SceneRouter")
	else:
		push_warning(msg)

func _info(msg: String) -> void:
	var log := get_node_or_null("/root/Log")
	if log != null:
		log.info(msg, "SceneRouter")
