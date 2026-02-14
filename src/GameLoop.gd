extends Node

## GameLoop - Controls the exploration → battle → menu game loop
## Manages scene transitions and player persistence

const BattleSceneRes = preload("res://src/battle/BattleScene.tscn")
const MenuSceneRes = preload("res://src/ui/MenuScene.tscn")
const OverworldSceneRes = preload("res://src/exploration/OverworldScene.tscn")
const CharacterCreationScreenClass = preload("res://src/ui/CharacterCreationScreen.gd")
const CustomizationScript = preload("res://src/character/CharacterCustomization.gd")
const TitleScreenClass = preload("res://src/ui/TitleScreen.gd")

enum LoopState {
	TITLE,
	BATTLE,
	MENU,
	EXPLORATION,
	AUTOGRIND
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
var _current_terrain: String = "plains"  # Current terrain type for battle backgrounds

## Overworld menu
var _overworld_menu: Control = null
var _overworld_menu_layer: CanvasLayer = null

## Autogrind
var _autogrind_controller: Node = null
var _autogrind_ui: Control = null
var _autogrind_ui_layer: CanvasLayer = null
var _is_autogrinding: bool = false

## Character creation
var _character_creation_screen: Control = null
var _party_customizations: Array = []  # Store CharacterCustomization data
var _first_launch: bool = true  # True if no save exists

## Title screen
var _title_screen: Control = null
var _title_layer: CanvasLayer = null

func _ready() -> void:
	# Initialize equipment pool with extra items
	_init_equipment_pool()

	# Check for existing save to determine if this is first launch
	_first_launch = not _save_exists()

	# Always show title screen first
	_show_title_screen()

	# Log startup
	if DebugLogOverlay:
		DebugLogOverlay.log("[GAME] Started")


func _input(event: InputEvent) -> void:
	# Block input handling during title screen or character creation
	if current_state == LoopState.TITLE or _character_creation_screen:
		return

	# During autogrind, block editor/menu but allow B to stop
	if current_state == LoopState.AUTOGRIND:
		if _autogrind_ui and is_instance_valid(_autogrind_ui):
			return  # UI handles its own input
		if event.is_action_pressed("ui_cancel"):
			_stop_autogrind("Manual stop")
			get_viewport().set_input_as_handled()
		return

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
	_overworld_menu.quit_to_title.connect(_on_quit_to_title)
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


func _on_quit_to_title() -> void:
	"""Handle quit to title from overworld menu settings"""
	print("[GAME] Returning to title screen")

	# Clean up overworld menu
	if _overworld_menu and is_instance_valid(_overworld_menu):
		_overworld_menu.queue_free()
		_overworld_menu = null
	if _overworld_menu_layer and is_instance_valid(_overworld_menu_layer):
		_overworld_menu_layer.queue_free()
		_overworld_menu_layer = null

	# Clean up exploration scene
	if _exploration_scene and is_instance_valid(_exploration_scene):
		_exploration_scene.queue_free()
		_exploration_scene = null

	# Clear party
	party.clear()

	# Show title screen
	_show_title_screen()


func _on_overworld_menu_action(action: String, target: Combatant) -> void:
	"""Handle menu action from overworld menu"""
	match action:
		"autobattle":
			# Close menu first, then open autobattle editor
			_on_overworld_menu_closed()
			if target:
				var char_id = target.combatant_name.to_lower().replace(" ", "_")
				_open_autobattle_for_character(char_id, target.combatant_name, target)
		"autogrind":
			# Close menu first, then open autogrind config UI
			_on_overworld_menu_closed()
			_open_autogrind_ui()


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


## Character Creation

func _save_exists() -> bool:
	"""Check if a save file exists (new or legacy format)"""
	# Check for new customization save
	if FileAccess.file_exists("user://save_data.json"):
		return true
	# Check for legacy save format
	if FileAccess.file_exists("user://saves/save_00.json"):
		return true
	return false


## Title Screen

func _show_title_screen() -> void:
	"""Show the title screen"""
	current_state = LoopState.TITLE

