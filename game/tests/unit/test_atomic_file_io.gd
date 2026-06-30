## test_atomic_file_io.gd — crash-safe write primitive (ADR-0005 §b).
extends GutTest

const AtomicIO := preload("res://src/save/atomic_file_io.gd")
const Serializer := preload("res://src/save/save_serializer.gd")

var _dir: String
var _path: String

func before_each() -> void:
	_dir = "user://gut_atomic_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)
	_path = _dir.path_join("save.sav")

func after_each() -> void:
	_rmrf(_dir)

func _rmrf(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	var d := DirAccess.open(dir)
	if d != null:
		d.list_dir_begin()
		var name := d.get_next()
		while name != "":
			d.remove(dir.path_join(name))
			name = d.get_next()
		d.list_dir_end()
	DirAccess.remove_absolute(dir)

func _payload(beat: String = "A1-01") -> Dictionary:
	return {
		"save_version": 1, "playtime_secs": 1.0,
		"rng_state": { "master_seed": 1, "cursors": {} },
		"story": { "current_beat_id": beat, "flags": {}, "unity": 0,
			"unity_sources_applied": [], "choices": {}, "endings_locked": false, "applied_beats": [] },
		"party": [], "inventory": {}, "quests": {}, "location": {}, "endings_unlocked": [],
		"divergence_snapshots": {},
	}

func _encode(beat: String) -> PackedByteArray:
	return Serializer.encode(_payload(beat))

func _write_garbage(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("totally not a valid save {{{{")
	f.close()

func _beat_of(bytes: PackedByteArray) -> String:
	var res := Serializer.decode(bytes)
	if res.is_err():
		return "<invalid>"
	return str((res.value as Dictionary)["story"]["current_beat_id"])

func test_write_then_read_round_trip():
	var io := AtomicIO.new()
	var w := io.write(_path, _encode("A2-05"))
	assert_true(w.is_ok(), "atomic write succeeds")
	var r := io.read_validated(_path)
	assert_true(r.is_ok(), "validated read succeeds")
	assert_eq(str((r.value as Dictionary)["source"]), "main", "read from the main file")
	assert_eq(_beat_of((r.value as Dictionary)["bytes"]), "A2-05", "round-tripped payload matches")

func test_corrupt_main_recovers_from_backup():
	var io := AtomicIO.new()
	io.write(_path, _encode("A1-01"))   # main = A1-01 (no bak yet)
	io.write(_path, _encode("A2-02"))   # main = A2-02, bak = A1-01 (validated promotion)
	_write_garbage(_path)               # main now torn
	var r := io.read_validated(_path)
	assert_true(r.is_ok(), "read recovers despite a corrupt main")
	assert_eq(str((r.value as Dictionary)["source"]), "backup", "recovered from .bak")
	assert_eq(_beat_of((r.value as Dictionary)["bytes"]), "A1-01", "backup holds the prior good save")

func test_corrupt_both_returns_err():
	var io := AtomicIO.new()
	io.write(_path, _encode("A1-01"))
	io.write(_path, _encode("A2-02"))   # creates a .bak
	_write_garbage(_path)
	_write_garbage(_path + ".bak")
	var r := io.read_validated(_path)
	assert_true(r.is_err(), "both main and backup corrupt -> err")

func test_torn_main_does_not_clobber_good_backup():
	# validate-before-bak: a torn main must NEVER be promoted over a good backup.
	var io := AtomicIO.new()
	io.write(_path, _encode("A1-01"))   # main = A1-01
	io.write(_path, _encode("A2-02"))   # main = A2-02, bak = A1-01 (good backup)
	_write_garbage(_path)               # simulate a torn main file
	var w := io.write(_path, _encode("A3-03"))   # write a fresh save over the torn main
	assert_true(w.is_ok(), "new write still succeeds")
	# The good backup (A1-01) must survive — the torn main was NOT promoted to .bak.
	var bak := FileAccess.get_file_as_bytes(_path + ".bak")
	assert_eq(_beat_of(bak), "A1-01", "good backup preserved (torn main not promoted)")
	# And the new main is the fresh save.
	var r := io.read_validated(_path)
	assert_eq(_beat_of((r.value as Dictionary)["bytes"]), "A3-03", "main is the new good save")

func test_delete_removes_all_artifacts():
	var io := AtomicIO.new()
	io.write(_path, _encode("A1-01"))
	io.write(_path, _encode("A2-02"))
	assert_true(io.exists(_path), "exists before delete")
	io.delete(_path)
	assert_false(io.exists(_path), "exists false after delete")
