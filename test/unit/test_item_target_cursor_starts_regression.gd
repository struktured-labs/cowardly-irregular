extends GutTest

## Opening a potion's target list used to rest on party member 0. When that
## person was already full, confirm refused and the hurt ally was one press
## away with no hint that they were the one the item could help.
## The cursor now opens on the first target a confirm would actually spend
## on. A list where nobody qualifies still opens on the first enabled row,
## and that row stays reachable so the existing refusal can be read.


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
	c.job = JobSystem.get_job("fighter")
	add_child_autofree(c)
	c.current_hp = hp
	c.current_mp = 20
	c.is_alive = hp > 0
	return c


func _open_field(party: Array, item_id: String):
	var menu = ItemsMenuScript.new()
	add_child_autofree(menu)
	menu.setup(party, {item_id: 1})
	await get_tree().process_frame
	assert_eq(menu._item_list.size(), 1, "CONTROL: %s is on the field list" % item_id)
	assert_eq(str(menu._item_list[0].get("id", "")), item_id)
	menu._begin_target_select()
	return menu


func _cursor(menu, index: int) -> String:
	var row = menu._target_labels[index]
	var cursor = row.get_node_or_null("Cursor")
	if cursor == null:
		return ""
	return str(cursor.text)


func test_the_field_potion_cursor_opens_on_the_hurt_ally() -> void:
	var bram := _person("Bram", 100, 100)
	var theron := _person("Theron", 30, 100)
	var menu = await _open_field([bram, theron], "potion")
	assert_eq(menu.selected_target_index, 1)
	assert_eq(_cursor(menu, 1), ">")
	assert_eq(_cursor(menu, 0), " ")
	assert_eq(ItemSystem.ineffective_use_reason("potion", [bram]), "Bram is already at full HP")
	assert_eq(ItemSystem.ineffective_use_reason("potion", [theron]), "")


func test_the_field_cursor_stays_on_a_hurt_leader() -> void:
	var bram := _person("Bram", 30, 100)
	var theron := _person("Theron", 100, 100)
	var menu = await _open_field([bram, theron], "potion")
	assert_eq(menu.selected_target_index, 0)
	assert_eq(_cursor(menu, 0), ">")


func test_a_field_list_nobody_can_use_still_opens_on_the_first_member() -> void:
	var bram := _person("Bram", 100, 100)
	var theron := _person("Theron", 80, 80)
	var menu = await _open_field([bram, theron], "potion")
	assert_eq(menu.selected_target_index, 0)
	assert_eq(_cursor(menu, 0), ">")
	assert_ne(ItemSystem.ineffective_use_reason("potion", [bram]), "")


func test_phoenix_down_opens_on_the_ko_not_the_hurt_living_ally() -> void:
	var bram := _person("Bram", 40, 100)
	var milo := _person("Milo", 0, 100)
	var menu = await _open_field([bram, milo], "phoenix_down")
	assert_eq(ItemSystem.ineffective_use_reason("phoenix_down", [bram]), "",
		"CONTROL: the bundled heal looks like a real field use; the cursor must still not start there")
	assert_eq(menu.selected_target_index, 1)
	assert_eq(_cursor(menu, 1), ">")
	assert_eq(ItemSystem.ineffective_use_reason("phoenix_down", [milo]), "")


func test_phoenix_down_does_not_open_on_a_permakilled_ally() -> void:
	var bram := _person("Bram", 100, 100)
	var milo := _person("Milo", 0, 100)
	milo.add_status("permakilled")
	var menu = await _open_field([bram, milo], "phoenix_down")
	assert_ne(ItemSystem.ineffective_use_reason("phoenix_down", [milo]), "")
	assert_eq(menu.selected_target_index, 0, "nobody can be revived, so the cursor stays where confirm explains the refusal")


func _menu(items: Array):
	var menu = Win98MenuClass.new()
	add_child_autofree(menu)
	menu.setup("Test", items, Vector2.ZERO, "fighter")
	return menu


func test_a_battle_target_list_opens_on_the_first_real_use() -> void:
	var menu = _menu([
		{"id": "full", "label": "Bram (100/100 HP)", "reject_reason": "Bram is already at full HP"},
		{"id": "hurt", "label": "Theron (30/100 HP)"},
	])
	assert_eq(menu.selected_index, 1)
	menu._step_selection(-1)
	assert_eq(menu.selected_index, 0, "the full-HP row stays landable so confirm can still say why")


func test_an_all_noop_battle_list_opens_on_the_first_enabled_row() -> void:
	var menu = _menu([
		{"id": "skip", "label": "Grey", "disabled": true},
		{"id": "full", "label": "Bram", "reject_reason": "Bram is already at full HP"},
		{"id": "also", "label": "Theron", "reject_reason": "Theron is already at full HP"},
	])
	assert_eq(menu.selected_index, 1)


func test_a_disabled_row_is_still_skipped_ahead_of_a_real_use() -> void:
	var menu = _menu([
		{"id": "grey", "label": "Grey", "disabled": true},
		{"id": "full", "label": "Bram", "reject_reason": "Bram is already at full HP"},
		{"id": "hurt", "label": "Theron"},
	])
	assert_eq(menu.selected_index, 2)


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
	var built = MenuClass.new(scene)
	return built.build_command_menu_items_with_targets(party[0])


func test_the_battle_potion_list_opens_on_the_ally_it_can_heal() -> void:
	var bram := _person("Bram", 100, 100)
	var theron := _person("Theron", 30, 100)
	var milo := _person("Milo", 0, 100)
	bram.add_item("potion", 1)
	bram.add_item("phoenix_down", 1)
	var rows: Array = await _battle_rows([bram, theron, milo])
	var potion: Array = _row(rows, "item_menu_potion").get("submenu", [])
	assert_eq(potion.size(), 2, "CONTROL: a potion offers the living allies, not the KO")
	var potion_menu = _menu(potion)
	assert_eq(str(potion_menu.menu_items[potion_menu.selected_index].get("id", "")), "item_potion_ally_1")
	var feather: Array = _row(rows, "item_menu_phoenix_down").get("submenu", [])
	assert_gte(feather.size(), 3, "CONTROL: Phoenix Down still lists the KO")
	var feather_menu = _menu(feather)
	assert_eq(str(feather_menu.menu_items[feather_menu.selected_index].get("id", "")), "item_phoenix_down_ally_2")
