## battle_engine.gd — headless ATB battle orchestrator (ADR-0004 / ADR-0009).
##
## Pure, headless, RefCounted — NO scene tree. Builds Combatants from a ContentDB encounter
## (enemies) plus caller-supplied party Combatants, runs the integer-ATB loop, consumes
## QUEUED player actions and EnemyBrain-produced enemy actions, resolves them via
## DamageFormula + StatusEngine, emits a typed BattleEvent stream, and detects win/lose.
##
## Determinism: all randomness flows through two injected RngStreams — `rng_battle`
## (damage/accuracy/crit) and `rng_ai` (EnemyBrain). Same seeds + same queued actions =>
## identical event stream (ADR-0009). The engine never mutates persistent party state; it
## works on battle-scoped Combatant copies and returns XP/loot in its result for the
## controller to hand to LevelSystem / Inventory.
##
## `content` is any object exposing ability(id)->Dictionary, status(id)->Dictionary and
## enemy(id)->Dictionary (ContentDB satisfies this; tests pass an equivalent stub).
class_name BattleEngine
extends RefCounted

enum Result { ONGOING, WIN, LOSE, FLED }

const ATB_MAX = TurnScheduler.ATB_MAX
const SONGSICK_ID = "songsick"

# Built-in free basic attack profile (kind == ATTACK / no ability id).
const BASIC_ATTACK = {
	"id": "basic_attack", "name": "Attack", "kind": "ATTACK",
	"cost": {"resource": "NONE", "amount": 0}, "target_kind": "ENEMY_SINGLE",
	"power_stat": "ATK", "defense_stat": "DEF", "power": 100,
	"effects": [{"type": "DAMAGE"}], "accuracy": 95, "element": "physical",
}

var _rng_battle
var _rng_ai
var _content

var _combatants: Array = []           # Array[Combatant], both sides
var _by_id: Dictionary = {}           # id -> Combatant
var _queued: Dictionary = {}          # actor_id -> Array[BattleAction] (FIFO)
var _events: Array = []
var _result: int = Result.ONGOING
var _turn_count: int = 0
var _next_id: int = 0
var _encounter: Dictionary = {}
var _flee_allowed: bool = false
## Rewards are rolled exactly ONCE, in _finish(), and cached here (MINOR-1, REVIEW_phase3_r3b1).
## rewards() returns this cache once the battle is over so the in-stream BATTLE_OVER event and
## the controller's battle_over signal report (and grant) the SAME loot — no double loot roll on
## the `battle` RNG stream, and no divergence once any drop chance < 1000.
var _final_rewards: Dictionary = {}
var _rewards_rolled: bool = false

func _init(rng_battle, rng_ai, content) -> void:
	_rng_battle = rng_battle
	_rng_ai = rng_ai
	_content = content

# --- setup -----------------------------------------------------------------

## Set up the fight. `player_combatants` are pre-built Combatants (built by the controller
## from GameState.party + LevelSystem). Enemies are built from the encounter via `content`.
func setup(player_combatants: Array, encounter: Dictionary) -> void:
	_encounter = encounter
	_flee_allowed = bool(encounter.get("flee_allowed", false))
	_combatants.clear()
	_by_id.clear()
	_queued.clear()
	_events.clear()
	_result = Result.ONGOING
	_turn_count = 0
	_next_id = 0
	_final_rewards = {}
	_rewards_rolled = false

	for c in player_combatants:
		c.side = Combatant.Side.PLAYER
		_register(c)

	for spec in encounter.get("enemies", []):
		var def: Dictionary = _content.enemy(str(spec.get("enemy", "")))
		var count = int(spec.get("count", 1))
		for _i in maxi(1, count):
			_register(_build_enemy(def))

	_apply_ambush(str(encounter.get("ambush", "none")))
	_emit(BattleEvent.BATTLE_START, {"combatants": _roster_summary()})

func _register(c) -> void:
	c.id = _next_id
	_next_id += 1
	_combatants.append(c)
	_by_id[c.id] = c
	_queued[c.id] = []

