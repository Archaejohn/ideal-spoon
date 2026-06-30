## damage_formula.gd — deterministic damage / heal / accuracy / crit (ADR-0004 / ADR-0009).
##
## Pure, static, headless. ALL randomness comes from the injected `rng` (an RngService
## .RngStream from the "battle" stream, or a FakeRng in tests). Integer math throughout —
## no float drift across platforms; every probability is integer permille (ADR-0009 §1).
## Same seed + same combatant stats => identical result, bit for bit.
##
## Draw discipline (so a saved cursor reproduces a fight exactly):
##   - compute(): accuracy roll FIRST. On MISS, that is the ONLY draw. On HIT, exactly two
##     more draws follow: variance, then crit. (miss => 1 draw; hit => 3 draws.)
##   - compute_heal(): exactly one draw (variance).
class_name DamageFormula
extends RefCounted

const DEFAULT_CRIT_PERMILLE = 50    # 5% baseline crit
const VARIANCE_LOW = 95
const VARIANCE_HIGH = 105

## Resolve an offensive ability hit. Returns:
##   miss -> { hit=false }
##   hit  -> { hit=true, amount>=1 (int), crit:bool, weak:bool, resist:bool }
static func compute(attacker, defender, ability: Dictionary, rng) -> Dictionary:
	var accuracy = int(ability.get("accuracy", 100))
	# accuracy is 0..100 -> permille (0..1000)
	if not rng.chance_permille(accuracy * 10):
		return {"hit": false}

	var power_stat = str(ability.get("power_stat", "ATK"))
	var defense_stat = str(ability.get("defense_stat", "DEF"))
	var base = attacker.stat(power_stat)
	var power = int(ability.get("power", 100))
	var raw = maxi(1, (base * power) / 100 - defender.stat(defense_stat))

	var variance = rng.randi_range(VARIANCE_LOW, VARIANCE_HIGH)   # +/-5%
	var dmg = (raw * variance) / 100

	var weak = _is_weakness(defender, ability)
	var resist = _is_resistance(defender, ability)
	if weak:
		dmg = (dmg * 150) / 100
	elif resist:
		dmg = (dmg * 50) / 100

	# crit roll is ALWAYS taken on a hit (keeps the cursor deterministic).
	var is_crit = rng.chance_permille(_crit_permille(attacker, ability))
	if is_crit:
		dmg = (dmg * 200) / 100

	if defender.defending:
		dmg = (dmg * 50) / 100

	return {"hit": true, "amount": maxi(1, dmg), "crit": is_crit, "weak": weak, "resist": resist}

## Resolve a heal. Returns { hit=true, amount>=1 (int) }. Exactly one draw (variance).
static func compute_heal(healer, _target, ability: Dictionary, rng) -> Dictionary:
	var power_stat = str(ability.get("power_stat", "MAG"))
	var base = healer.stat(power_stat)
	var power = int(ability.get("power", 100))
	var amount = (base * power) / 100
	var variance = rng.randi_range(VARIANCE_LOW, VARIANCE_HIGH)
	amount = (amount * variance) / 100
	return {"hit": true, "amount": maxi(1, amount)}

# --- pure helpers ---

static func _crit_permille(_attacker, ability: Dictionary) -> int:
	return clampi(int(ability.get("crit_permille", DEFAULT_CRIT_PERMILLE)), 0, 1000)

static func _is_weakness(defender, ability: Dictionary) -> bool:
	var el = str(ability.get("element", ""))
	return el != "" and defender.weaknesses.has(el)

static func _is_resistance(defender, ability: Dictionary) -> bool:
	var el = str(ability.get("element", ""))
	return el != "" and defender.resistances.has(el)
