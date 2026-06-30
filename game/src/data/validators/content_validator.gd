## content_validator.gd — layered content validation (ADR-0007).
##
## Pure & static. Two layers:
##   1. SCHEMA      — required fields present, correct types, enums valid, closed effect-op
##                    vocabulary, id naming. Always run; a violation is fatal (fail-fast).
##   2. REFERENCES  — cross-catalog integrity + domain rules (registered flags, branches
##                    merge, encounter enemy/item refs, eight UNITY sources). Run only when
##                    a CLOSED content set is loaded (strict=true). The shipped Phase-3
##                    `game/data` is an intentionally-incomplete one-file-per-kind SAMPLER
##                    with dangling refs, so reference validation is OFF for it by default
##                    (see ContentDB.load_all). The capability is unit-tested directly with
##                    a self-contained good/bad fixture set.
class_name ContentValidator
extends RefCounted

# Declarative schema: kind -> { id, required:{field:type}, enums:{field:[...]} }.
const SCHEMA := {
	"beats": {
		"id": "id",
		"required": {"id": "str", "act": "int", "location": "str", "scene": "str", "effects": "array", "next": "array"},
		"enums": {"scene": ["dialogue", "battle", "overworld", "cutscene", "branch", "ending"]},
	},
	"branches": {
		"id": "id",
		"required": {"id": "str", "trigger_beat": "str", "merge_beat": "str", "options": "array"},
		"enums": {},
	},
	"flags": {
		"id": "name",
		"required": {"name": "str", "gating": "bool", "kind": "str"},
		"enums": {"kind": ["story", "branch", "unity_source", "derived", "final_choice", "ending", "emotional"]},
	},
	"unity_sources": {
		"id": "source_id",
		"required": {"source_id": "str", "beat": "array", "owner": "str"},
		"enums": {"owner": ["beat", "branch_option"]},
	},
	"endings": {
		"id": "id",
		"required": {"id": "str", "name": "str", "final_choice": "str", "divergence_beat": "str", "requires": "dict", "epilogue_set": "str"},
		"enums": {"id": ["A", "B", "C", "D"], "final_choice": ["SHARE", "SLEEP", "TAKE", "WAKE"]},
	},
	"items": {
		"id": "id",
		"required": {"id": "str", "name": "str", "category": "str"},
		"enums": {"category": ["consumable", "weapon", "armor", "accessory", "key"]},
	},
	"enemies": {
		"id": "id",
		# `abilities` (top-level id list) is optional: enemies may declare their moves
		# solely through the `ai` block (as the shipped sampler does).
		"required": {"id": "str", "name": "str", "stats": "dict", "xp": "int", "ai": "dict"},
		"enums": {},
	},
	"abilities": {
		"id": "id",
		"required": {"id": "str", "name": "str", "kind": "str", "cost": "dict", "target_kind": "str", "power": "int", "effects": "array", "accuracy": "int"},
		"enums": {
			"kind": ["ATTACK", "ABILITY", "ITEM"],
			"target_kind": ["SELF", "ALLY_SINGLE", "ALLY_ALL", "ENEMY_SINGLE", "ENEMY_ALL", "ANY"],
		},
	},
	"statuses": {
		"id": "id",
		"required": {"id": "str", "name": "str", "stack_rule": "str", "category": "str"},
		"enums": {
			"stack_rule": ["REFRESH", "STACK", "IGNORE"],
			"category": ["buff", "debuff", "control", "ailment"],
		},
	},
	"encounters": {
		"id": "id",
		"required": {"id": "str", "enemies": "array", "flee_allowed": "bool", "victory": "str", "defeat": "str"},
		"enums": {
			"victory": ["all_enemies_down", "survive_turns", "target_down"],
			"defeat": ["all_party_down"],
			"ambush": ["none", "player_first_strike", "enemy_ambush"],
			"formation": ["single_back", "line", "spread", "flank"],
		},
	},
	"level_curves": {
		"id": "id",
		"required": {"id": "str", "max_level": "int", "xp_to_next": "dict", "growth_per_level": "dict"},
		"enums": {},
	},
	"party": {
		"id": "id",
		"required": {"id": "str", "name": "str", "role": "str", "base_stats": "dict", "growth": "str", "abilities": "array"},
		"enums": {},
	},
	"quests": {
		"id": "id",
		"required": {"id": "str", "name": "str", "type": "str"},
		"enums": {"type": ["companion", "world", "recruitment", "mastery"]},
	},
}

