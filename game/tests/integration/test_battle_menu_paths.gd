## test_battle_menu_paths.gd — MINOR-2 (REVIEW_phase3_r3b1): exercise the Battle scene's player
## action-menu surface headlessly. Opens the menu for a ready party member and submits an ABILITY
## and an ITEM (with target-select), and a FLEE on a fleeable encounter — asserting no script errors
## and that the correct BattleAction reaches the engine (the right ACTION/FLEE event is emitted).
##
## The scene is instantiated with NO encounter ctx so its _ready does not auto-start (and does not
## kick the async WAIT-mode pump); the fight is started directly through the BattleController and the
## menu handlers are driven in-process. For the non-terminal ability/item submits we set the scene's
## `_over` seam so _submit resolves the queued turn but skips the async enemy-turn pump.
extends GutTest

const BattleScene := preload("res://src/ui/battle/Battle.tscn")
const ATB_MAX := 10000

var _save_dir: String
var _routed: Array = []

func before_each() -> void:
	var r: Result = ContentDB.load_all(false)
	assert_true(r.is_ok(), "content loads: %s" % (r.error if r != null else ""))
	_save_dir = "user://gut_menu_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_save_dir)
	SaveManager.set_dir(_save_dir)
	SaveManager.set_debounce_ms(0)
	SaveManager.delete_all()
	_routed = []
	SceneRouter.set_loader(func(path: String) -> void: _routed.append(path))
	GameCoordinator.new_game()
	RngService.seed_run(777)

func after_each() -> void:
	SceneRouter.set_loader(Callable())
	SaveManager.delete_all()
	SaveManager.set_debounce_ms(3000)
	_rmrf(_save_dir)

# --- ABILITY submission ---

func test_menu_ability_path_submits_correct_action() -> void:
	var scene = _scene_for("sleepless_crane")
	var eng = BattleController.engine()
	var wren = _force_ready(eng, "wren")

	scene._open_action_menu(wren)
	assert_true(scene.get_node("ActionMenu").visible, "action menu opened for the ready actor")
	scene._on_ability()                       # builds the ability choice list
	assert_true(scene.get_node("ChoiceList").visible, "ability list shown")
	scene._choose_ability("song_lash")        # -> target select (enemy)
	scene._over = true                         # suppress the async WAIT pump after this submit
	var foe = _first_enemy(eng)
	var before := eng.events().size()
	scene._pick_target(foe.id)                 # -> _submit -> queue + advance resolves wren

	assert_true(_has_action_event(eng, before, wren.id, "song_lash"),
		"Song-Lash ABILITY by Wren reached the engine as an ACTION")

# --- ITEM submission (with consumption) ---

func test_menu_item_path_consumes_and_submits() -> void:
	GameState.inventory["items"] = {"lamp_herb": 1}
	var scene = _scene_for("sleepless_crane")
	var eng = BattleController.engine()
	var wren = _force_ready(eng, "wren")

	scene._open_action_menu(wren)
	scene._on_item()                           # ITEM (use_lamp_herb) -> ally target select
	scene._over = true
	var before := eng.events().size()
	scene._pick_target(wren.id)                # target self; consumes the herb, submits

	assert_eq(int((GameState.inventory.get("items", {}) as Dictionary).get("lamp_herb", 0)), 0,
		"lamp_herb consumed on use")
	assert_true(_has_action_event(eng, before, wren.id, "use_lamp_herb"),
		"lamp-herb ITEM by Wren reached the engine as an ACTION")

# --- FLEE on a fleeable encounter ---

func test_menu_flee_on_fleeable_encounter_routes_to_overworld() -> void:
	var scene = _scene_for("hollow_skirmish")   # flee_allowed = true
	var eng = BattleController.engine()
	var wren = _force_ready(eng, "wren")

	scene._open_action_menu(wren)
	scene._on_flee()                            # submit FLEE; ends the battle -> battle_over(FLED)

	assert_eq(BattleController.result(), BattleEngine.Result.FLED, "fleeable encounter => FLED")
	assert_true(_routed.has("res://src/ui/overworld/Overworld.tscn"),
		"FLEE returns to the overworld; routed %s" % str(_routed))

# --- helpers ---

## Instantiate the Battle scene without an encounter ctx (so _ready does not auto-start), then start
## `encounter_id` directly through the controller so the scene receives battle_started + builds cards.
func _scene_for(encounter_id: String) -> Control:
	var scene = BattleScene.instantiate()
	add_child_autofree(scene)                   # _ready: encounter ctx empty -> no auto-start/pump
	BattleController.configure()
	BattleController.start(encounter_id, GameState.party)
	return scene

## Make the named party combatant the unambiguous next-ready actor (all others ATB 0).
func _force_ready(eng, source_id: String):
	var who = null
	for c in eng.combatants():
		c.atb = 0
		if str(c.source_id) == source_id:
			who = c
	who.atb = ATB_MAX
	return who

func _first_enemy(eng):
	for c in eng.combatants():
		if c.side == Combatant.Side.ENEMY and c.is_alive():
			return c
	return null

func _has_action_event(eng, from_index: int, actor_id: int, ability_id: String) -> bool:
	var events: Array = eng.events()
	for i in range(from_index, events.size()):
		var e: Dictionary = events[i]
		if str(e.get("type", "")) == "action" and int(e.get("combatant", -1)) == actor_id \
			and str(e.get("ability", "")) == ability_id:
			return true
	return false

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
