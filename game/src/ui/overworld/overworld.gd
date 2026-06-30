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