	# Create title screen in its own layer
	_title_layer = CanvasLayer.new()
	_title_layer.layer = 100
	add_child(_title_layer)

	_title_screen = TitleScreenClass.new()
	_title_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_layer.add_child(_title_screen)

	# Connect signals
	_title_screen.new_game_selected.connect(_on_title_new_game)
	_title_screen.continue_selected.connect(_on_title_continue)
	_title_screen.settings_selected.connect(_on_title_settings)

	print("[GAME] Showing title screen")


func _close_title_screen() -> void:
	"""Close the title screen"""
	if _title_screen and is_instance_valid(_title_screen):
		_title_screen.queue_free()
		_title_screen = null
	if _title_layer and is_instance_valid(_title_layer):
		_title_layer.queue_free()
		_title_layer = null


func _on_title_new_game() -> void:
	"""Handle new game selected from title screen"""
	print("[GAME] New Game selected")
	_close_title_screen()
	# Show character creation for new game
	_show_character_creation()


func _on_title_continue() -> void:
	"""Handle continue selected from title screen"""
	print("[GAME] Continue selected")
	_close_title_screen()
	# Load saved party and start exploration
	_create_party()
	_start_exploration()


func _on_title_settings() -> void:
	"""Handle settings selected from title screen"""
	print("[GAME] Settings selected from title")
	# Create settings menu overlay
	var SettingsMenuClass = load("res://src/ui/SettingsMenu.gd")
	if SettingsMenuClass:
		var settings_layer = CanvasLayer.new()
		settings_layer.layer = 110  # Above title screen
		add_child(settings_layer)

		var settings_menu = SettingsMenuClass.new()
		settings_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
		settings_layer.add_child(settings_menu)

		# Connect close signal
		settings_menu.closed.connect(func():
			settings_layer.queue_free()
			# Rebuild title menu in case settings changed (e.g., save deleted)
			if _title_screen and is_instance_valid(_title_screen):
				if _title_screen.has_method("_build_menu"):
					_title_screen._build_menu()
		)


func _show_character_creation() -> void:
	"""Show the character creation screen"""
	var layer = CanvasLayer.new()
	layer.layer = 100
	add_child(layer)

	_character_creation_screen = CharacterCreationScreenClass.new()
	_character_creation_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_character_creation_screen)

	_character_creation_screen.creation_complete.connect(_on_character_creation_complete.bind(layer))
	_character_creation_screen.creation_skipped.connect(_on_character_creation_skipped.bind(layer))

	print("[GAME] Showing character creation screen")


func _on_character_creation_complete(customizations: Array, layer: CanvasLayer) -> void:
	"""Handle character creation completion"""
	_party_customizations = customizations
	print("[GAME] Character creation complete with %d characters" % customizations.size())

	# Create party from customizations
	_create_party_from_customizations(customizations)

	# Clean up creation screen
	if layer:
		layer.queue_free()
	_character_creation_screen = null

	# Save customizations
	_save_customizations(customizations)

	# Start exploration
	_start_exploration()


func _on_character_creation_skipped(layer: CanvasLayer) -> void:
	"""Handle character creation skip - use defaults"""
	print("[GAME] Character creation skipped, using defaults")

	# Clean up creation screen
	if layer:
		layer.queue_free()
	_character_creation_screen = null

	# Create default party
	_create_party()

	# Start exploration
	_start_exploration()


