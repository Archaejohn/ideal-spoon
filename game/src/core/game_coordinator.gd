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
const LevelSystemScript := preload("res://src/leveling/level_system.gd")

## The integration-shell start beat (R3a slice bootstrap; real Act-1 opening lands in R3b).
const START_BEAT := "SLICE-START"
## Periodic autosave backstop interval (ADR-0005 §a "~30–60s heartbeat").
const HEARTBEAT_SECS := 45.0

var _director                              # StoryDirector (RefCounted, owned here)
var _heartbeat: Timer

# --- battle flow (Owner #13 checkpoint loop) ---
## The beat we were sitting on when the current battle was entered (the resume unit). The
## pre-battle checkpoint snapshots GameState here; LOSE restores it and re-enters.
var _pre_battle_beat: String = ""
## Outcome of the last finished battle ({result:int, rewards:Dictionary}); consumed by
## after_battle() so the scene can show its victory/defeat panel before the route happens.
var _battle_outcome: Dictionary = {}

func _ready() -> void:
	_build_director()
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.beat_entered.connect(_on_beat_entered)
		# Content loads asynchronously at Boot; rebuild the director's graph once it is ready.
		bus.content_loaded.connect(_build_director)
	# Battle flow wiring (ADR-0005 §c / PHASE2_OWNER_RULINGS #2 / Owner #13). The BattleController
	# bridge emits these; the coordinator owns the checkpoint + reward + lose-restore + routing.
	var bc := _battle_controller()
	if bc != null:
		if not bc.checkpoint_requested.is_connected(_on_checkpoint_requested):
			bc.checkpoint_requested.connect(_on_checkpoint_requested)
		if not bc.battle_over.is_connected(_on_battle_over):
			bc.battle_over.connect(_on_battle_over)
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

# --- overworld -> battle flow (R3b-1 slice) ---

## Walk the story spine one step (the overworld "Enter the wreck" affordance uses this to reach
## the SLICE-BATTLE beat, which the SceneRouter turns into the Battle scene). Returns true if it
## moved. Refused while a branch is open (R3b-2 dialogue territory).
func advance_story() -> bool:
	if _director == null:
		return false
	var r: Result = _director.advance()
	if r != null and r.is_err():
		_log("warn", "advance_story: %s" % r.error)
		return false
	return r != null and bool(r.value)

## Resolve the OPEN branch by choosing `option_id` (the Dialogue/branch UI calls this). Applies the
## option's effects and routes to its goto via the StoryDirector (which drives the scene_intent to
## the merge path). Returns true on success. No-op if no branch is open or the option is unknown.
func choose_branch(option_id: String) -> bool:
	if _director == null:
		return false
	var bid: String = _director.current_branch_id()
	if bid == "":
		_log("warn", "choose_branch('%s'): no branch open" % option_id)
		return false
	var r: Result = _director.choose(bid, option_id)
	if r != null and r.is_err():
		_log("warn", "choose_branch: %s" % r.error)
		return false
	return true

## The option ids the open branch currently offers (for the choice UI). [] when no branch is open.
func offered_branch_options() -> Array:
	if _director == null:
		return []
	var bid: String = _director.current_branch_id()
	return _director.offered_options(bid) if bid != "" else []

## Start the fight for `encounter_id` against the live GameState party. Called by the Battle
## scene's _ready (which reads the encounter from SceneRouter.current_ctx) and by tests. Remembers
## the current beat as the pre-battle resume unit, then drives BattleController.start — which
## emits checkpoint_requested("pre_battle") that we turn into a SaveManager checkpoint.
func start_battle(encounter_id: String) -> void:
	var gs := _game_state()
	_pre_battle_beat = gs.current_beat_id if gs != null else ""
	_battle_outcome = {}
	var bc := _battle_controller()
	if bc == null:
		_log("error", "start_battle: no BattleController")
		return
	bc.configure()
	bc.start(encounter_id, gs.party if gs != null else [])

