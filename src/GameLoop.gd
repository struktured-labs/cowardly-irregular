extends Node

## GameLoop - Controls the exploration → battle → menu game loop
## Manages scene transitions and player persistence

const BattleSceneRes = preload("res://src/battle/BattleScene.tscn")
const MenuSceneRes = preload("res://src/ui/MenuScene.tscn")
const OverworldSceneRes = preload("res://src/exploration/OverworldScene.tscn")

enum LoopState {
	BATTLE,
	MENU,
	EXPLORATION
}

var current_state: LoopState = LoopState.EXPLORATION
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
var _autobattle_layer: CanvasLayer = null  # Separate layer to avoid camera zoom


## Exploration state
var _current_map_id: String = "overworld"
var _spawn_point: String = "default"
var _exploration_scene: Node = null
var _player_position: Vector2 = Vector2.ZERO  # Save position for battle return
var _current_cave_floor: int = 1  # Track current floor in multi-floor dungeons

## Overworld menu
var _overworld_menu: Control = null
var _overworld_menu_layer: CanvasLayer = null

func _ready() -> void:
	# Initialize equipment pool with extra items
	_init_equipment_pool()

	# Create persistent party
	_create_party()

	# Start with exploration (overworld)
	_start_exploration()

	# Log startup
	if DebugLogOverlay:
		DebugLogOverlay.log("[GAME] Started")


func _input(event: InputEvent) -> void:
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

	# Start button = Open autobattle editor for current deciding player
	# Only when editor is not already open (editor handles its own Start to close)
	if not _autobattle_editor or not is_instance_valid(_autobattle_editor):
		if event.is_action_pressed("ui_menu"):
			_toggle_autobattle_editor()
			get_viewport().set_input_as_handled()

	# X key or gamepad X/Y button = Open overworld menu (only in exploration mode)
	# Note: JOY_BUTTON_X=2 (Xbox X), JOY_BUTTON_Y=3 (Xbox Y) - support both for different controllers
	var x_pressed = false
	if event is InputEventKey and event.pressed and event.keycode == KEY_X:
		x_pressed = true
	elif event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_X, JOY_BUTTON_Y]:
		x_pressed = true
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		x_pressed = true

	if x_pressed:
		print("[MENU] X pressed, state=%s, menu=%s" % [LoopState.keys()[current_state], _overworld_menu != null])
		if current_state == LoopState.EXPLORATION and not _overworld_menu:
			_open_overworld_menu()
			get_viewport().set_input_as_handled()


func _toggle_autobattle_editor() -> void:
	"""Toggle the autobattle grid editor overlay"""
	if _autobattle_editor and is_instance_valid(_autobattle_editor):
		# Save before closing!
		if _autobattle_editor.has_method("save_and_close"):
			_autobattle_editor.save_and_close()
		else:
			_autobattle_editor.queue_free()
		_autobattle_editor = null
		if _autobattle_layer:
			_autobattle_layer.queue_free()
			_autobattle_layer = null
		# Show battle menu again if it was hidden
		_set_battle_menu_visible(true)
		# Resume exploration if we were in exploration mode
		if current_state == LoopState.EXPLORATION and _exploration_scene and _exploration_scene.has_method("resume"):
			_exploration_scene.resume()
		SoundManager.play_ui("autobattle_close")
		print("Autobattle editor closed (saved)")
		return

	# Pause exploration while editor is open (no encounters)
	if current_state == LoopState.EXPLORATION and _exploration_scene and _exploration_scene.has_method("pause"):
		_exploration_scene.pause()

	# Hide the battle menu while editor is open
	_set_battle_menu_visible(false)

	# During battle, open for currently selecting player
	var combatant: Combatant = null
	var char_id = "hero"
	var char_name = "Hero"

	if BattleManager and BattleManager.is_selecting() and BattleManager.current_combatant:
		var current = BattleManager.current_combatant
		if current in BattleManager.player_party:
			combatant = current
			char_id = current.combatant_name.to_lower().replace(" ", "_")
			char_name = current.combatant_name
	elif party.size() > 0:
		combatant = party[0]
		char_id = party[0].combatant_name.to_lower().replace(" ", "_")
		char_name = party[0].combatant_name

	# Create CanvasLayer to isolate from camera zoom
	_autobattle_layer = CanvasLayer.new()
	_autobattle_layer.layer = 50  # Above game, below BattleTransition
	add_child(_autobattle_layer)

	var AutobattleGridEditorClass = load("res://src/ui/autobattle/AutobattleGridEditor.gd")
	_autobattle_editor = AutobattleGridEditorClass.new()
	_autobattle_editor.set_anchors_preset(Control.PRESET_FULL_RECT)
	_autobattle_layer.add_child(_autobattle_editor)
	_autobattle_editor.setup(char_id, char_name, combatant, party)  # Pass party for R to cycle
	_autobattle_editor.closed.connect(_on_autobattle_editor_closed)
	SoundManager.play_ui("autobattle_open")
	print("Autobattle editor opened for %s (R to switch character, Start to save & exit)" % char_name)