func _create_party_from_customizations(customizations: Array) -> void:
	"""Create party members based on customizations"""
	party.clear()

	# Base stats for party members
	var base_stats_list = [
		{"max_hp": 150, "max_mp": 50, "attack": 25, "defense": 15, "magic": 12, "speed": 12},
		{"max_hp": 100, "max_mp": 120, "attack": 10, "defense": 12, "magic": 28, "speed": 14},
		{"max_hp": 90, "max_mp": 40, "attack": 18, "defense": 10, "magic": 8, "speed": 22},
		{"max_hp": 80, "max_mp": 150, "attack": 8, "defense": 8, "magic": 35, "speed": 12}
	]

	for i in range(min(customizations.size(), 4)):
		var custom = customizations[i]
		var base_stats = base_stats_list[i] if i < base_stats_list.size() else base_stats_list[0]

		var member = Combatant.new()
		member.initialize({
			"name": custom.name,
			"max_hp": base_stats["max_hp"],
			"max_mp": base_stats["max_mp"],
			"attack": base_stats["attack"],
			"defense": base_stats["defense"],
			"magic": base_stats["magic"],
			"speed": base_stats["speed"]
		})
		add_child(member)

		# Store customization reference for portraits
		member.customization = custom

		# Apply personality stat bonus
		custom.apply_stat_bonus(member)

		# Assign first job
		if custom.starting_jobs.size() > 0:
			JobSystem.assign_job(member, custom.starting_jobs[0])

		# Assign secondary job
		if custom.starting_jobs.size() > 1:
			JobSystem.assign_secondary_job(member, custom.starting_jobs[1])

		# Add starting items from personality
		var starting_items = custom.get_starting_items()
		for item_id in starting_items:
			member.add_item(item_id, starting_items[item_id])

		# Add phoenix down for all
		member.add_item("phoenix_down", 1)

		party.append(member)
		print("[PARTY] Created %s (%s) - %s personality" % [
			custom.name,
			custom.starting_jobs[0] if custom.starting_jobs.size() > 0 else "none",
			CustomizationScript.get_personality_name(custom.personality)
		])


func _save_customizations(customizations: Array) -> void:
	"""Save character customizations to file"""
	var data = []
	for custom in customizations:
		data.append(custom.to_dict())

	var file = FileAccess.open("user://save_data.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"party_customizations": data}))
		file.close()
		print("[SAVE] Saved party customizations")


func _load_customizations() -> Array:
	"""Load character customizations from file"""
	if not FileAccess.file_exists("user://save_data.json"):
		return []

	var file = FileAccess.open("user://save_data.json", FileAccess.READ)
	if not file:
		return []

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_string) != OK:
		return []

	var data = json.data
	if not data.has("party_customizations"):
		return []

	var customizations = []
	for custom_data in data["party_customizations"]:
		customizations.append(CustomizationScript.from_dict_with_script(custom_data, CustomizationScript))

	print("[LOAD] Loaded %d character customizations" % customizations.size())
	return customizations


func _create_party() -> void:
	"""Create the persistent party"""
	party.clear()

	# Get default customizations
	var default_customs = CustomizationScript.create_default_party_with_script(CustomizationScript)

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
	hero.customization = default_customs[0] if default_customs.size() > 0 else null
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
	mira.customization = default_customs[1] if default_customs.size() > 1 else null
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
	zack.customization = default_customs[2] if default_customs.size() > 2 else null
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
	vex.customization = default_customs[3] if default_customs.size() > 3 else null
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
	if current_scene and is_instance_valid(current_scene):
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

		# Wait for player to confirm before leaving victory screen
		await _wait_for_confirm()
		_return_to_exploration()
	else:
		# Game over - wait for confirm then restart
		await _wait_for_confirm()
		_create_party()
		battles_won = 0
		_current_map_id = "overworld"
		_spawn_point = "default"
		_start_exploration()


func _wait_for_confirm() -> void:
	"""Wait for the player to press confirm (A/Z/Enter) before continuing"""
	# Small delay so the press that ended the battle doesn't immediately confirm
	await get_tree().create_timer(0.5).timeout
	while true:
		await get_tree().process_frame
		if Input.is_action_just_pressed("ui_accept"):
			break