## Resolve the post-battle flow once the scene's panel button is pressed (victory "Continue" or
## defeat "Try again"). Kept separate from _on_battle_over so the scene can SHOW its panel before
## the route happens. WIN advances the spine; LOSE restores the pre-battle checkpoint and re-enters
## the fight (never a game-over to title, ADR-0005 §c); FLEE returns to the overworld with no reward.
func after_battle() -> void:
	var result := int(_battle_outcome.get("result", -1))
	match result:
		BattleEngine.Result.WIN:
			# Rewards were already applied + autosaved on battle_over; advance the story spine.
			if not advance_story():
				_log("info", "after_battle(WIN): no successor beat from '%s'." % _pre_battle_beat)
		BattleEngine.Result.LOSE:
			var sm := _save_manager()
			if sm != null and sm.restore_checkpoint("pre_battle"):
				_log("info", "after_battle(LOSE): restored pre_battle checkpoint; retrying.")
			# Re-enter the (restored) pre-battle beat so the player retries from just before the
			# fight — routes back to BATTLE, never to the Title.
			_build_director()
			var beat: String = _game_state().current_beat_id
			if beat == "":
				beat = _pre_battle_beat
			_director.goto_beat(beat)
		BattleEngine.Result.FLED:
			# Flee returns to the overworld with no reward (R3b-2 supplies real fleeable encounters
			# + a proper destination; the slice boss has flee_allowed=false so this is rare).
			var router := _scene_router()
			if router != null:
				router.goto("OVERWORLD", {"beat": _pre_battle_beat})
		_:
			_log("warn", "after_battle: no finished battle to resolve.")

func last_battle_result() -> int:
	return int(_battle_outcome.get("result", -1))

# --- battle signal handlers (Owner #13) ---

func _on_checkpoint_requested(tag: String) -> void:
	var sm := _save_manager()
	if sm != null:
		var ok: bool = sm.write_checkpoint(tag)
		_log("info", "pre-battle checkpoint '%s' written: %s" % [tag, str(ok)])

func _on_battle_over(result: int, rewards: Dictionary) -> void:
	_battle_outcome = {"result": result, "rewards": rewards.duplicate(true)}
	if result == BattleEngine.Result.WIN:
		_apply_rewards(rewards)
		_autosave("battle_win")
		_log("info", "battle WON: +%d xp, items %s" % [int(rewards.get("xp", 0)), str(rewards.get("items", []))])
	elif result == BattleEngine.Result.LOSE:
		_log("info", "battle LOST: pre-battle checkpoint restore available (Try Again).")

## Apply a WIN's rewards to the persistent run: XP -> LevelSystem per party member (level-ups
## fold in), loot items -> inventory. Pure GameState mutation; the engine never touched it.
func _apply_rewards(rewards: Dictionary) -> void:
	var gs := _game_state()
	var content := _content()
	if gs == null or content == null:
		return
	var xp := int(rewards.get("xp", 0))
	if xp > 0:
		for member in gs.party:
			var def: Dictionary = content.party_member(str(member.get("id", "")))
			var curve: Dictionary = content.level_curve(str(def.get("growth", "")))
			var res := LevelSystemScript.grant_xp(member, xp, curve)
			member["xp"] = int(res.get("xp", member.get("xp", 0)))
			member["level"] = int(res.get("level", member.get("level", 1)))
	var items: Dictionary = gs.inventory.get("items", {})
	for item_id in rewards.get("items", []):
		var key := str(item_id)
		if key != "":
			items[key] = int(items.get(key, 0)) + 1
	gs.inventory["items"] = items

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
	# R3b slice party: Wren (lead, Song) + Tam (gadgets), both at level 1. PartyMemberState is
	# data-only {id, level, xp}; BattleController builds Combatants from these + ContentDB stats.
	gs.party = [
		{ "id": "wren", "level": 1, "xp": 0 },
		{ "id": "tam", "level": 1, "xp": 0 },
	]

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

func _battle_controller() -> Node:
	return get_node_or_null("/root/BattleController")

func _scene_router() -> Node:
	return get_node_or_null("/root/SceneRouter")

func _log(level: String, msg: String) -> void:
	var log := get_node_or_null("/root/Log")
	if log == null:
		return
	match level:
		"error": log.error(msg, "GameCoordinator")
		"warn": log.warn(msg, "GameCoordinator")
		_: log.info(msg, "GameCoordinator")
