## test_integration_shell.gd — R3a headless integration: New Game -> autosave -> Continue.
##
## Drives the REAL autoload coordinators (GameCoordinator / SceneRouter / SaveManager) with no
## UI: a stub scene loader is injected into SceneRouter so scene_intent is exercised WITHOUT
## tearing down the GUT runner scene, and SaveManager is pointed at a temp dir. Proves the wired
## flow: GameCoordinator.new_game() reaches the START beat with the starting party, an autosave
## lands, and load_latest() round-trips the run (the basis for "Continue").
extends GutTest

const START_BEAT := "SLICE-START"

var _save_dir: String
var _routed: Array = []          # scene paths the SceneRouter stub was asked to load

func before_each() -> void:
	# Load the shipped content into the ContentDB autoload (Boot does this in-game).
	var r: Result = ContentDB.load_all(false)
	assert_true(r.is_ok(), "content loads: %s" % (r.error if r != null else ""))
	# Point the SaveManager autoload at an isolated temp dir.
	_save_dir = "user://gut_shell_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_save_dir)
	SaveManager.set_dir(_save_dir)
	# Force immediate writes: the autoload SaveManager's debounce uses the real wall clock and its
	# state persists across the suite (other tests' beat_entered cross-talk), so a 0ms debounce
	# makes New Game's autosave land deterministically for this test.
	SaveManager.set_debounce_ms(0)
	SaveManager.delete_all()
	# Stub the SceneRouter loader so scene_intent doesn't swap the running test scene.
	_routed = []
	SceneRouter.set_loader(func(path: String) -> void: _routed.append(path))

func after_each() -> void:
	SceneRouter.set_loader(Callable())   # restore default scene loader
	SaveManager.delete_all()
	SaveManager.set_debounce_ms(3000)    # restore the default debounce for other tests
	_rmrf(_save_dir)

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

# --- New Game lands at the START beat with the starting party ---

func test_new_game_initializes_run_at_start_beat_with_party() -> void:
	GameCoordinator.new_game()
	assert_eq(GameState.current_beat_id, START_BEAT, "run is at the START beat")
	assert_eq(GameState.party.size(), 1, "starting party has one member")
	assert_eq(str(GameState.party[0].get("id", "")), "wren", "Wren is in the starting party")
	# The START beat is scene 'overworld' -> SceneRouter routed to the Overworld scene.
	assert_true(_routed.has("res://src/ui/overworld/Overworld.tscn"),
		"scene_intent routed New Game to the overworld; got %s" % str(_routed))

# --- New Game autosaves, and the run round-trips via load_latest (the Continue basis) ---

func test_new_game_autosaves_and_continue_round_trips() -> void:
	GameCoordinator.new_game()
	# new_game emits beat_entered + an OVERWORLD scene_intent, both of which autosave.
	assert_true(SaveManager.has_save(), "a save exists after New Game")
	assert_true(GameCoordinator.has_save(), "coordinator reports a save is available")
	# Simulate the run drifting, then load the saved run back (what Continue does).
	GameState.current_beat_id = "DRIFTED"
	GameState.party = []
	assert_true(SaveManager.load_latest(), "load_latest restores the saved run")
	assert_eq(GameState.current_beat_id, START_BEAT, "Continue resumes at the saved beat")
	assert_eq(GameState.party.size(), 1, "party restored from save")
	assert_eq(str(GameState.party[0].get("id", "")), "wren", "Wren restored from save")

func test_continue_game_loads_and_routes() -> void:
	GameCoordinator.new_game()
	assert_true(GameCoordinator.has_save(), "save present before continue")
	# Drift, then continue: load_latest + re-enter the saved beat (re-emits the scene_intent).
	GameState.current_beat_id = "DRIFTED"
	_routed = []
	assert_true(GameCoordinator.continue_game(), "continue_game succeeds")
	assert_eq(GameState.current_beat_id, START_BEAT, "continue resumed the saved beat")
	assert_true(_routed.has("res://src/ui/overworld/Overworld.tscn"),
		"continue re-routed to the saved overworld scene")

func test_has_save_false_on_a_clean_slate() -> void:
	# No New Game performed in this test; the temp save dir is empty.
	assert_false(GameCoordinator.has_save(), "no save on a clean slate")
	assert_false(SaveManager.has_save(), "SaveManager agrees there is no save")