func _show_menu() -> void:
	"""Show the between-battle menu"""
	current_state = LoopState.MENU

	# Remove battle scene
	if current_scene and is_instance_valid(current_scene):
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
	if current_scene and is_instance_valid(current_scene):
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
		"frosthold_village":
			exploration_scene = _create_script_scene("res://src/maps/villages/FrostholdVillage.gd")
		"eldertree_village":
			exploration_scene = _create_script_scene("res://src/maps/villages/EldertreeVillage.gd")
		"grimhollow_village":
			exploration_scene = _create_script_scene("res://src/maps/villages/GrimhollowVillage.gd")
		"sandrift_village":
			exploration_scene = _create_script_scene("res://src/maps/villages/SandriftVillage.gd")
		"ironhaven_village":
			exploration_scene = _create_script_scene("res://src/maps/villages/IronhavenVillage.gd")
		"ice_dragon_cave":
			exploration_scene = _create_dragon_cave("res://src/maps/dungeons/IceDragonCave.gd")
		"shadow_dragon_cave":
			exploration_scene = _create_dragon_cave("res://src/maps/dungeons/ShadowDragonCave.gd")
		"lightning_dragon_cave":
			exploration_scene = _create_dragon_cave("res://src/maps/dungeons/LightningDragonCave.gd")
		"fire_dragon_cave":
			exploration_scene = _create_dragon_cave("res://src/maps/dungeons/FireDragonCave.gd")
		"steampunk_overworld":
			exploration_scene = _create_script_scene("res://src/exploration/SteampunkOverworld.gd")
		_:
			exploration_scene = OverworldSceneRes.instantiate()

	add_child(exploration_scene)
	current_scene = exploration_scene
	_exploration_scene = exploration_scene

	# Spawn player at correct position
	if exploration_scene.has_method("spawn_player_at"):
		exploration_scene.spawn_player_at(_spawn_point)

	# Set player appearance based on party leader
	if party.size() > 0:
		var leader = party[0]
		var leader_job = "fighter"
		if leader.job and leader.job is Dictionary:
			leader_job = leader.job.get("id", "fighter")
		elif leader.job is String:
			leader_job = leader.job

		# Try the new appearance method first, fall back to job-only
		if exploration_scene.has_method("set_player_appearance"):
			exploration_scene.set_player_appearance(leader)
		elif exploration_scene.has_method("set_player_job"):
			exploration_scene.set_player_job(leader_job)

	# Connect signals
	if exploration_scene.has_signal("battle_triggered"):
		exploration_scene.battle_triggered.connect(_on_exploration_battle_triggered)
	if exploration_scene.has_signal("area_transition"):
		exploration_scene.area_transition.connect(_on_area_transition)

	# Pre-warm common area sprites in background (deferred to not block scene setup)
	call_deferred("_prewarm_area_sprites")


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


func _prewarm_battle_sprites(enemies: Array) -> void:
	"""Pre-warm BattleAnimator sprite cache during battle transition.
	This generates and caches sprites while the transition animation plays,
	so they are ready instantly when BattleScene._create_battle_sprites() runs."""
	var monster_ids: Array = []
	for enemy in enemies:
		if enemy is Dictionary:
			var eid = enemy.get("id", enemy.get("type", ""))
			if eid != "" and eid not in monster_ids:
				monster_ids.append(eid)

	# Build party job data for pre-warming hero sprites
	var party_jobs: Array = []
	for member in party:
		if is_instance_valid(member):
			var job_id = "fighter"
			if member.job:
				job_id = member.job.get("id", "fighter")
			var weapon_id = member.equipped_weapon if member.equipped_weapon else ""
			party_jobs.append({"job_id": job_id, "weapon_id": weapon_id})

	if monster_ids.size() > 0 or party_jobs.size() > 0:
		print("[PREWARM] Pre-warming sprite cache: %d monsters, %d party members" % [monster_ids.size(), party_jobs.size()])
		BattleAnimator.prewarm_cache(monster_ids, party_jobs)
		print("[PREWARM] Sprite cache pre-warm complete")


