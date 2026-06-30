## battle_ui.gd — the playable ATB battle screen (Phase 3 R3b-1, ADR-0004 / ADR-0008).
##
## PRESENTATION ONLY. It holds NO battle math: it drives the headless BattleController via
## `start` / `queue_action` / `advance` and renders the BattleEvent stream from the
## `battle_started` / `events_emitted` / `battle_over` signals. Placeholder visuals
## (ColorRect / Label / ProgressBar) per ADR-0004 — real art is Phase 4.
##
## WAIT mode (PHASE2_OWNER_RULINGS #1, default): gauges pause while a party member's action
## menu is open. The loop:
##   _pump() -> controller.peek_next_actor()
##     - enemy  : auto-resolve (advance) after a short readable delay
##     - player : open the action menu (Attack / Ability / Item / Defend / Flee) + target select,
##                queue the BattleAction, then advance() to resolve exactly that actor's turn.
## The encounter id comes from SceneRouter.current_ctx(); the party comes from GameState (the
## controller builds Combatants). On battle_over the GameCoordinator owns rewards / checkpoint /
## routing — this screen only shows the victory / defeat panel and calls GameCoordinator.after_battle().
extends Control

const BattleActionScript := preload("res://src/battle/battle_action.gd")
const CombatantScript := preload("res://src/battle/combatant.gd")

const ATB_MAX := 10000                 # mirror of TurnScheduler.ATB_MAX for the gauges
const ENEMY_DELAY := 0.6               # seconds to linger on an enemy turn (readability)

const SIDE_COLORS := [
	Color(0.45, 0.72, 0.95),  # player A
	Color(0.95, 0.78, 0.40),  # player B
	Color(0.70, 0.85, 0.55),  # player C
]
const ENEMY_COLORS := [
	Color(0.85, 0.40, 0.45),  # enemy A (boss)
	Color(0.70, 0.45, 0.70),  # enemy B
	Color(0.60, 0.55, 0.50),  # enemy C
]

var _encounter_id: String = ""
var _roster: Array = []                # Array[Combatant] (live, from battle_started)
var _by_id: Dictionary = {}            # id -> Combatant
var _cards: Dictionary = {}            # id -> { hp:ProgressBar, atb:ProgressBar, name:Label, root:Control }
var _active_actor = null               # Combatant currently choosing an action
var _pending_kind: int = -1            # chosen BattleAction.Kind awaiting a target
var _pending_ability: String = ""      # ability/item id awaiting a target
var _over: bool = false

func _ready() -> void:
	_hide_all_menus()
	var vp := get_node_or_null("VictoryPanel")
	if vp != null: vp.visible = false
	var dp := get_node_or_null("DefeatPanel")
	if dp != null: dp.visible = false
	# Static action buttons.
	_connect_button("ActionMenu/VBox/Attack", _on_attack)
	_connect_button("ActionMenu/VBox/Ability", _on_ability)
	_connect_button("ActionMenu/VBox/Item", _on_item)
	_connect_button("ActionMenu/VBox/Defend", _on_defend)
	_connect_button("ActionMenu/VBox/Flee", _on_flee)
	_connect_button("VictoryPanel/VBox/Continue", _on_continue)
	_connect_button("DefeatPanel/VBox/TryAgain", _on_try_again)

	# Resolve the encounter from the SceneRouter ctx (set when the story routed us to BATTLE).
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and _encounter_id == "":
		_encounter_id = str(router.current_ctx().get("encounter", ""))

	# Connect to the controller BEFORE starting so we receive the opening battle_started batch.
	var bc := _controller()
	if bc != null:
		if not bc.battle_started.is_connected(_on_battle_started):
			bc.battle_started.connect(_on_battle_started)
		if not bc.events_emitted.is_connected(_on_events):
			bc.events_emitted.connect(_on_events)
		if not bc.battle_over.is_connected(_on_battle_over):
			bc.battle_over.connect(_on_battle_over)

	# Kick the fight off through the coordinator (it owns checkpoint + rewards + routing).
	if _encounter_id != "":
		var gc := get_node_or_null("/root/GameCoordinator")
		if gc != null:
			gc.start_battle(_encounter_id)
		elif bc != null:
			bc.configure()
			bc.start(_encounter_id, _party_states())
		_pump()

## Test seam: let a headless smoke test set the encounter before _ready runs.
func set_encounter(id: String) -> void:
	_encounter_id = id

