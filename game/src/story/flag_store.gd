## flag_store.gd — boolean flags + integer UNITY + enum-valued story choices (ADR-0003).
##
## Pure, headless (no scene tree, no autoload). Holds the run's story state DATA and the
## invariants that protect it:
##   * UNITY is monotonic (only increments), range 0..8, idempotent per UNITY source_id,
##     and FROZEN once lock_endings() runs at A3-13.
##   * Derived flags (WARDEN_TRUTH_WHOLE / FACTIONS_UNITED) are NEVER stored here — they
##     are computed-on-read by FlagView (ADR-0003 §3.3).
##   * FINAL_CHOICE / ENDING are enum scalars (ids.gd), kept in a separate enum store and
##     serialized under `story.choices` (ADR-0005 §d) — never as booleans.
class_name FlagStore
extends RefCounted

const UNITY_MAX := 8

var _flags: Dictionary = {}                 # name(String) -> bool
var _unity: int = 0
var _unity_sources_applied: Array = []      # source_ids already counted (idempotency)
var _locked: bool = false
var _final_choice: int = Ids.FinalChoice.NONE
var _ending: int = Ids.EndingId.NONE

# --- booleans ---

func get_flag(name: String) -> bool:
	return bool(_flags.get(name, false))

func set_flag(name: String, value: bool = true) -> void:
	if value:
		_flags[name] = true
	else:
		# Keep the map compact; absence == false.
		_flags.erase(name)

func all_flags() -> Dictionary:
	return _flags.duplicate(true)

# --- UNITY ---

func unity() -> int:
	return _unity

## Add +1 for a unique source_id (idempotent per source). No-op once locked, when the
## source was already counted, or when at the 0..8 cap (ADR-0003).
func add_unity_source(source_id: String, n: int = 1) -> void:
	if _locked:
		return
	if _unity_sources_applied.has(source_id):
		return
	_unity_sources_applied.append(source_id)
	_unity = clampi(_unity + n, 0, UNITY_MAX)

func unity_sources_applied() -> Array:
	return _unity_sources_applied.duplicate()

## A3-13: freeze UNITY and the underlying flag set. Derived flags stay computed-on-read.
func lock_endings() -> void:
	_locked = true

func is_locked() -> bool:
	return _locked

# --- enum-valued story state (NOT booleans) ---

func set_final_choice(choice: int) -> void:
	_final_choice = choice

func final_choice() -> int:
	return _final_choice

func set_ending(e: int) -> void:
	_ending = e

func ending() -> int:
	return _ending

## Hard-coded derived, NON-gating value (ADR-0003): the closed op vocabulary cannot
## express an enum-membership test, so this lives here. Never read by EndingResolver.
func bramble_sacrifice() -> bool:
	return _final_choice == Ids.FinalChoice.SHARE \
		or _final_choice == Ids.FinalChoice.SLEEP \
		or _final_choice == Ids.FinalChoice.TAKE

# --- typed read facade for the resolver ---

func view() -> FlagView:
	return FlagView.from_store(self)

# --- serialization (ADR-0005 §d shape) ---

func to_dict() -> Dictionary:
	return {
		"flags": _flags.duplicate(true),
		"unity": _unity,
		"unity_sources_applied": _unity_sources_applied.duplicate(),
		"endings_locked": _locked,
		"choices": {
			"final_choice": Ids.final_choice_to_str(_final_choice),
			"ending": Ids.ending_to_str(_ending),
		},
	}

func from_dict(d: Dictionary) -> void:
	_flags = (d.get("flags", {}) as Dictionary).duplicate(true)
	_unity = int(d.get("unity", 0))
	_unity_sources_applied = (d.get("unity_sources_applied", []) as Array).duplicate()
	_locked = bool(d.get("endings_locked", false))
	var choices: Dictionary = d.get("choices", {})
	_final_choice = Ids.final_choice_from_str(str(choices.get("final_choice", "NONE")))
	_ending = Ids.ending_from_str(str(choices.get("ending", "NONE")))