func _prewarm_area_sprites() -> void:
	"""Pre-warm common area enemy sprites on scene load for faster first battle."""
	var common_enemies: Array = []
	match _current_map_id:
		"overworld":
			common_enemies = ["slime", "bat", "goblin"]
		"whispering_cave":
			common_enemies = ["bat", "goblin", "skeleton"]
		"ice_dragon_cave":
			common_enemies = ["bat", "skeleton", "ice_dragon"]
		"shadow_dragon_cave":
			common_enemies = ["specter", "skeleton", "shadow_dragon"]
		"lightning_dragon_cave":
			common_enemies = ["goblin", "bat", "lightning_dragon"]
		"fire_dragon_cave":
			common_enemies = ["imp", "skeleton", "fire_dragon"]
		"steampunk_overworld":
			common_enemies = ["slime", "imp", "skeleton"]
		_:
			if "cave" in _current_map_id:
				common_enemies = ["bat", "skeleton", "imp"]
			elif "village" in _current_map_id:
				common_enemies = []  # Villages are safe zones
			else:
				common_enemies = ["slime", "bat"]
	if common_enemies.size() > 0:
		var enemy_data: Array = []
		for eid in common_enemies:
			enemy_data.append({"id": eid, "type": eid})
		_prewarm_battle_sprites(enemy_data)


func _on_exploration_battle_triggered(enemies: Array, terrain: String = "") -> void:
	"""Handle battle triggered from exploration"""
	# Disable player input during battle transition
	if _exploration_scene and _exploration_scene.has_method("pause"):
		_exploration_scene.pause()

	# Save terrain for battle background
	if terrain != "":
		_current_terrain = terrain
	else:
		# Infer terrain from map if not provided
		_current_terrain = _get_terrain_for_map(_current_map_id)
	print("[TERRAIN] Battle terrain: %s" % _current_terrain)

	# Save player position and cave floor before battle
	if _exploration_scene:
		var player = _exploration_scene.get("player")
		if player:
			_player_position = player.position
			print("[POSITION] Saved player at: %s" % _player_position)
			# Explicitly disable movement
			if player.has_method("set_can_move"):
				player.set_can_move(false)

		# Save current floor if in cave (any multi-floor dungeon)
		if "current_floor" in _exploration_scene:
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

	# Pre-warm sprite cache during transition (deferred so it runs during animation)
	call_deferred("_prewarm_battle_sprites", enemies)

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

	# Fade out transition to reveal battle
	if BattleTransition:
		print("[GAMELOOP] Starting fade out")
		await BattleTransition.fade_out()
		print("[GAMELOOP] Fade out complete - battle should be visible")


func _start_battle_async(specific_enemies: Array = []) -> void:
	"""Start battle using async-loaded scene"""
	current_state = LoopState.BATTLE

	# Remove old scene
	if current_scene and is_instance_valid(current_scene):
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
		# Boss battles use boss terrain
		battle_scene.set_terrain("boss")
	elif is_miniboss_battle:
		battle_scene.force_miniboss = true
		print("[MINIBOSS] Battle %d - A miniboss approaches!" % (battles_won + 1))
		battle_scene.set_terrain(_current_terrain)
	else:
		# Regular battle - use current terrain
		battle_scene.set_terrain(_current_terrain)

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
	_current_terrain = _get_terrain_for_map(target_map)  # Update terrain for new area
	_start_exploration()


func _get_terrain_for_map(map_id: String) -> String:
	"""Get the terrain type for a given map ID"""
	match map_id:
		"overworld":
			return "plains"
		"whispering_cave":
			return "cave"
		"harmonia_village", "tavern_interior":
			return "village"
		"frosthold_village":
			return "ice"
		"eldertree_village":
			return "forest"
		"grimhollow_village":
			return "swamp"
		"sandrift_village":
			return "desert"
		"ironhaven_village":
			return "volcanic"
		"ice_dragon_cave":
			return "ice_cave"
		"shadow_dragon_cave":
			return "dark_cave"
		"lightning_dragon_cave":
			return "storm_cave"
		"fire_dragon_cave":
			return "lava_cave"
		"steampunk_overworld":
			return "urban"
		_:
			if "cave" in map_id or "dungeon" in map_id:
				return "cave"
			elif "village" in map_id or "town" in map_id:
				return "village"
			elif "forest" in map_id:
				return "forest"
			return "plains"


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


