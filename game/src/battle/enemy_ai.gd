## enemy_ai.gd — EnemyBrain: pure, RNG-injected enemy action selection (ADR-0004 / ADR-0009).
##
## Pure, static, headless. NO scene tree, NO autoload access. Determinism comes from the
## injected `ai` RngStream (separate from "battle" so AI rolls never perturb damage
## reproducibility). The behavior is fully DATA-AUTHORED via the enemy's `ai` policy block
## (ADR-0007); the three policies basic|caster|boss_phased are the SAME engine driven by
## different authored blocks.
##
## Selection algorithm (ADR-0004 §"EnemyBrain"):
##   1. Read self.enemy_def.ai.
##   2. Keep ai.abilities[] entries whose `condition` evaluates true vs. the BattleState
##      (pure, no RNG): self_hp_below_permille | ally_down | turn_gte | phase.
##   3. Aggression-bias the eligible weights, then pick one by integer weight via
##      rng_ai.weighted_pick (ONE draw).
##   4. Resolve targets by the entry's `target_rule` (deterministic except `random`, which
##      draws ONE from rng_ai). lowest_hp / highest_threat ties break by stable id.
##   5. If nothing is eligible, fall back to a basic ATTACK on the lowest-hp opponent.
##
## Draw discipline: a chosen entry costs exactly ONE weighted_pick draw; `random` targeting
## adds exactly ONE randi_range draw. Everything else is a pure function of state.
class_name EnemyBrain
extends RefCounted

## Choose an action for `self_c` given the battle `state` and the injected `ai` RngStream.
static func choose_action(self_c, state, rng_ai) -> BattleAction:
	var ai = self_c.enemy_def.get("ai", {})
	var entries: Array = ai.get("abilities", []) if ai is Dictionary else []

	var eligible: Array = []
	for e in entries:
		if e is Dictionary and _condition_true(e.get("condition", null), self_c, state):
			eligible.append(e)

	if eligible.is_empty():
		return _basic_attack(self_c, state)

	var aggression = int(ai.get("aggression_permille", 500))
	var weights: Array = []
	for e in eligible:
		weights.append(_biased_weight(e, aggression))

	var idx = rng_ai.weighted_pick(weights)
	idx = clampi(idx, 0, eligible.size() - 1)
	var entry: Dictionary = eligible[idx]

	var targets = _pick_targets(entry, self_c, state, rng_ai)
	if targets.is_empty():
		return _basic_attack(self_c, state)

	return BattleAction.make(self_c.id, BattleAction.Kind.ABILITY, str(entry.get("ability", "")), targets)

# --- conditions (pure functions of state; no RNG) ---

static func _condition_true(cond, self_c, state) -> bool:
	if cond == null:
		return true
	if not (cond is Dictionary):
		return true
	var t = str(cond.get("type", ""))
	var v = int(cond.get("value", 0))
	match t:
		"self_hp_below_permille", "phase":
			return self_c.hp_cur * 1000 / maxi(1, self_c.max_hp) < v
		"turn_gte":
			return state.turn_count >= v
		"ally_down":
			return state.any_ally_down(self_c)
	return true

# --- weighting (aggression bias, ADR-0004 step 5) ---
#
# An entry may carry `"intent": "offense" | "support"`. Offense entries are scaled by
# aggression_permille, support entries by (1000 - aggression). Untagged entries keep their
# raw weight. weighted_pick uses RELATIVE weights, so the common /1000 factor is harmless.
static func _biased_weight(entry: Dictionary, aggression: int) -> int:
	var w = maxi(0, int(entry.get("weight", 1)))
	var intent = str(entry.get("intent", ""))
	match intent:
		"offense":
			return w * clampi(aggression, 0, 1000) / 1000
		"support":
			return w * clampi(1000 - aggression, 0, 1000) / 1000
	return w

# --- targeting ---

static func _pick_targets(entry: Dictionary, self_c, state, rng_ai) -> Array:
	var rule = str(entry.get("target_rule", "lowest_hp"))
	var foes = state.living_opponents(self_c)
	var allies = state.living_allies(self_c)
	match rule:
		"self":
			return [self_c.id]
		"all_enemies":
			return _ids(foes)
		"all_allies":
			return _ids(allies)
		"lowest_hp":
			return _wrap(_lowest_hp(foes))
		"highest_threat":
			return _wrap(_highest_threat(foes))
		"lowest_hp_ally":
			return _wrap(_lowest_hp(allies))
		"random":
			if foes.is_empty():
				return []
			var i = rng_ai.randi_range(0, foes.size() - 1)
			return [foes[i].id]
	return _wrap(_lowest_hp(foes))

static func _basic_attack(self_c, state) -> BattleAction:
	var foes = state.living_opponents(self_c)
	if foes.is_empty():
		return BattleAction.defend(self_c.id)
	return BattleAction.attack(self_c.id, _lowest_hp(foes))

# --- pure pickers (stable-id tie-break: iterate sorted-by-id, keep STRICT improvement) ---

static func _lowest_hp(list: Array) -> int:
	if list.is_empty():
		return -1
	var best = list[0]
	for c in list:
		if c.hp_cur < best.hp_cur:
			best = c
	return best.id

static func _highest_threat(list: Array) -> int:
	if list.is_empty():
		return -1
	var best = list[0]
	for c in list:
		if c.threat > best.threat:
			best = c
	return best.id

static func _ids(list: Array) -> Array:
	var out: Array = []
	for c in list:
		out.append(c.id)
	return out

static func _wrap(cid: int) -> Array:
	return [cid] if cid >= 0 else []
