extends GutTest

## Advance commit kept only rows that carried a target_idx. Cleave, Channel, and a party potion have no picker, so queuing them and committing (hold Defer, or Confirm once the queue holds more than one) dropped them. A lone Cleave became "No valid actions left — defer."

const MenuScript = preload("res://src/battle/BattleCommandMenu.gd")
const SceneScript = preload("res://src/battle/BattleScene.gd")

## BattleScene._ready builds UI off scene nodes this probe does not have.
class QuietScene extends SceneScript:
	func _ready() -> void:
		pass

	func log_message(_message: String) -> void:
		pass

	func _update_ui() -> void:
		pass


var _saved_party: Array
var _saved_order: Array
var _saved_index: int
var _saved_current
var _saved_state: int
var _saved_enemies: Array
var _saved_pending: Array
var _saved_auto: bool
var _saved_repeat: bool


func before_each() -> void:
	_saved_party = BattleManager.player_party.duplicate()
	_saved_order = BattleManager.selection_order.duplicate()
	_saved_index = BattleManager.selection_index
	_saved_current = BattleManager.current_combatant
	_saved_state = BattleManager.current_state
	_saved_enemies = BattleManager.enemy_party.duplicate()
	_saved_pending = BattleManager.pending_actions.duplicate()
	_saved_auto = BattleManager.is_autobattle_enabled
	_saved_repeat = BattleManager._filling_repeat


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
	BattleManager.is_autobattle_enabled = _saved_auto
	BattleManager._filling_repeat = _saved_repeat


func _alive(saved: Array) -> Array:
	var out: Array = []
	for c in saved:
		if is_instance_valid(c):
			out.append(c)
	return out


func _pc(who: String, job_id: String, alive: bool) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = who
	var job: Dictionary = JobSystem.get_job(job_id).duplicate(true)
	c.job = job
	c.max_hp = 400
	c.current_hp = 400 if alive else 0
	c.is_alive = alive
	c.max_mp = 80
	c.current_mp = 80
	c.current_ap = 1
	return c


func _field() -> Dictionary:
	var caster := _pc("CleaveUser", "fighter", true)
	var next_pc := _pc("NextPicker", "cleric", true)
	var downed := _pc("DownedAlly", "mage", false)
	var slime := _pc("Slime", "fighter", true)
	var bat := _pc("Bat", "fighter", true)
	var goblin := _pc("Goblin", "fighter", false)
	var scene := QuietScene.new()
	autofree(scene)
	var party: Array[Combatant] = [caster, next_pc, downed]
	var enemies: Array[Combatant] = [slime, bat, goblin]
	scene.party_members = party
	scene.test_enemies = enemies
	scene.command_memory_enabled = false
	var menu = MenuScript.new(scene)
	scene._command_menu = menu
	BattleManager.player_party.assign(party)
	BattleManager.enemy_party.assign(enemies)
	BattleManager.selection_order.assign([caster, next_pc])
	BattleManager.selection_index = 0
	BattleManager.current_combatant = caster
	BattleManager.current_state = BattleManager.BattleState.PLAYER_SELECTING
	BattleManager.is_autobattle_enabled = false
	BattleManager._filling_repeat = false
	BattleManager.pending_actions.clear()
	return {
		"menu": menu,
		"caster": caster,
		"next": next_pc,
		"downed": downed,
		"slime": slime,
		"bat": bat,
		"goblin": goblin,
	}


func _queued(row: Dictionary) -> Dictionary:
	return {"id": str(row.get("id", "")), "data": row.get("data", null), "label": str(row.get("label", ""))}


func _action_for(who: Combatant) -> Dictionary:
	for action in BattleManager.pending_actions:
		if action.get("combatant") == who:
			return action
	return {}


func _target_names(targets: Array) -> Array:
	var names: Array = []
	for t in targets:
		names.append(t.combatant_name if is_instance_valid(t) else "?")
	return names


func test_a_lone_cleave_advance_hits_every_living_enemy() -> void:
	var field := _field()
	var menu = field["menu"]
	var row: Dictionary = menu._build_ability_menu_item("cleave", field["caster"], menu.get_alive_enemies(), Transform2D())
	assert_eq(str(row.get("id", "")), "ability_cleave", "Cleave is the picker-less ability row the menu builds")
	var data: Variant = row.get("data", {})
	assert_true(data is Dictionary and not (data as Dictionary).has("target_idx"), "Cleave's queued data has no target_idx")
	menu._on_win98_actions_submitted([_queued(row)])
	var action := _action_for(field["caster"])
	assert_eq(str(action.get("type", "")), "advance", "a queued Cleave must advance — it was deferred as having no valid actions")
	var subs: Array = action.get("actions", [])
	assert_eq(subs.size(), 1, "the cleave is the one sub-action")
	if subs.is_empty():
		return
	assert_eq(str(subs[0].get("ability_id", "")), "cleave")
	assert_eq(_target_names(subs[0].get("targets", [])), ["Slime", "Bat"], "Cleave hits every living enemy and skips the KO'd one")


func test_advance_keeps_pickerless_rows_beside_a_picked_attack() -> void:
	var field := _field()
	var menu = field["menu"]
	var alive: Array = menu.get_alive_enemies()
	var cleave: Dictionary = menu._build_ability_menu_item("cleave", field["caster"], alive, Transform2D())
	var channel: Dictionary = menu._build_ability_menu_item("channel", field["caster"], alive, Transform2D())
	var channel_data: Variant = channel.get("data", {})
	assert_true(channel_data is Dictionary and not (channel_data as Dictionary).has("target_idx"), "Channel is self-targeted and has no picker")
	## The item menu's no-submenu branch emits exactly this shape for ALL_ALLIES (Mega Potion).
	var potion := {"id": "item_mega_potion", "data": {"item_id": "mega_potion"}, "label": "Mega Potion x1"}
	var attack := {"id": "attack_1", "data": {"target_idx": 1, "action": "attack"}, "label": "Bat"}
	menu._on_win98_actions_submitted([_queued(cleave), _queued(channel), _queued(potion), _queued(attack)])
	var action := _action_for(field["caster"])
	assert_eq(str(action.get("type", "")), "advance")
	var subs: Array = action.get("actions", [])
	assert_eq(subs.size(), 4, "Cleave, Channel, and the party potion must survive beside the picked attack")
	if subs.size() != 4:
		return
	assert_eq(str(subs[0].get("type", "")), "ability")
	assert_eq(str(subs[0].get("ability_id", "")), "cleave")
	assert_eq(_target_names(subs[0].get("targets", [])), ["Slime", "Bat"])
	assert_eq(str(subs[1].get("ability_id", "")), "channel")
	assert_eq(_target_names(subs[1].get("targets", [])), ["CleaveUser"], "Channel restores the caster, not the party")
	assert_eq(str(subs[2].get("type", "")), "item")
	assert_eq(str(subs[2].get("item_id", "")), "mega_potion")
	assert_eq(_target_names(subs[2].get("targets", [])), ["CleaveUser", "NextPicker"], "a party potion skips the KO'd ally")
	assert_eq(str(subs[3].get("type", "")), "attack")
	assert_eq(subs[3].get("target"), field["bat"], "a picked attack still hits only the enemy the cursor was on")