func _set_battle_menu_visible(visible: bool) -> void:
	"""Show or hide the battle menu in the current scene"""
	# Try the proper method first
	if current_scene and current_scene.has_method("set_command_menu_visible"):
		current_scene.set_command_menu_visible(visible)
	# Fallback to direct property access
	elif current_scene and current_scene.has_method("get"):
		var menu = current_scene.get("active_win98_menu")
		if menu and is_instance_valid(menu):
			menu.visible = visible


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
	if new_state:
		SoundManager.play_ui("autobattle_on")
	else:
		SoundManager.play_ui("autobattle_off")
	print("[AUTOBATTLE] All party members: %s (F6/Select to toggle)" % status)


func _on_autobattle_editor_closed() -> void:
	"""Handle editor close"""
	if _autobattle_editor and is_instance_valid(_autobattle_editor):
		_autobattle_editor.queue_free()
		_autobattle_editor = null
	if _autobattle_layer and is_instance_valid(_autobattle_layer):
		_autobattle_layer.queue_free()
		_autobattle_layer = null
	# Show battle menu again
	_set_battle_menu_visible(true)
	# Resume exploration if we were in exploration mode
	if current_state == LoopState.EXPLORATION and _exploration_scene and _exploration_scene.has_method("resume"):
		_exploration_scene.resume()


func _open_overworld_menu() -> void:
	"""Open the overworld/pause menu"""
	if _overworld_menu and is_instance_valid(_overworld_menu):
		return  # Already open

	# Pause exploration
	if _exploration_scene and _exploration_scene.has_method("pause"):
		_exploration_scene.pause()

	# Create menu in CanvasLayer
	_overworld_menu_layer = CanvasLayer.new()
	_overworld_menu_layer.layer = 50
	add_child(_overworld_menu_layer)

	var OverworldMenuClass = load("res://src/ui/OverworldMenu.gd")
	_overworld_menu = OverworldMenuClass.new()
	_overworld_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overworld_menu_layer.add_child(_overworld_menu)
	_overworld_menu.setup(party)
	_overworld_menu.closed.connect(_on_overworld_menu_closed)
	_overworld_menu.menu_action.connect(_on_overworld_menu_action)
	SoundManager.play_ui("menu_open")
	print("Overworld menu opened")


func _on_overworld_menu_closed() -> void:
	"""Handle overworld menu close"""
	if _overworld_menu and is_instance_valid(_overworld_menu):
		_overworld_menu.queue_free()
		_overworld_menu = null
	if _overworld_menu_layer and is_instance_valid(_overworld_menu_layer):
		_overworld_menu_layer.queue_free()
		_overworld_menu_layer = null

	# Resume exploration
	if _exploration_scene and _exploration_scene.has_method("resume"):
		_exploration_scene.resume()


func _on_overworld_menu_action(action: String, target: Combatant) -> void:
	"""Handle menu action from overworld menu"""
	match action:
		"autobattle":
			# Close menu first, then open autobattle editor
			_on_overworld_menu_closed()
			if target:
				var char_id = target.combatant_name.to_lower().replace(" ", "_")
				_open_autobattle_for_character(char_id, target.combatant_name, target)


func _open_autobattle_for_character(char_id: String, char_name: String, combatant: Combatant) -> void:
	"""Open autobattle editor for a specific character"""
	if _autobattle_editor and is_instance_valid(_autobattle_editor):
		return  # Already open

	# Pause exploration
	if _exploration_scene and _exploration_scene.has_method("pause"):
		_exploration_scene.pause()

	_autobattle_layer = CanvasLayer.new()
	_autobattle_layer.layer = 50
	add_child(_autobattle_layer)

	var AutobattleGridEditorClass = load("res://src/ui/autobattle/AutobattleGridEditor.gd")
	_autobattle_editor = AutobattleGridEditorClass.new()
	_autobattle_editor.set_anchors_preset(Control.PRESET_FULL_RECT)
	_autobattle_layer.add_child(_autobattle_editor)
	_autobattle_editor.setup(char_id, char_name, combatant, party)
	_autobattle_editor.closed.connect(_on_autobattle_editor_closed)
	SoundManager.play_ui("autobattle_open")
	print("Autobattle editor opened for %s" % char_name)


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

	# Set flags and party BEFORE adding to tree (since _ready() uses these)
	battle_scene.managed_by_game_loop = true  # Disable BattleScene's internal restart
	battle_scene.set_party(party)  # MUST be before add_child so _ready() uses correct party
	if is_miniboss_battle:
		battle_scene.force_miniboss = true
		print("[MINIBOSS] Battle %d - A miniboss approaches!" % (battles_won + 1))

	add_child(battle_scene)
	current_scene = battle_scene

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

		# Return to exploration after delay
		await get_tree().create_timer(1.5).timeout
		_return_to_exploration()
	else:
		# Game over - for now restart exploration
		print("GAME OVER - Restarting...")
		await get_tree().create_timer(2.0).timeout
		_create_party()
		battles_won = 0
		_current_map_id = "overworld"
		_spawn_point = "default"
		_start_exploration()


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
	"""Handle continue from menu - return to exploration"""
	_return_to_exploration()


