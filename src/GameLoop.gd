extends Node

## GameLoop - Controls the battle → menu → battle game loop
## Manages scene transitions and player persistence

const BattleSceneRes = preload("res://src/battle/BattleScene.tscn")
const MenuSceneRes = preload("res://src/ui/MenuScene.tscn")

enum LoopState {
	BATTLE,
	MENU
}

var current_state: LoopState = LoopState.BATTLE
var current_scene: Node = null

## Persistent party data
var party: Array[Combatant] = []
var battles_won: int = 0

## Shared equipment pool (unequipped items available to all party members)
var equipment_pool: Dictionary = {
	"weapons": [],
	"armors": [],
	"accessories": []
}


## Autobattle editor overlay
var _autobattle_editor: Control = null

func _ready() -> void:
	# Initialize equipment pool with extra items
	_init_equipment_pool()

	# Create persistent party
	_create_party()

	# Start with first battle
	_start_battle()


func _unhandled_input(event: InputEvent) -> void:
	# F5 = Open autobattle editor for current/first player
	if event is InputEventKey and event.pressed and event.keycode == KEY_F5:
		_toggle_autobattle_editor()
		get_viewport().set_input_as_handled()

	# F6 or Select button = Toggle autobattle for ALL players
	if event is InputEventKey and event.pressed and event.keycode == KEY_F6:
		_toggle_all_autobattle()
		get_viewport().set_input_as_handled()

	# Gamepad Select button (button 4 on most controllers)
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_BACK:
		_toggle_all_autobattle()
		get_viewport().set_input_as_handled()

	# Gamepad L+R together = Open autobattle editor
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER or event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			# Check if both L and R are held
			var joy_id = event.device
			if Input.is_joy_button_pressed(joy_id, JOY_BUTTON_LEFT_SHOULDER) and Input.is_joy_button_pressed(joy_id, JOY_BUTTON_RIGHT_SHOULDER):
				_toggle_autobattle_editor()
				get_viewport().set_input_as_handled()


func _toggle_autobattle_editor() -> void:
	"""Toggle the autobattle grid editor overlay"""
	if _autobattle_editor and is_instance_valid(_autobattle_editor):
		_autobattle_editor.queue_free()
		_autobattle_editor = null
		print("Autobattle editor closed")
		return

	# During battle, open for currently selecting player
	var char_id = "hero"
	var char_name = "Hero"

	if BattleManager and BattleManager.is_selecting() and BattleManager.current_combatant:
		var current = BattleManager.current_combatant
		if current in BattleManager.player_party:
			char_id = current.combatant_name.to_lower().replace(" ", "_")
			char_name = current.combatant_name
	elif party.size() > 0:
		char_id = party[0].combatant_name.to_lower().replace(" ", "_")
		char_name = party[0].combatant_name

	var AutobattleGridEditorClass = load("res://src/ui/autobattle/AutobattleGridEditor.gd")
	_autobattle_editor = AutobattleGridEditorClass.new()
	_autobattle_editor.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_autobattle_editor)
	_autobattle_editor.setup(char_id, char_name)
	_autobattle_editor.closed.connect(_on_autobattle_editor_closed)
	print("Autobattle editor opened for %s (F5/B to close)" % char_name)


func _toggle_all_autobattle() -> void:
	"""Toggle autobattle for ALL party members at once"""
	if party.size() == 0:
		return

	# Check if any are enabled - if so, disable all; otherwise enable all
	var any_enabled = false
	for member in party:
		var char_id = member.combatant_name.to_lower().replace(" ", "_")
		if AutobattleSystem.is_autobattle_enabled(char_id):
			any_enabled = true
			break

	# Toggle all to opposite state
	var new_state = not any_enabled
	for member in party:
		var char_id = member.combatant_name.to_lower().replace(" ", "_")
		AutobattleSystem.set_autobattle_enabled(char_id, new_state)

	var status = "ON" if new_state else "OFF"
	print("[AUTOBATTLE] All party members: %s (F6/Select to toggle)" % status)


func _on_autobattle_editor_closed() -> void:
	"""Handle editor close"""
	if _autobattle_editor and is_instance_valid(_autobattle_editor):
		_autobattle_editor.queue_free()
		_autobattle_editor = null


