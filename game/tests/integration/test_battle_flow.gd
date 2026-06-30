## test_battle_flow.gd — R3b-1 battle flow + Owner-#13 checkpoint loop (headless, deterministic).
##
## Drives a FULL fight through the real autoload coordinators (GameCoordinator / BattleController /
## SaveManager / SceneRouter) with no UI — a stub scene loader records routes instead of swapping
## the GUT runner scene, and SaveManager is pointed at a temp dir with 0ms debounce. Proves:
##   * WIN  — victory result, XP + loot granted to GameState, pre-battle checkpoint written at
##            start, autosave on win, and the story advances to the post-battle beat.
##   * LOSE — restore_checkpoint("pre_battle") restores GameState (party + beat + RNG cursors)
##            and routes BACK to the pre-battle context (the battle), never a game-over to title.
extends GutTest

const BATTLE_SCENE := "res://src/ui/battle/Battle.tscn"
const TITLE_SCENE := "res://src/ui/Title.tscn"

var _save_dir: String
var _routed: Array = []

func before_each() -> void:
	var r: Result = ContentDB.load_all(false)
	assert_true(r.is_ok(), "content loads: %s" % (r.error if r != null else ""))
	_save_dir = "user://gut_battle_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_save_dir)
	SaveManager.set_dir(_save_dir)
	SaveManager.set_debounce_ms(0)
	SaveManager.delete_all()
	_routed = []
	SceneRouter.set_loader(func(path: String) -> void: _routed.append(path))
	# Fresh run: installs the real slice party (Wren + Tam) and enters SLICE-START.
	GameCoordinator.new_game()

func after_each() -> void:
	SceneRouter.set_loader(Callable())
	SaveManager.delete_all()
	SaveManager.set_debounce_ms(3000)
	_rmrf(_save_dir)

# --- WIN ---

func test_full_battle_win_checkpoints_grants_rewards_and_advances() -> void:
	_advance_to_battle()
	assert_eq(GameState.current_beat_id, "SLICE-BATTLE", "at the battle beat")
	assert_true(_routed.has(BATTLE_SCENE), "routed to the Battle scene")

	RngService.seed_run(12345)   # fixed seed for a reproducible fight
	GameCoordinator.start_battle("sleepless_crane")
	assert_true(SaveManager.has_checkpoint("pre_battle"), "pre-battle checkpoint written at start")

	_drive_battle(func(actor): return _attack_first_living_enemy(actor))
	assert_eq(BattleController.result(), BattleEngine.Result.WIN, "party defeats the Crane => WIN")

	assert_gt(int(_member("wren").get("xp", 0)), 0, "Wren gained XP")
	assert_gt(int(_member("tam").get("xp", 0)), 0, "Tam gained XP")
	assert_true((GameState.inventory.get("items", {}) as Dictionary).has("lamp_herb"),
		"loot item (lamp_herb) granted to inventory")
	assert_true(SaveManager.has_save(), "autosave('battle_win') wrote the main save")

	# Victory "Continue" advances the spine to the post-battle beat.
	_routed = []
	GameCoordinator.after_battle()
	assert_eq(GameState.current_beat_id, "SLICE-AFTER", "WIN advances to the post-battle beat")
	assert_true(GameState.flags.get_flag("SLICE_BOSS_CLEARED"), "post-battle beat set its marker flag")

# --- LOSE ---

func test_full_battle_lose_restores_checkpoint_and_routes_back_not_title() -> void:
	_advance_to_battle()              # drive the slice spine to SLICE-BATTLE
	RngService.seed_run(999)
	GameCoordinator.start_battle("sleepless_crane")
	assert_true(SaveManager.has_checkpoint("pre_battle"), "pre-battle checkpoint written at start")
	var pre_battle_cursor: int = RngService.stream("battle").get_cursor()

	# Party only ever defends (no queued action -> engine auto-defends) => deterministic wipe.
	_drive_battle(func(_actor): return null)
	assert_eq(BattleController.result(), BattleEngine.Result.LOSE, "all-defend party wipes => LOSE")
	assert_gt(RngService.stream("battle").get_cursor(), pre_battle_cursor, "battle RNG advanced during the fight")

	# Prove the restore overwrites drifted state.
	GameState.party = []
	GameState.current_beat_id = "DRIFTED"
	_routed = []

	GameCoordinator.after_battle()   # the defeat panel's "Try Again"
	assert_eq(GameState.party.size(), 2, "party restored from the pre_battle checkpoint")
	assert_eq(str(_member("wren").get("id", "")), "wren", "Wren restored")
	assert_eq(GameState.current_beat_id, "SLICE-BATTLE", "restored to the pre-battle beat (resume unit)")
	assert_eq(RngService.stream("battle").get_cursor(), pre_battle_cursor, "RNG cursors restored to pre-battle")
	assert_true(_routed.has(BATTLE_SCENE), "routed BACK to the battle (retry from just before the fight)")
	assert_false(_routed.has(TITLE_SCENE), "never game-overs to the Title")

# --- driver / helpers ---

## Drive the slice spine from the fresh run to the SLICE-BATTLE beat: opening cutscene -> Hollowgate
## (TOWN) -> the dockside branch (take 'help') -> the wreck (MERGE) -> the battle. Mirrors the verbs
## the Dialogue/Location scenes use (advance_story / choose_branch).
func _advance_to_battle() -> void:
	assert_eq(GameState.current_beat_id, "SLICE-START", "fresh run at the opening")
	assert_true(GameCoordinator.advance_story(), "opening -> Hollowgate")
	assert_true(GameCoordinator.advance_story(), "Hollowgate -> the dockside fork")
	assert_eq(GameCoordinator.director().current_branch_id(), "BR-SLICE", "branch open at the docks")
	assert_true(GameCoordinator.choose_branch("help"), "choose a branch option")
	assert_true(GameCoordinator.advance_story(), "option beat -> the wreck (merge)")
	assert_true(GameCoordinator.advance_story(), "wreck -> the battle")

## Step the fight to completion. `action_for` is called for each ready PLAYER actor and returns
## a BattleAction to queue (or null to let the engine auto-defend). Mirrors the WAIT-mode UI loop.
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

func _member(id: String) -> Dictionary:
	for m in GameState.party:
		if str(m.get("id", "")) == id:
			return m
	return {}

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
