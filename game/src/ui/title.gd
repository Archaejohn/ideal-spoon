## title.gd — working title menu (ARCHITECTURE §5, ADR-0008 §TITLE).
##
## New Game -> GameCoordinator.new_game(); Continue (enabled iff a save exists) ->
## GameCoordinator.continue_game(); Settings (stub); Quit. The coordinator owns the run logic
## and the SceneRouter performs the resulting scene transition — the menu just dispatches.
extends Control

func _ready() -> void:
	var new_btn := get_node_or_null("Center/Menu/NewGame")
	var continue_btn := get_node_or_null("Center/Menu/Continue")
	var settings_btn := get_node_or_null("Center/Menu/Settings")
	var quit_btn := get_node_or_null("Center/Menu/Quit")
	if new_btn != null:
		new_btn.pressed.connect(_on_new_game)
	if continue_btn != null:
		continue_btn.disabled = not _has_save()      # only offer Continue when there is a save
		continue_btn.pressed.connect(_on_continue)
	if settings_btn != null:
		settings_btn.pressed.connect(_on_settings)
	if quit_btn != null:
		quit_btn.pressed.connect(_on_quit)

func _on_new_game() -> void:
	var gc := get_node_or_null("/root/GameCoordinator")
	if gc != null:
		gc.new_game()

func _on_continue() -> void:
	var gc := get_node_or_null("/root/GameCoordinator")
	if gc != null:
		gc.continue_game()

func _on_settings() -> void:
	# Stub (ADR-0008): the settings screen lands later; log so the button is observably wired.
	var log := get_node_or_null("/root/Log")
	if log != null:
		log.info("Settings selected (stub — screen lands in a later round).", "Title")

func _on_quit() -> void:
	get_tree().quit()

func _has_save() -> bool:
	var gc := get_node_or_null("/root/GameCoordinator")
	return gc != null and gc.has_save()
