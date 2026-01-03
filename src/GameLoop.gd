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


func _ready() -> void:
	# Create persistent party
	_create_party()

	# Start with first battle
	_start_battle()


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

	# Create battle scene
	var battle_scene = BattleSceneRes.instantiate()
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

	# Setup menu with party data (show first member for now)
	menu_scene.setup(party[0] if party.size() > 0 else null, battles_won)

	# Connect signals
	menu_scene.continue_pressed.connect(_on_continue_pressed)


func _on_continue_pressed() -> void:
	"""Handle continue from menu"""
	_start_battle()