func _create_script_scene(script_path: String) -> Node:
	"""Create a scene from a GDScript that self-constructs in _ready()"""
	var ScriptRes = load(script_path)
	if ScriptRes:
		return ScriptRes.new()
	push_warning("%s not found, falling back to overworld" % script_path)
	return OverworldSceneRes.instantiate()


func _create_dragon_cave(script_path: String) -> Node:
	"""Create a dragon cave scene and restore floor state"""
	var ScriptRes = load(script_path)
	if ScriptRes:
		var cave_scene = ScriptRes.new()
		# Restore the floor we were on before battle
		if _current_cave_floor > 1 and "current_floor" in cave_scene:
			cave_scene.current_floor = _current_cave_floor
			print("[CAVE] Restoring to floor %d" % _current_cave_floor)
		return cave_scene
	push_warning("%s not found, falling back to overworld" % script_path)
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


## Autogrind System

func _open_autogrind_ui() -> void:
	"""Open the autogrind configuration UI overlay"""
	if _autogrind_ui and is_instance_valid(_autogrind_ui):
		return  # Already open

	# Pause exploration
	if _exploration_scene and _exploration_scene.has_method("pause"):
		_exploration_scene.pause()

	# Create UI overlay in CanvasLayer
	_autogrind_ui_layer = CanvasLayer.new()
	_autogrind_ui_layer.layer = 50
	add_child(_autogrind_ui_layer)

	var AutogrindUIClass = load("res://src/ui/autogrind/AutogrindUI.gd")
	_autogrind_ui = AutogrindUIClass.new()
	_autogrind_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_autogrind_ui_layer.add_child(_autogrind_ui)

	# Get region name from current map
	var region_name = _current_map_id.replace("_", " ").capitalize()
	_autogrind_ui.setup(party, region_name)

	# Connect signals
	_autogrind_ui.closed.connect(_on_autogrind_ui_closed)
	_autogrind_ui.grind_requested.connect(_start_autogrind)
	_autogrind_ui.grind_stop_requested.connect(_on_autogrind_stop_requested)

	SoundManager.play_ui("menu_open")
	print("[AUTOGRIND] Config UI opened")


func _on_autogrind_ui_closed() -> void:
	"""Handle autogrind UI close"""
	if _autogrind_ui and is_instance_valid(_autogrind_ui):
		_autogrind_ui.queue_free()
		_autogrind_ui = null
	if _autogrind_ui_layer and is_instance_valid(_autogrind_ui_layer):
		_autogrind_ui_layer.queue_free()
		_autogrind_ui_layer = null

	# If not grinding, resume exploration
	if not _is_autogrinding:
		if _exploration_scene and _exploration_scene.has_method("resume"):
			_exploration_scene.resume()


func _start_autogrind(config: Dictionary) -> void:
	"""Start the autogrind session"""
	current_state = LoopState.AUTOGRIND
	_is_autogrinding = true

	# Create controller
	var AutogrindControllerClass = load("res://src/autogrind/AutogrindController.gd")
	_autogrind_controller = AutogrindControllerClass.new()
	add_child(_autogrind_controller)

	# Connect controller signals
	_autogrind_controller.grind_battle_requested.connect(_on_grind_battle_requested)
	_autogrind_controller.grind_complete.connect(_on_grind_complete)

	# Start grinding
	_autogrind_controller.start_grind(party, config, _current_terrain)

	print("[AUTOGRIND] Session started")


func _on_autogrind_stop_requested() -> void:
	"""Handle stop request from UI"""
	_stop_autogrind("Manual stop")


