## test_flag_ops.gd — the closed effect-op interpreter (ADR-0003).
extends GutTest

func _store() -> FlagStore:
	return FlagStore.new()

func test_set_op_sets_and_clears():
	var s := _store()
	var r := FlagOps.apply_effect(s, {"op": "SET", "flag": "RESONANT_REVEALED"})
	assert_false(r.is_err(), "SET ok")
	assert_true(s.get_flag("RESONANT_REVEALED"), "SET sets the flag true")
	FlagOps.apply_effect(s, {"op": "SET", "flag": "RESONANT_REVEALED", "value": false})
	assert_false(s.get_flag("RESONANT_REVEALED"), "SET value:false clears the flag")

func test_set_missing_flag_is_error():
	var s := _store()
	var r := FlagOps.apply_effect(s, {"op": "SET"})
	assert_true(r.is_err(), "SET without 'flag' is an error")

func test_if_flag_guard():
	var s := _store()
	# guard false → op skipped (still ok)
	var r1 := FlagOps.apply_effect(s, {"op": "SET", "flag": "X", "if_flag": "GATE"})
	assert_false(r1.is_err(), "guarded op returns ok even when skipped")
	assert_false(s.get_flag("X"), "guard false → SET skipped")
	# satisfy the guard, then it applies
	s.set_flag("GATE")
	FlagOps.apply_effect(s, {"op": "SET", "flag": "X", "if_flag": "GATE"})
	assert_true(s.get_flag("X"), "guard true → SET applies")

func test_inc_unity_and_idempotency():
	var s := _store()
	FlagOps.apply_effect(s, {"op": "INC_UNITY", "source_id": "u3_kestrel"})
	FlagOps.apply_effect(s, {"op": "INC_UNITY", "source_id": "u3_kestrel"})  # same source
	assert_eq(s.unity(), 1, "INC_UNITY idempotent per source_id")
	FlagOps.apply_effect(s, {"op": "INC_UNITY", "source_id": "u5_rookwise"})
	assert_eq(s.unity(), 2, "distinct source increments")

func test_inc_unity_missing_source_is_error():
	var s := _store()
	var r := FlagOps.apply_effect(s, {"op": "INC_UNITY"})
	assert_true(r.is_err(), "INC_UNITY without 'source_id' is an error")

func test_inc_unity_respects_if_flag():
	var s := _store()
	var r := FlagOps.apply_effect(s, {"op": "INC_UNITY", "source_id": "u1", "if_flag": "DID_IT"})
	assert_false(r.is_err(), "guarded INC_UNITY ok when skipped")
	assert_eq(s.unity(), 0, "INC_UNITY skipped when guard flag absent")

func test_unknown_op_is_error():
	var s := _store()
	var r := FlagOps.apply_effect(s, {"op": "FROBNICATE"})
	assert_true(r.is_err(), "unknown op is a fatal error")

func test_lock_endings_op_freezes_gating():
	var s := _store()
	FlagOps.apply_effect(s, {"op": "LOCK_ENDINGS"})
	assert_true(s.is_locked(), "LOCK_ENDINGS locks the store")
	FlagOps.apply_effect(s, {"op": "SET", "flag": "KESTREL_RECRUITED"})  # gating, post-lock
	assert_false(s.get_flag("KESTREL_RECRUITED"), "gating SET ignored after LOCK_ENDINGS")

func test_set_final_choice_valid_and_invalid():
	var s := _store()
	var ok := FlagOps.apply_effect(s, {"op": "SET_FINAL_CHOICE", "choice": "WAKE"})
	assert_false(ok.is_err(), "valid SET_FINAL_CHOICE ok")
	assert_eq(s.final_choice(), Ids.FinalChoice.WAKE, "final choice recorded")
	var bad := FlagOps.apply_effect(s, {"op": "SET_FINAL_CHOICE", "choice": "BANANA"})
	assert_true(bad.is_err(), "invalid choice string is an error")

func test_record_ending_resolves_via_resolver():
	# SLEEP and TAKE are always available, so they map deterministically to B and C.
	var s1 := _store()
	FlagOps.apply_effect(s1, {"op": "SET_FINAL_CHOICE", "choice": "SLEEP"})
	FlagOps.apply_effect(s1, {"op": "RECORD_ENDING"})
	assert_eq(s1.ending(), Ids.EndingId.B, "SLEEP → Ending B")

	var s2 := _store()
	FlagOps.apply_effect(s2, {"op": "SET_FINAL_CHOICE", "choice": "TAKE"})
	FlagOps.apply_effect(s2, {"op": "RECORD_ENDING"})
	assert_eq(s2.ending(), Ids.EndingId.C, "TAKE → Ending C")

func test_record_ending_share_when_factions_united():
	# Build a faithful FACTIONS_UNITED state, then SHARE → Ending A.
	var s := _store()
	s.set_flag("KESTREL_RECRUITED")
	s.set_flag("ORDER_ALLIED")
	for src in ["u1", "u2", "u3", "u4", "u6"]:
		s.add_unity_source(src)        # unity = 5
	assert_eq(s.unity(), 5, "precondition: unity 5")
	FlagOps.apply_effect(s, {"op": "SET_FINAL_CHOICE", "choice": "SHARE"})
	FlagOps.apply_effect(s, {"op": "RECORD_ENDING"})
	assert_eq(s.ending(), Ids.EndingId.A, "SHARE + factions_united → Ending A")

func test_apply_effects_applies_in_order_and_stops_on_error():
	var s := _store()
	var good := FlagOps.apply_effects(s, [
		{"op": "SET", "flag": "A"},
		{"op": "INC_UNITY", "source_id": "u1"},
		{"op": "SET", "flag": "B"},
	])
	assert_false(good.is_err(), "valid sequence ok")
	assert_true(s.get_flag("A") and s.get_flag("B"), "all SETs applied")
	assert_eq(s.unity(), 1, "INC applied")

	var s2 := _store()
	var bad := FlagOps.apply_effects(s2, [
		{"op": "SET", "flag": "FIRST"},
		{"op": "NOPE"},                       # error here
		{"op": "SET", "flag": "NEVER"},
	])
	assert_true(bad.is_err(), "sequence returns first error")
	assert_true(s2.get_flag("FIRST"), "effects before the error were applied")
	assert_false(s2.get_flag("NEVER"), "effects after the error were not applied")