## Exploration Management

func _start_exploration() -> void:
	"""Start exploration mode (overworld or interior)"""
	current_state = LoopState.EXPLORATION

	# Ensure normal speed in exploration (battle speed is separate)
	Engine.time_scale = 1.0

	# Remove old scene
	if current_scene:
		current_scene.queue_free()
		await current_scene.tree_exited

	# Create exploration scene based on current map
	var exploration_scene: Node = null

	match _current_map_id:
		"overworld":
			exploration_scene = OverworldSceneRes.instantiate()
		"harmonia_village":
			exploration_scene = _create_village_scene()
		"whispering_cave":
			exploration_scene = _create_cave_scene()
		"tavern_interior":
			exploration_scene = _create_tavern_scene()
		_:
			exploration_scene = OverworldSceneRes.instantiate()

	add_child(exploration_scene)
	current_scene = exploration_scene
	_exploration_scene = exploration_scene

	# Spawn player at correct position
	if exploration_scene.has_method("spawn_player_at"):
		exploration_scene.spawn_player_at(_spawn_point)

	# Set player job based on party leader
	if party.size() > 0 and exploration_scene.has_method("set_player_job"):
		var leader_job = "fighter"
		if party[0].job and party[0].job is Dictionary:
			leader_job = party[0].job.get("id", "fighter")
		elif party[0].job is String:
			leader_job = party[0].job
		exploration_scene.set_player_job(leader_job)

	# Connect signals
	if exploration_scene.has_signal("battle_triggered"):
		exploration_scene.battle_triggered.connect(_on_exploration_battle_triggered)
	if exploration_scene.has_signal("area_transition"):
		exploration_scene.area_transition.connect(_on_area_transition)


func _return_to_exploration() -> void:
	"""Return to exploration after battle"""
	# Reset engine time scale to normal (battle speed shouldn't affect overworld)
	Engine.time_scale = 1.0

	# Keep same map, restore player to saved position
	await _start_exploration()

	# Restore player position after scene is fully set up
	if _player_position != Vector2.ZERO and _exploration_scene:
		var player = _exploration_scene.get("player")
		if player:
			player.position = _player_position
			print("[POSITION] Restored player to: %s" % _player_position)
		else:
			push_warning("[POSITION] Could not get player from scene")

	# Clear saved position after restoring
	_player_position = Vector2.ZERO


func _on_exploration_battle_triggered(enemies: Array) -> void:
	"""Handle battle triggered from exploration"""
	# Disable player input during battle transition
	if _exploration_scene and _exploration_scene.has_method("pause"):
		_exploration_scene.pause()

	# Save player position and cave floor before battle
	if _exploration_scene:
		var player = _exploration_scene.get("player")
		if player:
			_player_position = player.position
			print("[POSITION] Saved player at: %s" % _player_position)
			# Explicitly disable movement
			if player.has_method("set_can_move"):
				player.set_can_move(false)

		# Save current floor if in cave
		if _current_map_id == "whispering_cave" and "current_floor" in _exploration_scene:
			_current_cave_floor = _exploration_scene.current_floor
			print("[CAVE] Saved floor: %d" % _current_cave_floor)

	# Extract enemy types for transition visual
	var enemy_types: Array = []
	for enemy in enemies:
		if enemy is Dictionary:
			var enemy_type = enemy.get("name", enemy.get("type", enemy.get("id", "unknown")))
			enemy_types.append(enemy_type)
		elif enemy is String:
			# Boss/specific enemy is passed as string ID
			enemy_types.append(enemy)

	print("[GAMELOOP] Battle triggered with enemies: %s" % [enemies])

	# Start battle loading in background (async)
	ResourceLoader.load_threaded_request("res://src/battle/BattleScene.tscn")

	# Play transition animation (loads in parallel)
	if BattleTransition:
		print("[GAMELOOP] Starting battle transition")
		await BattleTransition.play_battle_transition(enemy_types)
		print("[GAMELOOP] Battle transition complete")

	# Wait for battle scene to finish loading
	print("[GAMELOOP] Waiting for battle scene to load")
	while ResourceLoader.load_threaded_get_status("res://src/battle/BattleScene.tscn") == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	print("[GAMELOOP] Battle scene loaded")

	# Start battle with pre-loaded scene, passing specific enemies if provided
	await _start_battle_async(enemies)
	print("[GAMELOOP] Battle scene started")

	# Small delay to ensure battle scene is fully initialized
	# (battle_started may have already fired during _ready())
	await get_tree().create_timer(0.1).timeout

	# Fade out transition to reveal battle
	if BattleTransition:
		print("[GAMELOOP] Starting fade out")
		await BattleTransition.fade_out()
		print("[GAMELOOP] Fade out complete - battle should be visible")