func _stop_autogrind(reason: String) -> void:
	"""Stop the autogrind session"""
	if not _is_autogrinding:
		return

	_is_autogrinding = false

	# Stop controller
	if _autogrind_controller and is_instance_valid(_autogrind_controller):
		_autogrind_controller.stop_grind(reason)
		_autogrind_controller.queue_free()
		_autogrind_controller = null

	# Update UI state
	if _autogrind_ui and is_instance_valid(_autogrind_ui):
		_autogrind_ui.set_grinding(false)

	# Reset engine speed
	Engine.time_scale = 1.0

	print("[AUTOGRIND] Session stopped: %s" % reason)

	# Return to exploration if UI is also closed
	if not _autogrind_ui or not is_instance_valid(_autogrind_ui):
		_return_to_exploration()
	else:
		current_state = LoopState.EXPLORATION


func _on_grind_battle_requested(enemies: Array, terrain: String) -> void:
	"""Handle battle request from autogrind controller"""
	# Save player position before battle
	if _exploration_scene:
		var player = _exploration_scene.get("player")
		if player:
			_player_position = player.position

	# Set terrain
	_current_terrain = terrain

	# Start battle without transition animation (fast chain)
	await _start_autogrind_battle(enemies)


func _start_autogrind_battle(enemy_data: Array) -> void:
	"""Start a battle scene with pre-configured autogrind enemies"""
	# Remove old scene
	if current_scene and is_instance_valid(current_scene):
		current_scene.queue_free()
		await current_scene.tree_exited

	# Create battle scene
	var loaded_res = load("res://src/battle/BattleScene.tscn")
	if not loaded_res:
		push_error("GameLoop: Failed to load BattleScene.tscn")
		return
	var battle_scene = loaded_res.instantiate()

	# Configure for autogrind
	battle_scene.managed_by_game_loop = true
	battle_scene.set_party(party)
	battle_scene.autogrind_enemy_data = enemy_data
	battle_scene.set_terrain(_current_terrain)

	add_child(battle_scene)
	current_scene = battle_scene

	# Wait for scene to be ready
	await get_tree().process_frame

	# Connect to battle end with autogrind handler
	BattleManager.battle_ended.connect(_on_autogrind_battle_ended, CONNECT_ONE_SHOT)


func _on_autogrind_battle_ended(victory: bool) -> void:
	"""Handle battle end during autogrind"""
	if not _is_autogrinding:
		# Autogrind was stopped during battle
		_on_battle_ended(victory)
		return

	# Heal party between battles
	var exp_gained = 0
	var items_gained = {}

	if victory:
		# Calculate base EXP from defeated enemies (estimate from enemy stats)
		for enemy in BattleManager.enemy_party:
			if enemy is Combatant:
				exp_gained += int(enemy.max_hp * 0.5 + enemy.attack * 2)

		# Heal party between battles (rest bonus)
		for member in party:
			var heal_amount = int(member.max_hp * 0.25)
			member.heal(heal_amount)
			var mp_restore = int(member.max_mp * 0.25)
			member.restore_mp(mp_restore)
			member.current_ap = 0

	# Forward to controller
	if _autogrind_controller and is_instance_valid(_autogrind_controller):
		_autogrind_controller.on_battle_ended(victory, exp_gained, items_gained)

		# Update UI with latest stats
		if _autogrind_ui and is_instance_valid(_autogrind_ui):
			_autogrind_ui.update_stats(_autogrind_controller.get_grind_stats())
			_autogrind_ui.update_party_status()


func _on_grind_complete(reason: String) -> void:
	"""Handle autogrind session completion"""
	_is_autogrinding = false
	current_state = LoopState.EXPLORATION

	# Clean up controller
	if _autogrind_controller and is_instance_valid(_autogrind_controller):
		_autogrind_controller.queue_free()
		_autogrind_controller = null

	# Reset engine speed
	Engine.time_scale = 1.0

	# Update UI
	if _autogrind_ui and is_instance_valid(_autogrind_ui):
		_autogrind_ui.set_grinding(false)
	else:
		# If UI is closed, return to exploration
		_return_to_exploration()

	print("[AUTOGRIND] Grind complete: %s" % reason)
