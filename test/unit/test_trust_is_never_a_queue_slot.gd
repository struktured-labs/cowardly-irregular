extends GutTest

## struktured playing .792 (2026-11-12): "you can advance on Trust ... and it messes up with a queued ? action".
## Advance special-cased turnless rows, party moves and the Auto row; the Trust row fell through to the queue as if
## it were an action, and Confirm on it with a queue held appended it too. ONE predicate now: a row that hands the
## turn to the script (Auto: this turn, Trust: every turn) is never a queue slot, and a row whose `data.action` word
## nobody has classified cannot be queued either. BEHAVIOURAL against the real Win98Menu and the real menu builder.

const W98 := "res://src/ui/Win98Menu.gd"
const SCENE_PATH := "res://src/battle/BattleScene.gd"
const MenuClass = preload("res://src/battle/BattleCommandMenu.gd")

var _saved_enemy: Array = []
var _saved_player: Array = []
var _got: Array = []
var _submitted: Array = []


func before_each() -> void:
	Input.action_release("ui_accept")
	Win98Menu._last_advance_ms = -1000000
	_got = []
	_submitted = []
	_saved_enemy = BattleManager.enemy_party.duplicate()
	_saved_player = BattleManager.player_party.duplicate()
	BattleManager.enemy_party.assign(_saved_enemy.filter(func(e): return is_instance_valid(e)))
	BattleManager.player_party.assign(_saved_player.filter(func(p): return is_instance_valid(p)))


func after_each() -> void:
	Input.action_release("ui_accept")
	BattleManager.enemy_party.assign(_saved_enemy)
	BattleManager.player_party.assign(_saved_player)


func _on_selected(id: String, _data: Variant) -> void:
	_got.append(id)


func _on_submitted(actions: Array) -> void:
	_submitted.append(actions)


func _trust() -> Dictionary:
	return {"id": "trust_toggle", "label": "Trust (every turn): OFF", "skip_default": true, "data": {"action": "trust_toggle", "combatant": "pc"}}


func _auto() -> Dictionary:
	return {"id": "autobattle", "label": "Auto: this turn", "skip_default": true, "data": {"action": "autobattle", "combatant": "pc"}}


func _attack() -> Dictionary:
	return {"id": "attack_0", "label": "Attack", "data": {"action": "attack", "target_idx": 0}}


func _menu(rows: Array) -> Node:
	var m = load(W98).new()
	m.is_root_menu = true
	m.battle_mode = true
	add_child_autofree(m)
	m.setup("Command", rows, Vector2(10, 10), "fighter")
	m._can_accept_input = true
	m.set_max_queue_size(4)
	m.item_selected.connect(_on_selected)
	m.actions_submitted.connect(_on_submitted)
	return m


func _advance(m: Node, index: int) -> void:
	m.selected_index = index
	Win98Menu._last_advance_ms = -1000000
	m._handle_advance_input()


func test_the_floor_names_every_member_this_file_drives() -> void:
	var m = _menu([_attack()])
	for f in ["_handle_advance_input", "_queue_current_action", "_submit_actions", "_undo_last_action", "_sync_auto_row_disabled", "_reject_text", "get_queue_count", "set_max_queue_size"]:
		assert_true(m.has_method(f), "Win98Menu.%s must exist" % f)
	assert_true("_last_advance_ms" in Win98Menu and "_queued_actions" in m and "menu_items" in m, "Win98Menu's queue state must exist")
	assert_true(m.has_signal("item_selected") and m.has_signal("actions_submitted"), "Win98Menu's two commit signals must exist")
	assert_true(MenuClass.new(null).has_method("build_command_menu_items_with_targets"), "the real builder must exist")


## CONTROL for every arm below: an ordinary action DOES queue on Advance, so "the queue did not grow" can fail.
func test_an_action_queues_on_advance() -> void:
	var m = _menu([_attack(), _trust()])
	_advance(m, 0)
	assert_eq(m.get_queue_count(), 1, "CONTROL: Advance on Attack queues it")
	assert_eq(_got, [], "CONTROL: and commits nothing")


func test_advance_on_trust_toggles_it_and_queues_nothing() -> void:
	var m = _menu([_trust(), _attack()])
	_advance(m, 0)
	assert_eq(m.get_queue_count(), 0, "Advance on Trust leaves the queue as it was")
	assert_eq(_got, ["trust_toggle"], "and does what Confirm does: the toggle goes to battle once")
	assert_eq(_submitted, [], "never as a queued turn")


