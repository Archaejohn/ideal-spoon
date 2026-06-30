## crossroads.gd — ending-replay selector placeholder (Phase 3 R3b-2, ADR-0006 / ADR-0008).
##
## PRESENTATION ONLY, and intentionally a STUB this round: endings are not reachable in the slice,
## so this exists to fully satisfy the SceneRouter CROSSROADS mapping (no dangling state) and to give
## the ending-replay flow a home. It lists the endings unlocked in GameState (none in the slice) and
## offers a "Back to Title" affordance. The real replay sandbox UI lands when Act IV is content-complete.
extends Control

func _ready() -> void:
	var list := get_node_or_null("Center/VBox/Unlocked")
	if list != null:
		var gs := get_node_or_null("/root/GameState")
		var unlocked: Array = gs.endings_unlocked if gs != null else []
		list.text = "Endings unlocked: %d" % unlocked.size() if not unlocked.is_empty() \
			else "No endings unlocked yet."
	var back := get_node_or_null("Center/VBox/Back")
	if back != null:
		back.pressed.connect(_on_back)

func _on_back() -> void:
	var router := get_node_or_null("/root/SceneRouter")
	if router != null:
		router.goto("TITLE")
