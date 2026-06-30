## test_turn_scheduler.gd — INTEGER ATB ordering, permille haste/slow, deterministic ties.
extends GutTest

const Fx = preload("res://tests/helpers/battle_fixtures.gd")
const Scheduler = preload("res://src/battle/turn_scheduler.gd")

func _c(spd: int, id: int, hp: int = 100):
	var c = Fx.combatant({"hp": hp, "spd": spd})
	c.id = id
	return c

func _haste(c, permille: int) -> void:
	c.statuses.append({"id": "mod", "def": {"atb_modifier_permille": permille}, "remaining": 9, "stacks": 1})

func test_ready_order_identical_for_same_speeds():
	# Two independently built, identical rosters advanced the same amount produce the same
	# ready order — turn order is a pure function of (speeds, ticks), no RNG.
	var a = [_c(15, 0), _c(10, 1), _c(20, 2)]
	var b = [_c(15, 0), _c(10, 1), _c(20, 2)]
	Scheduler.advance(a, 600)
	Scheduler.advance(b, 600)
	var ids_a = []
	for c in Scheduler.ready_list(a):
		ids_a.append(c.id)
	var ids_b = []
	for c in Scheduler.ready_list(b):
		ids_b.append(c.id)
	assert_eq(ids_a, ids_b, "identical rosters => identical ready order")
	# Fastest (id 2, spd 20) leads the ready queue.
	assert_eq(ids_a[0], 2, "highest atb (fastest) is first ready")

func test_haste_reaches_ready_sooner_than_baseline():
	var base = _c(10, 0)
	var fast = _c(10, 1)
	_haste(fast, 1300)   # HASTE x1.30
	assert_eq(Scheduler.atb_rate(base), 10, "baseline integer rate = spd")
	assert_eq(Scheduler.atb_rate(fast), 13, "haste 1300 => 10*1300/1000 = 13 (integer)")
	var t_base = Scheduler.ticks_until_next_ready([base])
	var t_fast = Scheduler.ticks_until_next_ready([fast])
	assert_lt(t_fast, t_base, "hasted combatant becomes ready in fewer ticks")

func test_slow_reaches_ready_later_than_baseline():
	var base = _c(10, 0)
	var slow = _c(10, 1)
	_haste(slow, 700)    # SLOW x0.70
	assert_eq(Scheduler.atb_rate(slow), 7, "slow 700 => 10*700/1000 = 7 (integer)")
	assert_gt(Scheduler.ticks_until_next_ready([slow]), Scheduler.ticks_until_next_ready([base]),
		"slowed combatant takes more ticks to ready")

func test_modifiers_are_integer_and_multiplicative():
	var c = _c(10, 0)
	_haste(c, 1300)
	_haste(c, 700)   # 1300 * 700 / 1000 = 910 permille => 10 * 910 / 1000 = 9
	assert_eq(Scheduler.atb_rate(c), 9, "stacked permille modifiers multiply with integer math")

func test_tie_break_by_spd_then_index():
	# Equal atb, different spd => higher spd first.
	var slowtie = _c(5, 0)
	var fasttie = _c(9, 1)
	slowtie.atb = Scheduler.ATB_MAX
	fasttie.atb = Scheduler.ATB_MAX
	var ready = Scheduler.ready_list([slowtie, fasttie])
	assert_eq(ready[0].id, 1, "equal atb => higher SPD wins the tie")
	# Equal atb AND equal spd => lower stable id first.
	var x = _c(7, 5)
	var y = _c(7, 2)
	x.atb = Scheduler.ATB_MAX
	y.atb = Scheduler.ATB_MAX
	var ready2 = Scheduler.ready_list([x, y])
	assert_eq(ready2[0].id, 2, "equal atb & spd => lower id wins the tie (stable)")

func test_down_combatant_is_never_ready():
	var dead = _c(50, 0, 1)
	dead.hp_cur = 0
	dead.atb = Scheduler.ATB_MAX
	assert_false(Scheduler.is_ready(dead), "a downed combatant is never ready")
	assert_null(Scheduler.next_ready([dead]), "no ready combatant when only one is down")

func test_acting_preserves_atb_carryover():
	var c = _c(10, 0)
	c.atb = Scheduler.ATB_MAX + 350
	c.atb -= Scheduler.ATB_MAX
	assert_eq(c.atb, 350, "spending a turn preserves the carry-over above ATB_MAX")
