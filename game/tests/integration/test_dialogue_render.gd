## test_dialogue_render.gd — guards that the Dialogue scene actually RENDERS its lines.
## Regression guard for H1 (R3b-2 review): the script's node paths must match Dialogue.tscn,
## or the speaker/line/tint are silently never set and the narrative shows blank boxes.
extends GutTest

const DIALOGUE_SCENE := "res://src/ui/dialogue/Dialogue.tscn"

func test_dialogue_renders_speaker_and_line():
	var scene = load(DIALOGUE_SCENE).instantiate()
	# Inject lines via the test seam BEFORE _ready resolves from the router.
	scene.set_lines([{"speaker": "wren", "line": "The lamp is lit. We're aloft."}])
	add_child_autofree(scene)
	await wait_frames(2)

	var line_lbl = scene.get_node_or_null("Panel/Margin/VBox/Line")
	var speaker_lbl = scene.get_node_or_null("Panel/Margin/VBox/Speaker")
	assert_not_null(line_lbl, "Line label resolves at the real scene path")
	assert_not_null(speaker_lbl, "Speaker label resolves at the real scene path")
	assert_eq(line_lbl.text, "The lamp is lit. We're aloft.", "line text is actually rendered (not blank)")
	assert_eq(speaker_lbl.text, "Wren", "speaker name is rendered, capitalized")

func test_dialogue_advances_through_lines():
	var scene = load(DIALOGUE_SCENE).instantiate()
	scene.set_lines([
		{"speaker": "pell", "line": "First."},
		{"speaker": "wren", "line": "Second."},
	])
	add_child_autofree(scene)
	await wait_frames(2)
	var line_lbl = scene.get_node("Panel/Margin/VBox/Line")
	assert_eq(line_lbl.text, "First.", "shows first line")
	scene.advance_line()
	await wait_frames(1)
	assert_eq(line_lbl.text, "Second.", "advances to second line")
