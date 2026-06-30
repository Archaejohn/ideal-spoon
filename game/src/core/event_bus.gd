## event_bus.gd — global typed signal hub (ARCHITECTURE §2 autoload #3).
##
## Keeps modules decoupled: coordinators emit/listen here instead of holding hard refs
## to each other (ARCHITECTURE §3). Pure wiring — no game logic, no state. Registered as
## the `EventBus` autoload. Headless logic classes do NOT depend on this; only
## coordinators/UI use it.
extends Node

# --- Story (ADR-0003 / StoryDirector §7.5) ---
signal beat_entered(beat_id: String)
signal branch_opened(branch_id: String, options: Array)
signal flags_locked()
signal final_choice_made(choice: int)        # ids.FinalChoice
signal ending_reached(ending: int)            # ids.EndingId

# --- Save (ADR-0005 §SaveManager) ---
signal saved(reason: String)
signal loaded()
signal save_recovered(source: String)         # "backup" | "checkpoint"

# --- Battle (ARCHITECTURE §7.6) ---
signal battle_started(encounter_id: String)
signal battle_event(event: Variant)           # typed BattleEvent (battle/battle_event.gd)
signal battle_over(result: int, xp: int, loot: Array)

# --- Scene flow (ARCHITECTURE §7.9, ADR-0008) ---
signal state_changed(old_state: int, new_state: int)
## StoryDirector -> SceneRouter decoupling (ADR-0008 "how the story engine drives scene
## loads"). The director emits a scene INTENT (a target state key + ctx with beat/encounter/
## location) instead of holding a hard ref to SceneRouter or touching the scene tree; the
## SceneRouter (Round 3) listens and performs the actual transition.
signal scene_intent(state_key: String, ctx: Dictionary)

# --- Content ---
signal content_loaded()