func _build_enemy(def: Dictionary):
	var c = Combatant.new()
	c.side = Combatant.Side.ENEMY
	c.source_id = str(def.get("id", ""))
	c.name = str(def.get("name", c.source_id))
	var st: Dictionary = def.get("stats", {})
	c.stats = {
		"hp": int(st.get("hp", 1)), "atk": int(st.get("atk", 0)), "def": int(st.get("def", 0)),
		"mag": int(st.get("mag", 0)), "res": int(st.get("res", 0)), "spd": int(st.get("spd", 1)),
	}
	c.max_hp = int(st.get("hp", 1))
	c.hp_cur = c.max_hp
	c.weaknesses = (def.get("weaknesses", []) as Array).duplicate()
	c.resistances = (def.get("resistances", []) as Array).duplicate()
	c.tags = (def.get("tags", []) as Array).duplicate()
	c.enemy_def = def
	return c

func _apply_ambush(ambush: String) -> void:
	match ambush:
		"player_first_strike":
			for c in _combatants:
				if c.side == Combatant.Side.PLAYER:
					c.atb = ATB_MAX
		"enemy_ambush":
			for c in _combatants:
				if c.side == Combatant.Side.ENEMY:
					c.atb = ATB_MAX

# --- action queue ----------------------------------------------------------

## Queue a player (or scripted) action; consumed when its actor next becomes ready.
func queue_action(action) -> void:
	if not _queued.has(action.actor_id):
		_queued[action.actor_id] = []
	_queued[action.actor_id].append(action)

# --- main loop -------------------------------------------------------------

## Advance time to the next ready combatant and resolve exactly ONE turn. Returns the
## events emitted by that turn (also appended to the full stream). No-op once over.
func process_next_turn() -> Array:
	if is_over():
		return []
	var start = _events.size()
	var ready = TurnScheduler.next_ready(_combatants)
	if ready == null:
		var t = TurnScheduler.ticks_until_next_ready(_combatants)
		if t <= 0:
			# Nobody can ever advance (all rates 0) — safety stop.
			_finish()
			return _events.slice(start)
		TurnScheduler.advance(_combatants, t)
		ready = TurnScheduler.next_ready(_combatants)
		if ready == null:
			return _events.slice(start)
	_take_turn(ready)
	return _events.slice(start)

## Peek the combatant who will act NEXT, advancing ATB time to them without taking the turn.
## Mirrors the time-advance in process_next_turn (same ticks_until_next_ready), so a subsequent
## process_next_turn resolves exactly this actor — determinism is unchanged. Returns null when
## the battle is over or nobody can ever advance. Used by the WAIT-mode UI to decide whether to
## open a player's action menu (player turn) or auto-resolve (enemy turn).
func peek_next_actor():
	if is_over():
		return null
	var ready = TurnScheduler.next_ready(_combatants)
	if ready == null:
		var t = TurnScheduler.ticks_until_next_ready(_combatants)
		if t <= 0:
			return null
		TurnScheduler.advance(_combatants, t)
		ready = TurnScheduler.next_ready(_combatants)
	return ready

## Run to completion (tests). `max_turns` guards against a stall. Returns the full stream.
func run_until_over(max_turns: int = 10000) -> Array:
	var guard = 0
	while not is_over() and guard < max_turns:
		process_next_turn()
		guard += 1
	if not is_over():
		_finish()
	return _events

# --- turn resolution -------------------------------------------------------

func _take_turn(actor) -> void:
	_emit(BattleEvent.TURN_READY, {"combatant": actor.id})
	_turn_count += 1
	actor.defending = false

	# cooldowns tick down at turn start.
	for k in actor.cooldowns.keys():
		actor.cooldowns[k] = maxi(0, int(actor.cooldowns[k]) - 1)

	# status tick (DoT/regen, ageing/expiry).
	for ev in StatusEngine.tick(actor):
		_events.append(ev)
	if _check_down(actor):
		actor.atb = 0
		_post_turn()
		return

	_emit(BattleEvent.TURN_START, {"combatant": actor.id, "turn": _turn_count})

	# select the action.
	var action
	if actor.side == Combatant.Side.ENEMY:
		action = EnemyBrain.choose_action(actor, _make_state(), _rng_ai)
	else:
		action = _dequeue(actor.id)
		if action == null:
			action = BattleAction.defend(actor.id)   # kid-friendly auto-default

	actor.atb -= ATB_MAX   # spend gauge (carry-over preserved)
	_resolve(action, actor)
	_post_turn()

