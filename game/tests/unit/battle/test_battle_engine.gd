## test_battle_engine.gd — full deterministic fights: WIN/LOSE, reproducible streams,
## retarget/fizzle, and mid-battle RNG cursor save/restore.
extends GutTest

const Fx = preload("res://tests/helpers/battle_fixtures.gd")
const EngineScript = preload("res://src/battle/battle_engine.gd")
const BattleAction = preload("res://src/battle/battle_action.gd")
const CombatantScript = preload("res://src/battle/combatant.gd")
const RngServiceScript = preload("res://src/core/rng_service.gd")

var _db

func before_all():
	_db = Fx.content()

func after_all():
	if _db != null:
		_db.free()

func _svc(seed_value: int):
	var s = RngServiceScript.new()
	s.seed_run(seed_value)
	return s

func _engine(svc):
	return EngineScript.new(svc.stream("battle"), svc.stream("ai"), _db)

func _hero(stats: Dictionary):
	return Fx.combatant(stats, {"side": CombatantScript.Side.PLAYER, "name": "Hero"})

func test_scripted_encounter_runs_to_victory_with_rewards():
	var svc = autofree(_svc(111))
	var eng = _engine(svc)
	eng.setup([_hero({"hp": 80, "atk": 20, "def": 8, "spd": 12})], _db.encounter("enc_easy"))
	for _i in 12:
		eng.queue_action(BattleAction.attack(0, 1))   # hero(0) attacks dummy(1)
	eng.run_until_over()
	assert_eq(eng.result(), EngineScript.Result.WIN, "hero defeats the dummy => WIN")
	assert_eq(eng.rewards()["xp"], 50, "encounter reward xp applied")
	var last = eng.events()[eng.events().size() - 1]
	assert_eq(last["type"], "battle_over", "stream terminates with battle_over")

func test_two_runs_same_seed_produce_identical_event_streams():
	var a = autofree(_svc(2024))
	var b = autofree(_svc(2024))
	var ea = _engine(a)
	var eb = _engine(b)
	ea.setup([_hero({"hp": 80, "atk": 20, "def": 8, "spd": 12})], _db.encounter("enc_easy"))
	eb.setup([_hero({"hp": 80, "atk": 20, "def": 8, "spd": 12})], _db.encounter("enc_easy"))
	for _i in 12:
		ea.queue_action(BattleAction.attack(0, 1))
		eb.queue_action(BattleAction.attack(0, 1))
	var stream_a = ea.run_until_over()
	var stream_b = eb.run_until_over()
	assert_eq(stream_a, stream_b, "same seed + same queued actions => identical event stream")

func test_scripted_encounter_runs_to_defeat():
	var svc = autofree(_svc(7))
	var eng = _engine(svc)
	# A fragile hero who cannot meaningfully hurt the boss => deterministic LOSE.
	eng.setup([_hero({"hp": 20, "atk": 1, "def": 1, "spd": 5})], _db.encounter("enc_boss"))
	for _i in 20:
		eng.queue_action(BattleAction.attack(0, 1))
	eng.run_until_over()
	assert_eq(eng.result(), EngineScript.Result.LOSE, "party wipes => LOSE")
	assert_eq(eng.rewards()["xp"], 0, "no rewards on defeat")

func test_retargets_a_queued_action_off_a_dead_target():
	var svc = autofree(_svc(55))
	var eng = _engine(svc)
	# Hero one-shots; two dummies (ids 1 and 2). EVERY queued action targets dummy 1, so once
	# dummy 1 is dead the engine must retarget the rest onto dummy 2 (deterministic stable id).
	eng.setup([_hero({"hp": 200, "atk": 100, "def": 50, "spd": 12})], _db.encounter("enc_two"))
	for _i in 12:
		eng.queue_action(BattleAction.attack(0, 1))
	var stream = eng.run_until_over()
	assert_eq(eng.result(), EngineScript.Result.WIN, "both dummies fall => WIN")
	var saw_retarget = false
	for e in stream:
		if e["type"] == "retarget":
			saw_retarget = true
	assert_true(saw_retarget, "a queued action against a dead target is retargeted")

func test_unknown_ability_fizzles():
	var svc = autofree(_svc(9))
	var eng = _engine(svc)
	eng.setup([_hero({"hp": 80, "atk": 20, "def": 8, "spd": 12})], _db.encounter("enc_easy"))
	eng.queue_action(BattleAction.make(0, BattleAction.Kind.ABILITY, "does_not_exist", [1]))
	# Step through the hero's first turn.
	eng.process_next_turn()
	var saw_fizzle = false
	for e in eng.events():
		if e["type"] == "fizzle":
			saw_fizzle = true
	assert_true(saw_fizzle, "an action with an unknown ability fizzles (no effect)")

func test_cursor_save_restore_mid_battle_reproduces_subsequent_draws():
	var svc = autofree(_svc(4242))
	var eng = _engine(svc)
	eng.setup([_hero({"hp": 80, "atk": 20, "def": 8, "spd": 12})], _db.encounter("enc_boss"))
	for _i in 30:
		eng.queue_action(BattleAction.attack(0, 1))
	# Run a few turns so the battle stream cursor has advanced mid-fight.
	for _i in 5:
		eng.process_next_turn()
	assert_false(eng.is_over(), "still mid-battle after a few turns")
	var saved = svc.export_state()
	# Capture the draws the LIVE battle stream will produce next.
	var live = svc.stream("battle")
	var expected = []
	for _i in 12:
		expected.append(live.randi())
	# Restore the saved cursors into a fresh service and confirm identical draws.
	var svc2 = autofree(RngServiceScript.new())
	svc2.import_state(saved)
	var restored = []
	for _i in 12:
		restored.append(svc2.stream("battle").randi())
	assert_eq(restored, expected, "saved cursors reproduce subsequent battle draws mid-fight")
