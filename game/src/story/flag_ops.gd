## flag_ops.gd — the closed effect-op interpreter (ADR-0003).
##
## Pure & static. Applies the ONLY accepted ops a beat/branch-option may declare in data,
## in array order, against a FlagStore:
##   SET            set `flag` true (or false via value:false); optional `if_flag` guard.
##   INC_UNITY      +1 for a unique `source_id` (required), gated by `if_flag`; idempotent
##                  per source and a no-op once locked (enforced by FlagStore).
##   LOCK_ENDINGS   freeze UNITY + underlying flag set (A3-13).
##   SET_FINAL_CHOICE  record FINAL_CHOICE enum (A4-06) from `choice` string.
##   RECORD_ENDING  derive + store ENDING via EndingResolver (A4-07).
## An unknown op is a fatal validation error (returned as Result.err).
class_name FlagOps
extends RefCounted

const VALID_OPS := ["SET", "INC_UNITY", "LOCK_ENDINGS", "SET_FINAL_CHOICE", "RECORD_ENDING"]

## Apply one effect dict to `store`. Returns Result (ok/err with a precise message).
static func apply_effect(store: FlagStore, effect: Dictionary) -> Result:
	var op := str(effect.get("op", ""))
	match op:
		"SET":
			var flag := str(effect.get("flag", ""))
			if flag == "":
				return Result.make_err("SET op missing 'flag'")
			if not _guard_passes(store, effect):
				return Result.make_ok()
			store.set_flag(flag, bool(effect.get("value", true)))
			return Result.make_ok()
		"INC_UNITY":
			var source_id := str(effect.get("source_id", ""))
			if source_id == "":
				return Result.make_err("INC_UNITY op missing 'source_id'")
			if not _guard_passes(store, effect):
				return Result.make_ok()
			store.add_unity_source(source_id, int(effect.get("n", 1)))
			return Result.make_ok()
		"LOCK_ENDINGS":
			store.lock_endings()
			return Result.make_ok()
		"SET_FINAL_CHOICE":
			var choice_str := str(effect.get("choice", ""))
			var choice := Ids.final_choice_from_str(choice_str)
			if choice == Ids.FinalChoice.NONE:
				return Result.make_err("SET_FINAL_CHOICE has invalid choice '%s'" % choice_str)
			store.set_final_choice(choice)
			return Result.make_ok()
		"RECORD_ENDING":
			var ending := EndingResolver.resolve(store.view(), store.final_choice())
			store.set_ending(ending)
			return Result.make_ok()
		_:
			return Result.make_err("unknown effect op '%s' (valid: %s)" % [op, str(VALID_OPS)])

## Apply an ordered list of effects. Stops and returns the first error encountered.
static func apply_effects(store: FlagStore, effects: Array) -> Result:
	for effect in effects:
		var r := apply_effect(store, effect)
		if r.is_err():
			return r
	return Result.make_ok()

static func _guard_passes(store: FlagStore, effect: Dictionary) -> bool:
	if not effect.has("if_flag"):
		return true
	return store.get_flag(str(effect["if_flag"]))
