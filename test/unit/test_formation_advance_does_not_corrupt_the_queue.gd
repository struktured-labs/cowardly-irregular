extends GutTest

## Advancing the Formation row queued it as a battle action. The commit converter only knows
## attack, ability, and item, so that row vanished. A queue of only formation cycles became
## "No valid actions left — defer", which spent the turn the row is documented not to spend.
## A formation special in the same queue was dropped, or, alone, deferred instead of launching.
## Confirm and Advance cycle the reposition in place. A formation special still launches, once,
## when the personal queue is empty, and is refused when that queue already holds actions.

const MenuScript = preload("res://src/battle/BattleCommandMenu.gd")
const SceneScript = preload("res://src/battle/BattleScene.gd")
const Win98 = preload("res://src/ui/Win98Menu.gd")

class QuietScene extends SceneScript:
	var reopened := false

	func _ready() -> void:
		pass

	func log_message(_message: String) -> void:
		pass

	func _update_ui() -> void:
		pass

	func show_win98_command_menu(_combatant: Combatant) -> void:
		reopened = true


var _saved_party: Array
var _saved_order: Array
var _saved_index: int
var _saved_current
var _saved_state: int
var _saved_enemies: Array
var _saved_pending: Array
var _saved_execution: Array
var _saved_auto: bool
var _saved_repeat: bool
var _saved_formation: int
var _saved_formation_round: int
var _saved_round: int


func before_each() -> void:
	_saved_party = BattleManager.player_party.duplicate()
	_saved_order = BattleManager.selection_order.duplicate()
	_saved_index = BattleManager.selection_index
	_saved_current = BattleManager.current_combatant
	_saved_state = BattleManager.current_state
	_saved_enemies = BattleManager.enemy_party.duplicate()
	_saved_pending = BattleManager.pending_actions.duplicate()
	_saved_execution = BattleManager.execution_order.duplicate()
	_saved_auto = BattleManager.is_autobattle_enabled
	_saved_repeat = BattleManager._filling_repeat
	_saved_formation = SceneScript.current_formation
	_saved_formation_round = BattleManager._formation_last_round
	_saved_round = BattleManager.current_round


func after_each() -> void:
	BattleManager.player_party.assign(_alive(_saved_party))
	BattleManager.selection_order.assign(_alive(_saved_order))
	BattleManager.selection_index = _saved_index
	BattleManager.current_combatant = _saved_current if is_instance_valid(_saved_current) else null
	BattleManager.current_state = _saved_state
	BattleManager.enemy_party.assign(_alive(_saved_enemies))
	BattleManager.pending_actions.clear()
	for action in _saved_pending:
		if action is Dictionary:
			BattleManager.pending_actions.append(action)
	BattleManager.execution_order.clear()
	for action in _saved_execution:
		if action is Dictionary:
			BattleManager.execution_order.append(action)
	BattleManager.is_autobattle_enabled = _saved_auto
	BattleManager._filling_repeat = _saved_repeat
	SceneScript.current_formation = _saved_formation
	BattleManager._formation_last_round = _saved_formation_round
	BattleManager.current_round = _saved_round


func _alive(saved: Array) -> Array:
	var out: Array = []
	for c in saved:
		if is_instance_valid(c):
			out.append(c)
	return out


func _pc(who: String, job_id: String) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = who
	c.job = JobSystem.get_job(job_id).duplicate(true)
	c.max_hp = 400
	c.current_hp = 400
	c.is_alive = true
	c.max_mp = 80
	c.current_mp = 80
	c.current_ap = 4
	return c


func _field() -> Dictionary:
	var caster := _pc("Leader", "fighter")
	var ally := _pc("Healer", "cleric")
	var slime := _pc("Slime", "fighter")
	var scene := QuietScene.new()
	autofree(scene)
	var party: Array[Combatant] = [caster, ally]
	var enemies: Array[Combatant] = [slime]
	scene.party_members = party
	scene.test_enemies = enemies
	scene.command_memory_enabled = false
	var menu = MenuScript.new(scene)
	scene._command_menu = menu
	BattleManager.player_party.assign(party)
	BattleManager.enemy_party.assign(enemies)
	BattleManager.selection_order.assign([caster, ally])
	BattleManager.selection_index = 0
	BattleManager.current_combatant = caster
	BattleManager.current_state = BattleManager.BattleState.PLAYER_SELECTING
	BattleManager.is_autobattle_enabled = false
	BattleManager._filling_repeat = false
	BattleManager.pending_actions.clear()
	BattleManager.execution_order.clear()
	BattleManager.current_round = 4
	BattleManager._formation_last_round = 0
	return {"menu": menu, "scene": scene, "caster": caster, "ally": ally, "slime": slime}


