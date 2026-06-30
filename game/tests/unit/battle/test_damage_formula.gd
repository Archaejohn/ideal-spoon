## test_damage_formula.gd — integer dmg/heal, accuracy/miss, weakness/crit, min-1, determinism.
extends GutTest

const Fx = preload("res://tests/helpers/battle_fixtures.gd")
const DamageFormula = preload("res://src/battle/damage_formula.gd")
const FakeRng = preload("res://tests/helpers/fake_rng.gd")
const RngServiceScript = preload("res://src/core/rng_service.gd")

func _atk(atk: int):
	return Fx.combatant({"hp": 100, "atk": atk, "mag": atk})

func _def(def_val: int, opts: Dictionary = {}):
	return Fx.combatant({"hp": 100, "def": def_val, "res": def_val}, opts)

func _ability(power: int, extra: Dictionary = {}) -> Dictionary:
	var a = {"power_stat": "ATK", "defense_stat": "DEF", "power": power, "accuracy": 100, "crit_permille": 0}
	for k in extra:
		a[k] = extra[k]
	return a

func _rng(chances: Array, ranges: Array):
	var r = FakeRng.new()
	r.chances = chances.duplicate()
	r.ranges = ranges.duplicate()
	return r

func test_accuracy_zero_always_misses():
	var r = _rng([], [])   # default chance_permille(0) => false
	var res = DamageFormula.compute(_atk(100), _def(0), _ability(100, {"accuracy": 0}), r)
	assert_false(res["hit"], "accuracy 0 => miss")
	assert_eq(r.get_cursor(), 1, "a miss consumes exactly one draw (accuracy)")

func test_accuracy_hundred_always_hits():
	var r = _rng([], [100])   # default chance_permille(1000) => true; variance 100; crit default(0)=>false
	var res = DamageFormula.compute(_atk(100), _def(0), _ability(100), r)
	assert_true(res["hit"], "accuracy 100 => hit")
	assert_eq(res["amount"], 100, "raw 100 * variance 100% = 100")
	assert_eq(r.get_cursor(), 3, "a hit consumes three draws (accuracy, variance, crit)")

func test_crit_doubles_damage():
	var no_crit = DamageFormula.compute(_atk(100), _def(0), _ability(100), _rng([true, false], [100]))
	var crit = DamageFormula.compute(_atk(100), _def(0), _ability(100), _rng([true, true], [100]))
	assert_eq(no_crit["amount"], 100, "no crit => base")
	assert_eq(crit["amount"], 200, "crit => x2")
	assert_true(crit["crit"], "crit flag set")

func test_weakness_multiplies_by_150_percent():
	var defender = _def(0, {"weaknesses": ["resonance"]})
	var ab = _ability(100, {"element": "resonance"})
	var res = DamageFormula.compute(_atk(100), defender, ab, _rng([true, false], [100]))
	assert_eq(res["amount"], 150, "weakness => x1.5")
	assert_true(res["weak"], "weak flag set")

func test_resistance_halves_damage():
	var defender = _def(0, {"resistances": ["physical"]})
	var ab = _ability(100, {"element": "physical"})
	var res = DamageFormula.compute(_atk(100), defender, ab, _rng([true, false], [100]))
	assert_eq(res["amount"], 50, "resistance => x0.5")

func test_damage_never_below_one():
	# Huge defense floors raw at 1; min-1 after variance/crit too.
	var res = DamageFormula.compute(_atk(10), _def(9999), _ability(100), _rng([true, false], [95]))
	assert_eq(res["amount"], 1, "damage floors at 1 even against overwhelming defense")

func test_heal_is_positive_integer():
	var res = DamageFormula.compute_heal(Fx.combatant({"hp": 100, "mag": 50}), _atk(0),
		{"power_stat": "MAG", "power": 100, "accuracy": 100}, _rng([], [100]))
	assert_eq(res["amount"], 50, "heal = mag 50 * power 100% * variance 100%")

func test_deterministic_for_fixed_seed_via_cursor_replay():
	# Same battle RngStream replayed from the same cursor reproduces identical results.
	var svc = autofree(RngServiceScript.new())
	svc.seed_run(20260630)
	var s = svc.stream("battle")
	var attacker = _atk(60)
	var defender = _def(10)
	var ab = _ability(120)
	var start = s.get_cursor()
	var first = []
	for _i in 8:
		first.append(DamageFormula.compute(attacker, defender, ab, s))
	s.set_cursor(start)
	var second = []
	for _i in 8:
		second.append(DamageFormula.compute(attacker, defender, ab, s))
	assert_eq(first, second, "same seed+cursor => identical damage sequence")
