extends GutTest

## Phoenix Down revives at 25% HP. That percent is also a heal key, so the
## no-op check treated a hurt living ally as a real use. Battle execution
## then drops every living target of a revival item, the action fizzles,
## and the selection turn is already over. The item was not spent; the turn was.
##
## The battle item row must refuse first, with a reason, the same way a
## full-HP potion does. A KO'd ally, a party that includes one, and a direct
## use_item of something that both revives and heals stay as they were.

const ItemSystemScript = preload("res://src/items/ItemSystem.gd")
const ItemsMenuScript = preload("res://src/ui/ItemsMenu.gd")
const MenuClass = preload("res://src/battle/BattleCommandMenu.gd")
const Win98MenuClass = preload("res://src/ui/Win98Menu.gd")
const SCENE_PATH := "res://src/battle/BattleScene.gd"

var _saved_enemy: Array = []
var _saved_player: Array = []


func before_each() -> void:
	_saved_enemy = BattleManager.enemy_party.duplicate()
	_saved_player = BattleManager.player_party.duplicate()


func after_each() -> void:
	var live_e: Array[Combatant] = []
	for e in _saved_enemy:
		if is_instance_valid(e):
			live_e.append(e)
	var live_p: Array[Combatant] = []
	for p in _saved_player:
		if is_instance_valid(p):
			live_p.append(p)
	BattleManager.enemy_party.assign(live_e)
	BattleManager.player_party.assign(live_p)


func _person(who: String, hp: int, max_hp: int) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = who
	c.max_hp = max_hp
	c.max_mp = 20
	add_child_autofree(c)
	c.current_hp = hp
	c.current_mp = 20
	c.is_alive = hp > 0
	return c


func _put(sys: Node, id: String, effects: Dictionary) -> void:
	sys.items[id] = {"id": id, "name": id.capitalize(), "effects": effects}


func _row(rows: Array, id: String) -> Dictionary:
	for r in rows:
		if str(r.get("id", "")) == id:
			return r
		var sub = r.get("submenu", [])
		if sub is Array and not sub.is_empty():
			var nested := _row(sub, id)
			if not nested.is_empty():
				return nested
	return {}


func _battle_rows(party: Array) -> Array:
	var scene: Node = load(SCENE_PATH).new()
	add_child_autofree(scene)
	await get_tree().process_frame
	var enemy := Combatant.new()
	add_child_autofree(enemy)
	enemy.combatant_name = "Rat"
	enemy.max_hp = 10
	enemy.current_hp = 10
	scene.test_enemies.assign([enemy])
	var typed: Array[Combatant] = []
	for m in party:
		typed.append(m)
	scene.party_members.assign(typed)
	BattleManager.player_party.assign(typed)
	var menu = MenuClass.new(scene)
	return menu.build_command_menu_items_with_targets(party[0])


func _toast_text(node: Node) -> String:
	var found := ""
	for c in node.get_children():
		if c is Label and str(c.text) != "":
			found = str(c.text)
		var nested := _toast_text(c)
		if nested != "":
			found = nested
	return found


func test_battle_check_refuses_phoenix_down_on_someone_still_standing() -> void:
	var bram := _person("Bram", 40, 100)
	var down := _person("Milo", 0, 100)
	down.is_alive = false
	assert_eq(ItemSystem.ineffective_use_reason("phoenix_down", [bram], true), "Bram isn't knocked out",
		"a hurt living ally used to look like Phoenix Down's 25%% heal, then the battle executor fizzled the turn")
	var full := _person("Bram", 100, 100)
	assert_eq(ItemSystem.ineffective_use_reason("phoenix_down", [full], true), "Bram isn't knocked out",
		"full HP is the same refusal — the percent is the revive amount, not a reason to spend the turn")
	assert_eq(ItemSystem.ineffective_use_reason("phoenix_down", [down], true), "",
		"a KO'd ally is the use Phoenix Down exists for")
	var theron := _person("Theron", 80, 80)
	assert_eq(ItemSystem.ineffective_use_reason("phoenix_down", [bram, theron], true), "No one is knocked out")
	assert_eq(ItemSystem.ineffective_use_reason("phoenix_down", [bram, down], true), "",
		"a party-wide target list that includes one KO'd ally is still a real revive")