func _win(items: Array, scene: QuietScene, cmd):
	var m = Win98.new()
	m.is_root_menu = true
	m.battle_mode = true
	m.expand_left = true
	add_child_autofree(m)
	m.setup("Command", items, Vector2(200, 80), "fighter")
	m._can_accept_input = true
	m.set_max_queue_size(4)
	scene.active_win98_menu = m
	m.turnless_row_activated.connect(cmd._on_win98_turnless_row)
	m.item_selected.connect(cmd._on_win98_menu_selection)
	return m


func _advance(m) -> void:
	Win98._last_advance_ms = -1000000
	m._handle_advance_input()


func _ids(m) -> Array:
	var out: Array = []
	for action in m.get_queued_actions():
		out.append(str(action.get("id", "")))
	return out


## Execution can move a just-queued group out of pending. Count whichever list holds it, not both.
func _group_actions() -> Array:
	var pending: Array = []
	for action in BattleManager.pending_actions:
		if action is Dictionary and str(action.get("type", "")) == "group":
			pending.append(action)
	if not pending.is_empty():
		return pending
	var executing: Array = []
	for action in BattleManager.execution_order:
		if action is Dictionary and str(action.get("type", "")) == "group":
			executing.append(action)
	return executing


func _player_actions() -> Array:
	var out: Array = []
	for bucket in [BattleManager.pending_actions, BattleManager.execution_order]:
		for action in bucket:
			if action is Dictionary and action.get("combatant") != null:
				out.append(action)
	return out


func test_advance_cycles_the_formation_and_does_not_queue_it() -> void:
	var field := _field()
	var start: int = SceneScript.current_formation
	var row := {"id": "cycle_formation", "label": "Formation: V", "turnless": true, "data": null}
	var attack := {"id": "attack_0", "label": "Slime", "data": {"target_idx": 0, "action": "attack"}}
	var m = _win([attack, row], field["scene"], field["menu"])
	m.selected_index = 1
	_advance(m)
	_advance(m)
	assert_eq((start + 2) % SceneScript.PartyFormation.size(), SceneScript.current_formation,
		"each Advance on the Formation row cycles once")
	assert_eq(_ids(m), [], "those cycles must not enter the action queue")
	assert_false(m.is_queued_for_deletion(), "the menu stays open so the turn can continue")
	assert_eq(_player_actions().size(), 0, "cycling must not submit an advance or a defer")
	assert_eq(str(m.menu_items[1].get("label", "")), "Formation: %s" % SceneScript.FORMATION_NAMES[SceneScript.current_formation],
		"the open row reads the formation Advance just selected")


func test_advance_then_formation_keeps_the_attack_and_undo_still_pops_it() -> void:
	var field := _field()
	var row := {"id": "cycle_formation", "label": "Formation", "turnless": true, "data": null}
	var attack := {"id": "attack_0", "label": "Slime", "data": {"target_idx": 0, "action": "attack"}}
	var m = _win([attack, row], field["scene"], field["menu"])
	m.selected_index = 0
	_advance(m)
	m.selected_index = 1
	_advance(m)
	assert_eq(_ids(m), ["attack_0"], "the formation cycle must not push the queued attack aside")
	m._undo_last_action()
	assert_eq(_ids(m), [], "Back out of the queue removes the attack, not a phantom formation")
	m.selected_index = 0
	_advance(m)
	assert_eq(_ids(m), ["attack_0"], "the attack can be queued again after that")
	field["menu"]._on_win98_actions_submitted(m.get_queued_actions())
	var launched := _player_actions()
	assert_eq(launched.size(), 1, "confirming the remaining queue advances once")
	if launched.is_empty():
		return
	assert_eq(str(launched[0].get("type", "")), "advance")
	assert_eq((launched[0].get("actions", []) as Array).size(), 1, "and that advance is the one attack")


func test_confirm_on_the_formation_row_cycles_without_spending_the_turn() -> void:
	var field := _field()
	var start: int = SceneScript.current_formation
	var row := {"id": "cycle_formation", "label": "Formation", "turnless": true, "data": null}
	var m = _win([row], field["scene"], field["menu"])
	m.selected_index = 0
	m._submit_actions()
	assert_eq((start + 1) % SceneScript.PartyFormation.size(), SceneScript.current_formation,
		"Confirm still cycles the formation")
	assert_eq(_ids(m), [], "Confirm must not queue it either")
	assert_eq(_player_actions().size(), 0, "and must not defer or advance")
	assert_false(m.is_queued_for_deletion(), "the menu stays, because the turn is not over")


