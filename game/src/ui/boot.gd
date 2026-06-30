## boot.gd — first scene (ARCHITECTURE §5 app data flow).
##
## Loads + validates content, then routes to Title. Phase-3 minimal: it drives the
## ContentDB load and reports a clear error if validation fails, then changes to Title.tscn.
## (Full SceneRouter / SettingsService / SaveManager wiring lands in later phases.)
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
	# Route to the title screen.
	call_deferred("_goto_title")

func _goto_title() -> void:
	get_tree().change_scene_to_file("res://src/ui/Title.tscn")

func _node(name: String) -> Node:
	return get_node_or_null("/root/" + name)
