## turn_scheduler.gd — INTEGER permille ATB gauges & deterministic ready-order (ADR-0004/0009).
##
## Pure, static, headless, NO RNG. Turn order is an OUTCOME, so every number here is
## integer/fixed-point (scale = ATB_MAX for the gauge, permille for rate modifiers) — there
## are no floats anywhere in ATB advancement, guaranteeing identical turn order across
## Android/Chromebook/web (ADR-0009 §1).
##
## Model: each Combatant has `atb` in [0, ATB_MAX]. Per tick, `atb += rate(c)`, where
##   rate(c) = base_rate(SPD) * haste_permille / 1000
## and `haste_permille` is the product of every active status `atb_modifier_permille`
## (1000 = x1.00; SLOW 700, HASTE 1300, SONGSICK 700). When `atb >= ATB_MAX` the combatant
## is READY. On acting, `atb -= ATB_MAX` (carry-over preserved).
##
## Ready-order tie-break (documented, fully deterministic): higher `atb`, then higher SPD,
## then lower stable combatant `id`.
class_name TurnScheduler
extends RefCounted

const ATB_MAX = 10000

## Base ATB gain per tick from a SPD value. Linear & integer; min 1 so nobody stalls.
static func base_rate(spd: int) -> int:
	return maxi(1, spd)

## Effective integer ATB gain per tick for a combatant after status modifiers.
static func atb_rate(c) -> int:
	var permille = 1000
	for s in c.statuses:
		permille = permille * int((s["def"] as Dictionary).get("atb_modifier_permille", 1000)) / 1000
	return maxi(0, base_rate(c.stat("SPD")) * permille / 1000)

## Advance every living combatant's gauge by `dt_ticks`.
static func advance(combatants: Array, dt_ticks: int) -> void:
	for c in combatants:
		if c.is_down():
			continue
		c.atb += atb_rate(c) * maxi(0, dt_ticks)

static func is_ready(c) -> bool:
	return c.is_alive() and c.atb >= ATB_MAX

## All ready combatants, sorted by the documented tie-break (atb desc, spd desc, id asc).
static func ready_list(combatants: Array) -> Array:
	var ready: Array = []
	for c in combatants:
		if is_ready(c):
			ready.append(c)
	ready.sort_custom(Callable(TurnScheduler, "_cmp"))
	return ready

## The single highest-priority ready combatant, or null if none are ready.
static func next_ready(combatants: Array):
	var r = ready_list(combatants)
	return r[0] if r.size() > 0 else null

## Minimum whole ticks until SOME living combatant becomes ready (0 if one already is).
## Lets a headless run fast-forward deterministically to the next decision point.
static func ticks_until_next_ready(combatants: Array) -> int:
	var best = -1
	for c in combatants:
		if c.is_down():
			continue
		if c.atb >= ATB_MAX:
			return 0
		var rate = atb_rate(c)
		if rate <= 0:
			continue
		var need = ATB_MAX - c.atb
		var ticks = (need + rate - 1) / rate   # integer ceil
		if best < 0 or ticks < best:
			best = ticks
	return maxi(0, best)

static func _cmp(a, b) -> bool:
	if a.atb != b.atb:
		return a.atb > b.atb
	var sa: int = a.stat("SPD")
	var sb: int = b.stat("SPD")
	if sa != sb:
		return sa > sb
	return a.id < b.id
