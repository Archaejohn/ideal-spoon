## fake_rng.gd — a scripted RngStream stand-in for exact control in tests (ADR-0009).
##
## Implements the same surface as RngService.RngStream (randi / randi_range /
## chance_permille / weighted_pick / randf / get_cursor / set_cursor). Each high-level
## method pops from its own scripted queue; when a queue is empty it falls back to a
## documented deterministic default. Lets EnemyBrain/DamageFormula tests assert exact
## choices without depending on a particular seed.
extends RefCounted

var picks: Array = []        # scripted weighted_pick() return values (indices)
var ranges: Array = []       # scripted randi_range() return values
var chances: Array = []      # scripted chance_permille() return values (bools)
var ints: Array = []         # scripted randi() return values
var _cursor: int = 0

func _consume():
	_cursor += 1

func randi() -> int:
	_consume()
	return int(ints.pop_front()) if not ints.is_empty() else 0

func randi_range(a: int, b: int) -> int:
	_consume()
	if not ranges.is_empty():
		return clampi(int(ranges.pop_front()), a, b)
	return a   # default: lower bound

func chance_permille(p: int) -> bool:
	_consume()
	if not chances.is_empty():
		return bool(chances.pop_front())
	if p <= 0:
		return false
	if p >= 1000:
		return true
	return p >= 500   # default: deterministic midpoint

func weighted_pick(weights: Array) -> int:
	_consume()
	if not picks.is_empty():
		return int(picks.pop_front())
	# default: first non-zero weight.
	for i in weights.size():
		if int(weights[i]) > 0:
			return i
	return 0

func randf() -> float:
	_consume()
	return 0.0

func get_cursor() -> int:
	return _cursor

func set_cursor(n: int) -> void:
	_cursor = n
