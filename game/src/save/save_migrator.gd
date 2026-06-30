## save_migrator.gd — ordered, pure version migrations (ADR-0005 §d).
##
## Pure (RefCounted, no I/O). Applies ordered v(n)->v(n+1) steps to a decoded payload dict
## until it reaches the current SAVE_VERSION, refuses a save newer than the build, and
## re-validates the result's basic shape after migrating. The pre-migration *file* backup
## is written by SaveManager (it owns the disk); the migrator stays a pure transform.
##
## STEPS maps an integer version `n` to a Callable(payload:Dictionary) -> Dictionary that
## upgrades a v`n` payload to v`n+1`. It is empty at v1 (the framework is ready for v2).
## migrate() also accepts an injected target/steps so the stepping + refusal logic can be
## exercised end-to-end without bumping the real build version.
class_name SaveMigrator
extends RefCounted

const CURRENT_VERSION := 1
const STEPS := {}   # n(int) -> Callable(Dictionary) -> Dictionary  (migrates v n -> v n+1)

static func payload_version(payload: Dictionary) -> int:
	return int(payload.get("save_version", 1))

static func needs_migration(payload: Dictionary) -> bool:
	return payload_version(payload) < CURRENT_VERSION

## Migrate `payload` up to `target`, applying `steps`. The input dict is NOT mutated.
## Result.ok -> migrated payload dict ; Result.err -> reason (incl. "newer than build").
static func migrate(payload: Dictionary, target: int = CURRENT_VERSION, steps: Dictionary = STEPS) -> Result:
	var v := payload_version(payload)
	if v > target:
		return Result.make_err("save is newer than this build (v%d > v%d) — refusing to load" % [v, target])
	var cur: Dictionary = payload.duplicate(true)
	while v < target:
		if not steps.has(v):
			return Result.make_err("no migration step registered for v%d -> v%d" % [v, v + 1])
		var step: Callable = steps[v]
		var migrated: Variant = step.call(cur)
		if typeof(migrated) != TYPE_DICTIONARY:
			return Result.make_err("migration step v%d returned non-dict" % v)
		cur = migrated
		v += 1
		cur["save_version"] = v
	if not _is_valid_shape(cur):
		return Result.make_err("post-migration payload failed shape re-validation")
	return Result.make_ok(cur)

## Minimal structural re-validation after migrating (ADR-0005 §d: a buggy migration must
## not silently produce a degenerate save). The full schema lives in GameState.from_dict.
static func _is_valid_shape(payload: Dictionary) -> bool:
	if not payload.has("save_version"):
		return false
	if not (payload.has("story") and typeof(payload["story"]) == TYPE_DICTIONARY):
		return false
	if not (payload.has("rng_state") and typeof(payload["rng_state"]) == TYPE_DICTIONARY):
		return false
	return true
