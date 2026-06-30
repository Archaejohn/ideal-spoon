## story_director.gd — drives the beat ledger (ADR-0003 / ADR-0008, ARCHITECTURE §7.5).
##
## Headless coordinator logic: extends RefCounted and takes ALL collaborators by injection
## (ContentDB, GameState, and an optional EventBus). It NEVER touches the scene tree
## (no get_tree/get_node/change_scene) — instead it emits an `EventBus.scene_intent(state_key,
## ctx)` so the Round-3 SceneRouter performs the actual transition (ADR-0008 "how the story
## engine drives scene loads"). A thin autoload Node can construct + own one of these at boot.
##
## Responsibilities:
##   * goto_beat(id)  — enter a beat: apply its effects exactly once (per-beat ledger), emit
##                      `beat_entered` + a `scene_intent`, fire lock/choice/ending signals when
##                      those ops first run, and OPEN a branch if the beat is a branch trigger.
##   * advance()      — walk the single-track spine to the first gated successor.
##   * choose(b,o)    — apply a branch option's effects and route to its `goto` (paths reconverge
##                      at the branch's authored merge beat via the option targets' `next`).
## Re-entry safe: effects are guarded by GameState.applied_beats, so re-entering a beat re-emits
## presentation signals but never double-applies SET / double-counts UNITY.
class_name StoryDirector
extends RefCounted

## beat.scene -> SceneRouter state key (ADR-0008 mapping table).
const SCENE_TO_STATE := {
	"dialogue": "CUTSCENE",
	"cutscene": "CUTSCENE",
	"branch": "CUTSCENE",
	"battle": "BATTLE",
	"overworld": "OVERWORLD",
	"ending": "CUTSCENE",
}

var _db                          # ContentDB (injected)
var _state                       # GameState (injected)
var _bus                         # EventBus (injected, optional — may be null when headless)
var _graph: StoryGraph
var _open_branch_id: String = "" # the branch awaiting choose() ("" when none)
## Per-branch "already resolved" ledger (REVIEW_phase3_round2 N3): branch_id -> chosen option_id.
## Once a branch is resolved, re-entering its trigger (via goto_beat back-navigation, possible
## once the SceneRouter exists) re-opens it, but choose() will NOT apply a SECOND option's
## identity flags — SET never clears the first, so without this guard a second branch-identity
## flag could be set. Mirrors GameState.applied_beats for branch choices.
var _resolved_branches: Dictionary = {}

func _init(content_db, game_state, event_bus = null) -> void:
	_db = content_db
	_state = game_state
	_bus = event_bus
	_graph = StoryGraph.new(content_db)

func graph() -> StoryGraph:
	return _graph

func current_beat_id() -> String:
	return _state.current_beat_id

## The branch currently awaiting a choose() ("" when no branch is open).
func current_branch_id() -> String:
	return _open_branch_id

# --- entering / advancing ---

## Enter a beat: set it current, apply its effects (idempotently), emit presentation signals,
## and open a branch if this beat triggers one. Returns Result (err if the beat is unknown).
func goto_beat(beat_id: String) -> Result:
	var beat: Dictionary = _db.beat(beat_id)
	if beat.is_empty():
		return Result.make_err("goto_beat: unknown beat '%s'" % beat_id)
	_state.current_beat_id = beat_id
	var ar := apply_beat_effects(beat_id)
	if ar.is_err():
		return ar
	var newly_applied := bool(ar.value)
	_emit("beat_entered", [beat_id])
	_emit("scene_intent", [state_for(beat), _scene_ctx(beat)])
	# Op-derived signals fire only when the effects actually ran this entry (first visit).
	if newly_applied:
		_emit_effect_signals(beat)
	# Open a branch if this beat is its trigger; otherwise clear any stale open branch.
	if _graph.is_branch_node(beat_id):
		var br := _graph.branch_at(beat_id)
		_open_branch_id = str(br.get("id", ""))
		_emit("branch_opened", [_open_branch_id, offered_options(_open_branch_id)])
	else:
		_open_branch_id = ""
	return Result.make_ok(newly_applied)

## Apply a beat's declared effect ops against the FlagStore, exactly once per beat.
## Returns Result.ok(true) if it applied this call, Result.ok(false) if already applied
## (idempotent re-entry), or Result.err on an unknown/invalid op.
func apply_beat_effects(beat_id: String) -> Result:
	var beat: Dictionary = _db.beat(beat_id)
	if beat.is_empty():
		return Result.make_err("apply_beat_effects: unknown beat '%s'" % beat_id)
	if not _state.mark_beat_applied(beat_id):
		return Result.make_ok(false)
	var r := FlagOps.apply_effects(_state.flags, beat.get("effects", []))
	if r.is_err():
		return r
	return Result.make_ok(true)

