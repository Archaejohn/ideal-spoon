## status_engine.gd — apply / tick / expire status effects (ADR-0004 / ADR-0009).
##
## Pure, static, headless. All effects are deterministic integer math. A status instance
## on a Combatant is a dict: { id, def, remaining, stacks }, where `def` is the status data
## record (ADR-0007 schema). The engine never reaches for a global RNG; the optional `rng`
## argument is reserved for statuses with randomized application (none today).
##
## Status data fields used here:
##   - duration_turns / duration_ticks : lifetime (decremented once per tick()).
##   - stack_rule : REFRESH | STACK | IGNORE.
##   - tick_effect : { type: DAMAGE|HEAL|NONE, amount } applied each tick (scaled by stacks).
##   - atb_modifier_permille : read by TurnScheduler (turn order is an outcome — integer).
##   - stat_mod : { stat, permille } read by Combatant.stat() (buffs/debuffs).
##   - on_apply / on_expire : { block_resource } hooks (e.g. Songsickness blocks BREATH).
class_name StatusEngine
extends RefCounted

## Apply a status (by its data record) to `combatant`, honoring the stack rule.
static func apply(combatant, status_def: Dictionary, _source = null, _rng = null) -> Dictionary:
	var sid = str(status_def.get("id", ""))
	var rule = str(status_def.get("stack_rule", "REFRESH"))
	var duration = _duration(status_def)
	var existing = _find(combatant, sid)
	if existing != null:
		match rule:
			"REFRESH":
				existing["remaining"] = duration
			"STACK":
				existing["stacks"] = int(existing.get("stacks", 1)) + 1
				existing["remaining"] = maxi(int(existing["remaining"]), duration)
			"IGNORE":
				pass
		return existing
	var inst = {"id": sid, "def": status_def, "remaining": duration, "stacks": 1}
	combatant.statuses.append(inst)
	_on_apply(combatant, status_def)
	return inst

## Tick all statuses on `combatant` (called at the start of its turn). Applies tick effects,
## decrements durations, removes expired statuses. Returns an Array of event dicts.
static func tick(combatant) -> Array:
	var events: Array = []
	# 1. tick effects (DoT / regen), scaled by stacks; clamp hp to [0, max].
	for s in combatant.statuses.duplicate():
		var te = (s["def"] as Dictionary).get("tick_effect", {})
		if not (te is Dictionary):
			continue
		var t = str(te.get("type", "NONE"))
		var amount = int(te.get("amount", 0)) * int(s.get("stacks", 1))
		if amount <= 0:
			continue
		if t == "DAMAGE":
			combatant.hp_cur = maxi(0, combatant.hp_cur - amount)
			events.append({"type": BattleEvent.STATUS_TICK, "combatant": combatant.id,
				"status": s["id"], "hp_delta": -amount, "hp": combatant.hp_cur})
		elif t == "HEAL":
			combatant.hp_cur = mini(combatant.max_hp, combatant.hp_cur + amount)
			events.append({"type": BattleEvent.STATUS_TICK, "combatant": combatant.id,
				"status": s["id"], "hp_delta": amount, "hp": combatant.hp_cur})
	# 2. age + expire.
	for s in combatant.statuses.duplicate():
		s["remaining"] = int(s["remaining"]) - 1
		if int(s["remaining"]) <= 0:
			combatant.statuses.erase(s)
			_on_expire(combatant, s["def"])
			events.append({"type": BattleEvent.STATUS_EXPIRE, "combatant": combatant.id, "status": s["id"]})
	return events

## Remove a status by id (e.g. CLEANSE). Returns true if one was removed.
static func remove(combatant, status_id: String) -> bool:
	var inst = _find(combatant, status_id)
	if inst == null:
		return false
	combatant.statuses.erase(inst)
	_on_expire(combatant, inst["def"])
	return true

## Remove up to `count` ailment/debuff statuses (Steady's CLEANSE). Stable order by id.
static func cleanse(combatant, count: int) -> Array:
	var removed: Array = []
	var sorted = combatant.statuses.duplicate()
	sorted.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))
	for s in sorted:
		if removed.size() >= count:
			break
		var cat = str((s["def"] as Dictionary).get("category", ""))
		if cat == "debuff" or cat == "ailment" or cat == "control":
			combatant.statuses.erase(s)
			_on_expire(combatant, s["def"])
			removed.append(str(s["id"]))
	return removed

# --- helpers ---

static func _duration(status_def: Dictionary) -> int:
	if status_def.has("duration_turns"):
		return maxi(1, int(status_def["duration_turns"]))
	if status_def.has("duration_ticks"):
		return maxi(1, int(status_def["duration_ticks"]))
	return 1

static func _find(combatant, sid: String):
	for s in combatant.statuses:
		if str(s["id"]) == sid:
			return s
	return null

static func _on_apply(combatant, status_def: Dictionary) -> void:
	var oa = status_def.get("on_apply", {})
	if oa is Dictionary and oa.has("block_resource"):
		combatant.blocked_resources[str(oa["block_resource"])] = true

static func _on_expire(combatant, status_def: Dictionary) -> void:
	var oe = status_def.get("on_apply", {})  # the block is paired; clear on expire
	if oe is Dictionary and oe.has("block_resource"):
		combatant.blocked_resources.erase(str(oe["block_resource"]))
