## test_flag_store.gd — FlagStore behavior (ADR-0003).
extends GutTest

func _store() -> FlagStore:
	return FlagStore.new()

func test_set_get_flag():
	var s := _store()
	assert_false(s.get_flag("RESONANT_REVEALED"), "absent flag reads false")
	s.set_flag("RESONANT_REVEALED")
	assert_true(s.get_flag("RESONANT_REVEALED"), "set flag reads true")
	s.set_flag("RESONANT_REVEALED", false)
	assert_false(s.get_flag("RESONANT_REVEALED"), "clearing a flag reads false")

func test_unity_monotonic_and_capped():
	var s := _store()
	assert_eq(s.unity(), 0, "unity starts at 0")
	for i in 12:
		s.add_unity_source("u_%d" % i)
	assert_eq(s.unity(), FlagStore.UNITY_MAX, "unity caps at 8")

func test_unity_idempotent_per_source_id():
	var s := _store()
	s.add_unity_source("u3_kestrel")
	s.add_unity_source("u3_kestrel")    # same source again
	s.add_unity_source("u3_kestrel")
	assert_eq(s.unity(), 1, "same source_id counts once (no double-count)")
	s.add_unity_source("u5_rookwise")
	assert_eq(s.unity(), 2, "distinct source_id increments")
	assert_eq(s.unity_sources_applied().size(), 2, "ledger tracks applied sources")

func test_lock_freezes_unity():
	var s := _store()
	s.add_unity_source("u1")
	s.lock_endings()
	assert_true(s.is_locked(), "locked after lock_endings")
	s.add_unity_source("u2")             # should be ignored
	assert_eq(s.unity(), 1, "unity frozen after lock")

func test_lock_freezes_gating_flags_only():
	var s := _store()
	s.set_flag("KESTREL_RECRUITED")           # gating, set before lock
	s.lock_endings()
	# Gating flag changes are refused after lock (would alter the computed ending).
	s.set_flag("ORDER_ALLIED")                # gating, attempted after lock
	assert_false(s.get_flag("ORDER_ALLIED"), "gating flag cannot be set after lock")
	s.set_flag("KESTREL_RECRUITED", false)    # clearing a gating flag also refused
	assert_true(s.get_flag("KESTREL_RECRUITED"), "gating flag cannot be cleared after lock")
	# Non-gating flavor flags (e.g. Piggy's A3-13b late join) still work post-lock.
	s.set_flag("PIGGY_RECRUITED")
	assert_true(s.get_flag("PIGGY_RECRUITED"), "non-gating flag still writable after lock")

func test_add_unity_source_ignores_non_positive_n():
	var s := _store()
	s.add_unity_source("u_bad", 0)
	assert_eq(s.unity(), 0, "n=0 does not change unity")
	assert_eq(s.unity_sources_applied().size(), 0, "n=0 does not burn the source slot")
	s.add_unity_source("u_bad", 1)            # same id can still count later with valid n
	assert_eq(s.unity(), 1, "source still countable after a prior non-positive attempt")

func test_enum_choices():
	var s := _store()
	assert_eq(s.final_choice(), Ids.FinalChoice.NONE, "final_choice defaults NONE")
	assert_eq(s.ending(), Ids.EndingId.NONE, "ending defaults NONE")
	s.set_final_choice(Ids.FinalChoice.WAKE)
	s.set_ending(Ids.EndingId.D)
	assert_eq(s.final_choice(), Ids.FinalChoice.WAKE, "final_choice stored")
	assert_eq(s.ending(), Ids.EndingId.D, "ending stored")

func test_bramble_sacrifice_derived():
	var s := _store()
	for c in [Ids.FinalChoice.SHARE, Ids.FinalChoice.SLEEP, Ids.FinalChoice.TAKE]:
		s.set_final_choice(c)
		assert_true(s.bramble_sacrifice(), "bramble_sacrifice true for SHARE/SLEEP/TAKE")
	s.set_final_choice(Ids.FinalChoice.WAKE)
	assert_false(s.bramble_sacrifice(), "bramble_sacrifice false for WAKE")
	s.set_final_choice(Ids.FinalChoice.NONE)
	assert_false(s.bramble_sacrifice(), "bramble_sacrifice false when unchosen")

func test_to_from_dict_roundtrip():
	var s := _store()
	s.set_flag("KESTREL_RECRUITED")
	s.set_flag("ORDER_ALLIED")
	s.add_unity_source("u3_kestrel")
	s.add_unity_source("u6_order")
	s.set_final_choice(Ids.FinalChoice.SHARE)
	s.set_ending(Ids.EndingId.A)
	s.lock_endings()
	var d := s.to_dict()
	var s2 := FlagStore.new()
	s2.from_dict(d)
	assert_true(s2.get_flag("KESTREL_RECRUITED"), "flags round-trip")
	assert_eq(s2.unity(), 2, "unity round-trips")
	assert_eq(s2.unity_sources_applied().size(), 2, "applied sources round-trip")
	assert_eq(s2.final_choice(), Ids.FinalChoice.SHARE, "final_choice round-trips")
	assert_eq(s2.ending(), Ids.EndingId.A, "ending round-trips")
	assert_true(s2.is_locked(), "lock state round-trips")
	# choices serialize as enum STRINGS, not booleans (ADR-0005 §d).
	assert_eq(d["choices"]["final_choice"], "SHARE", "final_choice stored as string")
	assert_eq(d["choices"]["ending"], "A", "ending stored as string")
