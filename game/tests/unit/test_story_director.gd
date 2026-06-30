## test_story_director.gd — StoryGraph + StoryDirector behavior (ADR-0003 / ADR-0008).
##
## Uses a small SELF-CONTAINED fixture story graph (tests/helpers/content/story) loaded into a
## real ContentDB, plus a fresh headless GameState, so the director is exercised through its
## real APIs with no scene tree. Covers: apply-once idempotency, branch open/options/goto/merge
## convergence, if_flag gating (beat `next` AND branch option), LOCK_ENDINGS freeze, and full
## scripted traversals that yield endings B and A via the UNMODIFIED EndingResolver. Plus a guard
## test that the director logic never references the scene tree.
extends GutTest

const ContentDBScript := preload("res://src/data/content_db.gd")
const GameStateScript := preload("res://src/core/game_state.gd")
const FIXTURE := "res://tests/helpers/content/story"

var _db
var _gs
var _dir: StoryDirector

func before_each() -> void:
	_db = autofree(ContentDBScript.new())
	var r: Result = _db.load_from(FIXTURE, false)
	assert_true(r.is_ok(), "fixture loads cleanly: %s" % (r.error if r != null else ""))
	_gs = autofree(GameStateScript.new())
	_gs.flags = FlagStore.new()
	# Inject the real EventBus autoload so signal emission is exercised; watch it per-test.
	_dir = StoryDirector.new(_db, _gs, EventBus)

# --- graph wiring -----------------------------------------------------------

func test_graph_indexes_branch_trigger_and_merge():
	var g := _dir.graph()
	assert_true(g.is_branch_node("FX-BR-TRIGGER"), "trigger beat is a branch node")
	assert_false(g.is_branch_node("FX-A1"), "ordinary beat is not a branch node")
	assert_eq(g.branch_at("FX-BR-TRIGGER").get("id", ""), "FX-BR1", "branch indexed by trigger")
	assert_eq(g.merge_beat("FX-BR1"), "FX-MERGE", "merge beat exposed")
	assert_true(g.validate_connectivity().is_ok(), "fixture graph is fully connected")

# --- idempotent effect application -----------------------------------------

func test_entering_a_beat_applies_effects_exactly_once():
	watch_signals(EventBus)
	var r1: Result = _dir.goto_beat("FX-UNITY")
	assert_true(r1.is_ok() and bool(r1.value), "first entry applies effects")
	assert_eq(_gs.flags.unity(), 1, "UNITY counted once")
	assert_true(_gs.flags.get_flag("FX_ONCE"), "flag set on first entry")
	# Re-enter the SAME beat: presentation re-fires but effects must NOT re-apply.
	var r2: Result = _dir.goto_beat("FX-UNITY")
	assert_true(r2.is_ok() and not bool(r2.value), "re-entry reports not-newly-applied")
	assert_eq(_gs.flags.unity(), 1, "UNITY not double-counted on re-entry")
	assert_eq(_gs.applied_beats.count("FX-UNITY"), 1, "ledger records the beat once")
	assert_signal_emitted(EventBus, "beat_entered")

# --- branch: open, options, goto, merge convergence ------------------------

func test_branch_opens_at_trigger_with_offered_options():
	watch_signals(EventBus)
	_dir.goto_beat("FX-BR-TRIGGER")
	assert_eq(_dir.current_branch_id(), "FX-BR1", "branch is open at its trigger")
	# `secret` is gated by HAS_KEY (absent) → not offered.
	assert_eq(_dir.offered_options("FX-BR1"), ["left", "right"], "gated option hidden")
	assert_signal_emitted(EventBus, "branch_opened")

func test_left_option_applies_flags_and_routes_then_merges():
	_dir.goto_beat("FX-BR-TRIGGER")
	var r: Result = _dir.choose("FX-BR1", "left")
	assert_true(r.is_ok(), "choosing left succeeds")
	assert_true(_gs.flags.get_flag("FX_LEFT_TAKEN"), "left option flag applied")
	assert_eq(_dir.current_beat_id(), "FX-LEFT", "routed to option goto")
	assert_eq(_dir.current_branch_id(), "", "branch closed after choose")
	# The option target's `next` reconverges at the branch merge beat.
	_dir.advance()
	assert_eq(_dir.current_beat_id(), "FX-MERGE", "left path converges at merge")
	# Merge beat's if_flag-guarded recruitment fired because FX_LEFT_TAKEN is set.
	assert_true(_gs.flags.get_flag("KESTREL_RECRUITED"), "merge recruitment applied on left path")

func test_right_option_converges_at_same_merge_without_recruitment():
	_dir.goto_beat("FX-BR-TRIGGER")
	_dir.choose("FX-BR1", "right")
	assert_eq(_dir.current_beat_id(), "FX-RIGHT", "routed to right goto")
	assert_true(_gs.flags.get_flag("FX_RIGHT_TAKEN"), "right option flag applied")
	_dir.advance()
	assert_eq(_dir.current_beat_id(), "FX-MERGE", "right path converges at the SAME merge")
	# Right path never set FX_LEFT_TAKEN, so the guarded recruitment is skipped.
	assert_false(_gs.flags.get_flag("KESTREL_RECRUITED"), "guarded merge effect skipped on right path")

# --- gating ----------------------------------------------------------------

func test_next_gated_by_if_flag_is_skipped_when_flag_absent():
	_dir.goto_beat("FX-GATE")
	_dir.advance()
	assert_eq(_dir.current_beat_id(), "FX-PLAIN", "gated successor skipped; spine takes the open one")
	assert_true(_gs.flags.get_flag("REACHED_PLAIN"), "plain beat effects ran")
	assert_false(_gs.flags.get_flag("REACHED_SECRET"), "secret beat never entered")