func test_trust_is_unavailable_while_a_queue_is_held_and_comes_back() -> void:
	var m = _menu([_attack(), _trust(), _auto()])
	assert_false(bool(m.menu_items[1].get("disabled", false)), "CONTROL: Trust starts available")
	_advance(m, 0)
	assert_eq(m.get_queue_count(), 1, "CONTROL: one action is queued")
	assert_true(bool(m.menu_items[1].get("disabled", false)), "Trust is disabled while anything is queued")
	assert_true(bool(m.menu_items[2].get("disabled", false)), "CONTROL: and Auto still is, as before")
	assert_eq(m._reject_text(m.menu_items[1]), Win98Menu.HANDS_TURN_REASON, "and it says why")
	_advance(m, 1)
	assert_eq(m.get_queue_count(), 1, "Advance on the disabled Trust row queues nothing")
	assert_eq(_got, [], "and toggles nothing")
	m._undo_last_action()
	assert_eq(m.get_queue_count(), 0, "CONTROL: the undo emptied the queue")
	assert_false(bool(m.menu_items[1].get("disabled", false)), "Trust is available again")
	assert_false(bool(m.menu_items[2].get("disabled", false)), "CONTROL: and so is Auto")


## The earlier stages (the disabled flag) are DEFEATED here on purpose, so the commit path's own refusal is what is judged.
func test_confirm_on_trust_never_joins_a_held_queue() -> void:
	var m = _menu([_attack(), _trust()])
	_advance(m, 0)
	m.menu_items[1]["disabled"] = false
	m.selected_index = 1
	m._submit_actions()
	assert_eq(_submitted, [], "Confirm on Trust with a queue held submits no turn")
	assert_eq(_got, [], "and toggles nothing")
	assert_eq(m.get_queue_count(), 1, "the queue is still the one action the player queued")


## The queue itself fails closed, whatever called it.
func test_the_queue_refuses_a_row_that_is_not_an_action() -> void:
	var m = _menu([_attack(), _trust(), _auto(), {"id": "zzq", "label": "New row", "data": {"action": "zzq_unclassified"}}])
	for i in [1, 2, 3]:
		m.selected_index = i
		m._queue_current_action(m.menu_items[i])
		assert_eq(m.get_queue_count(), 0, "%s is not a queue slot" % m.menu_items[i]["id"])
	m.selected_index = 0
	m._queue_current_action(m.menu_items[0])
	assert_eq(m.get_queue_count(), 1, "CONTROL: an action is")


## CONTROL: Auto behaves as it did (test_auto_is_one_press_regression holds the rest).
func test_advance_on_auto_still_runs_it() -> void:
	var m = _menu([_auto(), _attack()])
	_advance(m, 0)
	assert_eq(m.get_queue_count(), 0, "Auto never sits in the queue")
	assert_eq(_got, ["autobattle"], "Advance on Auto runs it")


func _leaves(rows: Array, out: Array) -> void:
	for r in rows:
		if not (r is Dictionary):
			continue
		out.append(r)
		if (r as Dictionary).has("submenu"):
			_leaves((r as Dictionary)["submenu"], out)


## THE CENSUS: every row the REAL builder makes, at any depth, is classified, so the next non-action row added to the
## command menu cannot be queued silently. Its `data.action` word must be in one of Win98Menu's two lists.
func test_every_real_command_row_is_classified() -> void:
	assert_eq(Win98Menu.row_kind({"id": "x", "data": {"action": "zzq_unclassified"}}), "unclassified", "CONTROL: an unknown action word is reported")
	assert_eq(Win98Menu.row_kind(_trust()), "hands_turn", "Trust hands the turn over")
	assert_eq(Win98Menu.row_kind(_auto()), "hands_turn", "Auto hands the turn over")
	assert_eq(Win98Menu.row_kind(_attack()), "action", "CONTROL: an attack is an action")
	var scene: Node = load(SCENE_PATH).new()
	add_child_autofree(scene)
	await get_tree().process_frame
	var enemies: Array = []
	for i in 2:
		var e := Combatant.new()
		add_child_autofree(e)
		e.combatant_name = "Dummy%d" % i
		e.max_hp = 10
		e.current_hp = 10
		enemies.append(e)
	scene.test_enemies.assign(enemies)
	var seen := 0
	var handed: Array = []
	var bad: Array = []
	for job in ["fighter", "cleric", "mage", "rogue", "bard"]:
		var pc := Combatant.new()
		add_child_autofree(pc)
		pc.combatant_name = job.capitalize()
		pc.max_hp = 30
		pc.current_hp = 30
		pc.max_mp = 20
		pc.current_mp = 20
		pc.job = JobSystem.get_job(job)
		var all: Array = []
		_leaves(MenuClass.new(scene).build_command_menu_items_with_targets(pc), all)
		for r in all:
			seen += 1
			var kind: String = Win98Menu.row_kind(r)
			if kind == "unclassified":
				bad.append("%s: %s" % [job, r.get("id", "?")])
			elif kind == "hands_turn" and not (str(r.get("id", "")) in handed):
				handed.append(str(r.get("id", "")))
	assert_gt(seen, 40, "CONTROL: the real builder produced real menus (%d rows over five jobs)" % seen)
	handed.sort()
	assert_eq(handed, ["autobattle", "trust_toggle"], "the rows that hand the turn over are exactly Auto and Trust")
	assert_eq(bad, [], "every command row is classified (add its data.action to HANDS_TURN_ACTIONS or QUEUEABLE_ACTIONS): %s" % [bad])
