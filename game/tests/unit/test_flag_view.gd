## test_flag_view.gd — FlagView typed props + computed-on-read derived flags (ADR-0003 §3.3).
extends GutTest

func test_props_from_store():
	var s := FlagStore.new()
	s.set_flag("KESTREL_RECRUITED")
	s.set_flag("TRUTH_SHARED")
	s.add_unity_source("a"); s.add_unity_source("b"); s.add_unity_source("c")
	s.add_unity_source("d"); s.add_unity_source("e")        # unity = 5
	var v := s.view()
	assert_true(v.KESTREL_RECRUITED, "bool prop mirrors store")
	assert_true(v.TRUTH_SHARED, "bool prop mirrors store")
	assert_false(v.ORDER_ALLIED, "unset prop is false")
	assert_eq(v.unity, 5, "unity mirrored")

func test_warden_truth_whole_truth_table():
	# (DEP and PROM) OR (ROOKWISE and (DEP or PROM))
	var cases := [
		# dep, prom, rook -> expected
		[false, false, false, false],
		[true,  false, false, false],   # one shard, no rookwise
		[false, true,  false, false],
		[true,  true,  false, true],    # both shards
		[true,  false, true,  true],    # one shard + rookwise
		[false, true,  true,  true],
		[false, false, true,  false],   # rookwise but no shard
		[true,  true,  true,  true],
	]
	for c in cases:
		var v := FlagView.from_dict({
			"BRAMBLE_SHARD_DEPARTURE": c[0],
			"BRAMBLE_SHARD_PROMISE": c[1],
			"ROOKWISE_RECRUITED": c[2],
		}, 0)
		assert_eq(v.warden_truth_whole(), c[3],
			"WTW(dep=%s,prom=%s,rook=%s)" % [c[0], c[1], c[2]])

func test_factions_united_truth_table():
	# unity>=5 AND KESTREL AND (ORDER or TRUTH)
	var cases := [
		# unity, kestrel, order, truth -> expected
		[5, true,  true,  false, true],
		[5, true,  false, true,  true],
		[5, true,  false, false, false],   # no aligned faith
		[4, true,  true,  false, false],   # unity too low
		[5, false, true,  true,  false],   # no kestrel
		[8, true,  true,  true,  true],
		[0, false, false, false, false],
	]
	for c in cases:
		var v := FlagView.from_dict({
			"KESTREL_RECRUITED": c[1],
			"ORDER_ALLIED": c[2],
			"TRUTH_SHARED": c[3],
		}, c[0])
		assert_eq(v.factions_united(), c[4],
			"FU(unity=%d,kes=%s,ord=%s,tru=%s)" % [c[0], c[1], c[2], c[3]])

func test_derived_not_stored_recompute_on_read():
	var s := FlagStore.new()
	var v1 := s.view()
	assert_false(v1.warden_truth_whole(), "initially false")
	s.set_flag("BRAMBLE_SHARD_DEPARTURE")
	s.set_flag("BRAMBLE_SHARD_PROMISE")
	var v2 := s.view()
	assert_true(v2.warden_truth_whole(), "recomputed true after underlying flags change")
