## test_save_manager.gd — autosave debounce, checkpoints (incl. RNG), replay guard,
## backup recovery, has_save/delete_all (ADR-0005, ADR-0009, PHASE2_OWNER_RULINGS #2/#4).
extends GutTest

const SaveManagerScript := preload("res://src/save/save_manager.gd")
const AtomicIO := preload("res://src/save/atomic_file_io.gd")
const GameStateScript := preload("res://src/core/game_state.gd")
const Serializer := preload("res://src/save/save_serializer.gd")

var _dir: String
var _clock := [0]   # mutable injected clock (ms); _clock[0] is "now"

func before_each() -> void:
	_dir = "user://gut_savemgr_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)
	_clock = [0]

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

# Fresh GameState wired to the real RngService autoload (needs the tree).
func _make_game_state(seed: int) -> Node:
	var gs = GameStateScript.new()
	add_child_autofree(gs)
	gs.new_run(seed)
	return gs

func _make_manager(gs: Node, debounce_ms: int = 3000) -> Node:
	var mgr = autofree(SaveManagerScript.new())
	mgr.set_io(AtomicIO.new())
	mgr.set_dir(_dir)
	mgr.set_game_state(gs)
	mgr.set_debounce_ms(debounce_ms)
	mgr.set_clock(func() -> int: return _clock[0])
	return mgr

func _rng() -> Node:
	return get_tree().root.get_node_or_null("RngService")

# --- autosave debounce ---

func test_autosave_debounce_collapses_rapid_calls():
	var gs := _make_game_state(123)
	var mgr := _make_manager(gs)
	watch_signals(mgr)
	# t=0: first call writes (idle window elapsed since -inf); rapid follow-ups collapse.
	_clock[0] = 0
	mgr.autosave("beat")
	mgr.autosave("map")
	mgr.autosave("menu")
	assert_signal_emit_count(mgr, "saved", 1, "rapid debounced calls collapse to one write")
	# After the interval, the coalesced pending write flushes.
	_clock[0] = 5000
	mgr.flush_pending()
	assert_signal_emit_count(mgr, "saved", 2, "pending debounced write flushes after interval")

func test_lifecycle_reason_bypasses_debounce():
	var gs := _make_game_state(123)
	var mgr := _make_manager(gs)
	watch_signals(mgr)
	_clock[0] = 0
	mgr.autosave("beat")                  # write #1
	mgr.autosave("focus_out")             # lifecycle: immediate, bypasses debounce -> #2
	assert_signal_emit_count(mgr, "saved", 2, "lifecycle reason writes immediately")

# --- checkpoint write/restore reproduces RNG (ADR-0009) ---

func test_checkpoint_restore_reproduces_rng_cursors():
	var gs := _make_game_state(777)
	var mgr := _make_manager(gs)
	var rng := _rng()
	# Advance the battle stream a few draws before the checkpoint.
	for _i in 3:
		rng.stream("battle").randi()
	assert_true(mgr.write_checkpoint("pre_battle"), "checkpoint write succeeds")
	assert_true(mgr.has_checkpoint("pre_battle"), "checkpoint exists")
	# Draw a sequence AFTER the checkpoint (simulating a battle that the player then loses).
	var seq_a := []
	for _i in 6:
		seq_a.append(rng.stream("battle").randi())
	# Restore: RNG cursors must rewind to the checkpoint, reproducing the exact next draws.
	assert_true(mgr.restore_checkpoint("pre_battle"), "checkpoint restore succeeds")
	var seq_b := []
	for _i in 6:
		seq_b.append(rng.stream("battle").randi())
	assert_eq(seq_b, seq_a, "post-restore draws reproduce the pre-restore sequence (RNG cursors restored)")

func test_checkpoint_restore_reproduces_game_state():
	var gs := _make_game_state(42)
	var mgr := _make_manager(gs)
	gs.current_beat_id = "A3-06"
	gs.flags.set_flag("KESTREL_RECRUITED")
	mgr.write_checkpoint("pre_battle")
	# Mutate state as if a battle happened, then restore.
	gs.current_beat_id = "B9-99"
	gs.flags.set_flag("KESTREL_RECRUITED", false)
	assert_true(mgr.restore_checkpoint("pre_battle"), "restore ok")
	assert_eq(gs.current_beat_id, "A3-06", "beat restored from checkpoint")
	assert_true(gs.flags.get_flag("KESTREL_RECRUITED"), "flag restored from checkpoint")

