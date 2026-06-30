## story_graph.gd — navigable beat+branch graph over ContentDB (ADR-0003, ARCHITECTURE §7.5).
##
## Pure & headless: built from an injected ContentDB (no scene tree, no autoload, no RNG).
## Indexes branches by their `trigger_beat` so the director can detect a fork the instant it
## enters that beat, resolves a beat's gated successors (`next`), exposes a branch's options /
## merge target, and validates that a content set is fully connected (every `next`/`goto`/
## `trigger_beat`/`merge_beat` names a real beat). Story logic only — no flag mutation here.
##
## `next` entry shapes (both accepted):
##   "A2-05"                              — unconditional successor
##   { "beat": "A2-05", "if_flag": "X" }  — successor gated by a boolean flag (skipped if X is
##                                          false/absent). `goto` is accepted as a synonym for
##                                          `beat` so authors can reuse the branch-option key.
class_name StoryGraph
extends RefCounted

var _db                                  # ContentDB (injected)
var _branch_by_trigger: Dictionary = {}  # trigger_beat_id -> branch record

func _init(content_db) -> void:
	_db = content_db
	_index()

func _index() -> void:
	_branch_by_trigger.clear()
	for bid in _db.catalog("branches"):
		var br: Dictionary = _db.catalog("branches")[bid]
		var trig := str(br.get("trigger_beat", ""))
		if trig != "":
			_branch_by_trigger[trig] = br

# --- beats ---

func has_beat(beat_id: String) -> bool:
	return not _db.beat(beat_id).is_empty()

func beat(beat_id: String) -> Dictionary:
	return _db.beat(beat_id)

## Gated successors of a beat, in authored order (the spine takes the first that passes).
## `flags` is a FlagStore; a dict entry's `if_flag` must be true for the successor to appear.
func next_beats(beat_id: String, flags) -> Array:
	var out: Array = []
	for entry in _db.beat(beat_id).get("next", []):
		var target := ""
		var guard := ""
		if entry is String:
			target = entry
		elif entry is Dictionary:
			target = str(entry.get("beat", entry.get("goto", "")))
			guard = str(entry.get("if_flag", ""))
		if target == "":
			continue
		if guard != "" and not flags.get_flag(guard):
			continue
		out.append(target)
	return out

# --- branches ---

func is_branch_node(beat_id: String) -> bool:
	return _branch_by_trigger.has(beat_id)

## The branch record triggered when this beat is entered ({} if the beat is not a trigger).
func branch_at(beat_id: String) -> Dictionary:
	return _branch_by_trigger.get(beat_id, {})

func branch_options(branch_id: String) -> Array:
	return _db.branch(branch_id).get("options", [])

## The option record for `option_id` within a branch ({} if not found).
func option(branch_id: String, option_id: String) -> Dictionary:
	for opt in branch_options(branch_id):
		if opt is Dictionary and str(opt.get("id", "")) == option_id:
			return opt
	return {}

func merge_beat(branch_id: String) -> String:
	return str(_db.branch(branch_id).get("merge_beat", ""))

# --- connectivity validation (for a given content set) ---

## Assert every beat `next`, every branch `trigger_beat`/`merge_beat`, and every option `goto`
## names a real beat. Returns the first violation as Result.err, else Result.ok.
func validate_connectivity() -> Result:
	for bid in _db.catalog("beats"):
		for entry in _db.beat(bid).get("next", []):
			var target := ""
			if entry is String:
				target = entry
			elif entry is Dictionary:
				target = str(entry.get("beat", entry.get("goto", "")))
			if target != "" and not has_beat(target):
				return Result.make_err("beat '%s' next references unknown beat '%s'" % [bid, target])
	for brid in _db.catalog("branches"):
		var br: Dictionary = _db.catalog("branches")[brid]
		if not has_beat(str(br.get("trigger_beat", ""))):
			return Result.make_err("branch '%s' trigger_beat '%s' is not a real beat" % [brid, str(br.get("trigger_beat", ""))])
		if not has_beat(str(br.get("merge_beat", ""))):
			return Result.make_err("branch '%s' merge_beat '%s' is not a real beat" % [brid, str(br.get("merge_beat", ""))])
		for opt in br.get("options", []):
			if not has_beat(str(opt.get("goto", ""))):
				return Result.make_err("branch '%s' option '%s' goto '%s' is not a real beat"
					% [brid, str(opt.get("id", "")), str(opt.get("goto", ""))])
	return Result.make_ok()