func _create_party() -> void:
	"""Create the persistent party"""
	party.clear()

	# Create Hero (Fighter)
	var hero = Combatant.new()
	hero.initialize({
		"name": "Hero",
		"max_hp": 150,
		"max_mp": 50,
		"attack": 25,
		"defense": 15,
		"magic": 12,
		"speed": 12
	})
	add_child(hero)
	JobSystem.assign_job(hero, "fighter")
	EquipmentSystem.equip_weapon(hero, "iron_sword")
	EquipmentSystem.equip_armor(hero, "leather_armor")
	EquipmentSystem.equip_accessory(hero, "power_ring")
	hero.learn_passive("weapon_mastery")
	hero.learn_passive("hp_boost")
	PassiveSystem.equip_passive(hero, "weapon_mastery")
	PassiveSystem.equip_passive(hero, "hp_boost")
	hero.add_item("potion", 5)
	hero.add_item("hi_potion", 2)
	hero.add_item("ether", 3)
	hero.add_item("phoenix_down", 1)
	party.append(hero)

	# Create Mira (White Mage)
	var mira = Combatant.new()
	mira.initialize({
		"name": "Mira",
		"max_hp": 100,
		"max_mp": 120,
		"attack": 10,
		"defense": 12,
		"magic": 28,
		"speed": 14
	})
	add_child(mira)
	JobSystem.assign_job(mira, "white_mage")
	EquipmentSystem.equip_weapon(mira, "oak_staff")
	EquipmentSystem.equip_armor(mira, "cloth_robe")
	EquipmentSystem.equip_accessory(mira, "magic_ring")
	mira.learn_passive("magic_boost")
	mira.learn_passive("mp_boost")
	PassiveSystem.equip_passive(mira, "magic_boost")
	PassiveSystem.equip_passive(mira, "mp_boost")
	party.append(mira)

	# Create Zack (Thief)
	var zack = Combatant.new()
	zack.initialize({
		"name": "Zack",
		"max_hp": 90,
		"max_mp": 40,
		"attack": 18,
		"defense": 10,
		"magic": 8,
		"speed": 22
	})
	add_child(zack)
	JobSystem.assign_job(zack, "thief")
	EquipmentSystem.equip_weapon(zack, "iron_dagger")
	EquipmentSystem.equip_armor(zack, "thief_garb")
	EquipmentSystem.equip_accessory(zack, "speed_boots")
	zack.learn_passive("critical_strike")
	zack.learn_passive("speed_boost")
	PassiveSystem.equip_passive(zack, "critical_strike")
	PassiveSystem.equip_passive(zack, "speed_boost")
	party.append(zack)

	# Create Vex (Black Mage)
	var vex = Combatant.new()
	vex.initialize({
		"name": "Vex",
		"max_hp": 80,
		"max_mp": 150,
		"attack": 8,
		"defense": 8,
		"magic": 35,
		"speed": 12
	})
	add_child(vex)
	JobSystem.assign_job(vex, "black_mage")
	EquipmentSystem.equip_weapon(vex, "shadow_rod")
	EquipmentSystem.equip_armor(vex, "dark_robe")
	EquipmentSystem.equip_accessory(vex, "mp_amulet")
	vex.learn_passive("magic_boost")
	vex.learn_passive("mp_efficiency")
	PassiveSystem.equip_passive(vex, "magic_boost")
	PassiveSystem.equip_passive(vex, "mp_efficiency")
	party.append(vex)


func _start_battle() -> void:
	"""Start a new battle"""
	current_state = LoopState.BATTLE

	# Remove old scene
	if current_scene:
		current_scene.queue_free()
		await current_scene.tree_exited

	# Check if this is a miniboss battle (every 3rd battle)
	var is_miniboss_battle = (battles_won + 1) % 3 == 0 and battles_won > 0

	# Create battle scene
	var battle_scene = BattleSceneRes.instantiate()

	# Set flags BEFORE adding to tree (since _ready() spawns enemies)
	battle_scene.managed_by_game_loop = true  # Disable BattleScene's internal restart
	if is_miniboss_battle:
		battle_scene.force_miniboss = true
		print("[MINIBOSS] Battle %d - A miniboss approaches!" % (battles_won + 1))

	add_child(battle_scene)
	current_scene = battle_scene

	# Pass party to battle scene
	battle_scene.set_party(party)

	# Connect to battle end
	BattleManager.battle_ended.connect(_on_battle_ended, CONNECT_ONE_SHOT)