# --- controller signals ---

func _on_battle_started(roster: Array) -> void:
	_roster = roster
	_by_id.clear()
	for c in roster:
		_by_id[c.id] = c
	_build_cards()
	_refresh_cards()
	_set_log("The %s stirs in the wreck!" % _enemy_title())

func _on_events(events: Array) -> void:
	for e in events:
		_render_event(e)
	_refresh_cards()

func _on_battle_over(result: int, rewards: Dictionary) -> void:
	_over = true
	_hide_all_menus()
	_refresh_cards()
	if result == BattleEngine.Result.WIN:
		_show_victory(rewards)
	elif result == BattleEngine.Result.LOSE:
		_show_defeat()
	else:
		# Fled (or other): no panel; let the coordinator return us to the overworld.
		var gc := get_node_or_null("/root/GameCoordinator")
		if gc != null:
			gc.after_battle()

# --- the WAIT-mode pump ---

func _pump() -> void:
	if _over:
		return
	var bc := _controller()
	if bc == null or bc.is_over():
		return
	var actor = bc.peek_next_actor()
	_refresh_cards()
	if actor == null:
		return
	if actor.side == CombatantScript.Side.PLAYER:
		_open_action_menu(actor)
	else:
		# Enemy turn: resolve automatically after a brief, readable pause.
		_set_log("%s acts..." % actor.name)
		await get_tree().create_timer(ENEMY_DELAY).timeout
		if _over:
			return
		bc.advance()
		if not _over:
			_pump()

func _submit(action) -> void:
	_hide_all_menus()
	var bc := _controller()
	if bc == null:
		return
	bc.queue_action(action)
	bc.advance()             # resolve exactly this actor's queued turn
	if not _over:
		_pump()

# --- player action menu ---

func _open_action_menu(actor) -> void:
	_active_actor = actor
	_pending_kind = -1
	_pending_ability = ""
	_clear_choice_list()
	_hide_choice_list()
	_show_action_buttons()
	var menu := get_node_or_null("ActionMenu")
	if menu != null:
		menu.visible = true
	_set_log("%s's turn — choose an action." % actor.name)
	# Disable Ability if this actor has no learned abilities.
	var ability_btn := get_node_or_null("ActionMenu/VBox/Ability")
	if ability_btn != null:
		ability_btn.disabled = _active_actor.ability_ids.is_empty()
	var item_btn := get_node_or_null("ActionMenu/VBox/Item")
	if item_btn != null:
		item_btn.disabled = _lamp_herb_count() <= 0

func _on_attack() -> void:
	_pending_kind = BattleActionScript.Kind.ATTACK
	_pending_ability = ""
	_begin_target_select(false)

func _on_ability() -> void:
	# Show the actor's learned abilities; picking one moves to target select.
	_hide_action_buttons()
	var list := _choice_list()
	if list == null:
		return
	for aid in _active_actor.ability_ids:
		var def := _ability(aid)
		var label := str(def.get("name", aid))
		var cost: Dictionary = def.get("cost", {})
		var amt := int(cost.get("amount", 0))
		if amt > 0:
			label += " (%s %d)" % [str(cost.get("resource", "")), amt]
		_add_choice_button(label, func(): _choose_ability(aid))
	_add_choice_button("< Back", _back_to_actions)
	list.visible = true

func _choose_ability(aid: String) -> void:
	_pending_kind = BattleActionScript.Kind.ABILITY
	_pending_ability = aid
	_begin_target_select(_ability_targets_allies(aid))

func _on_item() -> void:
	if _lamp_herb_count() <= 0:
		return
	_pending_kind = BattleActionScript.Kind.ITEM
	_pending_ability = "use_lamp_herb"
	_begin_target_select(true)   # lamp-herb heals an ally

func _on_defend() -> void:
	_submit(BattleActionScript.defend(_active_actor.id))

func _on_flee() -> void:
	_submit(BattleActionScript.make(_active_actor.id, BattleActionScript.Kind.FLEE))

func _begin_target_select(want_allies: bool) -> void:
	_hide_action_buttons()
	var pool: Array = []
	for c in _roster:
		if not c.is_alive():
			continue
		var is_ally: bool = c.side == CombatantScript.Side.PLAYER
		if is_ally == want_allies:
			pool.append(c)
	if pool.is_empty():
		_back_to_actions()
		return
	if pool.size() == 1:
		_pick_target(pool[0].id)
		return
	var list := _choice_list()
	if list == null:
		return
	_set_log("Choose a target.")
	for c in pool:
		var cid: int = c.id
		_add_choice_button("%s  (HP %d)" % [c.name, c.hp_cur], func(): _pick_target(cid))
	_add_choice_button("< Back", _back_to_actions)
	list.visible = true

