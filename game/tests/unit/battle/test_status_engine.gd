## test_status_engine.gd — apply/tick/expire, stack rules, stat mods, Songsickness.
extends GutTest

const Fx = preload("res://tests/helpers/battle_fixtures.gd")
const StatusEngine = preload("res://src/battle/status_engine.gd")

var _db

func before_all():
	_db = Fx.content()

func after_all():
	if _db != null:
		_db.free()

func _c(stats: Dictionary = {"hp": 100}):
	return Fx.combatant(stats)

func test_dot_ticks_the_right_total_then_expires():
	var c = _c({"hp": 100})
	StatusEngine.apply(c, _db.status("poison"))   # 10 dmg/turn, 3 turns
	var total = 0
	for _i in 3:
		for ev in StatusEngine.tick(c):
			total += -int(ev.get("hp_delta", 0)) if int(ev.get("hp_delta", 0)) < 0 else 0
	assert_eq(total, 30, "poison ticks 10 x 3 = 30 total")
	assert_eq(c.hp_cur, 70, "hp reduced by exactly the DoT total")
	assert_false(c.has_status("poison"), "status expired after its duration")
	# A further tick does nothing.
	var hp_before = c.hp_cur
	StatusEngine.tick(c)
	assert_eq(c.hp_cur, hp_before, "no effect once expired")

func test_regen_heals_capped_at_max():
	var c = _c({"hp": 100})
	c.hp_cur = 80
	StatusEngine.apply(c, _db.status("regen"))   # +15/turn
	StatusEngine.tick(c)
	assert_eq(c.hp_cur, 95, "regen heals +15")
	StatusEngine.tick(c)
	assert_eq(c.hp_cur, 100, "regen is capped at max_hp")

func test_buff_changes_attack_stat():
	var c = _c({"hp": 100, "atk": 20})
	assert_eq(c.stat("ATK"), 20, "base ATK")
	StatusEngine.apply(c, _db.status("attack_up"))   # x1.5
	assert_eq(c.stat("ATK"), 30, "attack_up => 20 * 1500/1000 = 30")

func test_debuff_changes_defense_stat_and_reverts_on_expiry():
	var c = _c({"hp": 100, "def": 20})
	StatusEngine.apply(c, _db.status("defense_down"))   # x0.5, 3 turns
	assert_eq(c.stat("DEF"), 10, "defense_down => 20 * 500/1000 = 10")
	for _i in 3:
		StatusEngine.tick(c)
	assert_false(c.has_status("defense_down"), "debuff expired")
	assert_eq(c.stat("DEF"), 20, "stat reverts to base after expiry")

func test_stack_rule_stacks_dot():
	var c = _c({"hp": 100})
	StatusEngine.apply(c, _db.status("poison"))
	StatusEngine.apply(c, _db.status("poison"))   # STACK => stacks 2
	var inst = c.statuses[0]
	assert_eq(int(inst["stacks"]), 2, "poison stacked to 2")
	StatusEngine.tick(c)
	assert_eq(c.hp_cur, 80, "stacked poison ticks 10 * 2 = 20")

func test_refresh_rule_does_not_stack():
	var c = _c({"hp": 100})
	StatusEngine.apply(c, _db.status("regen"))
	StatusEngine.tick(c)   # remaining 3 -> 2
	StatusEngine.apply(c, _db.status("regen"))   # REFRESH back to 3
	var inst = c.statuses[0]
	assert_eq(int(inst["stacks"]), 1, "refresh keeps a single stack")
	assert_eq(int(inst["remaining"]), 3, "refresh resets the duration")

func test_songsickness_blocks_breath_then_clears_on_expiry():
	var c = _c({"hp": 100})
	c.resources["BREATH"] = 5
	StatusEngine.apply(c, _db.status("songsick"))
	assert_true(c.blocked_resources.get("BREATH", false), "songsick blocks BREATH on apply")
	assert_eq(int(_db.status("songsick").get("atb_modifier_permille", 1000)), 700,
		"songsick carries an integer permille atb penalty (read by TurnScheduler)")
	for _i in 3:
		StatusEngine.tick(c)
	assert_false(c.has_status("songsick"), "songsick expired")
	assert_false(c.blocked_resources.get("BREATH", false), "BREATH unblocked on expiry")

func test_cleanse_removes_debuffs_only():
	var c = _c({"hp": 100})
	StatusEngine.apply(c, _db.status("poison"))      # ailment
	StatusEngine.apply(c, _db.status("regen"))       # buff
	var removed = StatusEngine.cleanse(c, 1)
	assert_eq(removed, ["poison"], "cleanse removes the ailment, not the buff")
	assert_true(c.has_status("regen"), "buff survives cleanse")
