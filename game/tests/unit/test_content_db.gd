## test_content_db.gd — content loading + validation (ADR-0007).
extends GutTest

const ContentDBScript := preload("res://src/data/content_db.gd")

func _db() -> Node:
	return ContentDBScript.new()

func test_loads_example_data_cleanly():
	var db = autofree(_db())
	var r: Result = db.load_from("res://data", false)
	assert_true(r.is_ok(), "example data validates cleanly (schema): %s" % (r.error if r != null else ""))
	assert_true(db.is_loaded(), "db reports loaded")
	# Spot-check catalogs built from the example files.
	assert_true(db.beat("A1-04").has("scene"), "beat A1-04 loaded")
	assert_eq(db.enemy("sleepless_crane")["is_boss"], true, "enemy loaded")
	assert_true(db.has_flag("KESTREL_RECRUITED"), "flag registry loaded")
	assert_true(db.is_gating_flag("KESTREL_RECRUITED"), "gating flag flagged")
	assert_false(db.is_gating_flag("PIGGY_RECRUITED"), "non-gating flag flagged")
	assert_eq(db.count("unity_sources"), 8, "eight UNITY sources loaded")
	assert_true(db.unity_source("u3").has("beat"), "unity source u3 loaded")

func test_malformed_record_rejected_with_clear_error():
	var db = autofree(_db())
	var r: Result = db.load_from("res://tests/helpers/content/bad", false)
	assert_true(r.is_err(), "malformed beat is rejected")
	assert_string_contains(r.error, "unknown op", "error names the offending rule")
	assert_string_contains(r.error, "FROOBLE", "error names the bad value")

func test_schema_rejects_missing_required_field():
	var bad := {"id": "A9-01", "act": 1, "location": "x", "scene": "cutscene", "_source": "<inline>"}
	# missing 'effects' and 'next'
	var r: Result = ContentValidator.validate_record("beats", bad)
	assert_true(r.is_err(), "missing required field rejected")
	assert_string_contains(r.error, "required field missing", "clear required-field error")

func test_schema_rejects_bad_enum():
	var bad := {"id": "A9-02", "act": 1, "location": "x", "scene": "teleport",
		"effects": [], "next": [], "_source": "<inline>"}
	var r: Result = ContentValidator.validate_record("beats", bad)
	assert_true(r.is_err(), "invalid scene enum rejected")
	assert_string_contains(r.error, "not in", "clear enum error")

func test_reference_validation_good_closed_set():
	# A tiny CLOSED content set passes the strict reference/domain pass.
	var catalogs := {
		"flags": {
			"KESTREL_RECRUITED": {"name": "KESTREL_RECRUITED", "kind": "story", "gating": true},
			"WARDEN_TRUTH_WHOLE": {"name": "WARDEN_TRUTH_WHOLE", "kind": "derived", "gating": true},
		},
		"beats": {
			"A1-01": {"id": "A1-01", "effects": [{"op": "SET", "flag": "KESTREL_RECRUITED"}], "next": ["A1-02"]},
			"A1-02": {"id": "A1-02", "effects": [], "next": []},
		},
		"branches": {}, "encounters": {}, "enemies": {}, "abilities": {}, "items": {},
		"endings": {
			"A": {"id": "A", "requires": {"flags_all": ["KESTREL_RECRUITED"]}},
		},
	}
	var r: Result = ContentValidator.validate_references(catalogs)
	assert_true(r.is_ok(), "closed set passes references: %s" % (r.error if r != null else ""))

func test_reference_validation_unregistered_flag_rejected():
	var catalogs := {
		"flags": {}, "branches": {}, "encounters": {}, "enemies": {}, "abilities": {},
		"items": {}, "endings": {},
		"beats": {"A1-01": {"id": "A1-01", "effects": [{"op": "SET", "flag": "GHOST_FLAG"}], "next": []}},
	}
	var r: Result = ContentValidator.validate_references(catalogs)
	assert_true(r.is_err(), "beat SETting an unregistered flag is rejected")
	assert_string_contains(r.error, "GHOST_FLAG", "error names the offending flag")

func test_reference_validation_rejects_derived_in_requires():
	var catalogs := {
		"flags": {"WARDEN_TRUTH_WHOLE": {"name": "WARDEN_TRUTH_WHOLE", "kind": "derived", "gating": true}},
		"beats": {}, "branches": {}, "encounters": {}, "enemies": {}, "abilities": {}, "items": {},
		"endings": {"D": {"id": "D", "requires": {"flags_all": ["WARDEN_TRUTH_WHOLE"]}}},
	}
	var r: Result = ContentValidator.validate_references(catalogs)
	assert_true(r.is_err(), "derived flag in ending.requires is rejected")
	assert_string_contains(r.error, "derived", "error explains derived-flag rule")