func _pick_target(target_id: int) -> void:
	if _pending_kind == BattleActionScript.Kind.ITEM:
		_consume_lamp_herb()
	var action = BattleActionScript.make(_active_actor.id, _pending_kind, _pending_ability, [target_id])
	_submit(action)

func _back_to_actions() -> void:
	_clear_choice_list()
	_hide_choice_list()
	if _active_actor != null:
		_open_action_menu(_active_actor)

# --- victory / defeat panels ---

func _show_victory(rewards: Dictionary) -> void:
	var panel := get_node_or_null("VictoryPanel")
	if panel == null:
		return
	var lbl := get_node_or_null("VictoryPanel/VBox/Label")
	if lbl != null:
		var items: Array = rewards.get("items", [])
		lbl.text = "Victory!\n+%d XP%s" % [int(rewards.get("xp", 0)),
			("\nFound: " + ", ".join(PackedStringArray(_strs(items)))) if not items.is_empty() else ""]
	panel.visible = true

func _show_defeat() -> void:
	var panel := get_node_or_null("DefeatPanel")
	if panel == null:
		return
	var lbl := get_node_or_null("DefeatPanel/VBox/Label")
	if lbl != null:
		lbl.text = "The lamp gutters out...\nbut the Song isn't done yet."
	panel.visible = true

func _on_continue() -> void:
	var gc := get_node_or_null("/root/GameCoordinator")
	if gc != null:
		gc.after_battle()

func _on_try_again() -> void:
	var gc := get_node_or_null("/root/GameCoordinator")
	if gc != null:
		gc.after_battle()

# --- event rendering ---

func _render_event(e: Dictionary) -> void:
	match str(e.get("type", "")):
		"action":
			var who := _name(int(e.get("combatant", -1)))
			_set_log("%s uses %s." % [who, _ability_name(str(e.get("ability", "")))])
		"hit":
			var crit := " (crit!)" if e.get("crit", false) else ""
			var weak := " WEAK!" if e.get("weak", false) else ""
			_set_log("%s hits %s for %d%s%s" % [_name(int(e.get("source", -1))),
				_name(int(e.get("target", -1))), int(e.get("amount", 0)), crit, weak])
		"miss":
			_set_log("%s misses %s." % [_name(int(e.get("source", -1))), _name(int(e.get("target", -1)))])
		"heal":
			_set_log("%s restores %d HP to %s." % [_name(int(e.get("source", -1))),
				int(e.get("amount", 0)), _name(int(e.get("target", -1)))])
		"status_apply":
			_set_log("%s is afflicted with %s." % [_name(int(e.get("target", -1))), str(e.get("status", ""))])
		"songsick":
			_set_log("%s is Songsick — Breath blocked!" % _name(int(e.get("combatant", -1))))
		"defend":
			_set_log("%s defends." % _name(int(e.get("combatant", -1))))
		"flee":
			_set_log("Flee %s." % ("succeeds" if e.get("success", false) else "fails — no way out!"))
		"combatant_down":
			_set_log("%s falls." % _name(int(e.get("combatant", -1))))
		"retarget":
			_set_log("%s redirects the attack." % _name(int(e.get("combatant", -1))))

# --- card (combatant panel) building / refresh ---

func _build_cards() -> void:
	var enemy_row := get_node_or_null("EnemyRow")
	var party_row := get_node_or_null("PartyRow")
	if enemy_row == null or party_row == null:
		return
	for child in enemy_row.get_children():
		child.queue_free()
	for child in party_row.get_children():
		child.queue_free()
	_cards.clear()
	var p_idx := 0
	var e_idx := 0
	for c in _roster:
		var is_player: bool = c.side == CombatantScript.Side.PLAYER
		var color: Color = (SIDE_COLORS[p_idx % SIDE_COLORS.size()] if is_player
			else ENEMY_COLORS[e_idx % ENEMY_COLORS.size()])
		var card := _make_card(c, color)
		if is_player:
			party_row.add_child(card["root"])
			p_idx += 1
		else:
			enemy_row.add_child(card["root"])
			e_idx += 1
		_cards[c.id] = card