func _post_turn() -> void:
	_sweep_downs()
	if _is_decided():
		_finish()

## True once the battle has a foregone outcome: a side is fully down, a flee succeeded, or the
## result is already set. Drives turn-by-turn termination so process_next_turn()/advance() detect
## WIN/LOSE the moment it happens (not only run_until_over's trailing _finish()).
func _is_decided() -> bool:
	if _result != Result.ONGOING:
		return true
	var players_alive := false
	var enemies_alive := false
	for c in _combatants:
		if c.is_alive():
			if c.side == Combatant.Side.PLAYER:
				players_alive = true
			else:
				enemies_alive = true
	return not players_alive or not enemies_alive

func _resolve(action, actor) -> void:
	match action.kind:
		BattleAction.Kind.DEFEND:
			actor.defending = true
			_emit(BattleEvent.DEFEND, {"combatant": actor.id})
			return
		BattleAction.Kind.FLEE:
			if _flee_allowed:
				_result = Result.FLED
				_emit(BattleEvent.FLEE, {"combatant": actor.id, "success": true})
			else:
				_emit(BattleEvent.FLEE, {"combatant": actor.id, "success": false})
			return

	var ability = _ability_for(action)
	if ability.is_empty():
		_emit(BattleEvent.FIZZLE, {"combatant": actor.id, "reason": "unknown_ability"})
		return

	# resource / cooldown gating.
	if not _pay_costs(actor, ability):
		_emit(BattleEvent.FIZZLE, {"combatant": actor.id, "ability": str(ability.get("id", "")), "reason": "cost"})
		return

	var targets = _resolve_targets(action, ability, actor)
	if targets.is_empty() and _needs_target(ability):
		_emit(BattleEvent.FIZZLE, {"combatant": actor.id, "ability": str(ability.get("id", "")), "reason": "no_target"})
		return

	_emit(BattleEvent.ACTION, {"combatant": actor.id, "ability": str(ability.get("id", "")),
		"kind": action.kind, "targets": targets.duplicate()})

	for tid in targets:
		_apply_ability_to(actor, _by_id[tid], ability)

	# set cooldown after use.
	var cd = int(ability.get("cooldown_turns", 0))
	if cd > 0:
		actor.cooldowns[str(ability.get("id", ""))] = cd

func _apply_ability_to(actor, target, ability: Dictionary) -> void:
	for eff in ability.get("effects", []):
		var et = str(eff.get("type", ""))
		match et:
			"DAMAGE":
				var r = DamageFormula.compute(actor, target, ability, _rng_battle)
				if not r.get("hit", false):
					_emit(BattleEvent.MISS, {"source": actor.id, "target": target.id, "ability": str(ability.get("id", ""))})
					continue
				target.hp_cur = maxi(0, target.hp_cur - int(r["amount"]))
				actor.threat += int(r["amount"])
				_emit(BattleEvent.HIT, {"source": actor.id, "target": target.id,
					"ability": str(ability.get("id", "")), "amount": int(r["amount"]),
					"crit": r.get("crit", false), "weak": r.get("weak", false), "hp": target.hp_cur})
			"HEAL":
				var h = DamageFormula.compute_heal(actor, target, ability, _rng_battle)
				var before = target.hp_cur
				# Steady can relight a downed (but not pacified) ally.
				target.hp_cur = mini(target.max_hp, target.hp_cur + int(h["amount"]))
				_emit(BattleEvent.HEAL, {"source": actor.id, "target": target.id,
					"ability": str(ability.get("id", "")), "amount": target.hp_cur - before, "hp": target.hp_cur})
			"APPLY_STATUS":
				var sdef: Dictionary = _content.status(str(eff.get("status", "")))
				if not sdef.is_empty():
					StatusEngine.apply(target, sdef, actor, _rng_battle)
					_emit(BattleEvent.STATUS_APPLY, {"source": actor.id, "target": target.id, "status": str(sdef.get("id", ""))})
			"CLEANSE":
				var removed = StatusEngine.cleanse(target, int(eff.get("count", 1)))
				if not removed.is_empty():
					_emit(BattleEvent.STATUS_EXPIRE, {"target": target.id, "cleansed": removed})
			"PACIFY":
				target.pacified = true
				_emit(BattleEvent.PACIFY, {"source": actor.id, "target": target.id})

