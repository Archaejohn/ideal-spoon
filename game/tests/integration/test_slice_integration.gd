## test_slice_integration.gd — R3b-2 full vertical-slice drive (headless, deterministic).
##
## Drives the ENTIRE Act-I micro-arc through the real autoload coordinators + StoryDirector with a
## stub SceneRouter loader (records routes, no scene-tree swap) and a fixed RNG seed:
##   Meadowmoor opening (CUTSCENE) -> Hollowgate (TOWN) -> the dockside BRANCH -> the wreck (DUNGEON,
##   the branch MERGE) -> the Sleepless Crane battle (WIN) -> the closing beat (SLICE_BOSS_CLEARED).
## One test takes branch option A (help), a second takes option B (hurry); both prove the distinct
## identity flag is set, the two arms MERGE at the same beat, and the slice completes start->finish.
extends GutTest

const OVERWORLD_SCENE := "res://src/ui/overworld/Overworld.tscn"
const DIALOGUE_SCENE := "res://src/ui/dialogue/Dialogue.tscn"
const LOCATION_SCENE := "res://src/ui/overworld/Location.tscn"
const BATTLE_SCENE := "res://src/ui/battle/Battle.tscn"

var _save_dir: String
var _routed: Array = []

func before_each() -> void:
	var r: Result = ContentDB.load_all(false)
	assert_true(r.is_ok(), "content loads: %s" % (r.error if r != null else ""))
	_save_dir = "user://gut_slice_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_save_dir)
	SaveManager.set_dir(_save_dir)
	SaveManager.set_debounce_ms(0)
	SaveManager.delete_all()
	_routed = []
	SceneRouter.set_loader(func(path: String) -> void: _routed.append(path))

func after_each() -> void:
	SceneRouter.set_loader(Callable())
	SaveManager.delete_all()
	SaveManager.set_debounce_ms(3000)
	_rmrf(_save_dir)

# --- ARM A: help the dock-hand ---

func test_slice_completes_on_branch_arm_help() -> void:
	_run_to_branch()
	# Take option A; it sets its own identity flag and routes to its beat.
	assert_true(GameCoordinator.choose_branch("help"), "choose 'help' succeeds")
	assert_eq(GameState.current_beat_id, "SLICE-HELP", "routed to the help option's beat")
	assert_true(GameState.flags.get_flag("SLICE_HELPED_DOCKHAND"), "help identity flag set")
	assert_false(GameState.flags.get_flag("SLICE_HURRIED_WRECK"), "the other arm's flag is NOT set")
	_run_through_merge_and_battle()
	assert_true(GameState.flags.get_flag("SLICE_HELPED_DOCKHAND"), "help flag persists to the end")

# --- ARM B: hurry to the wreck ---

func test_slice_completes_on_branch_arm_hurry() -> void:
	_run_to_branch()
	assert_true(GameCoordinator.choose_branch("hurry"), "choose 'hurry' succeeds")
	assert_eq(GameState.current_beat_id, "SLICE-HURRY", "routed to the hurry option's beat")
	assert_true(GameState.flags.get_flag("SLICE_HURRIED_WRECK"), "hurry identity flag set")
	assert_false(GameState.flags.get_flag("SLICE_HELPED_DOCKHAND"), "the other arm's flag is NOT set")
	_run_through_merge_and_battle()
	assert_true(GameState.flags.get_flag("SLICE_HURRIED_WRECK"), "hurry flag persists to the end")

# --- guard: branch blocks the linear advance until a choice is made ---

func test_branch_blocks_advance_until_choice() -> void:
	_run_to_branch()
	assert_false(GameCoordinator.advance_story(), "advance_story refused while the branch is open")
	assert_eq(GameState.current_beat_id, "SLICE-DOCKS", "still at the branch trigger")

# --- shared drivers ---

## new_game -> opening cutscene -> town -> branch trigger (branch open at SLICE-DOCKS).
func _run_to_branch() -> void:
	GameCoordinator.new_game()
	assert_eq(GameState.current_beat_id, "SLICE-START", "New Game lands at the opening cutscene")
	assert_true(GameState.flags.get_flag("SLICE_OPENING_SEEN"), "opening effect applied")
	assert_true(_routed.has(DIALOGUE_SCENE), "opening routed to the Dialogue scene")

	assert_true(GameCoordinator.advance_story(), "opening -> Hollowgate")
	assert_eq(GameState.current_beat_id, "SLICE-HOLLOWGATE", "reached Hollowgate (TOWN)")
	assert_true(_routed.has(LOCATION_SCENE), "TOWN routed to the Location scene")

	assert_true(GameCoordinator.advance_story(), "Hollowgate -> the dockside fork")
	assert_eq(GameState.current_beat_id, "SLICE-DOCKS", "reached the branch trigger")
	assert_eq(GameCoordinator.director().current_branch_id(), "BR-SLICE", "branch BR-SLICE is open")
	assert_eq(GameCoordinator.director().merge_beat("BR-SLICE"), "SLICE-WRECK", "branch merges at the wreck")
	assert_eq(GameCoordinator.offered_branch_options(), ["help", "hurry"], "both options offered")

## option beat -> MERGE (the wreck) -> battle (WIN) -> closing beat. Both arms run this identically,
## proving they reconverge at SLICE-WRECK and complete the slice.
func _run_through_merge_and_battle() -> void:
	assert_true(GameCoordinator.advance_story(), "option beat -> the merge (wreck)")
	assert_eq(GameState.current_beat_id, "SLICE-WRECK", "both arms MERGE at SLICE-WRECK")
	assert_true(_routed.has(LOCATION_SCENE), "DUNGEON routed to the Location scene")

	assert_true(GameCoordinator.advance_story(), "wreck -> the battle")
	assert_eq(GameState.current_beat_id, "SLICE-BATTLE", "reached the Sleepless Crane battle")
	assert_true(_routed.has(BATTLE_SCENE), "battle routed to the Battle scene")

	# Win the fight deterministically (same approach/seed proven in test_battle_flow).
	RngService.seed_run(12345)
	GameCoordinator.start_battle("sleepless_crane")
	assert_true(SaveManager.has_checkpoint("pre_battle"), "pre-battle checkpoint written")
	_drive_battle(func(actor): return _attack_first_living_enemy(actor))
	assert_eq(BattleController.result(), BattleEngine.Result.WIN, "party defeats the Crane")

	GameCoordinator.after_battle()    # victory "Continue" advances the spine
	assert_eq(GameState.current_beat_id, "SLICE-AFTER", "WIN advances to the closing beat")
	assert_true(GameState.flags.get_flag("SLICE_BOSS_CLEARED"), "closing beat set SLICE_BOSS_CLEARED")
	# Closing beat is terminal — the slice is complete end-to-end.
	assert_false(GameCoordinator.advance_story(), "closing beat is terminal (slice complete)")

func _drive_battle(action_for: Callable) -> void:
	var guard := 0
	while not BattleController.is_over() and guard < 6000:
		var actor = BattleController.peek_next_actor()
		if actor == null:
			break
		if actor.side == Combatant.Side.PLAYER:
			var act = action_for.call(actor)
			if act != null:
				BattleController.queue_action(act)
		BattleController.advance()
		guard += 1

func _attack_first_living_enemy(actor):
	for c in BattleController.engine().combatants():
		if c.side == Combatant.Side.ENEMY and c.is_alive():
			return BattleAction.attack(actor.id, c.id)
	return BattleAction.defend(actor.id)

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
