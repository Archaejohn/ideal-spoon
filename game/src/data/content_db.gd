## content_db.gd — loads + validates all game/data/** into read-only catalogs (ADR-0007).
##
## Autoload #4 (ARCHITECTURE §2). At boot, walks each data/<kind>/ directory, parses every
## `.json`, runs the matching schema validator, and builds Dictionary catalogs keyed by id,
## exposed via typed accessors (beat/enemy/encounter/ability/item/status/branch/ending/
## level_curve/flag/quest/party_member). Schema errors are fatal in debug (fail-fast,
## precise message). Cross-catalog reference + domain validation runs only when `strict`
## (a CLOSED content set); the shipped Phase-3 data is an incomplete sampler, so the boot
## load uses strict=false (see content_validator.gd for the rationale).
extends Node

## dir name under data/ -> { kind, id_field }. `flags/` is split by record shape below.
const SIMPLE_KINDS := {
	"beats": "id",
	"branches": "id",
	"endings": "id",
	"items": "id",
	"enemies": "id",
	"abilities": "id",
	"statuses": "id",
	"level_curves": "id",
	"encounters": "id",
	"party": "id",
	"quests": "id",
}

var _catalogs: Dictionary = {}     # kind -> { id: record }
var _loaded: bool = false

func _init() -> void:
	_reset()

func _reset() -> void:
	_catalogs = {
		"beats": {}, "branches": {}, "endings": {}, "items": {}, "enemies": {},
		"abilities": {}, "statuses": {}, "level_curves": {}, "encounters": {},
		"party": {}, "quests": {}, "flags": {}, "unity_sources": {},
	}

## Load + validate the shipped content at res://data (schema only). Returns Result.
func load_all(strict: bool = false) -> Result:
	return load_from("res://data", strict)

## Load + validate content from an arbitrary root (used by tests with fixture dirs).
func load_from(root: String, strict: bool = false) -> Result:
	_reset()
	# Simple kinds.
	for dir_name in SIMPLE_KINDS:
		var id_field := str(SIMPLE_KINDS[dir_name])
		var r := JsonLoader.load_dir(root.path_join(dir_name))
		if r.is_err():
			return r
		for rec in r.value:
			var vr := ContentValidator.validate_record(dir_name, rec)
			if vr.is_err():
				return vr
			_catalogs[dir_name][str(rec[id_field])] = rec
	# flags/ holds two record shapes (registry + unity sources).
	var fr := JsonLoader.load_dir(root.path_join("flags"))
	if fr.is_err():
		return fr
	for rec in fr.value:
		if rec.has("source_id"):
			var vr := ContentValidator.validate_record("unity_sources", rec)
			if vr.is_err():
				return vr
			_catalogs["unity_sources"][str(rec["source_id"])] = rec
		else:
			var vr2 := ContentValidator.validate_record("flags", rec)
			if vr2.is_err():
				return vr2
			_catalogs["flags"][str(rec["name"])] = rec
	# Optional strict cross-reference + domain pass (closed content set only).
	if strict:
		var refr := ContentValidator.validate_references(_catalogs)
		if refr.is_err():
			return refr
	_loaded = true
	return Result.make_ok()

func is_loaded() -> bool:
	return _loaded

# --- typed read-only accessors (ARCHITECTURE §6) ---

func beat(id: String) -> Dictionary: return _catalogs["beats"].get(id, {})
## Inline dialogue lines for a beat (R3b-2): an Array of { speaker, line }. [] when absent.
func beat_dialogue(id: String) -> Array: return _catalogs["beats"].get(id, {}).get("dialogue", [])
func branch(id: String) -> Dictionary: return _catalogs["branches"].get(id, {})
func ending(id: String) -> Dictionary: return _catalogs["endings"].get(id, {})
func item(id: String) -> Dictionary: return _catalogs["items"].get(id, {})
func enemy(id: String) -> Dictionary: return _catalogs["enemies"].get(id, {})
func ability(id: String) -> Dictionary: return _catalogs["abilities"].get(id, {})
func status(id: String) -> Dictionary: return _catalogs["statuses"].get(id, {})
func level_curve(id: String) -> Dictionary: return _catalogs["level_curves"].get(id, {})
func encounter(id: String) -> Dictionary: return _catalogs["encounters"].get(id, {})
func party_member(id: String) -> Dictionary: return _catalogs["party"].get(id, {})
func quest(id: String) -> Dictionary: return _catalogs["quests"].get(id, {})
func flag(name: String) -> Dictionary: return _catalogs["flags"].get(name, {})
func unity_source(id: String) -> Dictionary: return _catalogs["unity_sources"].get(id, {})

func has_flag(name: String) -> bool: return _catalogs["flags"].has(name)
func is_gating_flag(name: String) -> bool:
	return _catalogs["flags"].has(name) and bool(_catalogs["flags"][name].get("gating", false))

## Whole catalog for a kind (read-only intent). Used by validators/tests.
func catalog(kind: String) -> Dictionary:
	return _catalogs.get(kind, {})

func count(kind: String) -> int:
	return _catalogs.get(kind, {}).size()
