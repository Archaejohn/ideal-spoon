## level_system.gd — XP -> level + per-level stat growth (ADR-0004 / ADR-0007).
##
## Pure, static, headless, INTEGER-ONLY (no floats) so leveling is deterministic and unit-
## testable. Reads a data-authored level_curve record (ADR-0007 schema):
##   - max_level          : level cap.
##   - xp_to_next         : formula descriptor for XP needed at level L -> L+1.
##                          { type:"poly", base, factor, exp } => base + factor * L^exp
##                          { type:"linear", base, factor }     => base + factor * L
##   - growth_per_level   : integer added to each stat per level gained.
##   - growth_overrides   : { "<level>": { stat:int } } — REPLACES that level's growth for
##                          the named stats (hand-tuned breakpoints).
##
## XP model: `total` is cumulative XP. Thresholds accumulate xp_to_next(1)+...+xp_to_next(L-1)
## to reach level L. Thresholds are strictly monotonic (xp_to_next >= 1 enforced).
class_name LevelSystem
extends RefCounted

## XP required to go from `level` to `level+1` for this curve. Integer.
static func xp_to_next(level: int, curve: Dictionary) -> int:
	var f: Dictionary = curve.get("xp_to_next", {})
	var base = int(f.get("base", 0))
	var factor = int(f.get("factor", 0))
	match str(f.get("type", "poly")):
		"poly":
			return maxi(1, base + factor * _ipow(level, int(f.get("exp", 2))))
		"linear":
			return maxi(1, base + factor * level)
	return maxi(1, base)

## Cumulative XP needed to BE at `level` (xp at level 1 = 0). Integer, monotonic.
static func total_xp_for_level(level: int, curve: Dictionary) -> int:
	var max_level = int(curve.get("max_level", 99))
	var lvl = clampi(level, 1, max_level)
	var acc = 0
	for L in range(1, lvl):
		acc += xp_to_next(L, curve)
	return acc

## The level a given cumulative `total` XP reaches (clamped to max_level).
static func level_for_total_xp(total: int, curve: Dictionary) -> int:
	var max_level = int(curve.get("max_level", 99))
	var level = 1
	var acc = 0
	while level < max_level:
		var need = xp_to_next(level, curve)
		if total >= acc + need:
			acc += need
			level += 1
		else:
			break
	return level

## Stats at a given `level`, starting from `base_stats` (the level-1 stats), applying
## growth_per_level for each level gained, with growth_overrides taking precedence.
static func stats_at_level(base_stats: Dictionary, level: int, curve: Dictionary) -> Dictionary:
	var max_level = int(curve.get("max_level", 99))
	var lvl = clampi(level, 1, max_level)
	var growth: Dictionary = curve.get("growth_per_level", {})
	var overrides: Dictionary = curve.get("growth_overrides", {})
	var out: Dictionary = {}
	for stat in base_stats:
		out[stat] = int(base_stats[stat])
	for L in range(2, lvl + 1):
		var ov = overrides.get(str(L), {})
		for stat in growth:
			var inc = int(ov[stat]) if (ov is Dictionary and ov.has(stat)) else int(growth[stat])
			out[stat] = int(out.get(stat, 0)) + inc
		# overrides may add a stat not present in growth_per_level.
		if ov is Dictionary:
			for stat in ov:
				if not growth.has(stat):
					out[stat] = int(out.get(stat, 0)) + int(ov[stat])
	return out

## Grant `gained` XP to a member state {xp, level, ...} against `curve`. Returns a NEW dict
## (pure) describing the result; callers persist it. Does not mutate the input.
static func grant_xp(member_state: Dictionary, gained: int, curve: Dictionary) -> Dictionary:
	var new_total = maxi(0, int(member_state.get("xp", 0)) + maxi(0, gained))
	var old_level = int(member_state.get("level", 1))
	var new_level = level_for_total_xp(new_total, curve)
	return {
		"xp": new_total,
		"level": new_level,
		"leveled_up": new_level > old_level,
		"levels_gained": maxi(0, new_level - old_level),
	}

# --- helpers ---

static func _ipow(base: int, exp: int) -> int:
	var r = 1
	for _i in maxi(0, exp):
		r *= base
	return r
