## battle_event.gd — the typed BattleEvent vocabulary (ADR-0004).
##
## Pure, headless. Events are emitted by BattleEngine as plain Dictionaries keyed by a
## stable `type` String drawn from the constants below. Dictionaries are chosen over a
## class instance so the event stream is trivially comparable/serializable in tests
## (reproducibility = two runs produce equal event arrays) and renderable by the Round-3
## scene layer without coupling to engine internals. The constants ARE the type contract.
class_name BattleEvent
extends RefCounted

const BATTLE_START := "battle_start"
const TURN_READY := "turn_ready"      # a combatant's gauge filled (controller opens UI)
const TURN_START := "turn_start"      # the combatant's turn begins (after cooldown/status tick)
const ACTION := "action"              # an action is being resolved
const HIT := "hit"                    # damage landed
const MISS := "miss"                  # accuracy roll failed
const HEAL := "heal"
const STATUS_APPLY := "status_apply"
const STATUS_TICK := "status_tick"    # DoT/regen tick
const STATUS_EXPIRE := "status_expire"
const RESOURCE_SPEND := "resource_spend"
const SONGSICK := "songsick"          # Breath overspend penalty applied
const PACIFY := "pacify"              # Quiet the Hollow
const DEFEND := "defend"
const FIZZLE := "fizzle"              # action had no valid target / could not resolve
const RETARGET := "retarget"          # queued target was down; retargeted at resolution
const COMBATANT_DOWN := "combatant_down"
const FLEE := "flee"
const BATTLE_OVER := "battle_over"

## Build an event dict. Extra fields are merged into the result.
static func make(type: String, data: Dictionary = {}) -> Dictionary:
	var e := {"type": type}
	for k in data:
		e[k] = data[k]
	return e
