## test_enemy_ai.gd — EnemyBrain: condition/weight/target rules, boss phases, retarget.
extends GutTest

const Fx = preload("res://tests/helpers/battle_fixtures.gd")
const EnemyBrain = preload("res://src/battle/enemy_ai.gd")
const BattleStateScript = preload("res://src/battle/battle_state.gd")
const CombatantScript = preload("res://src/battle/combatant.gd")
const BattleAction = preload("res://src/battle/battle_action.gd")
const FakeRng = preload("res://tests/helpers/fake_rng.gd")

var _db

func before_all():
	_db = Fx.content()

func after_all():
	if _db != null:
		_db.free()

func _rng(picks: Array = [], ranges: Array = []):
	var r = FakeRng.new()
	r.picks = picks.duplicate()
	r.ranges = ranges.duplicate()
	return r

func _player(id: int, hp: int):
	var c = Fx.combatant({"hp": hp, "atk": 10, "spd": 10}, {"side": CombatantScript.Side.PLAYER})
	c.id = id
	c.hp_cur = hp
	return c

func test_basic_picks_strike_on_lowest_hp_target():
	var enemy = Fx.enemy(_db, "dummy")
	enemy.id = 1
	var p_full = _player(0, 50)
	var p_low = _player(2, 12)
	var state = BattleStateScript.new([p_full, enemy, p_low], 0)
	var act = EnemyBrain.choose_action(enemy, state, _rng([0]))
	assert_eq(act.ability_id, "enemy_strike", "basic policy uses its single weighted ability")
	assert_eq(act.target_ids, [2], "lowest_hp targets the weakest opponent (id 2)")

func test_lowest_hp_tie_breaks_by_stable_id():
	var enemy = Fx.enemy(_db, "dummy")
	enemy.id = 5
	var a = _player(3, 20)
	var b = _player(1, 20)   # same hp, lower id
	var state = BattleStateScript.new([enemy, a, b], 0)
	var act = EnemyBrain.choose_action(enemy, state, _rng([0]))
	assert_eq(act.target_ids, [1], "lowest_hp tie -> lower stable id")

func test_boss_phase_gates_screech_below_hp_threshold():
	var crane = Fx.enemy(_db, "crane")   # screech needs self_hp_below_permille 500
	crane.id = 0
	var p = _player(1, 100)
	var state = BattleStateScript.new([crane, p], 3)
	# Above threshold: only enemy_strike eligible; weighted_pick(index 0) -> strike.
	var act_high = EnemyBrain.choose_action(crane, state, _rng([0]))
	assert_eq(act_high.ability_id, "enemy_strike", "above 50% hp the boss cannot screech")
	# Drop to 40% hp: both eligible; pick index 1 -> screech, targets all opponents.
	crane.hp_cur = crane.max_hp * 40 / 100
	var p2 = _player(2, 100)
	var state2 = BattleStateScript.new([crane, p, p2], 3)
	var act_low = EnemyBrain.choose_action(crane, state2, _rng([1]))
	assert_eq(act_low.ability_id, "screech", "below 50% hp the boss may screech (phase condition)")
	assert_eq(act_low.target_ids, [1, 2], "all_enemies targets every living opponent (stable id order)")

func test_retargets_when_lowest_hp_target_is_dead():
	var enemy = Fx.enemy(_db, "dummy")
	enemy.id = 9
	var dead = _player(0, 1)
	dead.hp_cur = 0          # the would-be lowest_hp target is down
	var living = _player(1, 40)
	var state = BattleStateScript.new([dead, enemy, living], 0)
	var act = EnemyBrain.choose_action(enemy, state, _rng([0]))
	assert_eq(act.target_ids, [1], "brain selects only living opponents (retargets off the dead)")

func test_caster_heals_lowest_hp_ally_only_when_ally_down():
	# healer_bot: mend gated on ally_down -> lowest_hp_ally; else enemy_strike.
	var healer = Fx.enemy(_db, "healer_bot")
	healer.id = 0
	var ally_hurt = Fx.enemy(_db, "brute")
	ally_hurt.id = 1
	ally_hurt.hp_cur = 10
	var ally_dead = Fx.enemy(_db, "brute")
	ally_dead.id = 2
	ally_dead.hp_cur = 0     # triggers ally_down condition
	var foe = _player(3, 100)
	var state = BattleStateScript.new([healer, ally_hurt, ally_dead, foe], 0)
	# mend is eligible (ally_down true); pick index 0 -> mend, target lowest_hp living ally.
	var act = EnemyBrain.choose_action(healer, state, _rng([0]))
	assert_eq(act.ability_id, "mend", "caster heals when an ally is down")
	assert_eq(act.target_ids, [1], "lowest_hp_ally targets the hurt living ally (id 1)")

func test_caster_attacks_when_no_ally_is_down():
	var healer = Fx.enemy(_db, "healer_bot")
	healer.id = 0
	var ally = Fx.enemy(_db, "brute")
	ally.id = 1
	var foe = _player(2, 100)
	var state = BattleStateScript.new([healer, ally, foe], 0)
	# Only enemy_strike eligible -> single weight; index 0.
	var act = EnemyBrain.choose_action(healer, state, _rng([0]))
	assert_eq(act.ability_id, "enemy_strike", "caster attacks when no ally needs healing")
	assert_eq(act.target_ids, [2], "attacks the lone opponent")