func test_next_gated_by_if_flag_is_taken_when_flag_present():
	_gs.flags.set_flag("HAS_KEY")
	_dir.goto_beat("FX-GATE")
	_dir.advance()
	assert_eq(_dir.current_beat_id(), "FX-SECRET", "gated successor taken when flag present")
	assert_true(_gs.flags.get_flag("REACHED_SECRET"), "secret beat effects ran")

func test_gated_branch_option_is_offered_and_selectable_only_with_flag():
	# Without HAS_KEY the secret option is neither offered nor selectable.
	_dir.goto_beat("FX-BR-TRIGGER")
	assert_false(_dir.offered_options("FX-BR1").has("secret"), "secret option hidden without flag")
	var blocked: Result = _dir.choose("FX-BR1", "secret")
	assert_true(blocked.is_err(), "selecting a gated-off option is rejected")
	# With HAS_KEY it becomes offered and selectable.
	before_each()
	_gs.flags.set_flag("HAS_KEY")
	_dir.goto_beat("FX-BR-TRIGGER")
	assert_true(_dir.offered_options("FX-BR1").has("secret"), "secret option offered with flag")
	var ok: Result = _dir.choose("FX-BR1", "secret")
	assert_true(ok.is_ok(), "gated option selectable when flag present")
	assert_true(_gs.flags.get_flag("FX_SECRET_TAKEN"), "secret option effects applied")

# --- LOCK_ENDINGS freeze ---------------------------------------------------

func test_lock_endings_freezes_gating_flags_and_unity():
	watch_signals(EventBus)
	# Seed some pre-lock state.
	_gs.flags.set_flag("ORDER_ALLIED")
	_dir.goto_beat("FX-LOCK")
	assert_true(_gs.flags.is_locked(), "store locked at the lock beat")
	assert_signal_emitted(EventBus, "flags_locked")
	# Post-lock beat tries to SET a gating flag and INC_UNITY — both must be frozen no-ops.
	_dir.advance()
	assert_eq(_dir.current_beat_id(), "FX-POSTLOCK", "advanced into post-lock beat")
	assert_false(_gs.flags.get_flag("KESTREL_RECRUITED"), "gating SET frozen after lock")
	assert_eq(_gs.flags.unity(), 0, "UNITY frozen after lock")

# --- full traversals → endings via the UNMODIFIED EndingResolver -----------

func test_full_traversal_yields_ending_B():
	watch_signals(EventBus)
	_dir.goto_beat("FX-CHOICE-B")
	assert_eq(_gs.flags.final_choice(), Ids.FinalChoice.SLEEP, "SLEEP recorded")
	assert_signal_emitted(EventBus, "final_choice_made")
	_dir.advance()   # → FX-RECORD-B (RECORD_ENDING)
	assert_eq(_dir.current_beat_id(), "FX-RECORD-B", "reached the ending beat")
	assert_eq(_gs.flags.ending(), Ids.EndingId.B, "SLEEP resolves to ending B")
	assert_true(_gs.endings_unlocked.has(Ids.EndingId.B), "ending B unlocked in GameState")
	assert_signal_emitted(EventBus, "ending_reached")

func test_full_traversal_yields_ending_A():
	# FX-SET-A sets KESTREL+ORDER and 5 UNITY sources (→ FACTIONS_UNITED), then lock, SHARE, record.
	_dir.goto_beat("FX-SET-A")
	assert_eq(_gs.flags.unity(), 5, "five UNITY sources counted")
	_dir.advance()   # → FX-LOCK-A
	assert_true(_gs.flags.is_locked(), "endings locked before the final choice")
	_dir.advance()   # → FX-CHOICE-A (SHARE)
	assert_eq(_gs.flags.final_choice(), Ids.FinalChoice.SHARE, "SHARE recorded")
	_dir.advance()   # → FX-RECORD-A (RECORD_ENDING)
	assert_eq(_gs.flags.ending(), Ids.EndingId.A, "SHARE + FACTIONS_UNITED resolves to ending A")
	assert_true(_gs.endings_unlocked.has(Ids.EndingId.A), "ending A unlocked in GameState")

# --- error / boundary ------------------------------------------------------

func test_goto_unknown_beat_errors():
	var r: Result = _dir.goto_beat("NOPE")
	assert_true(r.is_err(), "unknown beat is rejected")

func test_advance_refuses_while_branch_open():
	_dir.goto_beat("FX-BR-TRIGGER")
	var r: Result = _dir.advance()
	assert_true(r.is_err(), "advance refuses while a branch is open")

func test_director_logic_does_not_reference_the_scene_tree():
	# Guard (ADR-0008): the director is headless logic — no scene-tree coupling.
	var src := FileAccess.get_file_as_string("res://src/story/story_director.gd")
	assert_ne(src, "", "director source readable")
	# Scan CODE only — strip comment lines so the module docstring (which names these tokens
	# precisely to say it does NOT use them) doesn't trip the guard.
	var code_lines: Array = []
	for line in src.split("\n"):
		if not line.strip_edges().begins_with("#"):
			code_lines.append(line)
	var code := "\n".join(PackedStringArray(code_lines))
	for forbidden in ["get_tree", "get_node", "add_child", "change_scene", "SceneTree"]:
		assert_false(code.contains(forbidden), "director code must not reference '%s'" % forbidden)
	# It is RefCounted (injected deps), not a Node bound to the tree.
	assert_true(src.contains("extends RefCounted"), "director extends RefCounted")
