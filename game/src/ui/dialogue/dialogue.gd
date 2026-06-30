## dialogue.gd — the scripted dialogue / cutscene screen (Phase 3 R3b-2, ADR-0007 / ADR-0008).
##
## PRESENTATION ONLY. Renders a beat's inline `dialogue` list (an array of { speaker, line }) one
## line at a time: speaker name + line, a simple per-speaker tint, advance on click / Enter. The
## line list comes from the beat the StoryDirector routed us to (SceneRouter.current_ctx().beat_id
## -> ContentDB.beat_dialogue). Placeholder visuals (ColorRect / Label) — real art is Phase 4.
##
## On completion the spine continues through the StoryDirector verbs the GameCoordinator exposes:
##   * a BRANCH-trigger beat (a fork is open) -> show the offered options as buttons; a pick calls
##     GameCoordinator.choose_branch(option_id), which applies effects and routes onward.
##   * otherwise -> GameCoordinator.advance_story(); if there is no successor (a terminal closing
##     beat) the slice is complete and we route back to the Title.
extends Control

## Per-speaker placeholder tint (real portraits are Phase 4). Unknown speakers get the default.
const SPEAKER_TINTS := {
	"wren": Color(0.96, 0.80, 0.42),
	"pell": Color(0.62, 0.78, 0.95),
	"tam": Color(0.72, 0.88, 0.56),
	"sable": Color(0.80, 0.66, 0.60),
}
const DEFAULT_TINT := Color(0.70, 0.72, 0.82)

var _lines: Array = []
var _idx: int = 0
var _done: bool = false
var _showing_choices: bool = false

func _ready() -> void:
	_hide_choices()
	# Resolve the line list from the beat the router brought us to (unless a test pre-set it).
	if _lines.is_empty():
		_lines = _lines_from_router()
	if _lines.is_empty():
		# A CUTSCENE beat with no authored lines: continue immediately rather than stall.
		_on_lines_complete()
		return
	_idx = 0
	_show_line()

## Test seam: inject the line list before adding the scene to the tree.
func set_lines(lines: Array) -> void:
	_lines = lines.duplicate(true)

func is_done() -> bool:
	return _done

# --- input: advance on click / Enter ---

func _unhandled_input(event: InputEvent) -> void:
	if _showing_choices or _done:
		return
	var advance := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance = true
	elif event.is_action_pressed("ui_accept"):
		advance = true
	if advance:
		accept_event()
		advance_line()

## Step to the next line, or finish the sequence at the end. Public so a headless test can drive it.
func advance_line() -> void:
	if _showing_choices or _done:
		return
	_idx += 1
	if _idx >= _lines.size():
		_on_lines_complete()
	else:
		_show_line()

# --- rendering ---

func _show_line() -> void:
	var line: Dictionary = _lines[_idx]
	var speaker := str(line.get("speaker", ""))
	var name_lbl := get_node_or_null("Panel/Margin/VBox/Speaker")
	if name_lbl != null:
		name_lbl.text = speaker.capitalize()
		name_lbl.add_theme_color_override("font_color", _tint(speaker))
	var swatch := get_node_or_null("Panel/Margin/VBox/Tint")
	if swatch != null:
		swatch.color = _tint(speaker)
	var line_lbl := get_node_or_null("Panel/Margin/VBox/Line")
	if line_lbl != null:
		line_lbl.text = str(line.get("line", ""))
	var hint := get_node_or_null("Hint")
	if hint != null:
		hint.text = "Click or press Enter  (%d / %d)" % [_idx + 1, _lines.size()]

func _tint(speaker: String) -> Color:
	return SPEAKER_TINTS.get(speaker, DEFAULT_TINT)

# --- completion / continuation ---

func _on_lines_complete() -> void:
	# A branch trigger beat opens a fork; present its options instead of auto-advancing.
	var gc := _gc()
	if gc != null and not gc.offered_branch_options().is_empty():
		_present_choices(gc)
		return
	_finish_and_continue()

func _present_choices(gc) -> void:
	_showing_choices = true
	var panel := get_node_or_null("Panel")
	if panel != null:
		panel.visible = false
	var hint := get_node_or_null("Hint")
	if hint != null:
		hint.text = "What do you do?"
	var box := get_node_or_null("ChoiceBox")
	if box == null:
		return
	for child in box.get_children():
		child.queue_free()
	for opt_id in gc.offered_branch_options():
		var btn := Button.new()
		btn.text = _option_label(gc, str(opt_id))
		var oid := str(opt_id)
		btn.pressed.connect(func(): _on_choice(oid))
		box.add_child(btn)
	box.visible = true

func _on_choice(option_id: String) -> void:
	_done = true
	var gc := _gc()
	if gc != null:
		gc.choose_branch(option_id)   # applies effects + routes to the option goto (scene swap)

func _finish_and_continue() -> void:
	_done = true
	var gc := _gc()
	if gc == null:
		return
	# advance_story emits the scene_intent for the next beat (the SceneRouter swaps the scene). A
	# false return means there is no successor — a terminal closing beat — so the slice is complete.
	if not gc.advance_story():
		var router := get_node_or_null("/root/SceneRouter")
		if router != null:
			router.goto("TITLE")

# --- helpers ---

func _option_label(gc, option_id: String) -> String:
	var dir = gc.director()
	if dir == null:
		return option_id
	var bid: String = dir.current_branch_id()
	var opt: Dictionary = dir.graph().option(bid, option_id)
	return str(opt.get("label", opt.get("label_key", option_id)))

func _lines_from_router() -> Array:
	var router := get_node_or_null("/root/SceneRouter")
	var db := get_node_or_null("/root/ContentDB")
	if router == null or db == null:
		return []
	var beat_id := str(router.current_ctx().get("beat_id", ""))
	return db.beat_dialogue(beat_id) if beat_id != "" else []

func _hide_choices() -> void:
	var box := get_node_or_null("ChoiceBox")
	if box != null:
		box.visible = false

func _gc() -> Node:
	return get_node_or_null("/root/GameCoordinator")
