## battle_controller.gd — THIN bridge between the headless BattleEngine and the (Round-3)
## battle scene / HUD. Contains NO battle math (ADR-0004): all logic lives in BattleEngine,
## DamageFormula, StatusEngine, EnemyBrain, TurnScheduler, LevelSystem.
##
## Round-3 responsibilities (scene wiring) are intentionally LEFT AS STUBS here. What this
## bridge owns and exposes now:
##   - start(encounter_id): read ContentDB.encounter(id), build party Combatants from
##     GameState.party (+ LevelSystem stats), construct the engine with the injected
##     RngService "battle"/"ai" streams, and run setup().
##   - queue_action / advance / tick: forward player intent + time to the engine.
##   - relay the engine's BattleEvent stream to the scene (real-time -> tick mapping and
##     animation happen in the scene; the controller never computes outcomes).
##
## The pre-battle checkpoint (SaveManager.restore_checkpoint("pre_battle") on LOSE,
## ADR-0005 §c) is requested via signals here; SaveManager wiring lands in Round 3.
extends Node

signal battle_started(roster: Array)
signal events_emitted(events: Array)
signal battle_over(result: int, rewards: Dictionary)
signal checkpoint_requested(tag: String)   # Round 3: SaveManager listens (pre_battle)

const EngineScript := preload("res://src/battle/battle_engine.gd")
const CombatantScript := preload("res://src/battle/combatant.gd")
const LevelSystemScript := preload("res://src/leveling/level_system.gd")

var _engine                                  # BattleEngine
var _content                                 # ContentDB (autoload) or injected stub
var _rng                                     # RngService (autoload) or injected stub

## Inject dependencies (defaults resolve the autoloads when inside the tree). Lets headless
## tests pass stubs without a scene tree.
func configure(content = null, rng = null) -> void:
	_content = content if content != null else _autoload("ContentDB")
	_rng = rng if rng != null else _autoload("RngService")

## Build and start the fight for `encounter_id`. Emits an initial event batch. The scene is
## expected to have requested the pre-battle checkpoint already; we also signal for it.
func start(encounter_id: String, party_states: Array = []) -> void:
	if _content == null:
		configure()
	emit_signal("checkpoint_requested", "pre_battle")
	var encounter: Dictionary = _content.encounter(encounter_id)
	var party := _build_party(party_states)
	_engine = EngineScript.new(_rng.stream("battle"), _rng.stream("ai"), _content)
	_engine.setup(party, encounter)
	emit_signal("battle_started", _engine.combatants())
	emit_signal("events_emitted", _engine.events())

## Forward a queued player action to the engine.
func queue_action(action) -> void:
	if _engine != null:
		_engine.queue_action(action)

## Resolve one turn (the scene drives cadence; "active vs wait" is a settings concern).
func advance() -> Array:
	if _engine == null or _engine.is_over():
		return []
	var ev: Array = _engine.process_next_turn()
	if not ev.is_empty():
		emit_signal("events_emitted", ev)
	if _engine.is_over():
		emit_signal("battle_over", _engine.result(), _engine.rewards())
	return ev

func is_over() -> bool:
	return _engine != null and _engine.is_over()

func result() -> int:
	return _engine.result() if _engine != null else EngineScript.Result.ONGOING

func engine():
	return _engine

# --- helpers ---

func _build_party(party_states: Array) -> Array:
	var out: Array = []
	for ms in party_states:
		var member: Dictionary = _content.party_member(str(ms.get("id", "")))
		if member.is_empty():
			continue
		var level := int(ms.get("level", 1))
		var curve: Dictionary = _content.level_curve(str(member.get("growth", "")))
		var stats := LevelSystemScript.stats_at_level(member.get("base_stats", {}), level, curve)
		var c = CombatantScript.new()
		c.side = CombatantScript.Side.PLAYER
		c.source_id = str(member.get("id", ""))
		c.name = str(member.get("name", c.source_id))
		c.stats = {
			"hp": int(stats.get("hp", 1)), "atk": int(stats.get("atk", 0)), "def": int(stats.get("def", 0)),
			"mag": int(stats.get("mag", 0)), "res": int(stats.get("res", 0)), "spd": int(stats.get("spd", 1)),
		}
		c.max_hp = int(stats.get("hp", 1))
		c.hp_cur = c.max_hp
		var res := str(member.get("resource", "NONE"))
		if res == "BREATH" or res == "POMP":
			c.resources[res] = int(ms.get(res.to_lower(), 10))
		for ab in member.get("abilities", []):
			if int(ab.get("learn_level", 1)) <= level:
				c.ability_ids.append(str(ab.get("id", "")))
		out.append(c)
	return out

func _autoload(name: String) -> Node:
	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		return get_tree().root.get_node_or_null(name)
	return null
