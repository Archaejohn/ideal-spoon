## title.gd — minimal title screen (ARCHITECTURE §5).
##
## New Game / Continue. Phase-3 minimal: the scene loads without error and the buttons are
## wired to safe stubs (New Game seeds a fresh run; Continue is disabled until SaveManager
## exists). Full routing to the overworld/story lands in later phases.
extends Control

func _ready() -> void:
	var new_btn := get_node_or_null("Center/Menu/NewGame")
	var continue_btn := get_node_or_null("Center/Menu/Continue")
	if new_btn != null:
		new_btn.pressed.connect(_on_new_game)
	if continue_btn != null:
		# No SaveManager yet -> nothing to continue.
		continue_btn.disabled = true
		continue_btn.pressed.connect(_on_continue)

func _on_new_game() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.new_run(int(Time.get_unix_time_from_system()))
	var log := get_node_or_null("/root/Log")
	if log != null:
		log.info("New Game started.", "Title")

func _on_continue() -> void:
	pass