## Validate one record of `kind` against its schema (layer 1). Returns Result.
static func validate_record(kind: String, rec: Dictionary) -> Result:
	if not SCHEMA.has(kind):
		return Result.make_err("no schema for content kind '%s'" % kind)
	var spec: Dictionary = SCHEMA[kind]
	var src := str(rec.get("_source", "<inline>"))
	var id_field := str(spec["id"])
	var rid := str(rec.get(id_field, "<missing-id>"))

	# required fields + types
	for field in spec["required"]:
		var want := str(spec["required"][field])
		if not rec.has(field):
			return _err(kind, src, rid, field, "required field missing")
		if not _type_ok(rec[field], want):
			return _err(kind, src, rid, field, "expected %s" % want)

	# enums
	for field in spec["enums"]:
		if rec.has(field):
			var allowed: Array = spec["enums"][field]
			if not allowed.has(rec[field]):
				return _err(kind, src, rid, field, "value '%s' not in %s" % [str(rec[field]), str(allowed)])

	# kind-specific structural checks
	match kind:
		"beats":
			return _validate_effects(kind, src, rid, rec.get("effects", []))
		"branches":
			for opt in rec.get("options", []):
				if not (opt is Dictionary):
					return _err(kind, src, rid, "options", "option must be an object")
				if not opt.has("id") or not opt.has("goto"):
					return _err(kind, src, rid, "options", "each option needs 'id' and 'goto'")
				var er := _validate_effects(kind, src, rid, opt.get("effects", []))
				if er.is_err():
					return er
		"enemies":
			return _validate_enemy_ai(src, rid, rec.get("ai", {}))
		"endings":
			# requires must contain NO derived-kind flag is a domain rule (strict); here we
			# just check shape.
			var req = rec.get("requires", {})
			if not (req is Dictionary):
				return _err(kind, src, rid, "requires", "must be an object")
	return Result.make_ok()

## Validate a list of effect ops (closed vocabulary, required sub-fields).
static func _validate_effects(kind: String, src: String, rid: String, effects) -> Result:
	if not (effects is Array):
		return _err(kind, src, rid, "effects", "must be an array")
	for e in effects:
		if not (e is Dictionary):
			return _err(kind, src, rid, "effects", "each effect must be an object")
		var op := str(e.get("op", ""))
		if not FlagOps.VALID_OPS.has(op):
			return _err(kind, src, rid, "effects", "unknown op '%s' (valid: %s)" % [op, str(FlagOps.VALID_OPS)])
		match op:
			"SET":
				if not e.has("flag"):
					return _err(kind, src, rid, "effects", "SET op missing 'flag'")
			"INC_UNITY":
				if not e.has("source_id"):
					return _err(kind, src, rid, "effects", "INC_UNITY op missing 'source_id'")
			"SET_FINAL_CHOICE":
				if not e.has("choice"):
					return _err(kind, src, rid, "effects", "SET_FINAL_CHOICE op missing 'choice'")
	return Result.make_ok()

static func _validate_enemy_ai(src: String, rid: String, ai) -> Result:
	if not (ai is Dictionary):
		return _err("enemies", src, rid, "ai", "must be an object")
	var policy := str(ai.get("policy", ""))
	if not ["basic", "caster", "boss_phased"].has(policy):
		return _err("enemies", src, rid, "ai.policy", "invalid policy '%s'" % policy)
	if not (ai.get("abilities", null) is Array):
		return _err("enemies", src, rid, "ai.abilities", "must be an array")
	for a in ai["abilities"]:
		if not (a is Dictionary) or not a.has("ability") or not a.has("target_rule"):
			return _err("enemies", src, rid, "ai.abilities", "each entry needs 'ability' and 'target_rule'")
	return Result.make_ok()

# --- layer 2: references + domain rules (strict / closed content set) ---