func _start_battle_async(specific_enemies: Array = []) -> void:
	"""Start battle using async-loaded scene"""
	current_state = LoopState.BATTLE

	# Remove old scene
	if current_scene:
		current_scene.queue_free()
		await current_scene.tree_exited

	# Check if specific enemies were provided (e.g., boss battles)
	var has_forced_enemies = specific_enemies.size() > 0 and specific_enemies[0] is String

	# Check if this is a miniboss battle (every 3rd battle), but not if forced enemies
	var is_miniboss_battle = not has_forced_enemies and (battles_won + 1) % 3 == 0 and battles_won > 0

	# Get pre-loaded battle scene
	var loaded_res = ResourceLoader.load_threaded_get("res://src/battle/BattleScene.tscn")
	var battle_scene = loaded_res.instantiate()

	# Set flags and party BEFORE adding to tree (since _ready() uses these)
	battle_scene.managed_by_game_loop = true
	battle_scene.set_party(party)

	# Handle forced enemies (boss battles)
	if has_forced_enemies:
		battle_scene.forced_enemies = specific_enemies
		print("[BOSS] Forcing specific enemies: %s" % [specific_enemies])
	elif is_miniboss_battle:
		battle_scene.force_miniboss = true
		print("[MINIBOSS] Battle %d - A miniboss approaches!" % (battles_won + 1))

	add_child(battle_scene)
	current_scene = battle_scene

	# Wait for battle scene to be fully ready before proceeding
	await get_tree().process_frame
	print("[GAMELOOP] BattleScene added - visible: %s, in tree: %s, parent: %s" % [battle_scene.visible, battle_scene.is_inside_tree(), battle_scene.get_parent().name])

	# Connect to battle end
	BattleManager.battle_ended.connect(_on_battle_ended, CONNECT_ONE_SHOT)


func _on_area_transition(target_map: String, spawn_point: String) -> void:
	"""Handle transitioning between areas"""
	_current_map_id = target_map
	_spawn_point = spawn_point
	_player_position = Vector2.ZERO  # Clear saved position when changing maps
	_start_exploration()


func _create_village_scene() -> Node:
	"""Create Harmonia Village scene (placeholder until scene file exists)"""
	# For now, just return overworld - village scene will be created later
	var VillageSceneRes = load("res://src/maps/villages/HarmoniaVillage.tscn")
	if VillageSceneRes:
		return VillageSceneRes.instantiate()
	# Fallback to overworld if scene doesn't exist
	push_warning("HarmoniaVillage.tscn not found, using overworld")
	return OverworldSceneRes.instantiate()


func _create_cave_scene() -> Node:
	"""Create Whispering Cave scene and restore floor state"""
	var CaveSceneRes = load("res://src/maps/dungeons/WhisperingCave.tscn")
	if CaveSceneRes:
		var cave_scene = CaveSceneRes.instantiate()
		# Restore the floor we were on before battle
		if _current_cave_floor > 1 and "current_floor" in cave_scene:
			cave_scene.current_floor = _current_cave_floor
			print("[CAVE] Restoring to floor %d" % _current_cave_floor)
		return cave_scene
	# Fallback to overworld if scene doesn't exist
	push_warning("WhisperingCave.tscn not found, using overworld")
	return OverworldSceneRes.instantiate()


func _create_tavern_scene() -> Node:
	"""Create The Dancing Tonberry tavern interior scene"""
	var TavernScript = load("res://src/maps/interiors/TavernInterior.gd")
	if TavernScript:
		var tavern_scene = TavernScript.new()
		return tavern_scene
	# Fallback to village if script doesn't exist
	push_warning("TavernInterior.gd not found, returning to village")
	_current_map_id = "harmonia_village"
	_spawn_point = "bar_exit"
	return _create_village_scene()


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
