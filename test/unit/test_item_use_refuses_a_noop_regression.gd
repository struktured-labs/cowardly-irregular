extends GutTest

## A potion on a full-HP ally used to play the heal sound and leave the bag.
## ItemSystem.use_item returns true whenever the item exists — a 0 HP heal is
## still "success" — so the menu spent the item and had nothing to explain.
## The same hole ate an antidote with no poison, a Smoke Bomb on the field,
## and a key item whose effects dict is empty.
##
## The fix refuses before the spend and says which. A use that would actually
## change HP, MP, a status, a revive, a buff, or an in-battle escape still goes
## through. Amounts are untouched.


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


func _sys() -> Node:
	return ItemSystemScript.new()


func _person(sys_name: String, hp: int, max_hp: int) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = sys_name
	c.max_hp = max_hp
	c.max_mp = 30
	add_child_autofree(c)
	c.current_hp = hp
	c.current_mp = 30
	c.is_alive = hp > 0
	return c


func _put(sys: Node, id: String, effects: Dictionary) -> void:
	sys.items[id] = {"id": id, "name": id.capitalize(), "effects": effects}


func test_a_full_heal_is_a_real_use_and_a_zero_heal_is_not() -> void:
	var sys := _sys()
	_put(sys, "potion", {"heal_hp": 500})
	var full := _person("Bram", 100, 100)
	var hurt := _person("Milo", 40, 100)
	assert_eq(sys.ineffective_use_reason("potion", [full]), "Bram is already at full HP")
	assert_eq(sys.ineffective_use_reason("potion", [hurt]), "")
	# The executor still reports success for the zero heal. The menu is what has to refuse.
	assert_true(sys.use_item(full, "potion", [full] as Array[Combatant]))
	assert_eq(full.current_hp, 100, "the zero heal must not move HP — that is the use the menu now refuses")
	assert_true(sys.use_item(hurt, "potion", [hurt] as Array[Combatant]))
	assert_gt(hurt.current_hp, 40, "a hurt ally still receives the heal")
	sys.free()


func test_party_heal_names_the_party_only_when_nobody_needs_it() -> void:
	var sys := _sys()
	_put(sys, "mega", {"heal_hp": 1000})
	var a := _person("Bram", 100, 100)
	var b := _person("Milo", 100, 100)
	assert_eq(sys.ineffective_use_reason("mega", [a, b]), "The party is already at full HP")
	b.current_hp = 10
	assert_eq(sys.ineffective_use_reason("mega", [a, b]), "",
		"one hurt ally is enough — the item still heals them")
	sys.free()


func test_mp_status_revive_and_battle_only_items_each_say_why() -> void:
	var sys := _sys()
	_put(sys, "potion", {"heal_hp": 500})
	_put(sys, "ether", {"heal_mp": 30})
	_put(sys, "elixir", {"heal_hp_percent": 100, "heal_mp_percent": 100})
	_put(sys, "antidote", {"cure_status": ["poison"]})
	_put(sys, "remedy", {"cure_all_status": true})
	_put(sys, "phoenix", {"revive": true, "heal_hp_percent": 25})
	_put(sys, "smoke", {"escape_battle": true})
	sys.items["smoke"]["name"] = "Smoke Bomb"
	_put(sys, "coin", {})
	sys.items["coin"]["name"] = "Shiny Coin"
	_put(sys, "drink", {"add_buff": {"type": "attack_up", "power": 1.5, "duration": 3}})
	var full := _person("Bram", 80, 80)
	full.current_mp = full.max_mp
	assert_eq(sys.ineffective_use_reason("ether", [full]), "Bram is already at full MP")
	full.current_mp = 5
	assert_eq(sys.ineffective_use_reason("ether", [full]), "")
	full.current_mp = full.max_mp
	assert_eq(sys.ineffective_use_reason("elixir", [full]), "Bram is already at full HP and MP")
	full.current_mp = 5
	assert_eq(sys.ineffective_use_reason("elixir", [full]), "", "missing MP is a real elixir use")
	assert_eq(sys.ineffective_use_reason("antidote", [full]), "Bram isn't poisoned")
	full.status_effects.append("poison")
	assert_eq(sys.ineffective_use_reason("antidote", [full]), "")
	full.status_effects.clear()
	assert_eq(sys.ineffective_use_reason("remedy", [full]), "Bram has no status to cure")
	var down := _person("Milo", 0, 80)
	down.is_alive = false
	assert_eq(sys.ineffective_use_reason("potion", [down]), "Milo is knocked out")
	assert_eq(sys.ineffective_use_reason("phoenix", [down]), "")
	assert_eq(sys.ineffective_use_reason("phoenix", [full]), "Bram is already at full HP",
		"Phoenix Down's bundled heal is real on a living ally, and a no-op when they are already full")
	var scratched := _person("Theron", 10, 80)
	assert_eq(sys.ineffective_use_reason("phoenix", [scratched]), "",
		"a living hurt ally still receives Phoenix Down's heal when use_item runs; the battle menu passes in_battle and refuses")
	assert_eq(sys.ineffective_use_reason("smoke", [full]), "Smoke Bomb only works in battle")
	assert_eq(sys.ineffective_use_reason("smoke", [full], true), "",
		"the same Smoke Bomb is a real action once a battle is underway")
	assert_eq(sys.ineffective_use_reason("coin", [full]), "Shiny Coin can't be used")
	assert_eq(sys.ineffective_use_reason("drink", [full], true), "", "a buff still lands at full HP in battle")
	assert_eq(sys.ineffective_use_reason("drink", [full]), "Drink only works in battle",
		"the same buff spent from the pause menu is wiped at the next battle's start")
	sys.free()