## Validate cross-catalog references + key domain rules over a CLOSED content set.
## `catalogs` is { kind: { id: record } }. Returns Result with the first violation.
static func validate_references(catalogs: Dictionary) -> Result:
	var flags: Dictionary = catalogs.get("flags", {})
	var beats: Dictionary = catalogs.get("beats", {})
	var items: Dictionary = catalogs.get("items", {})
	var enemies: Dictionary = catalogs.get("enemies", {})
	var abilities: Dictionary = catalogs.get("abilities", {})

	# Every flag a beat/branch SETs must be registered (and not enum/derived kind).
	for bid in beats:
		var rb: Result = _check_effects_flags(flags, beats[bid].get("effects", []), "beat", bid)
		if rb.is_err():
			return rb
		if beats[bid].has("encounter"):
			var enc := str(beats[bid]["encounter"])
			if not catalogs.get("encounters", {}).has(enc):
				return Result.make_err("beat '%s' references unknown encounter '%s'" % [bid, enc])
		for nxt in beats[bid].get("next", []):
			if not beats.has(str(nxt)):
				return Result.make_err("beat '%s' next references unknown beat '%s'" % [bid, str(nxt)])
	for brid in catalogs.get("branches", {}):
		var br: Dictionary = catalogs["branches"][brid]
		if not beats.has(str(br.get("merge_beat", ""))):
			return Result.make_err("branch '%s' merge_beat '%s' is not a real beat" % [brid, str(br.get("merge_beat", ""))])
		for opt in br.get("options", []):
			if not beats.has(str(opt.get("goto", ""))):
				return Result.make_err("branch '%s' option goto '%s' is not a real beat" % [brid, str(opt.get("goto", ""))])
			var ro: Result = _check_effects_flags(flags, opt.get("effects", []), "branch", brid)
			if ro.is_err():
				return ro
	# Encounter -> enemy / reward item refs.
	for eid in catalogs.get("encounters", {}):
		var enc: Dictionary = catalogs["encounters"][eid]
		for em in enc.get("enemies", []):
			if not enemies.has(str(em.get("enemy", ""))):
				return Result.make_err("encounter '%s' references unknown enemy '%s'" % [eid, str(em.get("enemy", ""))])
		for rw in enc.get("rewards", {}).get("items", []):
			if not items.has(str(rw.get("item", ""))):
				return Result.make_err("encounter '%s' reward references unknown item '%s'" % [eid, str(rw.get("item", ""))])
	# Enemy ai ability refs.
	for nid in enemies:
		for a in enemies[nid].get("ai", {}).get("abilities", []):
			if not abilities.has(str(a.get("ability", ""))):
				return Result.make_err("enemy '%s' ai references unknown ability '%s'" % [nid, str(a.get("ability", ""))])
	# Ending.requires must reference only registered, NON-derived flags.
	for endid in catalogs.get("endings", {}):
		var req: Dictionary = catalogs["endings"][endid].get("requires", {})
		var named: Array = []
		named.append_array(req.get("flags_all", []))
		named.append_array(req.get("flags_any", []))
		for fn in named:
			if not flags.has(str(fn)):
				return Result.make_err("ending '%s' requires unknown flag '%s'" % [endid, str(fn)])
			if str(flags[str(fn)].get("kind", "")) == "derived":
				return Result.make_err("ending '%s' requires derived flag '%s' (must be underlying)" % [endid, str(fn)])
	# Domain: exactly eight distinct UNITY source_ids.
	if catalogs.has("unity_sources"):
		var n: int = catalogs["unity_sources"].size()
		if n != 8:
			return Result.make_err("expected exactly 8 UNITY source_ids, found %d" % n)
	return Result.make_ok()

static func _check_effects_flags(flags: Dictionary, effects, owner_kind: String, owner_id: String) -> Result:
	for e in effects:
		if str(e.get("op", "")) == "SET":
			var fn := str(e.get("flag", ""))
			if not flags.has(fn):
				return Result.make_err("%s '%s' SETs unregistered flag '%s'" % [owner_kind, owner_id, fn])
			var k := str(flags[fn].get("kind", ""))
			if k == "derived" or k == "final_choice" or k == "ending":
				return Result.make_err("%s '%s' SETs %s-kind flag '%s' (not a boolean SET target)" % [owner_kind, owner_id, k, fn])
	return Result.make_ok()

# --- helpers ---

static func _type_ok(v, want: String) -> bool:
	match want:
		"str", "id": return v is String
		"int": return (v is int) or (v is float and float(v) == floor(v))
		"float": return (v is float) or (v is int)
		"bool": return v is bool
		"array": return v is Array
		"dict": return v is Dictionary
	return false

static func _err(kind: String, src: String, rid: String, field: String, rule: String) -> Result:
	return Result.make_err("[%s] %s (id=%s) field '%s': %s" % [kind, src, rid, field, rule])