# --- replay-mode guard (every write path) ---

func test_replay_mode_blocks_autosave_and_lifecycle():
	var gs := _make_game_state(123)
	var mgr := _make_manager(gs)
	watch_signals(mgr)
	mgr.enter_replay_mode()
	# autosave path blocked.
	mgr.autosave("beat")
	assert_signal_emit_count(mgr, "saved", 0, "autosave blocked in replay mode")
	assert_false(mgr.has_save(), "no real save written during replay (autosave)")
	# lifecycle _notification path blocked too (focus-out during a sandboxed replay).
	mgr._notification(mgr.NOTIFICATION_WM_CLOSE_REQUEST)
	mgr._notification(mgr.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_signal_emit_count(mgr, "saved", 0, "lifecycle save blocked in replay mode")
	assert_false(mgr.has_save(), "no real save written during replay (lifecycle)")
	# checkpoint write blocked too.
	assert_false(mgr.write_checkpoint("pre_battle"), "checkpoint write blocked in replay mode")
	assert_false(mgr.has_checkpoint("pre_battle"), "no checkpoint written during replay")
	# After exit, normal saving resumes.
	mgr.exit_replay_mode()
	mgr.autosave("beat")
	assert_signal_emit_count(mgr, "saved", 1, "saving resumes after exit_replay_mode")
	assert_true(mgr.has_save(), "real save written after leaving replay")

# --- load_latest recovery + migration ---

func test_load_latest_recovers_from_backup():
	var gs := _make_game_state(123)
	var mgr := _make_manager(gs)
	watch_signals(mgr)
	gs.current_beat_id = "A1-01"
	mgr.autosave("beat")                 # main = A1-01
	gs.current_beat_id = "A2-02"
	mgr.autosave("focus_out")            # lifecycle bypass: main = A2-02, bak = A1-01
	# Corrupt the main file on disk.
	var main_path := _dir.path_join("save_main.sav")
	var f := FileAccess.open(main_path, FileAccess.WRITE)
	f.store_string("garbage{{{")
	f.close()
	# Load: should recover from the backup (A1-01) and emit save_recovered("backup").
	gs.current_beat_id = "WIPED"
	assert_true(mgr.load_latest(), "load_latest recovers from backup")
	assert_eq(gs.current_beat_id, "A1-01", "state loaded from backup")
	assert_signal_emitted_with_parameters(mgr, "save_recovered", ["backup"], 0)

func test_load_latest_migrates_with_pre_backup():
	var gs := _make_game_state(123)
	var mgr := _make_manager(gs)
	# Save at v1, then load with the build "advanced" to v2 via an injected migrator step.
	gs.current_beat_id = "A1-01"
	mgr.autosave("beat")
	var step := {
		1: func(p: Dictionary) -> Dictionary:
			var d := p.duplicate(true)
			d["migrated_marker"] = true
			return d,
	}
	mgr.set_migrator(2, step)
	assert_true(mgr.load_latest(), "load_latest migrates an older save")
	assert_eq(int(gs.save_version), 2, "GameState reflects the migrated version")
	# A pre-migration backup of the original v1 file must exist.
	var pre := "%s.premigrate.v1.bak" % _dir.path_join("save_main.sav")
	assert_true(FileAccess.file_exists(pre), "pre-migration backup kept before migrating")

func test_load_latest_false_when_no_save():
	var gs := _make_game_state(123)
	var mgr := _make_manager(gs)
	assert_false(mgr.load_latest(), "no save -> load_latest returns false (start fresh)")

# --- has_save / delete_all ---

func test_has_save_and_delete_all():
	var gs := _make_game_state(123)
	var mgr := _make_manager(gs)
	assert_false(mgr.has_save(), "no save initially")
	mgr.autosave("beat")
	mgr.write_checkpoint("pre_battle")
	assert_true(mgr.has_save(), "has_save after autosave")
	assert_true(mgr.has_checkpoint("pre_battle"), "has_checkpoint after write")
	mgr.delete_all()
	assert_false(mgr.has_save(), "has_save false after delete_all")
	assert_false(mgr.has_checkpoint("pre_battle"), "has_checkpoint false after delete_all")
