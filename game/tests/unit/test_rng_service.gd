## test_rng_service.gd — RNG determinism (ADR-0009).
extends GutTest

const RngServiceScript := preload("res://src/core/rng_service.gd")

func _make() -> Node:
	var svc = RngServiceScript.new()
	return svc

func _draw(svc, stream_name: String, n: int) -> Array:
	var out := []
	var s = svc.stream(stream_name)
	for _i in n:
		out.append(s.randi())
	return out

func test_same_seed_identical_sequences():
	var a = autofree(_make())
	var b = autofree(_make())
	a.seed_run(123456789)
	b.seed_run(123456789)
	assert_eq(_draw(a, "battle", 16), _draw(b, "battle", 16), "same seed => identical battle sequence")

func test_different_seed_differs():
	var a = autofree(_make())
	var b = autofree(_make())
	a.seed_run(1)
	b.seed_run(2)
	assert_ne(_draw(a, "battle", 16), _draw(b, "battle", 16), "different seeds => different sequence")

func test_streams_independent():
	var a = autofree(_make())
	a.seed_run(42)
	var battle := _draw(a, "battle", 16)
	var loot := _draw(a, "loot", 16)
	assert_ne(battle, loot, "distinct named streams produce distinct sequences")

func test_stream_draw_does_not_perturb_other_stream():
	# Drawing from "ai" must not change what "battle" yields (isolation, ADR-0009).
	var a = autofree(_make())
	var b = autofree(_make())
	a.seed_run(777)
	b.seed_run(777)
	# a: interleave ai draws between battle draws; b: only battle draws.
	var sa = a.stream("battle")
	var ai = a.stream("ai")
	var seq_a := []
	for _i in 8:
		ai.randi()                 # perturbation on a different stream
		seq_a.append(sa.randi())
	var seq_b := _draw(b, "battle", 8)
	assert_eq(seq_a, seq_b, "battle stream is unaffected by ai-stream draws")

func test_cursor_save_restore_reproduces_next_values():
	var a = autofree(_make())
	a.seed_run(2024)
	var s = a.stream("story")
	for _i in 5:
		s.randi()
	var cursor: int = s.get_cursor()
	var expected := []
	for _i in 5:
		expected.append(s.randi())
	# Rewind and replay.
	s.set_cursor(cursor)
	var replayed := []
	for _i in 5:
		replayed.append(s.randi())
	assert_eq(replayed, expected, "set_cursor reproduces the exact next draws")
	assert_eq(s.get_cursor(), cursor + 5, "cursor advances by number of draws")

func test_export_import_state_roundtrip():
	var a = autofree(_make())
	a.seed_run(31337)
	a.stream("battle").randi()
	a.stream("battle").randi()
	a.stream("loot").randi()
	var st: Dictionary = a.export_state()
	var expected_battle: int = a.stream("battle").randi()
	var expected_loot: int = a.stream("loot").randi()
	# Fresh service, import state, continue.
	var b = autofree(_make())
	b.import_state(st)
	assert_eq(b.stream("battle").randi(), expected_battle, "battle continues after import")
	assert_eq(b.stream("loot").randi(), expected_loot, "loot continues after import")
	assert_eq(int(st["master_seed"]), 31337, "master seed exported")
	assert_eq(int(st["cursors"]["battle"]), 2, "battle cursor exported")

func test_integer_helpers_deterministic_and_bounded():
	var a = autofree(_make())
	a.seed_run(9)
	var s = a.stream("encounter")
	for _i in 100:
		var r: int = s.randi_range(3, 7)
		assert_between(r, 3, 7, "randi_range stays in bounds")
	# chance_permille extremes are absolute.
	assert_true(s.chance_permille(1000), "permille 1000 always true")
	assert_false(s.chance_permille(0), "permille 0 always false")
	# weighted_pick respects a zero weight.
	var picks := {}
	for _i in 200:
		var idx: int = s.weighted_pick([1, 0, 1])
		picks[idx] = true
	assert_false(picks.has(1), "zero-weight index never picked")
