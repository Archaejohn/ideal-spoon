## test_ending_resolver.gd — THE GOLDEN TEST (ADR-0009), pinned to story 04 §4-§5.
##
## Exhaustively enumerates FINAL_CHOICE ∈ {SHARE,SLEEP,TAKE,WAKE} crossed with every
## gating flag/UNITY combination, and asserts BOTH the resolved ENDING (A/B/C/D) and the
## offered_options set match 04 EXACTLY:
##   Sleep->B and Take->C always; Share->A iff FACTIONS_UNITED; Wake->D iff
##   WARDEN_TRUTH_WHOLE AND ROOKWISE_RECRUITED AND MARROW_REDEEMED.
extends GutTest

const SHARE := Ids.FinalChoice.SHARE
const SLEEP := Ids.FinalChoice.SLEEP
const TAKE := Ids.FinalChoice.TAKE
const WAKE := Ids.FinalChoice.WAKE

# --- independent reference implementations (mirror 04 §3.3 / §5) ---
func _ref_wtw(dep: bool, prom: bool, rook: bool) -> bool:
	return (dep and prom) or (rook and (dep or prom))

func _ref_factions(unity: int, kes: bool, ord: bool, tru: bool) -> bool:
	return unity >= 5 and kes and (ord or tru)

func _ref_canwake(dep: bool, prom: bool, rook: bool, marrow: bool) -> bool:
	return _ref_wtw(dep, prom, rook) and rook and marrow

func _build(unity: int, kes: bool, ord: bool, tru: bool, dep: bool, prom: bool, rook: bool, marrow: bool) -> FlagView:
	return FlagView.from_dict({
		"KESTREL_RECRUITED": kes,
		"ORDER_ALLIED": ord,
		"TRUTH_SHARED": tru,
		"BRAMBLE_SHARD_DEPARTURE": dep,
		"BRAMBLE_SHARD_PROMISE": prom,
		"ROOKWISE_RECRUITED": rook,
		"MARROW_REDEEMED": marrow,
	}, unity)

func test_golden_exhaustive():
	var checked := 0
	for unity in [4, 5]:
		for kes in [false, true]:
			for ord in [false, true]:
				for tru in [false, true]:
					for dep in [false, true]:
						for prom in [false, true]:
							for rook in [false, true]:
								for marrow in [false, true]:
									_check_combo(unity, kes, ord, tru, dep, prom, rook, marrow)
									checked += 1
	assert_eq(checked, 256, "exhaustive over 2 unity x 2^7 flag combos")

func _check_combo(unity, kes, ord, tru, dep, prom, rook, marrow) -> void:
	var v := _build(unity, kes, ord, tru, dep, prom, rook, marrow)
	var can_share := _ref_factions(unity, kes, ord, tru)
	var can_wake := _ref_canwake(dep, prom, rook, marrow)

	# offered_options must match the gated set EXACTLY.
	var expected := [SLEEP, TAKE]
	if can_share: expected.append(SHARE)
	if can_wake: expected.append(WAKE)
	expected.sort()
	var got: Array = EndingResolver.offered_options(v).duplicate()
	got.sort()
	assert_eq(got, expected, "offered_options for unity=%d kes=%s ord=%s tru=%s dep=%s prom=%s rook=%s marrow=%s"
		% [unity, kes, ord, tru, dep, prom, rook, marrow])

	# Sleep and Take are ALWAYS offered and resolve to B / C.
	assert_eq(EndingResolver.resolve(v, SLEEP), Ids.EndingId.B, "SLEEP->B always")
	assert_eq(EndingResolver.resolve(v, TAKE), Ids.EndingId.C, "TAKE->C always")

	# Share/Wake resolve only when their gate is true (and only then are they offered).
	if can_share:
		assert_eq(EndingResolver.resolve(v, SHARE), Ids.EndingId.A, "SHARE->A when factions united")
		assert_true(got.has(SHARE), "SHARE offered when gate true")
	else:
		assert_false(got.has(SHARE), "SHARE NOT offered when gate false")
	if can_wake:
		assert_eq(EndingResolver.resolve(v, WAKE), Ids.EndingId.D, "WAKE->D when can_wake")
		assert_true(got.has(WAKE), "WAKE offered when gate true")
	else:
		assert_false(got.has(WAKE), "WAKE NOT offered when gate false")

func test_canonical_ending_states_offer_their_option():
	# Ending A canonical: unity>=5, Kestrel, an aligned faith.
	var va := _build(5, true, true, false, false, false, false, false)
	assert_true(EndingResolver.offered_options(va).has(SHARE), "A-state offers SHARE")
	assert_eq(EndingResolver.resolve(va, SHARE), Ids.EndingId.A, "A-state resolves A")
	# Ending D canonical: one shard + Rookwise (=> WTW) + Marrow redeemed.
	var vd := _build(0, false, false, false, true, false, true, true)
	assert_true(EndingResolver.offered_options(vd).has(WAKE), "D-state offers WAKE")
	assert_eq(EndingResolver.resolve(vd, WAKE), Ids.EndingId.D, "D-state resolves D")

func test_nongating_flags_never_change_result():
	# A FlagView only carries gating fields; setting an unrelated flag on the store must
	# not change offered options or the resolved ending (non-gating provably excluded).
	var s := FlagStore.new()
	s.set_flag("KESTREL_RECRUITED"); s.set_flag("ORDER_ALLIED")
	for i in 5: s.add_unity_source("u%d" % i)
	var before := EndingResolver.offered_options(s.view()).duplicate(); before.sort()
	s.set_flag("PIGGY_RECRUITED")          # non-gating
	s.set_flag("HAVEN_RELIT")              # non-gating
	var after := EndingResolver.offered_options(s.view()).duplicate(); after.sort()
	assert_eq(after, before, "non-gating flags do not change offered options")
	assert_eq(EndingResolver.resolve(s.view(), SHARE), Ids.EndingId.A, "resolution unchanged by non-gating flags")
