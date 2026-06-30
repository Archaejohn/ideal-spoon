## game_state.gd — the entire savable run state (ARCHITECTURE §7.2, ADR-0005 §d).
##
## Autoload #6, DATA ONLY (god-object guard): it holds state but contains NO rules — it
## cannot decide an ending, roll damage, or pick a branch. Those live in EndingResolver,
## BattleEngine, StoryGraph. The single source of truth for everything SaveManager
## serializes (ADR-0005). Enum story choices live on `flags` (FlagStore), reached via
## flags.final_choice()/flags.ending().
extends Node

const SAVE_VERSION := 1
const MAGIC := "AETHER"

var flags: FlagStore                       # booleans + UNITY + enum choices
var party: Array = []                      # PartyMemberState dicts (id, level, xp, ...)
var inventory: Dictionary = { "items": {}, "key_items": [] }
var quests: Dictionary = {}                # quest_id -> "LOCKED"|"AVAILABLE"|"ACTIVE"|"DONE"
var current_beat_id: String = ""
var applied_beats: Array = []              # per-beat idempotency ledger (ADR-0003)
var location: Dictionary = { "skyland": "", "entry": "" }
var rng_state: Dictionary = {}             # RngService.export_state()
var endings_unlocked: Array = []           # [EndingId] for the Crossroads selector
var divergence_snapshots: Dictionary = {}  # ending_id -> snapshot (ADR-0006)
var playtime_secs: float = 0.0
var save_version: int = SAVE_VERSION

func _ready() -> void:
	if flags == null:
		flags = FlagStore.new()

## Start a fresh run: seed the RNG, reset all run state (ARCHITECTURE §5 / §7.2).
func new_run(master_seed: int) -> void:
	flags = FlagStore.new()
	party = []
	inventory = { "items": {}, "key_items": [] }
	quests = {}
	current_beat_id = ""
	applied_beats = []
	location = { "skyland": "", "entry": "" }
	endings_unlocked = []
	divergence_snapshots = {}
	playtime_secs = 0.0
	save_version = SAVE_VERSION
	var rng := _rng_service()
	if rng != null:
		rng.seed_run(master_seed)
		rng_state = rng.export_state()
	else:
		rng_state = { "master_seed": master_seed, "cursors": {} }

## Record idempotently that a beat's effects have been applied (ADR-0003 ledger).
func mark_beat_applied(beat_id: String) -> bool:
	if applied_beats.has(beat_id):
		return false
	applied_beats.append(beat_id)
	return true

func record_ending(ending: int, divergence_snapshot: Dictionary = {}) -> void:
	flags.set_ending(ending)
	if not endings_unlocked.has(ending):
		endings_unlocked.append(ending)
	if not divergence_snapshot.is_empty():
		divergence_snapshots[Ids.ending_to_str(ending)] = divergence_snapshot

# --- serialization (ADR-0005 §d) ---

func to_dict() -> Dictionary:
	# Refresh cursors from the live RNG so the save reflects draws taken this session.
	var rng := _rng_service()
	if rng != null:
		rng_state = rng.export_state()
	var flag_dict := flags.to_dict()
	return {
		"save_version": save_version,
		"magic": MAGIC,
		"playtime_secs": playtime_secs,
		"rng_state": rng_state.duplicate(true),
		"story": {
			"current_beat_id": current_beat_id,
			"flags": flag_dict["flags"],
			"unity": flag_dict["unity"],
			"unity_sources_applied": flag_dict["unity_sources_applied"],
			"choices": flag_dict["choices"],
			"endings_locked": flag_dict["endings_locked"],
			"applied_beats": applied_beats.duplicate(),
		},
		"party": party.duplicate(true),
		"inventory": inventory.duplicate(true),
		"quests": quests.duplicate(true),
		"location": location.duplicate(true),
		"endings_unlocked": endings_unlocked.duplicate(),
		"divergence_snapshots": divergence_snapshots.duplicate(true),
	}

func from_dict(d: Dictionary) -> void:
	save_version = int(d.get("save_version", SAVE_VERSION))
	playtime_secs = float(d.get("playtime_secs", 0.0))
	rng_state = (d.get("rng_state", {}) as Dictionary).duplicate(true)
	var story: Dictionary = d.get("story", {})
	flags = FlagStore.new()
	flags.from_dict({
		"flags": story.get("flags", {}),
		"unity": story.get("unity", 0),
		"unity_sources_applied": story.get("unity_sources_applied", []),
		"endings_locked": story.get("endings_locked", false),
		"choices": story.get("choices", {}),
	})
	current_beat_id = str(story.get("current_beat_id", ""))
	applied_beats = (story.get("applied_beats", []) as Array).duplicate()
	party = (d.get("party", []) as Array).duplicate(true)
	inventory = (d.get("inventory", { "items": {}, "key_items": [] }) as Dictionary).duplicate(true)
	quests = (d.get("quests", {}) as Dictionary).duplicate(true)
	location = (d.get("location", { "skyland": "", "entry": "" }) as Dictionary).duplicate(true)
	endings_unlocked = (d.get("endings_unlocked", []) as Array).duplicate()
	divergence_snapshots = (d.get("divergence_snapshots", {}) as Dictionary).duplicate(true)
	# Restore RNG cursors so subsequent draws continue the exact sequence.
	var rng := _rng_service()
	if rng != null and not rng_state.is_empty():
		rng.import_state(rng_state)

## Deep copy for checkpoints (ADR-0005 §c). A plain dict so it can be stored/serialized.
func snapshot() -> Dictionary:
	return to_dict().duplicate(true)

func restore_snapshot(snap: Dictionary) -> void:
	from_dict(snap)

func _rng_service() -> Node:
	var tree := get_tree() if is_inside_tree() else null
	if tree != null and tree.root != null:
		return tree.root.get_node_or_null("RngService")
	return null
