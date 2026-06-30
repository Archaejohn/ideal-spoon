## test_battle_scene_smoke.gd — R3b-1 headless scene smoke for Battle.tscn.
##
## Instantiates the real Battle scene headlessly, feeds it the slice encounter via the
## BattleController, and asserts _ready + the BattleEvent rendering path run with NO script
## errors: combatant cards are built for both sides, and advancing turns updates the scene
## without error. UI may touch autoloads/scene tree; the battle LOGIC stays headless/pure.
extends GutTest

const BattleScene := preload("res://src/ui/battle/Battle.tscn")

var _save_dir: String
var _routed: Array = []

func before_each() -> void:
	var r: Result = ContentDB.load_all(false)
	assert_true(r.is_ok(), "content loads")
	_save_dir = "user://gut_battlesmoke_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_save_dir)
	SaveManager.set_dir(_save_dir)
	SaveManager.set_debounce_ms(0)
	SaveManager.delete_all()
	_routed = []
	SceneRouter.set_loader(func(path: String) -> void: _routed.append(path))
	GameCoordinator.new_game()

func after_each() -> void:
	SceneRouter.set_loader(Callable())
	SaveManager.delete_all()
	SaveManager.set_debounce_ms(3000)
	_rmrf(_save_dir)

func test_battle_scene_boots_and_builds_cards() -> void:
	GameCoordinator.advance_story()         # -> SLICE-BATTLE, sets SceneRouter ctx (encounter)
	RngService.seed_run(2024)
	var scene = BattleScene.instantiate()
	add_child_autofree(scene)               # _ready runs synchronously: reads ctx + starts battle

	assert_eq(str(scene._encounter_id), "sleepless_crane", "scene read the encounter from the ctx")
	var party_row := scene.get_node("PartyRow")
	var enemy_row := scene.get_node("EnemyRow")
	assert_eq(party_row.get_child_count(), 2, "two party cards built (Wren + Tam)")
	assert_eq(enemy_row.get_child_count(), 2, "two enemy cards built (Crane + Husk)")
	assert_false(BattleController.is_over(), "battle is live after boot")

	# Feed a few turns directly through the controller; the scene's _on_events must render cleanly.
	for _i in 8:
		if BattleController.is_over():
			break
		BattleController.advance()
	pass_test("Battle scene handled _ready + event stream with no script errors")

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
