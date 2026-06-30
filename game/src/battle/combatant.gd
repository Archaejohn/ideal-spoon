## combatant.gd — battle-scoped runtime struct for one fighter (ADR-0004).
##
## Pure, headless, RefCounted. A Combatant is a COPY built from a ContentDB enemy def or
## from a GameState party member (the engine never mutates persistent party state —
## ADR-0004 "Leveling"). All stats are integers. Stat reads apply active status stat
## modifiers (integer permille) so buffs/debuffs are deterministic (ADR-0009 §1).
class_name Combatant
extends RefCounted

enum Side { PLAYER, ENEMY }

var id: int = -1                   # stable battle index (tie-break key, never reused)
var name: String = ""
var side: int = Side.PLAYER
var source_id: String = ""         # party member id or enemy id (for rewards/loot)

# Base stats (integers): hp/atk/def/mag/res/spd. `hp` here is the MAX; live hp is `hp_cur`.
var stats: Dictionary = {"hp": 1, "atk": 0, "def": 0, "mag": 0, "res": 0, "spd": 1}
var max_hp: int = 1
var hp_cur: int = 1

var atb: int = 0                   # integer ATB gauge [0, ATB_MAX]; carry-over preserved
var resources: Dictionary = {}     # "BREATH"/"POMP" -> int
var blocked_resources: Dictionary = {}  # resource -> true (e.g. Songsickness blocks BREATH)
var cooldowns: Dictionary = {}     # ability_id -> turns remaining

var statuses: Array = []           # Array of status-instance dicts {id, def, remaining, stacks}
var weaknesses: Array = []         # element/resonance tags
var resistances: Array = []
var tags: Array = []               # e.g. "machine" (for vs_machine abilities)

var enemy_def: Dictionary = {}     # full enemy record (carries the `ai` policy block)
var ability_ids: Array = []        # ability ids this combatant may use

var pacified: bool = false         # Wren's QUIET_THE_HOLLOW — out of the fight, not dead
var defending: bool = false        # halves incoming damage until this combatant's next turn
var threat: int = 0                # for `highest_threat` targeting
var announced_down: bool = false   # engine bookkeeping: COMBATANT_DOWN emitted once

func is_alive() -> bool:
	return hp_cur > 0 and not pacified

func is_down() -> bool:
	return not is_alive()

## Effective integer value of a named stat (ATK/MAG/DEF/RES/SPD/HP), with active status
## `stat_mod` permille multipliers applied multiplicatively. Deterministic integer math.
func stat(stat_name: String) -> int:
	var key = stat_name.to_lower()
	var base = int(stats.get(key, 0))
	var permille = 1000
	for s in statuses:
		var sm = (s["def"] as Dictionary).get("stat_mod", {})
		if sm is Dictionary and str(sm.get("stat", "")).to_lower() == key:
			permille = permille * int(sm.get("permille", 1000)) / 1000
	var defended = 1
	return maxi(0, base * permille / 1000 * defended)

## Spend a resource; returns the amount actually spent (clamped to what's available).
func spend_resource(resource: String, amount: int) -> int:
	var have = int(resources.get(resource, 0))
	var spent = mini(have, amount)
	resources[resource] = have - spent
	return spent

func has_status(status_id: String) -> bool:
	for s in statuses:
		if str(s["id"]) == status_id:
			return true
	return false