func test_a_queued_formation_cycle_does_not_defer_the_turn() -> void:
	var field := _field()
	var start: int = SceneScript.current_formation
	field["menu"]._on_win98_actions_submitted([
		{"id": "cycle_formation", "data": null, "label": "Formation"},
		{"id": "cycle_formation", "data": null, "label": "Formation"},
	])
	await get_tree().process_frame
	assert_eq((start + 2) % SceneScript.PartyFormation.size(), SceneScript.current_formation,
		"a commit that is only formation cycles still applies each one")
	assert_eq(_player_actions().size(), 0, "it must not become a defer")
	assert_true(field["scene"].reopened, "and the menu comes back, because the turn is still this character's")


func test_a_formation_special_advances_once_when_the_queue_is_empty() -> void:
	var field := _field()
	var row := {
		"id": "group_formation",
		"label": "Four Heroes",
		"commits_alone": true,
		"data": {"group_type": "formation", "formation_id": "four_heroes"},
	}
	var m = _win([row], field["scene"], field["menu"])
	m.selected_index = 0
	_advance(m)
	_advance(m)
	var groups := _group_actions()
	assert_eq(groups.size(), 1, "Advance on a formation special launches it once, not twice and not as a defer")
	if groups.is_empty():
		return
	assert_eq(str(groups[0].get("group_type", "")), "formation")
	assert_eq(str(groups[0].get("formation_id", "")), "four_heroes")


func test_a_formation_special_does_not_join_a_personal_queue() -> void:
	var field := _field()
	var special := {
		"id": "group_formation",
		"label": "Four Heroes",
		"commits_alone": true,
		"data": {"group_type": "formation", "formation_id": "four_heroes"},
	}
	var attack := {"id": "attack_0", "label": "Slime", "data": {"target_idx": 0, "action": "attack"}}
	var m = _win([attack, special], field["scene"], field["menu"])
	m.selected_index = 0
	_advance(m)
	m.selected_index = 1
	_advance(m)
	assert_eq(_ids(m), ["attack_0"], "Advance on the special must leave the queued attack where it is")
	assert_eq(_player_actions().size(), 0, "and must not launch the special on top of that queue")
	m._submit_actions()
	assert_eq(_player_actions().size(), 0, "Confirm on the special, while attacks are queued, does not launch either")
	assert_eq(_ids(m), ["attack_0"], "the attack is still queued for a later confirm")


func test_a_commit_that_already_mixed_them_keeps_the_attack_and_one_special_does_not_duplicate() -> void:
	var field := _field()
	field["menu"]._on_win98_actions_submitted([
		{"id": "attack_0", "data": {"target_idx": 0, "action": "attack"}, "label": "Slime"},
		{"id": "group_formation", "data": {"group_type": "formation", "formation_id": "four_heroes"}, "label": "Four Heroes"},
		{"id": "cycle_formation", "data": null, "label": "Formation"},
	])
	var launched := _player_actions()
	assert_eq(launched.size(), 1, "the mixed commit is one personal advance")
	if launched.is_empty():
		return
	assert_eq(str(launched[0].get("type", "")), "advance")
	var subs: Array = launched[0].get("actions", [])
	assert_eq(subs.size(), 1, "the formation rows are not extra or missing attack slots")
	assert_eq(str(subs[0].get("type", "")), "attack")
	assert_eq(subs[0].get("target"), field["slime"])
	var again := _field()
	again["menu"]._on_win98_actions_submitted([
		{"id": "group_formation", "data": {"group_type": "formation", "formation_id": "four_heroes"}, "label": "Four Heroes"},
		{"id": "group_formation", "data": {"group_type": "formation", "formation_id": "four_heroes"}, "label": "Four Heroes"},
	])
	var groups := _group_actions()
	assert_eq(groups.size(), 1, "two queued formation specials launch once")
	if groups.is_empty():
		return
	assert_eq(str(groups[0].get("formation_id", "")), "four_heroes")


func test_an_ordinary_attack_advance_is_unchanged() -> void:
	var field := _field()
	var attack := {"id": "attack_0", "label": "Slime", "data": {"target_idx": 0, "action": "attack"}}
	var guard := {"id": "attack_0", "label": "Slime again", "data": {"target_idx": 0, "action": "attack"}}
	var m = _win([attack, guard], field["scene"], field["menu"])
	m.selected_index = 0
	_advance(m)
	_advance(m)
	assert_eq(_ids(m), ["attack_0", "attack_0"], "two Advances on an attack still queue two attacks")
	field["menu"]._on_win98_actions_submitted(m.get_queued_actions())
	var launched := _player_actions()
	assert_eq(launched.size(), 1)
	if launched.is_empty():
		return
	assert_eq(str(launched[0].get("type", "")), "advance")
	assert_eq((launched[0].get("actions", []) as Array).size(), 2)
