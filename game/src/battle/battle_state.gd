## battle_state.gd — a read-only-ish view of the fight passed to EnemyBrain (ADR-0004).
##
## Pure, headless, RefCounted. Wraps the live combatant array + turn counter and exposes
## deterministic, stable-ordered queries (always sorted by combatant id) so EnemyBrain's
## target rules and conditions are reproducible (ADR-0009 §3 stable ordering).
class_name BattleState
extends RefCounted

var combatants: Array = []         # Array[Combatant]
var turn_count: int = 0

func _init(p_combatants: Array = [], p_turn_count: int = 0) -> void:
	combatants = p_combatants
	turn_count = p_turn_count

func by_id(cid: int):
	for c in combatants:
		if c.id == cid:
			return c
	return null

## Living combatants on `side`, sorted by stable id (deterministic).
func living(side: int) -> Array:
	var out: Array = []
	for c in combatants:
		if c.side == side and c.is_alive():
			out.append(c)
	out.sort_custom(func(a, b): return a.id < b.id)
	return out

## Living combatants on the OPPOSITE side from `c` (its valid targets), stable id order.
func living_opponents(c) -> Array:
	var other = Combatant.Side.PLAYER if c.side == Combatant.Side.ENEMY else Combatant.Side.ENEMY
	return living(other)

## Living combatants on the SAME side as `c` (includes `c` itself), stable id order.
func living_allies(c) -> Array:
	return living(c.side)

## True if any ally of `c` (same side, excluding `c`) is currently down.
func any_ally_down(c) -> bool:
	for o in combatants:
		if o.side == c.side and o.id != c.id and o.is_down():
			return true
	return false