func test_the_field_menu_keeps_a_potion_that_would_heal_nothing() -> void:
	var menu := ItemsMenuScript.new()
	add_child_autofree(menu)
	await get_tree().process_frame
	var bram := _person("Bram", 100, 100)
	bram.add_item("potion", 1)
	var data: Dictionary = ItemSystem.get_item("potion")
	assert_false(data.is_empty(), "CONTROL: the real potion is loaded")
	menu.party = [bram]
	menu.inventory = {"potion": 1}
	menu._item_list = [{"id": "potion", "quantity": 1, "data": data}]
	menu.selected_item_index = 0
	menu.selected_target_index = 0
	menu._use_selected_item()
	assert_eq(int(menu.inventory.get("potion", 0)), 1, "a full-HP confirm must leave the potion in the bag")
	assert_eq(bram.current_hp, 100)
	assert_eq(int(bram.get_item_count("potion")), 1)


func test_the_field_menu_still_spends_a_potion_on_someone_hurt() -> void:
	var menu := ItemsMenuScript.new()
	add_child_autofree(menu)
	await get_tree().process_frame
	var milo := _person("Milo", 40, 100)
	milo.add_item("potion", 1)
	var data: Dictionary = ItemSystem.get_item("potion")
	assert_false(data.is_empty(), "CONTROL: the real potion is loaded")
	menu.party = [milo]
	menu.inventory = {"potion": 1}
	menu._item_list = [{"id": "potion", "quantity": 1, "data": data}]
	menu.selected_item_index = 0
	menu.selected_target_index = 0
	menu._use_selected_item()
	assert_eq(int(menu.inventory.get("potion", 0)), 0, "a hurt ally still consumes the potion")
	assert_gt(milo.current_hp, 40, "and the heal still lands")
	assert_eq(int(milo.get_item_count("potion")), 0)


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


func test_the_battle_item_list_refuses_a_full_party_and_allows_a_hurt_one() -> void:
	var bram := _person("Bram", 100, 100)
	var milo := _person("Milo", 100, 100)
	bram.job = JobSystem.get_job("fighter")
	milo.job = JobSystem.get_job("fighter")
	bram.add_item("potion", 1)
	bram.add_item("mega_potion", 1)
	var rows: Array = await _battle_rows([bram, milo])
	assert_false(_row(rows, "item_menu").is_empty(), "CONTROL: the item command was built")
	var mega := _row(rows, "item_mega_potion")
	assert_eq(str(mega.get("reject_reason", "")), "The party is already at full HP",
		"a party potion must look at every ally, not only the leader. Got: %s" % str(mega))
	assert_eq(str(_row(rows, "item_potion_ally_0").get("reject_reason", "")), "Bram is already at full HP")
	assert_eq(str(_row(rows, "item_potion_ally_1").get("reject_reason", "")), "Milo is already at full HP")
	milo.current_hp = 12
	rows = await _battle_rows([bram, milo])
	assert_false(_row(rows, "item_mega_potion").has("reject_reason"),
		"once anyone is hurt the party potion is a real use")
	assert_false(_row(rows, "item_potion_ally_1").has("reject_reason"),
		"the hurt ally stays selectable")
	assert_eq(str(_row(rows, "item_potion_ally_0").get("reject_reason", "")), "Bram is already at full HP",
		"the ally who is still full stays refused")


func _menu(rows: Array) -> Node:
	var m = Win98MenuClass.new()
	add_child_autofree(m)
	m.setup("Test", rows, Vector2(40, 40), "fighter")
	await get_tree().process_frame
	return m


func test_a_no_op_item_row_can_be_landed_on_and_confirm_does_not_take_it() -> void:
	var reason := "Bram is already at full HP"
	var m = await _menu([
		{"id": "ok", "label": "Attack"},
		{"id": "grey", "label": "Meteor", "disabled": true},
		{"id": "full", "label": "Bram (100/100 HP)", "reject_reason": reason},
	])
	m.selected_index = 0
	m._step_selection(1)
	assert_eq(m.selected_index, 2,
		"the cursor skips a disabled row and still lands on a no-op item, so the player can ask why")
	var hint := Label.new()
	add_child_autofree(hint)
	hint.text = "hint"
	m._hint_label_cache = hint
	var picked: Array = []
	m.item_selected.connect(func(id, _data): picked.append(id))
	m._can_accept_input = true
	m._on_item_pressed(2)
	assert_eq(picked.size(), 0, "confirm must not submit the no-op row")
	assert_eq(hint.text, reason)
	m._last_advance_ms = 0
	m._handle_advance_input()
	assert_eq(m.get_queue_count(), 0, "advance must not queue a no-op item either")
	m._on_item_pressed(0)
	assert_eq(picked.size(), 1, "CONTROL: an ordinary row still confirms")
	assert_eq(str(picked[0]), "ok")