## Walk the single-track spine to the first gated successor of the current beat. Refuses while
## a branch is open (use choose()). Returns Result.ok(true) if it moved, ok(false) at a terminal
## beat (no successor), err on a bad state.
func advance() -> Result:
	var id: String = _state.current_beat_id
	if id == "":
		return Result.make_err("advance: no current beat")
	if _open_branch_id != "":
		return Result.make_err("advance: branch '%s' is open — call choose()" % _open_branch_id)
	var nexts := _graph.next_beats(id, _state.flags)
	if nexts.is_empty():
		return Result.make_ok(false)
	return goto_beat(str(nexts[0]))

# --- branches ---

## Option ids whose `if_flag` guard passes (the set the UI should present), in authored order.
func offered_options(branch_id: String) -> Array:
	var out: Array = []
	for opt in _graph.branch_options(branch_id):
		if opt is Dictionary and _option_available(opt):
			out.append(str(opt.get("id", "")))
	return out

## Accept a chosen option on the open branch: apply its effects, then route to its `goto`
## (the target's `next` reconverges at the branch's merge beat). Returns Result (err if the
## branch isn't open, the option is unknown, or the option's gate is closed).
func choose(branch_id: String, option_id: String) -> Result:
	if _open_branch_id != branch_id:
		return Result.make_err("choose: branch '%s' is not open (open: '%s')" % [branch_id, _open_branch_id])
	var opt := _graph.option(branch_id, option_id)
	if opt.is_empty():
		return Result.make_err("choose: branch '%s' has no option '%s'" % [branch_id, option_id])
	if not _option_available(opt):
		return Result.make_err("choose: option '%s' is gated off (if_flag not satisfied)" % option_id)
	var goto := str(opt.get("goto", ""))
	if goto == "":
		return Result.make_err("choose: option '%s' has no goto" % option_id)
	# Per-branch resolution guard (N3): a branch's identity flags are applied at most once. If the
	# branch was already resolved with a DIFFERENT option, refuse — re-choosing must not set a
	# second option's identity flags. Re-choosing the SAME option is idempotent (re-routes only).
	var prior := str(_resolved_branches.get(branch_id, ""))
	if prior != "" and prior != option_id:
		return Result.make_err("choose: branch '%s' already resolved with option '%s'" % [branch_id, prior])
	if prior == "":
		var r := FlagOps.apply_effects(_state.flags, opt.get("effects", []))
		if r.is_err():
			return r
		_resolved_branches[branch_id] = option_id
	_open_branch_id = ""   # branch resolved; the goto target drives toward the merge beat
	return goto_beat(goto)

func merge_beat(branch_id: String) -> String:
	return _graph.merge_beat(branch_id)

# --- helpers ---

func state_for(beat: Dictionary) -> String:
	return str(SCENE_TO_STATE.get(str(beat.get("scene", "")), "CUTSCENE"))

func _scene_ctx(beat: Dictionary) -> Dictionary:
	return {
		"beat_id": str(beat.get("id", "")),
		"scene": str(beat.get("scene", "")),
		"location": str(beat.get("location", "")),
		"encounter": str(beat.get("encounter", "")),
	}

func _option_available(opt: Dictionary) -> bool:
	if not opt.has("if_flag"):
		return true
	return _state.flags.get_flag(str(opt["if_flag"]))

## Fire the EventBus signals tied to the state-changing ops a beat ran (lock / final-choice /
## ending). Ending also records the unlock in GameState (ADR-0006 Crossroads).
func _emit_effect_signals(beat: Dictionary) -> void:
	for e in beat.get("effects", []):
		match str(e.get("op", "")):
			"LOCK_ENDINGS":
				_emit("flags_locked", [])
			"SET_FINAL_CHOICE":
				_emit("final_choice_made", [_state.flags.final_choice()])
			"RECORD_ENDING":
				var ending: int = _state.flags.ending()
				_state.record_ending(ending)
				_emit("ending_reached", [ending])

func _emit(signal_name: String, args: Array) -> void:
	if _bus == null:
		return
	match args.size():
		0: _bus.emit_signal(signal_name)
		1: _bus.emit_signal(signal_name, args[0])
		2: _bus.emit_signal(signal_name, args[0], args[1])
		_: push_error("StoryDirector._emit: unsupported arg count %d" % args.size())