# --- targeting / retargeting (ADR-0004 retarget-or-fizzle) -----------------

func _resolve_targets(action, ability: Dictionary, actor) -> Array:
	var valid: Array = []
	for tid in action.target_ids:
		if _by_id.has(tid) and _is_valid_target(_by_id[tid], ability, actor):
			valid.append(tid)
	if not valid.is_empty():
		return valid
	# original target(s) gone — retarget deterministically to the same side.
	var retargeted = _retarget(ability, actor)
	if not retargeted.is_empty():
		_emit(BattleEvent.RETARGET, {"combatant": actor.id, "from": action.target_ids.duplicate(), "to": retargeted.duplicate()})
	return retargeted

func _retarget(ability: Dictionary, actor) -> Array:
	if not _needs_target(ability):
		return [actor.id]
	var want_ally = _targets_allies(ability)
	var pool: Array = []
	for c in _combatants:
		if c.is_alive() and ((want_ally and c.side == actor.side) or (not want_ally and c.side != actor.side)):
			pool.append(c)
	pool.sort_custom(func(a, b): return a.id < b.id)
	return [pool[0].id] if pool.size() > 0 else []

func _is_valid_target(target, ability: Dictionary, _actor) -> bool:
	# A heal/relight may target a downed (not pacified) ally; offense needs a living foe.
	if _is_heal(ability):
		return not target.pacified
	return target.is_alive()

# --- costs -----------------------------------------------------------------

func _pay_costs(actor, ability: Dictionary) -> bool:
	# cooldown gate.
	if int(actor.cooldowns.get(str(ability.get("id", "")), 0)) > 0:
		return false
	var cost: Dictionary = ability.get("cost", {})
	var resource = str(cost.get("resource", "NONE"))
	var amount = int(cost.get("amount", 0))
	if resource == "NONE" or amount <= 0:
		return true
	if resource == "ITEM":
		return true   # item consumption handled by Inventory (Round 3); allowed headless.
	# BREATH / POMP.
	if actor.blocked_resources.get(resource, false):
		# resource is blocked (e.g. Songsickness blocks BREATH) — overspend penalty path.
		if resource == "BREATH":
			_overspend_breath(actor)
		return false
	var have = int(actor.resources.get(resource, 0))
	if have >= amount:
		actor.resources[resource] = have - amount
		_emit(BattleEvent.RESOURCE_SPEND, {"combatant": actor.id, "resource": resource, "amount": amount})
		return true
	# insufficient: BREATH overspend hurts (Songsickness); POMP simply fizzles.
	if resource == "BREATH":
		actor.resources[resource] = 0
		_emit(BattleEvent.RESOURCE_SPEND, {"combatant": actor.id, "resource": resource, "amount": have})
		_overspend_breath(actor)
		return true   # the song still goes out, but at a cost
	return false

func _overspend_breath(actor) -> void:
	var sdef: Dictionary = _content.status(SONGSICK_ID)
	if not sdef.is_empty():
		StatusEngine.apply(actor, sdef, actor, _rng_battle)
		_emit(BattleEvent.SONGSICK, {"combatant": actor.id})

# --- win / lose ------------------------------------------------------------

func is_over() -> bool:
	return _result != Result.ONGOING

func result() -> int:
	return _result

func _sweep_downs() -> void:
	for c in _combatants:
		if c.hp_cur <= 0 and not c.announced_down:
			c.announced_down = true
			_emit(BattleEvent.COMBATANT_DOWN, {"combatant": c.id, "side": c.side})

func _check_down(c) -> bool:
	if c.hp_cur <= 0 and not c.announced_down:
		c.announced_down = true
		_emit(BattleEvent.COMBATANT_DOWN, {"combatant": c.id, "side": c.side})
		return true
	return c.hp_cur <= 0

