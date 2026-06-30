## battle_action.gd — an action intent (ADR-0004 "BattleAction").
##
## Pure, headless, RefCounted. Player actions are queued by the controller/UI via
## BattleEngine.queue_action(); enemy actions are produced by EnemyBrain. The engine
## consumes these and resolves them via DamageFormula + StatusEngine.
class_name BattleAction
extends RefCounted

enum Kind { ATTACK, ABILITY, ITEM, DEFEND, FLEE }

var actor_id: int = -1
var kind: int = Kind.ATTACK
var ability_id: String = ""        # ability id (ABILITY) or item id (ITEM)
var target_ids: Array = []         # stable combatant ids

static func make(actor_id: int, kind: int, ability_id: String = "", target_ids: Array = []) -> BattleAction:
	var a := BattleAction.new()
	a.actor_id = actor_id
	a.kind = kind
	a.ability_id = ability_id
	a.target_ids = target_ids.duplicate()
	return a

static func attack(actor_id: int, target_id: int) -> BattleAction:
	return make(actor_id, Kind.ATTACK, "", [target_id])

static func defend(actor_id: int) -> BattleAction:
	return make(actor_id, Kind.DEFEND, "", [])
