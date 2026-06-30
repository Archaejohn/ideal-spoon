## test_save_migrator.gd — ordered pure version migration (ADR-0005 §d).
extends GutTest

const Migrator := preload("res://src/save/save_migrator.gd")

# A frozen v1 fixture (the shape SaveSerializer/GameState produce at the current version).
func _frozen_v1() -> Dictionary:
	return {
		"save_version": 1,
		"playtime_secs": 5.0,
		"rng_state": { "master_seed": 1, "cursors": { "battle": 0 } },
		"story": { "current_beat_id": "A1-01", "flags": {}, "unity": 0,
			"unity_sources_applied": [], "choices": { "final_choice": "NONE", "ending": "NONE" },
			"endings_locked": false, "applied_beats": [] },
		"party": [], "inventory": { "items": {}, "key_items": [] }, "quests": {},
		"location": { "skyland": "", "entry": "" }, "endings_unlocked": [],
		"divergence_snapshots": {},
	}

func test_frozen_v1_migrates_to_current():
	var res := Migrator.migrate(_frozen_v1())
	assert_true(res.is_ok(), "v1 fixture migrates (no-op) to current SAVE_VERSION")
	assert_eq(int(res.value["save_version"]), Migrator.CURRENT_VERSION, "lands at current version")

func test_newer_than_build_refused():
	var newer := _frozen_v1()
	newer["save_version"] = Migrator.CURRENT_VERSION + 1
	var res := Migrator.migrate(newer)
	assert_true(res.is_err(), "a save newer than the build is refused")
	assert_string_contains(res.error, "newer", "error explains the save is newer")

func test_ordered_steps_applied_and_original_preserved():
	# Exercise the stepping logic end-to-end with an injected target + steps (without
	# bumping the real build version). The migrator must NOT mutate the input dict — the
	# pre-migration copy is preserved (the in-memory analogue of the pre-backup).
	var original := _frozen_v1()
	var steps := {
		1: func(p: Dictionary) -> Dictionary:
			var d := p.duplicate(true)
			d["added_in_v2"] = true
			return d,
	}
	var res := Migrator.migrate(original, 2, steps)
	assert_true(res.is_ok(), "v1 -> v2 via a registered step succeeds")
	assert_eq(int(res.value["save_version"]), 2, "result is stamped v2")
	assert_true(bool(res.value.get("added_in_v2", false)), "the v1->v2 step ran")
	# Original untouched.
	assert_eq(int(original["save_version"]), 1, "input dict version unchanged")
	assert_false(original.has("added_in_v2"), "input dict not mutated by migration")

func test_missing_step_is_error():
	var res := Migrator.migrate(_frozen_v1(), 2, {})   # target v2 but no step registered
	assert_true(res.is_err(), "missing migration step is a refused, not silent, failure")

func test_post_migration_shape_revalidated():
	# A buggy step that drops a required key must be caught by re-validation.
	var steps := {
		1: func(_p: Dictionary) -> Dictionary:
			return { "save_version": 2 },   # missing story/rng_state
	}
	var res := Migrator.migrate(_frozen_v1(), 2, steps)
	assert_true(res.is_err(), "post-migration shape re-validation rejects a degenerate save")
