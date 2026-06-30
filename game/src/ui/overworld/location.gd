## location.gd — a simple navigable location screen (Phase 3 R3b-2, ADR-0008).
##
## PRESENTATION ONLY. One reusable scene for TOWN and DUNGEON beats: it shows the location's
## display name, a couple of placeholder interaction points (flavor + a menu/autosave hook), and a
## single "continue" affordance that advances the story spine (GameCoordinator.advance_story), which
## the StoryDirector turns into the next scene_intent. Which kind (town vs. dungeon) it is comes from
## SceneRouter.current_state(); the location id comes from SceneRouter.current_ctx().location.
## Placeholder visuals (ColorRect / Label) — real maps/art are Phase 4.
extends Control

## location id -> display name (placeholder gazetteer; canonical names per 01_WORLD / 03_MAIN_STORY).
const LOCATION_NAMES := {
	"meadowmoor": "Meadowmoor",
	"hollowgate": "Hollowgate",
	"hollowgate_wreck": "The Hollowgate Wreck",
}

func _ready() -> void:
	var ctx: Dictionary = _ctx()
	var loc := str(ctx.get("location", ""))
	var is_dungeon := _is_dungeon()

	var title := get_node_or_null("CenterLabel")
	if title != null:
		title.text = LOCATION_NAMES.get(loc, loc.capitalize().replace("_", " "))
	var sub := get_node_or_null("SubLabel")
	if sub != null:
		sub.text = "The wreck groans below. Hollow-light drifts in the dark." if is_dungeon \
			else "Windmills turn. Dock-bells ring. The island leans on its tethers."

	var look_btn := get_node_or_null("HUD/Look")
	if look_btn != null:
		look_btn.text = "Search the wreck" if is_dungeon else "Look around"
		look_btn.pressed.connect(_on_look)

	var continue_btn := get_node_or_null("HUD/Continue")
	if continue_btn != null:
		continue_btn.text = "Descend into the wreck >" if is_dungeon else "Continue >"
		continue_btn.pressed.connect(_on_continue)

func _on_continue() -> void:
	# Advance the spine; the StoryDirector emits the next scene_intent (SceneRouter swaps the scene).
	var gc := get_node_or_null("/root/GameCoordinator")
	if gc != null:
		gc.advance_story()

func _on_look() -> void:
	# Flavor interaction point + an explicit autosave (ADR-0005 §a "menu/interaction" hook).
	var sub := get_node_or_null("SubLabel")
	if sub != null:
		sub.text = "Nothing stirs but you. Best keep moving."
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null:
		sm.autosave("look")

func _is_dungeon() -> bool:
	var router := get_node_or_null("/root/SceneRouter")
	if router == null:
		return false
	return router.current_state() == router.AppState.DUNGEON

func _ctx() -> Dictionary:
	var router := get_node_or_null("/root/SceneRouter")
	return router.current_ctx() if router != null else {}
