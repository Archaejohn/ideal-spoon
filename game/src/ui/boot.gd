## boot.gd — first scene (ARCHITECTURE §5 app data flow).
##
## Loads + validates content, emits content_loaded, then hands off to the SceneRouter to enter
## the Title screen. The SceneRouter (autoload) owns the actual transition (ADR-0008); Boot only
## kicks it off so there is one home for scene swaps.
extends Node

func _ready() -> void:
	var log := _node("Log")
	var content := _node("ContentDB")
	if content != null:
		var r: Result = content.load_all(false)
		if r.is_ok():
			if log != null:
				log.info("Content loaded: %d beats, %d flags." % [content.count("beats"), content.count("flags")], "Boot")
			if has_node("/root/EventBus"):
				get_node("/root/EventBus").content_loaded.emit()
		else:
			if log != null:
				log.error("Content load failed: %s" % r.error, "Boot")
			else:
				push_error("Content load failed: %s" % r.error)
	# Hand off to the SceneRouter for the Title transition (deferred so this _ready returns first).
	call_deferred("_goto_title")

func _goto_title() -> void:
	var router := get_node_or_null("/root/SceneRouter")
	if router != null:
		router.goto("TITLE")
	else:
		# Fallback if the router autoload is somehow absent (keeps Boot resilient).
		get_tree().change_scene_to_file("res://src/ui/Title.tscn")

func _node(name: String) -> Node:
	return get_node_or_null("/root/" + name)
