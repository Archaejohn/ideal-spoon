## test_level_system.gd — data-authored XP curve, monotonic thresholds, integer stat growth.
extends GutTest

const Fx = preload("res://tests/helpers/battle_fixtures.gd")
const LevelSystem = preload("res://src/leveling/level_system.gd")

var _curve: Dictionary
var _db

func before_all():
	_db = Fx.content()
	_curve = _db.level_curve("test_curve")

func after_all():
	if _db != null:
		_db.free()

func test_xp_to_next_matches_poly_formula():
	# xp(L) = base 50 + factor 25 * L^exp 2
	assert_eq(LevelSystem.xp_to_next(1, _curve), 75, "L1->2 = 50 + 25*1 = 75")
	assert_eq(LevelSystem.xp_to_next(2, _curve), 150, "L2->3 = 50 + 25*4 = 150")
	assert_eq(LevelSystem.xp_to_next(3, _curve), 275, "L3->4 = 50 + 25*9 = 275")

func test_thresholds_are_strictly_monotonic():
	var prev = -1
	for L in range(1, 20):
		var t = LevelSystem.total_xp_for_level(L, _curve)
		assert_gt(t, prev, "cumulative XP threshold strictly increases at L=%d" % L)
		prev = t

func test_level_for_total_xp_boundaries():
	assert_eq(LevelSystem.level_for_total_xp(0, _curve), 1, "0 xp => level 1")
	assert_eq(LevelSystem.level_for_total_xp(74, _curve), 1, "just below first threshold => level 1")
	assert_eq(LevelSystem.level_for_total_xp(75, _curve), 2, "exactly the threshold => level 2")
	assert_eq(LevelSystem.level_for_total_xp(224, _curve), 2, "just below second threshold => level 2")
	assert_eq(LevelSystem.level_for_total_xp(225, _curve), 3, "75+150 => level 3")

func test_level_caps_at_max_level():
	var huge = 999999999
	assert_eq(LevelSystem.level_for_total_xp(huge, _curve), int(_curve["max_level"]),
		"level clamps at max_level")

func test_stats_grow_per_level():
	var base = {"hp": 80, "atk": 20, "def": 8, "mag": 6, "res": 6, "spd": 12}
	assert_eq(LevelSystem.stats_at_level(base, 1, _curve), base, "level 1 == base stats")
	var l2 = LevelSystem.stats_at_level(base, 2, _curve)
	assert_eq(l2["hp"], 86, "hp +6 per level")
	assert_eq(l2["mag"], 9, "mag +3 per level")

func test_growth_override_breakpoint_applied():
	var base = {"hp": 80, "atk": 20, "def": 8, "mag": 6, "res": 6, "spd": 12}
	var l9 = LevelSystem.stats_at_level(base, 9, _curve)
	var l10 = LevelSystem.stats_at_level(base, 10, _curve)
	# Override "10": {"mag": 5} REPLACES the normal +3 mag growth for that level.
	assert_eq(l10["mag"] - l9["mag"], 5, "level-10 override grows mag by 5, not 3")
	var l24 = LevelSystem.stats_at_level(base, 24, _curve)
	var l25 = LevelSystem.stats_at_level(base, 25, _curve)
	assert_eq(l25["hp"] - l24["hp"], 12, "level-25 override grows hp by 12, not 6")

func test_grant_xp_reports_level_up():
	var member = {"id": "hero", "level": 1, "xp": 0}
	var r = LevelSystem.grant_xp(member, 75, _curve)
	assert_eq(r["xp"], 75, "xp accumulates")
	assert_eq(r["level"], 2, "crossing the threshold levels up")
	assert_true(r["leveled_up"], "leveled_up flag set")
	assert_eq(member["level"], 1, "grant_xp is pure (input unchanged)")
