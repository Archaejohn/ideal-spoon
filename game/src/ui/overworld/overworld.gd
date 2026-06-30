## overworld.gd — minimal placeholder overworld (R3a integration shell, ADR-0008 §OVERWORLD).
##
## The START beat routes here so New Game lands somewhere real and Continue can resume to it.
## It carries a "pause menu" stub: opening shows the panel; closing hides it and fires
## SaveManager.autosave("menu") (ADR-0005 §a menu-close hook). The real town/dungeon/battle
## scenes + slice content arrive in R3b.
extends Control

func _ready() -> void:
	var pause := get_node_or_null("PauseMenu")
	if pause != null:
		pause.visible = false
	var open_btn := get_node_or_null("HUD/OpenMenu")
	if open_btn != null:
		open_btn.pressed.connect(_open_menu)
	var close_btn := get_node_or_null("PauseMenu/Panel/Margin/VBox/Close")
	if close_btn != null:
		close_btn.pressed.connect(_close_menu)
	# R3b-1 slice affordance: advance the story spine (e.g. SLICE-START -> SLICE-BATTLE), which
	# the SceneRouter turns into the next scene (the Sleepless Crane battle). R3b-2 replaces this
	# with the real Meadowmoor->wreck journey + dialogue.
	var advance_btn := get_node_or_null("HUD/Advance")
	if advance_btn != null:
		advance_btn.pressed.connect(_advance_story)

func _advance_story() -> void:
	var gc := get_node_or_null("/root/GameCoordinator")
	if gc != null:
		gc.advance_story()

func _open_menu() -> void:
	var pause := get_node_or_null("PauseMenu")
	if pause != null:
		pause.visible = true

func _close_menu() -> void:
	var pause := get_node_or_null("PauseMenu")
	if pause != null:
		pause.visible = false
	# Menu close fires an autosave (ADR-0005 §a).
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null:
		sm.autosave("menu")