func test_a_bundled_heal_still_lands_when_use_item_runs() -> void:
	# use_item still applies the bundled heal. Battle menus pass in_battle and refuse;
	# queued actions keep going through _execute_item, which this file also pins.
	var sys := ItemSystemScript.new()
	_put(sys, "phoenix", {"revive": true, "heal_hp_percent": 25})
	_put(sys, "salve", {"revive": true, "heal_hp": 40})
	var scratched := _person("Theron", 10, 80)
	assert_eq(sys.ineffective_use_reason("phoenix", [scratched]), "",
		"without the battle flag the bundled heal is still a real use_item")
	assert_eq(sys.ineffective_use_reason("salve", [scratched]), "",
		"an item that both revives and heals is unchanged for callers that run use_item")
	assert_true(sys.use_item(scratched, "salve", [scratched] as Array[Combatant]))
	assert_eq(scratched.current_hp, 50, "the flat heal on a living ally must still land")
	var other := _person("Bram", 40, 100)
	assert_true(sys.use_item(other, "phoenix", [other] as Array[Combatant]))
	assert_eq(other.current_hp, 65, "Phoenix Down's 25%% still heals when use_item itself runs")
	var down := _person("Milo", 0, 100)
	down.is_alive = false
	assert_eq(sys.ineffective_use_reason("salve", [scratched, down], true), "",
		"in battle, one KO'd ally still makes a revive-and-heal a real use")
	sys.free()


func test_the_battle_item_row_refuses_and_confirm_does_not_take_the_turn() -> void:
	var bram := _person("Bram", 40, 100)
	var milo := _person("Milo", 0, 80)
	milo.is_alive = false
	bram.job = JobSystem.get_job("fighter")
	milo.job = JobSystem.get_job("fighter")
	bram.add_item("phoenix_down", 1)
	var rows: Array = await _battle_rows([bram, milo])
	var living := _row(rows, "item_phoenix_down_ally_0")
	var ko := _row(rows, "item_phoenix_down_ally_1")
	assert_false(living.is_empty(), "CONTROL: Phoenix Down offered Bram")
	assert_eq(str(living.get("reject_reason", "")), "Bram isn't knocked out")
	assert_false(ko.has("reject_reason"), "Milo is KO'd — Phoenix Down must stay selectable. Row: %s" % str(ko))
	var m = Win98MenuClass.new()
	add_child_autofree(m)
	m.setup("Test", [living], Vector2(40, 40), "fighter")
	await get_tree().process_frame
	var picked: Array = []
	m.item_selected.connect(func(id, _data): picked.append(id))
	var hint := Label.new()
	add_child_autofree(hint)
	hint.text = "hint"
	m._hint_label_cache = hint
	m._can_accept_input = true
	m.selected_index = 0
	m._on_item_pressed(0)
	assert_eq(picked.size(), 0, "confirm must not queue the revive")
	assert_eq(hint.text, "Bram isn't knocked out")
	assert_eq(bram.get_item_count("phoenix_down"), 1, "the feather stays in the bag")


func test_the_field_menu_names_who_is_not_knocked_out_and_keeps_the_item() -> void:
	var menu := ItemsMenuScript.new()
	add_child_autofree(menu)
	await get_tree().process_frame
	var bram := _person("Bram", 40, 100)
	bram.add_item("phoenix_down", 1)
	var data: Dictionary = ItemSystem.get_item("phoenix_down")
	assert_false(data.is_empty(), "CONTROL: phoenix_down is loaded")
	menu.party = [bram]
	menu.inventory = {"phoenix_down": 1}
	menu._item_list = [{"id": "phoenix_down", "quantity": 1, "data": data}]
	menu.selected_item_index = 0
	menu.selected_target_index = 0
	menu._use_selected_item()
	assert_eq(int(menu.inventory.get("phoenix_down", 0)), 1, "the field menu must not spend a revive on someone standing")
	assert_eq(bram.current_hp, 40, "and it must not apply the 25%% heal either")
	assert_eq(int(bram.get_item_count("phoenix_down")), 1)
	assert_eq(_toast_text(menu), "Bram isn't knocked out")


func test_a_queued_phoenix_down_on_the_living_still_fizzles_without_spending() -> void:
	# Already-queued actions, enemy item use, and autobattle resolve through
	# _execute_item. That path keeps dropping living targets. The menu refusal
	# must not turn it into a heal.
	var bram := _person("Bram", 40, 100)
	bram.add_item("phoenix_down", 1)
	var typed: Array[Combatant] = [bram]
	BattleManager.player_party.assign(typed)
	BattleManager._execute_item(bram, "phoenix_down", [bram])
	assert_eq(bram.current_hp, 40, "execution still does not heal a living ally with Phoenix Down")
	assert_eq(bram.get_item_count("phoenix_down"), 1, "and it still does not spend the feather")
