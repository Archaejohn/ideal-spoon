## test_save_serializer.gd — on-disk envelope round-trip + tamper detection (ADR-0005 §d).
extends GutTest

const Serializer := preload("res://src/save/save_serializer.gd")

func _sample(version: int = 1) -> Dictionary:
	return {
		"save_version": version,
		"magic": "AETHER",
		"playtime_secs": 12.5,
		"rng_state": { "master_seed": 777, "cursors": { "battle": 3, "story": 1 } },
		"story": {
			"current_beat_id": "A3-06",
			"flags": { "KESTREL_RECRUITED": true },
			"unity": 2,
			"unity_sources_applied": ["u3_kestrel"],
			"choices": { "final_choice": "NONE", "ending": "NONE" },
			"endings_locked": false,
			"applied_beats": ["A1-01", "A1-02"],
		},
		"party": [{ "id": "wren", "level": 14 }],
		"inventory": { "items": { "lamp_herb": 5 }, "key_items": ["keepers_lamp"] },
		"quests": { "SQ-PIGGY": "DONE" },
		"location": { "skyland": "thornholt", "entry": "junk_market" },
		"endings_unlocked": [],
		"divergence_snapshots": {},
	}

func test_envelope_round_trip():
	var bytes := Serializer.encode(_sample())
	var res := Serializer.decode(bytes)
	assert_true(res.is_ok(), "valid envelope decodes")
	var p: Dictionary = res.value
	assert_eq(int(p["save_version"]), 1, "save_version round-trips")
	assert_eq(str(p["story"]["current_beat_id"]), "A3-06", "nested story field round-trips")
	assert_eq(int(p["rng_state"]["cursors"]["battle"]), 3, "rng cursor round-trips")
	assert_true(Serializer.is_valid(bytes), "is_valid true for a clean envelope")

func test_bad_checksum_rejected():
	var bytes := Serializer.encode(_sample())
	var env: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
	env["payload"] = str(env["payload"]) + " "   # tamper payload; checksum no longer matches
	var tampered := JSON.stringify(env).to_utf8_buffer()
	var res := Serializer.decode(tampered)
	assert_true(res.is_err(), "tampered payload is rejected by checksum")

func test_tampered_version_handled():
	var bytes := Serializer.encode(_sample())
	var env: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
	env["save_version"] = 999   # version is inside the checksum scope -> mismatch
	var tampered := JSON.stringify(env).to_utf8_buffer()
	assert_true(Serializer.decode(tampered).is_err(), "tampered version is rejected")

func test_bad_magic_rejected():
	var env := { "magic": "NOPE", "save_version": 1, "checksum": "x", "payload": "{}" }
	var bytes := JSON.stringify(env).to_utf8_buffer()
	assert_true(Serializer.decode(bytes).is_err(), "wrong magic rejected")

func test_garbage_bytes_rejected():
	var res := Serializer.decode("not json at all {{{".to_utf8_buffer())
	assert_true(res.is_err(), "non-JSON rejected")
	assert_false(Serializer.is_valid(PackedByteArray()), "empty bytes invalid")
