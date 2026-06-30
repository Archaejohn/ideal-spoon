## battle_fixtures.gd — self-contained builders for battle unit tests.
##
## Loads the tiny validated content set under tests/helpers/content/battle via the REAL
## ContentDB loader (schema validation on), and builds Combatants directly so tests control
## stats precisely. No autoloads, no scene tree.
extends RefCounted

const ContentDBScript := preload("res://src/data/content_db.gd")
const CombatantScript := preload("res://src/battle/combatant.gd")
const FAKE_CONTENT_ROOT := "res://tests/helpers/content/battle"

## A loaded ContentDB (Node) over the battle fixture set. Caller should autofree it.
static func content() -> Node:
	var db = ContentDBScript.new()
	var r = db.load_from(FAKE_CONTENT_ROOT, false)
	if r.is_err():
		push_error("battle fixture content failed to load: %s" % r.error)
	return db

## Build a combatant with explicit stats. `opts` may carry weaknesses/resistances/tags/
## resources/ability_ids/enemy_def/side/name/source_id.
static func combatant(stats: Dictionary, opts: Dictionary = {}):
	var c = CombatantScript.new()
	c.side = int(opts.get("side", CombatantScript.Side.PLAYER))
	c.name = str(opts.get("name", "C"))
	c.source_id = str(opts.get("source_id", c.name))
	c.stats = {
		"hp": int(stats.get("hp", 1)), "atk": int(stats.get("atk", 0)), "def": int(stats.get("def", 0)),
		"mag": int(stats.get("mag", 0)), "res": int(stats.get("res", 0)), "spd": int(stats.get("spd", 1)),
	}
	c.max_hp = int(stats.get("hp", 1))
	c.hp_cur = c.max_hp
	c.weaknesses = (opts.get("weaknesses", []) as Array).duplicate()
	c.resistances = (opts.get("resistances", []) as Array).duplicate()
	c.tags = (opts.get("tags", []) as Array).duplicate()
	c.resources = (opts.get("resources", {}) as Dictionary).duplicate()
	c.ability_ids = (opts.get("ability_ids", []) as Array).duplicate()
	c.enemy_def = (opts.get("enemy_def", {}) as Dictionary).duplicate(true)
	return c

## Convenience: build an enemy combatant from a fixture enemy def (so enemy_def/ai is set).
static func enemy(db, enemy_id: String, opts: Dictionary = {}):
	var def: Dictionary = db.enemy(enemy_id)
	var st: Dictionary = def.get("stats", {})
	var o := opts.duplicate()
	o["side"] = CombatantScript.Side.ENEMY
	o["name"] = def.get("name", enemy_id)
	o["source_id"] = enemy_id
	o["weaknesses"] = def.get("weaknesses", [])
	o["resistances"] = def.get("resistances", [])
	o["enemy_def"] = def
	return combatant(st, o)