func _on_battle_ended(victory: bool) -> void:
	"""Handle battle end"""
	if victory:
		battles_won += 1

		# Heal party between battles (rest bonus)
		for member in party:
			var heal_amount = int(member.max_hp * 0.25)
			member.heal(heal_amount)
			var mp_restore = int(member.max_mp * 0.25)
			member.restore_mp(mp_restore)
			member.current_ap = 0

		# Show menu after delay
		await get_tree().create_timer(1.5).timeout
		_show_menu()
	else:
		# Game over - for now just restart
		print("GAME OVER - Restarting...")
		await get_tree().create_timer(2.0).timeout
		_create_party()
		battles_won = 0
		_start_battle()


func _show_menu() -> void:
	"""Show the between-battle menu"""
	current_state = LoopState.MENU

	# Remove battle scene
	if current_scene:
		current_scene.queue_free()
		await current_scene.tree_exited

	# Create menu scene
	var menu_scene = MenuSceneRes.instantiate()
	add_child(menu_scene)
	current_scene = menu_scene

	# Setup menu with full party data
	menu_scene.setup(party, battles_won)

	# Connect signals
	menu_scene.continue_pressed.connect(_on_continue_pressed)


func _on_continue_pressed() -> void:
	"""Handle continue from menu"""
	_start_battle()


## Equipment Pool Management

func _init_equipment_pool() -> void:
	"""Initialize equipment pool with extra items"""
	equipment_pool = {
		"weapons": ["bronze_sword", "wooden_staff"],
		"armors": ["cloth_robe", "iron_armor"],
		"accessories": ["hp_amulet", "speed_boots"]
	}


func get_available_equipment(slot: String) -> Array:
	"""Get list of equipment available in pool for a slot type"""
	var pool_key = slot + "s"  # weapon -> weapons, armor -> armors
	if slot == "accessory":
		pool_key = "accessories"
	return equipment_pool.get(pool_key, [])


func equip_from_pool(combatant: Combatant, slot: String, item_id: String) -> bool:
	"""Equip item from pool to combatant, return old item to pool"""
	var pool_key = slot + "s"
	if slot == "accessory":
		pool_key = "accessories"

	# Check if item is in pool
	if item_id not in equipment_pool.get(pool_key, []):
		return false

	# Get current equipped item
	var old_item: String = ""
	match slot:
		"weapon":
			old_item = combatant.equipped_weapon
		"armor":
			old_item = combatant.equipped_armor
		"accessory":
			old_item = combatant.equipped_accessory

	# Remove new item from pool
	equipment_pool[pool_key].erase(item_id)

	# Add old item to pool if it exists
	if old_item and old_item != "":
		equipment_pool[pool_key].append(old_item)

	# Equip new item
	match slot:
		"weapon":
			EquipmentSystem.equip_weapon(combatant, item_id)
		"armor":
			EquipmentSystem.equip_armor(combatant, item_id)
		"accessory":
			EquipmentSystem.equip_accessory(combatant, item_id)

	return true


func unequip_to_pool(combatant: Combatant, slot: String) -> bool:
	"""Unequip item from combatant and return to pool"""
	var pool_key = slot + "s"
	if slot == "accessory":
		pool_key = "accessories"

	var item_id: String = ""
	match slot:
		"weapon":
			item_id = combatant.equipped_weapon
			combatant.equipped_weapon = ""
		"armor":
			item_id = combatant.equipped_armor
			combatant.equipped_armor = ""
		"accessory":
			item_id = combatant.equipped_accessory
			combatant.equipped_accessory = ""

	if item_id and item_id != "":
		equipment_pool[pool_key].append(item_id)
		combatant.recalculate_stats()
		return true

	return false