func _make_card(c, color: Color) -> Dictionary:
	var root := PanelContainer.new()
	root.custom_minimum_size = Vector2(180, 0)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	root.add_child(vbox)
	var swatch := ColorRect.new()
	swatch.color = color
	swatch.custom_minimum_size = Vector2(160, 46)
	vbox.add_child(swatch)
	var name_lbl := Label.new()
	name_lbl.text = c.name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)
	var hp := ProgressBar.new()
	hp.max_value = maxi(1, c.max_hp)
	hp.value = c.hp_cur
	hp.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(hp)
	var atb := ProgressBar.new()
	atb.max_value = ATB_MAX
	atb.value = c.atb
	atb.show_percentage = false
	atb.custom_minimum_size = Vector2(0, 8)
	atb.modulate = Color(0.7, 0.9, 1.0)
	vbox.add_child(atb)
	return {"root": root, "hp": hp, "atb": atb, "name": name_lbl, "swatch": swatch}

func _refresh_cards() -> void:
	for id in _cards:
		var c = _by_id.get(id, null)
		if c == null:
			continue
		var card: Dictionary = _cards[id]
		card["hp"].value = c.hp_cur
		card["atb"].value = clampi(c.atb, 0, ATB_MAX)
		card["name"].text = c.name + ("  (down)" if not c.is_alive() else "")
		card["root"].modulate = Color(1, 1, 1, 0.4) if not c.is_alive() else Color(1, 1, 1, 1)

# --- small helpers ---

func _controller() -> Node:
	return get_node_or_null("/root/BattleController")

func _party_states() -> Array:
	var gs := get_node_or_null("/root/GameState")
	return gs.party if gs != null else []

func _ability(aid: String) -> Dictionary:
	var db := get_node_or_null("/root/ContentDB")
	return db.ability(aid) if db != null else {}

func _ability_name(aid: String) -> String:
	if aid == "" or aid == "basic_attack":
		return "Attack"
	var def := _ability(aid)
	return str(def.get("name", aid))

func _ability_targets_allies(aid: String) -> bool:
	var tk := str(_ability(aid).get("target_kind", "ENEMY_SINGLE"))
	return tk in ["ALLY_SINGLE", "ALLY_ALL", "SELF"]

func _lamp_herb_count() -> int:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return 0
	return int((gs.inventory.get("items", {}) as Dictionary).get("lamp_herb", 0))

func _consume_lamp_herb() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	var items: Dictionary = gs.inventory.get("items", {})
	items["lamp_herb"] = maxi(0, int(items.get("lamp_herb", 0)) - 1)
	gs.inventory["items"] = items

func _name(id: int) -> String:
	var c = _by_id.get(id, null)
	return c.name if c != null else "?"

func _enemy_title() -> String:
	for c in _roster:
		if c.side == CombatantScript.Side.ENEMY:
			return c.name
	return "enemy"

func _set_log(text: String) -> void:
	var lbl := get_node_or_null("Log")
	if lbl != null:
		lbl.text = text

func _strs(arr: Array) -> Array:
	var out: Array = []
	for a in arr:
		out.append(str(a))
	return out

# --- menu visibility ---

func _hide_all_menus() -> void:
	_hide_action_buttons()
	_hide_choice_list()
	var menu := get_node_or_null("ActionMenu")
	if menu != null:
		menu.visible = false

func _hide_action_buttons() -> void:
	var vbox := get_node_or_null("ActionMenu/VBox")
	if vbox != null:
		vbox.visible = false

func _show_action_buttons() -> void:
	var vbox := get_node_or_null("ActionMenu/VBox")
	if vbox != null:
		vbox.visible = true

func _choice_list() -> Node:
	return get_node_or_null("ChoiceList")

func _hide_choice_list() -> void:
	var list := _choice_list()
	if list != null:
		list.visible = false

func _clear_choice_list() -> void:
	var list := _choice_list()
	if list == null:
		return
	for child in list.get_children():
		child.queue_free()

func _add_choice_button(text: String, on_press: Callable) -> void:
	var list := _choice_list()
	if list == null:
		return
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(on_press)
	list.add_child(btn)

func _connect_button(path: String, fn: Callable) -> void:
	var btn := get_node_or_null(path)
	if btn != null and btn is BaseButton:
		btn.pressed.connect(fn)