func _finish() -> void:
	if _result == Result.FLED:
		_emit(BattleEvent.BATTLE_OVER, {"result": _result})
		return
	var players_alive = false
	var enemies_alive = false
	for c in _combatants:
		if c.is_alive():
			if c.side == Combatant.Side.PLAYER:
				players_alive = true
			else:
				enemies_alive = true
	if not enemies_alive:
		_result = Result.WIN
	elif not players_alive:
		_result = Result.LOSE
	# Roll rewards exactly ONCE here (MINOR-1): the BATTLE_OVER event and every later rewards()
	# call (incl. the controller's battle_over signal) share this cached, single loot roll.
	_final_rewards = _roll_rewards()
	_rewards_rolled = true
	_emit(BattleEvent.BATTLE_OVER, {"result": _result, "rewards": _final_rewards})

# --- rewards ---------------------------------------------------------------

## XP + loot for a WIN. Idempotent once the battle is over: returns the cache rolled in _finish()
## so loot is never re-rolled (no double advance of the `battle` RNG cursor, no divergence between
## the reported and granted loot). Pre-finish calls roll fresh (only used by run-to-completion tests).
func rewards() -> Dictionary:
	if _rewards_rolled:
		return _final_rewards
	return _roll_rewards()

## The actual XP + loot computation (encounter rewards override enemy defaults). Loot rolled on
## the "battle" stream for determinism (ADR-0009). Called once from _finish() (cached).
func _roll_rewards() -> Dictionary:
	if _result != Result.WIN:
		return {"xp": 0, "items": []}
	var enc_rewards: Dictionary = _encounter.get("rewards", {})
	var xp = 0
	var items: Array = []
	if enc_rewards.has("xp"):
		xp = int(enc_rewards["xp"])
		for it in enc_rewards.get("items", []):
			if _rng_battle.chance_permille(int(it.get("chance_permille", 1000))):
				items.append(str(it.get("item", "")))
	else:
		for c in _combatants:
			if c.side == Combatant.Side.ENEMY:
				xp += int(c.enemy_def.get("xp", 0))
				for it in c.enemy_def.get("loot", []):
					if _rng_battle.chance_permille(int(it.get("chance_permille", 1000))):
						items.append(str(it.get("item", "")))
	return {"xp": xp, "items": items}

# --- introspection (controller / tests) ------------------------------------

func events() -> Array:
	return _events

func combatants() -> Array:
	return _combatants

func combatant(id: int):
	return _by_id.get(id, null)

func turn_count() -> int:
	return _turn_count

func rng_battle():
	return _rng_battle

# --- internal helpers ------------------------------------------------------

func _dequeue(actor_id: int):
	var q: Array = _queued.get(actor_id, [])
	if q.is_empty():
		return null
	return q.pop_front()

func _ability_for(action) -> Dictionary:
	if action.kind == BattleAction.Kind.ATTACK or action.ability_id == "":
		return BASIC_ATTACK
	var a: Dictionary = _content.ability(action.ability_id)
	return a if not a.is_empty() else {}

func _needs_target(ability: Dictionary) -> bool:
	return str(ability.get("target_kind", "ENEMY_SINGLE")) != "SELF"

func _targets_allies(ability: Dictionary) -> bool:
	var tk = str(ability.get("target_kind", "ENEMY_SINGLE"))
	return tk in ["ALLY_SINGLE", "ALLY_ALL", "SELF"]

func _is_heal(ability: Dictionary) -> bool:
	for eff in ability.get("effects", []):
		if str(eff.get("type", "")) in ["HEAL", "CLEANSE"]:
			return true
	return _targets_allies(ability)

func _make_state() -> BattleState:
	return BattleState.new(_combatants, _turn_count)

func _emit(type: String, data: Dictionary = {}) -> void:
	_events.append(BattleEvent.make(type, data))

func _roster_summary() -> Array:
	var out: Array = []
	for c in _combatants:
		out.append({"id": c.id, "name": c.name, "side": c.side, "hp": c.max_hp})
	return out
