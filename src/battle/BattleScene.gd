extends Control

## BattleScene - FF-style battle UI with sprites
## Enemies on left, party on right, classic JRPG layout

# Preload class dependencies to ensure they're registered before use
const BattleAnimatorClass = preload("res://src/battle/BattleAnimator.gd")
const RetroFontClass = preload("res://src/ui/RetroFont.gd")
const Win98MenuClass = preload("res://src/ui/Win98Menu.gd")
const DamageNumber = preload("res://src/ui/DamageNumber.gd")
const AutobattleToggleUIClass = preload("res://src/ui/autobattle/AutobattleToggleUI.gd")
const BattleDialogueClass = preload("res://src/ui/BattleDialogue.gd")
const BattleBackgroundClass = preload("res://src/battle/BattleBackground.gd")
const CharacterPortraitClass = preload("res://src/ui/CharacterPortrait.gd")

## UI References
@onready var battle_log: RichTextLabel = $UI/BattleLogPanel/MarginContainer/VBoxContainer/BattleLog
@onready var turn_info: Label = $UI/TurnInfoPanel/TurnInfo

## Action buttons (legacy - hidden when using Win98 menu)
@onready var action_menu_panel: PanelContainer = $UI/ActionMenuPanel
@onready var btn_attack: Button = $UI/ActionMenuPanel/MarginContainer/VBoxContainer/AttackButton
@onready var btn_ability: Button = $UI/ActionMenuPanel/MarginContainer/VBoxContainer/AbilityButton
@onready var btn_item: Button = $UI/ActionMenuPanel/MarginContainer/VBoxContainer/ItemButton
@onready var btn_default: Button = $UI/ActionMenuPanel/MarginContainer/VBoxContainer/DefaultButton
@onready var btn_bide: Button = $UI/ActionMenuPanel/MarginContainer/VBoxContainer/BideButton

## Win98 style menu
var active_win98_menu: Win98MenuClass = null
var use_win98_menus: bool = true  # Toggle for Win98 style menus

## Party status UI
@onready var char1_name: Label = $UI/PartyStatusPanel/VBoxContainer/Character1/Name
@onready var char1_hp: ProgressBar = $UI/PartyStatusPanel/VBoxContainer/Character1/HP
@onready var char1_hp_label: Label = $UI/PartyStatusPanel/VBoxContainer/Character1/HP/HPLabel
@onready var char1_mp: ProgressBar = $UI/PartyStatusPanel/VBoxContainer/Character1/MP
@onready var char1_mp_label: Label = $UI/PartyStatusPanel/VBoxContainer/Character1/MP/MPLabel
@onready var char1_ap: Label = $UI/PartyStatusPanel/VBoxContainer/Character1/AP

## Sprite containers
@onready var enemy_sprites: Node2D = $BattleField/EnemySprites
@onready var party_sprites: Node2D = $BattleField/PartySprites

## Sprite positions
@onready var enemy_positions: Array[Marker2D] = [
	$BattleField/EnemyArea/Enemy1Pos,
	$BattleField/EnemyArea/Enemy2Pos,
	$BattleField/EnemyArea/Enemy3Pos
]

@onready var party_positions: Array[Marker2D] = [
	$BattleField/PartyArea/Player1Pos,
	$BattleField/PartyArea/Player2Pos,
	$BattleField/PartyArea/Player3Pos,
	$BattleField/PartyArea/Player4Pos
]

## Test combatants
var party_members: Array[Combatant] = []
var test_enemies: Array[Combatant] = []

## Sprite nodes
var party_sprite_nodes: Array[AnimatedSprite2D] = []
var enemy_sprite_nodes: Array[AnimatedSprite2D] = []

## Animators
var party_animators: Array[BattleAnimatorClass] = []
var enemy_animators: Array[BattleAnimatorClass] = []

## Legacy single-player references (point to first party member)
var test_player: Combatant:
	get: return party_members[0] if party_members.size() > 0 else null
var player_sprite: AnimatedSprite2D:
	get: return party_sprite_nodes[0] if party_sprite_nodes.size() > 0 else null
var player_animator: BattleAnimatorClass:
	get: return party_animators[0] if party_animators.size() > 0 else null

## Target selection state
var pending_action: Dictionary = {}
var is_selecting_target: bool = false

## External party flag
var _has_external_party: bool = false

## Battle end state
var _battle_ended: bool = false
var _battle_victory: bool = false
var managed_by_game_loop: bool = false  # When true, don't handle restart internally
var command_memory_enabled: bool = true  # Remember last command per character
var force_miniboss: bool = false  # When true, spawn a miniboss instead of regular enemies
var forced_enemies: Array = []  # When set, spawn these specific enemies (e.g., ["cave_rat_king"])
var autogrind_enemy_data: Array = []  # When set, spawn pre-configured enemies from autogrind system

## Battle speed settings
const BATTLE_SPEEDS: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0]
const BATTLE_SPEED_LABELS: Array[String] = ["0.25x", "0.5x", "1x", "2x", "4x"]
var _battle_speed_index: int = 2  # Default to 1x
var _speed_indicator: RichTextLabel = null

## Autobattle toggle UI
var _autobattle_toggle_ui: AutobattleToggleUIClass = null

## Danger music state
var _is_danger_music: bool = false

## Dialogue system
var _battle_dialogue: BattleDialogueClass = null
var _boss_dialogue_data: Dictionary = {}  # Stores dialogue for current boss
var _waiting_for_dialogue: bool = false  # Pauses battle during dialogue
var _base_music_track: String = "battle"  # "battle" or "boss"
const DANGER_HP_THRESHOLD: float = 0.25  # Switch to danger music below 25% HP

## Autobattle state
var _all_autobattle_enabled: bool = false  # True when all players are on autobattle
# Note: cancel flag is stored in AutobattleSystem.cancel_all_next_turn for persistence across scenes

## Terrain/background
var _current_terrain: String = "plains"
var _battle_background: BattleBackgroundClass = null


func set_player(player: Combatant) -> void:
	"""Set external player from GameLoop (legacy single player)"""
	party_members = [player]
	_has_external_party = true


func set_party(party: Array[Combatant]) -> void:
	"""Set external party from GameLoop"""
	party_members = party
	_has_external_party = true


func set_terrain(terrain: String) -> void:
	"""Set the terrain type for battle background and elemental modifiers"""
	_current_terrain = terrain
	if _battle_background and is_instance_valid(_battle_background):
		_battle_background.set_terrain_from_string(terrain)
	# Pass terrain to BattleManager for damage modifiers
	BattleManager.set_terrain(terrain)


func _ready() -> void:
	# Reset any camera zoom from exploration scenes
	var viewport = get_viewport()
	if viewport:
		var current_camera = viewport.get_camera_2d()
		if current_camera:
			current_camera.zoom = Vector2(1.0, 1.0)

	# Create dynamic battle background (behind everything)
	_create_battle_background()

	# Apply retro font styling
	RetroFontClass.configure_battle_log(battle_log)

	# Connect to BattleManager signals (CTB system)
	BattleManager.battle_started.connect(_on_battle_started)
	BattleManager.battle_ended.connect(_on_battle_ended)
	BattleManager.selection_phase_started.connect(_on_selection_phase_started)
	BattleManager.selection_turn_started.connect(_on_selection_turn_started)
	BattleManager.selection_turn_ended.connect(_on_selection_turn_ended)
	BattleManager.execution_phase_started.connect(_on_execution_phase_started)
	BattleManager.action_executing.connect(_on_action_executing)
	BattleManager.action_executed.connect(_on_action_executed)
	BattleManager.round_ended.connect(_on_round_ended)
	BattleManager.damage_dealt.connect(_on_damage_dealt)
	BattleManager.healing_done.connect(_on_healing_done)
	BattleManager.battle_log_message.connect(_on_battle_log_message)
	BattleManager.monster_summoned.connect(_on_monster_summoned)
	BattleManager.one_shot_achieved.connect(_on_one_shot_achieved)
	BattleManager.autobattle_victory.connect(_on_autobattle_victory)

	# Connect button signals (for legacy mode)
	btn_attack.pressed.connect(_on_attack_pressed)
	btn_ability.pressed.connect(_on_ability_pressed)
	btn_item.pressed.connect(_on_item_pressed)
	btn_default.pressed.connect(_on_default_pressed)
	btn_bide.pressed.connect(_on_bide_pressed)

	# Hide legacy action panel if using Win98 menus
	if use_win98_menus:
		action_menu_panel.visible = false
		action_menu_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Disable focus on all buttons to prevent accidental activation
		btn_attack.focus_mode = Control.FOCUS_NONE
		btn_ability.focus_mode = Control.FOCUS_NONE
		btn_item.focus_mode = Control.FOCUS_NONE
		btn_default.focus_mode = Control.FOCUS_NONE
		btn_bide.focus_mode = Control.FOCUS_NONE

	# Defer non-critical UI creation to avoid blocking battle load
	# Speed indicator and autobattle toggle are not needed until player can interact
	call_deferred("_create_autobattle_toggle")
	call_deferred("_create_speed_indicator")

	# Dialogue system must be ready before _start_test_battle (boss intros need it)
	_create_dialogue_system()

	# Load default autobattle script
	BattleManager.set_autobattle_script("Aggressive")

	# Start a test battle
	_start_test_battle()


func _create_autobattle_toggle() -> void:
	"""Setup autobattle indicators - shown inline in party status panel"""
	# Removed overlapping UI - autobattle indicators now shown next to character names
	# The "Auto" command in battle menu enables autobattle for individual characters
	pass


func _create_battle_background() -> void:
	"""Create the dynamic battle background based on terrain"""
	_battle_background = BattleBackgroundClass.new()
	_battle_background.name = "BattleBackground"
	# Insert at index 0 to be behind everything
	add_child(_battle_background)
	move_child(_battle_background, 0)
	# Apply current terrain
	_battle_background.set_terrain_from_string(_current_terrain)


func set_command_menu_visible(visible: bool) -> void:
	"""Public method to show/hide the command menu (called by GameLoop for autobattle editor)"""
	if active_win98_menu and is_instance_valid(active_win98_menu):
		active_win98_menu.visible = visible
		# Restore focus when making visible again
		if visible:
			active_win98_menu.grab_focus()


## Hold-A detection for autobattle editor
var _hold_timer: float = 0.0
var _holding_auto: bool = false
var _auto_combatant: Combatant = null
const HOLD_DURATION: float = 1.5  # Seconds to hold for editor (1.5s feels responsive)


func _create_speed_indicator() -> void:
	"""Create battle speed indicator in top-left corner"""
	_speed_indicator = RichTextLabel.new()
	_speed_indicator.name = "SpeedIndicator"
	_speed_indicator.bbcode_enabled = true
	_speed_indicator.fit_content = true
	_speed_indicator.scroll_active = false
	_speed_indicator.custom_minimum_size = Vector2(80, 24)

	# Style it
	_speed_indicator.add_theme_font_size_override("normal_font_size", 16)

	# Position in top-left corner
	_speed_indicator.position = Vector2(8, 8)

	# Add to UI layer
	$UI.add_child(_speed_indicator)
	_update_speed_indicator()


func _update_speed_indicator() -> void:
	"""Update the speed indicator display with stylish BBCode"""
	if not _speed_indicator:
		return

	var speed_label = BATTLE_SPEED_LABELS[_battle_speed_index]
	var text = ""

	match _battle_speed_index:
		0:  # 0.25x - ultra slow (purple)
			text = "[color=#8866aa]▸[/color] [color=#aa88cc]%s[/color] [color=#664488]◂[/color]" % speed_label
		1:  # 0.5x - slow (blue)
			text = "[color=#6688aa]▸[/color] [color=#88aacc]%s[/color] [color=#446688]◂[/color]" % speed_label
		2:  # 1x - normal (white/cyan)
			text = "[color=#88cccc]▸[/color] [color=#ffffff]%s[/color] [color=#66aaaa]◂[/color]" % speed_label
		3:  # 2x - fast (yellow)
			text = "[color=#ccaa44]▸▸[/color] [color=#ffcc00]%s[/color] [color=#aa8822]◂◂[/color]" % speed_label
		4:  # 4x - turbo (orange/red)
			text = "[color=#cc6622]▸▸▸[/color] [color=#ff6600]%s[/color] [color=#aa4400]◂◂◂[/color]" % speed_label

	_speed_indicator.text = text


func _create_dialogue_system() -> void:
	"""Create battle dialogue overlay"""
	_battle_dialogue = BattleDialogueClass.new()
	_battle_dialogue.dialogue_finished.connect(_on_dialogue_finished)
	add_child(_battle_dialogue)


func _on_dialogue_finished() -> void:
	"""Handle dialogue completion - resume battle"""
	_waiting_for_dialogue = false
	# Now actually start the battle
	_start_battle_after_dialogue()


func _show_boss_intro_dialogue() -> void:
	"""Show boss intro dialogue if available"""
	if _boss_dialogue_data.has("intro") and _boss_dialogue_data["intro"].size() > 0:
		_waiting_for_dialogue = true
		_battle_dialogue.show_boss_intro("Boss", _boss_dialogue_data["intro"])


func _start_battle_after_dialogue() -> void:
	"""Start the battle after dialogue is finished"""
	BattleManager.start_battle(party_members, test_enemies)


func _toggle_battle_speed() -> void:
	"""Cycle through battle speeds"""
	_battle_speed_index = (_battle_speed_index + 1) % BATTLE_SPEEDS.size()
	var speed = BATTLE_SPEEDS[_battle_speed_index]
	Engine.time_scale = speed
	_update_speed_indicator()
	log_message("[color=gray]Battle speed: %s[/color]" % BATTLE_SPEED_LABELS[_battle_speed_index])


# Duplicate _input function removed - merged with the one at line 2250


func _repeat_previous_actions() -> void:
	"""Repeat all players' previous turn actions (Y button)"""
	var is_in_selection = BattleManager.current_state == BattleManager.BattleState.SELECTION_PHASE or \
						  BattleManager.current_state == BattleManager.BattleState.PLAYER_SELECTING
	if is_in_selection:
		if BattleManager.repeat_previous_actions():
			_close_win98_menu()
			log_message("[color=yellow]>>> Repeating previous actions![/color]")


func _start_test_battle() -> void:
	"""Start a test battle with sprite display"""
	log_message("[color=cyan]=== COWARDLY IRREGULAR ===[/color]")
	log_message("[color=yellow]Battle Start![/color]")

	# Use external party if provided, otherwise create default party
	if not _has_external_party:
		_create_default_party()

	# Create test enemies (1-3 random enemies)
	_spawn_enemies()

	# Connect party member signals
	for i in range(party_members.size()):
		var member = party_members[i]
		if not member.hp_changed.is_connected(_on_party_hp_changed):
			member.hp_changed.connect(_on_party_hp_changed.bind(i))
		if not member.ap_changed.is_connected(_on_party_ap_changed):
			member.ap_changed.connect(_on_party_ap_changed.bind(i))

	# Create sprites
	_create_battle_sprites()

	# Check for boss dialogue - if present, show it before starting battle
	if _boss_dialogue_data.has("intro") and _boss_dialogue_data["intro"].size() > 0:
		_show_boss_intro_dialogue()
	else:
		# Start battle immediately
		BattleManager.start_battle(party_members, test_enemies)


func _create_default_party() -> void:
	"""Create default party for standalone mode"""
	party_members.clear()

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
	party_members.append(hero)

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
	party_members.append(mira)

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
	party_members.append(zack)

	# Create Vex (Black Mage)
	var vex = Combatant.new()
	vex.initialize({
		"name": "Vex",
		"max_hp": 80,
		"max_mp": 300,
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
	party_members.append(vex)


## Available monster types for random encounters
const MONSTER_TYPES = [
	{
		"id": "slime",
		"name": "Slime",
		"color": Color(0.3, 0.8, 0.3),
		"stats": {"max_hp": 80, "max_mp": 20, "attack": 10, "defense": 8, "magic": 5, "speed": 8},
		"weaknesses": ["fire"],
		"resistances": ["ice"]
	},
	{
		"id": "bat",
		"name": "Bat",
		"color": Color(0.4, 0.3, 0.5),
		"stats": {"max_hp": 50, "max_mp": 15, "attack": 12, "defense": 5, "magic": 6, "speed": 18},
		"weaknesses": ["fire", "lightning"],
		"resistances": []
	},
	{
		"id": "mushroom",
		"name": "Fungoid",
		"color": Color(0.6, 0.4, 0.3),
		"stats": {"max_hp": 100, "max_mp": 25, "attack": 8, "defense": 12, "magic": 10, "speed": 5},
		"weaknesses": ["fire"],
		"resistances": ["poison"]
	},
	{
		"id": "imp",
		"name": "Imp",
		"color": Color(0.8, 0.3, 0.3),
		"stats": {"max_hp": 70, "max_mp": 50, "attack": 8, "defense": 8, "magic": 18, "speed": 14},
		"weaknesses": ["ice", "holy"],
		"resistances": ["fire", "dark"]
	},
	{
		"id": "goblin",
		"name": "Goblin",
		"color": Color(0.5, 0.6, 0.3),
		"stats": {"max_hp": 120, "max_mp": 30, "attack": 15, "defense": 10, "magic": 8, "speed": 12},
		"weaknesses": ["lightning"],
		"resistances": []
	},
	{
		"id": "skeleton",
		"name": "Skeleton",
		"color": Color(0.9, 0.9, 0.85),
		"stats": {"max_hp": 90, "max_mp": 10, "attack": 14, "defense": 6, "magic": 3, "speed": 10},
		"weaknesses": ["holy", "fire"],
		"resistances": ["dark", "poison"]
	},
	{
		"id": "wolf",
		"name": "Dire Wolf",
		"color": Color(0.4, 0.35, 0.3),
		"stats": {"max_hp": 110, "max_mp": 15, "attack": 18, "defense": 8, "magic": 4, "speed": 16},
		"weaknesses": ["fire"],
		"resistances": ["ice"]
	},
	{
		"id": "ghost",
		"name": "Specter",
		"color": Color(0.7, 0.8, 0.9),
		"stats": {"max_hp": 60, "max_mp": 80, "attack": 6, "defense": 4, "magic": 20, "speed": 14},
		"weaknesses": ["holy"],
		"resistances": ["physical", "dark"]
	},
	{
		"id": "snake",
		"name": "Viper",
		"color": Color(0.3, 0.5, 0.2),
		"stats": {"max_hp": 70, "max_mp": 30, "attack": 12, "defense": 7, "magic": 8, "speed": 20},
		"weaknesses": ["ice"],
		"resistances": ["poison"]
	},
	{
		"id": "cave_rat",
		"name": "Cave Rat",
		"color": Color(0.45, 0.35, 0.3),
		"stats": {"max_hp": 90, "max_mp": 15, "attack": 30, "defense": 8, "magic": 10, "speed": 14},
		"weaknesses": ["fire"],
		"resistances": []
	},
	{
		"id": "rat_guard",
		"name": "Rat Guard",
		"color": Color(0.4, 0.35, 0.35),
		"stats": {"max_hp": 160, "max_mp": 25, "attack": 40, "defense": 18, "magic": 12, "speed": 11},
		"weaknesses": ["lightning"],
		"resistances": ["physical"]
	}
]


func _spawn_enemies() -> void:
	"""Spawn 1-3 random enemies for the battle - sometimes mixed groups"""
	# Clear any existing enemies
	for enemy in test_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	test_enemies.clear()

	# Check for autogrind pre-configured enemies
	if autogrind_enemy_data.size() > 0:
		_spawn_from_data(autogrind_enemy_data)
		return

	# Check for forced specific enemies (e.g., boss battles)
	if forced_enemies.size() > 0:
		_spawn_forced_enemies()
		return

	# Check for miniboss battle
	if force_miniboss:
		_spawn_miniboss()
		return

	# Random number of enemies (2-3, limited by available positions)
	var max_enemies = mini(3, enemy_positions.size())
	var num_enemies = randi_range(2, max_enemies)

	# 40% chance of mixed group, 60% chance of same type
	var use_mixed_group = randf() < 0.4 and num_enemies > 1

	# Pick monster types for this encounter
	var monster_types_for_encounter: Array = []
	if use_mixed_group:
		# Pick different types for each enemy
		var available_types = MONSTER_TYPES.duplicate()
		available_types.shuffle()
		for i in range(num_enemies):
			monster_types_for_encounter.append(available_types[i % available_types.size()])
	else:
		# All same type
		var monster_type = MONSTER_TYPES[randi() % MONSTER_TYPES.size()]
		for i in range(num_enemies):
			monster_types_for_encounter.append(monster_type)

	# Track names for encounter message
	var enemy_names: Dictionary = {}

	for i in range(num_enemies):
		var monster_type = monster_types_for_encounter[i]
		var enemy = Combatant.new()

		# Count how many of this type we've spawned for suffix
		var type_count = 0
		for j in range(i):
			if monster_types_for_encounter[j]["id"] == monster_type["id"]:
				type_count += 1

		var stats = monster_type["stats"].duplicate()
		# Only add suffix if there are multiple of the same type
		var same_type_total = monster_types_for_encounter.count(monster_type)
		if same_type_total > 1:
			stats["name"] = monster_type["name"] + " " + ["A", "B", "C"][type_count]
		else:
			stats["name"] = monster_type["name"]

		# Slight speed variation for turn order variety
		stats["speed"] = stats["speed"] + i
		enemy.initialize(stats)
		add_child(enemy)

		# Store monster type ID for sprite selection
		enemy.set_meta("monster_type", monster_type["id"])

		# Add weaknesses/resistances from monster type
		for weakness in monster_type.get("weaknesses", []):
			enemy.elemental_weaknesses.append(weakness)
		for resistance in monster_type.get("resistances", []):
			enemy.elemental_resistances.append(resistance)

		# Connect signals
		enemy.hp_changed.connect(_on_enemy_hp_changed.bind(i))
		enemy.died.connect(_on_enemy_died.bind(i))

		test_enemies.append(enemy)

		# Track for message
		if monster_type["name"] in enemy_names:
			enemy_names[monster_type["name"]] += 1
		else:
			enemy_names[monster_type["name"]] = 1

	# Build encounter message
	var msg_parts: Array = []
	for enemy_name in enemy_names:
		var count = enemy_names[enemy_name]
		if count > 1:
			msg_parts.append("%d %s" % [count, enemy_name + "s"])
		else:
			msg_parts.append("1 %s" % enemy_name)
	log_message("[color=gray]%s appeared![/color]" % " and ".join(msg_parts))

	_update_ui()


func _spawn_from_data(enemy_data_array: Array) -> void:
	"""Spawn enemies from pre-configured data dictionaries (used by autogrind system)"""
	var enemy_names: Dictionary = {}
	var max_enemies = mini(enemy_data_array.size(), enemy_positions.size())

	for i in range(max_enemies):
		var data = enemy_data_array[i]
		var enemy = Combatant.new()

		var stats = {}
		if data.has("stats"):
			stats = data["stats"].duplicate()
		else:
			stats = {
				"max_hp": data.get("max_hp", 100),
				"max_mp": data.get("max_mp", 20),
				"attack": data.get("attack", 10),
				"defense": data.get("defense", 10),
				"magic": data.get("magic", 10),
				"speed": data.get("speed", 8)
			}

		# Count duplicates for suffixing
		var type_id = data.get("id", "unknown")
		var type_name = data.get("name", "Monster")
		var same_type_count = 0
		for j in range(i):
			if enemy_data_array[j].get("id", "") == type_id:
				same_type_count += 1

		var total_same = 0
		for ed in enemy_data_array:
			if ed.get("id", "") == type_id:
				total_same += 1

		if total_same > 1:
			stats["name"] = type_name + " " + ["A", "B", "C"][same_type_count % 3]
		else:
			stats["name"] = type_name

		# Slight speed variation
		stats["speed"] = stats.get("speed", 8) + i

		enemy.initialize(stats)
		add_child(enemy)

		# Store monster type ID for sprite selection
		enemy.set_meta("monster_type", type_id)

		# Add weaknesses/resistances from data
		for weakness in data.get("weaknesses", []):
			enemy.elemental_weaknesses.append(weakness)
		for resistance in data.get("resistances", []):
			enemy.elemental_resistances.append(resistance)

		# Store corruption effects if present
		if data.has("corruption_effects"):
			enemy.set_meta("corruption_effects", data["corruption_effects"])

		# Connect signals
		enemy.hp_changed.connect(_on_enemy_hp_changed.bind(i))
		enemy.died.connect(_on_enemy_died.bind(i))

		test_enemies.append(enemy)

		# Track for encounter message
		if type_name in enemy_names:
			enemy_names[type_name] += 1
		else:
			enemy_names[type_name] = 1

	# Build encounter message
	var msg_parts: Array = []
	for enemy_name in enemy_names:
		var count = enemy_names[enemy_name]
		if count > 1:
			msg_parts.append("%d %s" % [count, enemy_name + "s"])
		else:
			msg_parts.append("1 %s" % enemy_name)
	log_message("[color=gray]%s appeared![/color]" % " and ".join(msg_parts))

	_update_ui()


const MINIBOSS_TYPES = [
	{
		"id": "cave_troll",
		"name": "Cave Troll",
		"stats": {"max_hp": 400, "max_mp": 30, "attack": 55, "defense": 25, "magic": 10, "speed": 6},
		"weaknesses": ["fire", "lightning"],
		"resistances": ["ice"]
	},
	{
		"id": "shadow_knight",
		"name": "Shadow Knight",
		"stats": {"max_hp": 350, "max_mp": 80, "attack": 48, "defense": 30, "magic": 25, "speed": 12},
		"weaknesses": ["holy", "fire"],
		"resistances": ["dark", "ice"]
	}
]


func _spawn_forced_enemies() -> void:
	"""Spawn specific enemies from the forced_enemies array (e.g., boss battles)"""
	# Load monster data
	var monsters_data = _load_monsters_data()
	if monsters_data.is_empty():
		push_error("Failed to load monsters.json - falling back to random enemies")
		forced_enemies.clear()
		_spawn_enemies()
		return

	var enemy_names: Array = []
	var is_boss_battle = false

	for i in range(forced_enemies.size()):
		var enemy_id = forced_enemies[i]
		if not monsters_data.has(enemy_id):
			push_warning("Unknown monster ID: %s" % enemy_id)
			continue

		var monster_data = monsters_data[enemy_id]
		var enemy = Combatant.new()
		var stats = {
			"name": monster_data.get("name", enemy_id),
			"max_hp": monster_data["stats"].get("max_hp", 100),
			"max_mp": monster_data["stats"].get("max_mp", 0),
			"attack": monster_data["stats"].get("attack", 10),
			"defense": monster_data["stats"].get("defense", 5),
			"magic": monster_data["stats"].get("magic", 5),
			"speed": monster_data["stats"].get("speed", 10)
		}
		enemy.initialize(stats)
		add_child(enemy)

		# Store monster type ID for sprite selection
		enemy.set_meta("monster_type", enemy_id)
		if monster_data.get("boss", false) or monster_data.get("miniboss", false):
			enemy.set_meta("is_boss", true)
			enemy.set_meta("is_miniboss", true)  # For music selection
			is_boss_battle = true
			# Store dialogue data for this boss
			if monster_data.has("dialogue"):
				_boss_dialogue_data = monster_data["dialogue"]

		# Connect signals
		enemy.hp_changed.connect(_on_enemy_hp_changed.bind(i))
		enemy.died.connect(_on_enemy_died.bind(i))

		test_enemies.append(enemy)
		enemy_names.append(stats["name"])

	# Announcement based on battle type
	if is_boss_battle:
		log_message("")
		log_message("[color=red]═══════════════════════════════[/color]")
		log_message("[color=orange]   👑  BOSS BATTLE!  👑[/color]")
		for enemy_name in enemy_names:
			log_message("[color=yellow]   %s appeared![/color]" % enemy_name)
		log_message("[color=red]═══════════════════════════════[/color]")
		log_message("")
	else:
		for enemy_name in enemy_names:
			log_message("[color=yellow]%s appeared![/color]" % enemy_name)

	_update_ui()


func _load_monsters_data() -> Dictionary:
	"""Load monster definitions from data file"""
	var file_path = "res://data/monsters.json"
	if not FileAccess.file_exists(file_path):
		return {}

	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return {}

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_string) == OK:
		return json.data
	return {}


func _spawn_miniboss() -> void:
	"""Spawn a single miniboss enemy"""
	# Pick a random miniboss
	var boss_type = MINIBOSS_TYPES[randi() % MINIBOSS_TYPES.size()]

	var enemy = Combatant.new()
	var stats = boss_type["stats"].duplicate()
	stats["name"] = boss_type["name"]
	enemy.initialize(stats)
	add_child(enemy)

	# Store monster type ID for sprite selection
	enemy.set_meta("monster_type", boss_type["id"])
	enemy.set_meta("is_miniboss", true)

	# Add weaknesses/resistances
	for weakness in boss_type.get("weaknesses", []):
		enemy.elemental_weaknesses.append(weakness)
	for resistance in boss_type.get("resistances", []):
		enemy.elemental_resistances.append(resistance)

	# Connect signals
	enemy.hp_changed.connect(_on_enemy_hp_changed.bind(0))
	enemy.died.connect(_on_enemy_died.bind(0))

	test_enemies.append(enemy)

	# Epic announcement!
	log_message("")
	log_message("[color=red]═══════════════════════════════[/color]")
	log_message("[color=orange]   ⚔️  MINIBOSS BATTLE!  ⚔️[/color]")
	log_message("[color=yellow]   %s appeared![/color]" % boss_type["name"])
	log_message("[color=red]═══════════════════════════════[/color]")
	log_message("")

	_update_ui()


func _create_battle_sprites() -> void:
	"""Create animated battle sprites (12-bit style)"""

	# Clear existing party sprites
	for sprite in party_sprite_nodes:
		if is_instance_valid(sprite):
			sprite.queue_free()
	party_sprite_nodes.clear()

	for animator in party_animators:
		if is_instance_valid(animator):
			animator.queue_free()
	party_animators.clear()

	# Clear existing enemy sprites
	for sprite in enemy_sprite_nodes:
		if is_instance_valid(sprite):
			sprite.queue_free()
	enemy_sprite_nodes.clear()

	for animator in enemy_animators:
		if is_instance_valid(animator):
			animator.queue_free()
	enemy_animators.clear()

	# Create party member sprites
	for i in range(party_members.size()):
		var member = party_members[i]
		var sprite = AnimatedSprite2D.new()

		# Choose sprite based on job and set scale
		# Fighter (hero) is already large, others get scaled up
		var job_id = member.job.get("id", "fighter") if member.job else "fighter"
		var weapon_id = member.equipped_weapon if member.equipped_weapon else ""
		var sprite_scale = Vector2(1.0, 1.0)  # Default scale
		match job_id:
			"white_mage":
				sprite.sprite_frames = BattleAnimatorClass.create_mage_sprite_frames(Color(0.9, 0.9, 1.0), weapon_id)
				sprite_scale = Vector2(1.4, 1.4)  # Mira bigger
			"black_mage":
				sprite.sprite_frames = BattleAnimatorClass.create_mage_sprite_frames(Color(0.15, 0.1, 0.25), weapon_id)
				sprite_scale = Vector2(1.3, 1.3)  # Vex bigger
			"thief":
				sprite.sprite_frames = BattleAnimatorClass.create_thief_sprite_frames(weapon_id)
				sprite_scale = Vector2(1.35, 1.35)  # Zack bigger
			_:
				sprite.sprite_frames = BattleAnimatorClass.create_hero_sprite_frames(weapon_id)
				sprite_scale = Vector2(1.0, 1.0)  # Hero already large

		sprite.scale = sprite_scale
		sprite.position = party_positions[i].global_position if i < party_positions.size() else Vector2(600, 100 + i * 100)
		sprite.flip_h = true  # Flip to face left
		sprite.play("idle")
		party_sprites.add_child(sprite)
		party_sprite_nodes.append(sprite)

		var animator = BattleAnimatorClass.new()
		animator.setup(sprite)
		add_child(animator)
		party_animators.append(animator)

		# Add label with character name
		_add_sprite_label(sprite, member.combatant_name.to_upper(), Vector2(-20, 40))

	# Create enemy sprites
	for i in range(test_enemies.size()):
		var enemy = test_enemies[i]

		var sprite = AnimatedSprite2D.new()
		# Choose sprite based on monster type ID stored in enemy
		var monster_id = enemy.get_meta("monster_type", "slime")
		sprite.sprite_frames = _get_monster_sprite_frames(monster_id)
		sprite.position = enemy_positions[i].global_position if i < enemy_positions.size() else Vector2(200 + i * 100, 300)
		sprite.play("idle")
		$BattleField/EnemySprites.add_child(sprite)
		enemy_sprite_nodes.append(sprite)

		var animator = BattleAnimatorClass.new()
		animator.setup(sprite)
		add_child(animator)
		enemy_animators.append(animator)

		# Add label with enemy name
		_add_sprite_label(sprite, enemy.combatant_name.to_upper(), Vector2(-20, 40))


func _get_monster_sprite_frames(monster_id: String) -> SpriteFrames:
	"""Get the appropriate sprite frames for a monster type"""
	match monster_id:
		"slime":
			return BattleAnimatorClass.create_slime_sprite_frames()
		"skeleton":
			return BattleAnimatorClass.create_skeleton_sprite_frames()
		"ghost":
			return BattleAnimatorClass.create_specter_sprite_frames()
		"imp":
			return BattleAnimatorClass.create_imp_sprite_frames()
		"wolf":
			return BattleAnimatorClass.create_wolf_sprite_frames()
		"snake":
			return BattleAnimatorClass.create_viper_sprite_frames()
		"bat":
			return BattleAnimatorClass.create_bat_sprite_frames()
		"mushroom":
			return BattleAnimatorClass.create_fungoid_sprite_frames()
		"goblin":
			return BattleAnimatorClass.create_goblin_sprite_frames()
		"shadow_knight":
			return BattleAnimatorClass.create_shadow_knight_sprite_frames()
		"cave_troll":
			return BattleAnimatorClass.create_cave_troll_sprite_frames()
		"cave_rat_king":
			return BattleAnimatorClass.create_cave_rat_king_sprite_frames()
		"cave_rat":
			return BattleAnimatorClass.create_cave_rat_sprite_frames()
		"rat_guard":
			return BattleAnimatorClass.create_rat_guard_sprite_frames()
		_:
			# Default to slime for unknown types
			return BattleAnimatorClass.create_slime_sprite_frames()


func _add_sprite_label(sprite: AnimatedSprite2D, text: String, offset: Vector2) -> void:
	"""Add a label below a sprite"""
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = offset
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	sprite.add_child(label)


func _create_character_sprite(color: Color, label: String) -> Sprite2D:
	"""Create a placeholder character sprite with 12-bit aesthetic"""
	var sprite = Sprite2D.new()

	# Create a simple colored sprite placeholder
	var img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Draw character silhouette (simple rectangle for now)
	for y in range(10, 60):
		for x in range(20, 44):
			var c = color
			# Add simple shading
			if x < 24 or y < 15:
				c = color.lightened(0.2)
			elif x > 38 or y > 50:
				c = color.darkened(0.2)
			img.set_pixel(x, y, c)

	# Add label
	var texture = ImageTexture.create_from_image(img)
	sprite.texture = texture
	sprite.centered = true

	# Add label below sprite
	var label_node = Label.new()
	label_node.text = label
	label_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_node.position = Vector2(-32, 35)
	sprite.add_child(label_node)

	return sprite


func _create_enemy_sprite(color: Color, label: String) -> Sprite2D:
	"""Create a placeholder enemy sprite"""
	var sprite = Sprite2D.new()

	# Create enemy sprite (blob-like for slime)
	var img = Image.create(80, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Draw blob shape
	for y in range(20, 55):
		for x in range(15, 65):
			var dist_from_center = sqrt(pow(x - 40, 2) + pow(y - 37, 2))
			if dist_from_center < 22:
				var c = color
				# Gradient shading
				if y < 30:
					c = color.lightened(0.3)
				elif y > 45:
					c = color.darkened(0.3)
				img.set_pixel(x, y, c)

	var texture = ImageTexture.create_from_image(img)
	sprite.texture = texture
	sprite.centered = true

	# Add label
	var label_node = Label.new()
	label_node.text = label
	label_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_node.position = Vector2(-40, 35)
	sprite.add_child(label_node)

	return sprite


func _update_ui() -> void:
	"""Update all UI elements"""
	_update_character_status()
	_update_enemy_status()
	_update_action_buttons()
	_update_danger_music()


func _update_danger_music() -> void:
	"""Update music danger intensity based on party HP"""
	var members = BattleManager.player_party if BattleManager.player_party.size() > 0 else party_members
	if members.size() == 0:
		return

	# Calculate party danger level
	var total_hp_percent = 0.0
	var alive_count = 0
	var dead_count = 0

	for member in members:
		if not is_instance_valid(member):
			continue
		if member.is_alive:
			total_hp_percent += member.get_hp_percentage()
			alive_count += 1
		else:
			dead_count += 1

	# Calculate danger intensity:
	# - 0.0 = party above 75% average HP, no deaths
	# - 0.5 = party around 40% average HP or 1 death
	# - 1.0 = party critical (below 20% average HP or 2+ deaths)
	var avg_hp_percent = total_hp_percent / max(1, alive_count)
	var death_penalty = dead_count * 25.0  # Each death adds 25% to danger

	# Convert HP to danger (inverse relationship)
	# 100% HP = 0 danger, 0% HP = 100 danger
	var hp_danger = (100.0 - avg_hp_percent) + death_penalty

	# Scale to 0.0 - 1.0 range (danger starts above 25% damage)
	var intensity = clamp((hp_danger - 25.0) / 75.0, 0.0, 1.0)

	# Apply to music system
	if has_node("/root/SoundManager"):
		get_node("/root/SoundManager").set_danger_intensity(intensity)


## Dynamic party status UI elements
var _party_status_boxes: Array = []

## Dynamic enemy status UI elements
var _enemy_status_boxes: Array = []

## Track which enemies have been "scanned" to reveal HP/MP
var _revealed_enemies: Dictionary = {}


func _update_character_status() -> void:
	"""Update character status display for all party members"""
	# Use BattleManager's player_party for accurate current state
	var members = BattleManager.player_party if BattleManager.player_party.size() > 0 else party_members
	if members.size() == 0:
		return

	# Create status boxes if needed
	_ensure_party_status_boxes()

	# Update each party member's status
	for i in range(members.size()):
		if i >= _party_status_boxes.size():
			break
		_update_member_status(i, members[i])


func _ensure_party_status_boxes() -> void:
	"""Ensure we have status boxes for all party members (only creates once)"""
	var members = BattleManager.player_party if BattleManager.player_party.size() > 0 else party_members

	# Skip if already created for this party
	if _party_status_boxes.size() == members.size():
		var all_valid = true
		for box in _party_status_boxes:
			if not is_instance_valid(box):
				all_valid = false
				break
		if all_valid:
			return

	var container = $UI/PartyStatusPanel/VBoxContainer

	# Clear existing dynamic boxes
	for box in _party_status_boxes:
		if is_instance_valid(box):
			box.queue_free()
	_party_status_boxes.clear()

	# Hide the static Character1 node if it exists
	var char1_node = container.get_node_or_null("Character1")
	if char1_node:
		char1_node.visible = false

	# Create status boxes for each party member
	for i in range(members.size()):
		var member = members[i]
		var box = _create_character_status_box(i, member)
		container.add_child(box)
		_party_status_boxes.append(box)


func _create_character_status_box(idx: int, member: Combatant) -> VBoxContainer:
	"""Create a status box for a party member"""
	var box = VBoxContainer.new()
	box.name = "Character%d" % (idx + 1)

	# Header row with portrait and name
	var header = HBoxContainer.new()
	header.name = "Header"

	# Portrait
	var job_id = member.job.get("id", "fighter") if member.job else "fighter"
	var portrait = CharacterPortraitClass.new(member.customization, job_id, CharacterPortraitClass.PortraitSize.SMALL)
	portrait.name = "Portrait"
	header.add_child(portrait)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(4, 0)
	header.add_child(spacer)

	# Name label with autobattle indicator
	var name_label = Label.new()
	name_label.name = "Name"
	var job_name = member.job.get("name", "None") if member.job else "None"
	var char_id = member.combatant_name.to_lower().replace(" ", "_")
	var auto_indicator = " [A]" if AutobattleSystem.is_autobattle_enabled(char_id) else ""
	name_label.text = "%s (%s)%s" % [member.combatant_name, job_name, auto_indicator]
	name_label.add_theme_font_size_override("font_size", 13)
	if auto_indicator != "":
		name_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(name_label)

	box.add_child(header)

	# HP bar
	var hp_bar = ProgressBar.new()
	hp_bar.name = "HP"
	hp_bar.custom_minimum_size = Vector2(0, 22)
	hp_bar.max_value = member.max_hp
	hp_bar.value = member.current_hp
	hp_bar.show_percentage = false
	box.add_child(hp_bar)

	# HP label inside bar
	var hp_label = Label.new()
	hp_label.name = "HPLabel"
	hp_label.text = "HP: %d/%d" % [member.current_hp, member.max_hp]
	hp_label.add_theme_font_size_override("font_size", 12)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_bar.add_child(hp_label)

	# MP bar
	var mp_bar = ProgressBar.new()
	mp_bar.name = "MP"
	mp_bar.custom_minimum_size = Vector2(0, 18)
	mp_bar.max_value = member.max_mp
	mp_bar.value = member.current_mp
	mp_bar.show_percentage = false
	box.add_child(mp_bar)

	# MP label inside bar
	var mp_label = Label.new()
	mp_label.name = "MPLabel"
	mp_label.text = "MP: %d/%d" % [member.current_mp, member.max_mp]
	mp_label.add_theme_font_size_override("font_size", 11)
	mp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	mp_bar.add_child(mp_label)

	# AP/Status label
	var ap_label = RichTextLabel.new()
	ap_label.name = "AP"
	ap_label.bbcode_enabled = true
	ap_label.fit_content = true
	ap_label.custom_minimum_size = Vector2(0, 20)
	ap_label.add_theme_font_size_override("normal_font_size", 13)
	ap_label.add_theme_font_size_override("bold_font_size", 13)
	ap_label.text = "AP: 0"
	box.add_child(ap_label)

	return box


func _update_member_status(idx: int, member: Combatant) -> void:
	"""Update a single party member's status display"""
	if idx >= _party_status_boxes.size():
		return

	var box = _party_status_boxes[idx]
	if not is_instance_valid(box):
		return

	# Update name with autobattle indicator
	var name_label = box.get_node_or_null("Name")
	if name_label:
		var job_name = member.job.get("name", "None") if member.job else "None"
		var level_text = " Lv.%d" % member.job_level if member.job_level > 1 else ""
		var char_id = member.combatant_name.to_lower().replace(" ", "_")
		var is_auto_enabled = AutobattleSystem.is_autobattle_enabled(char_id)
		var auto_indicator = ""
		var name_color: Color = Color.WHITE

		if is_auto_enabled:
			if AutobattleSystem.cancel_all_next_turn:
				# Autobattle is on but pending cancel - show orange [A]
				auto_indicator = " [A]"
				name_color = Color(1.0, 0.6, 0.2)  # Orange for pending cancel
			else:
				# Autobattle is on - show green [A]
				auto_indicator = " [A]"
				name_color = Color(0.4, 1.0, 0.4)  # Green for auto

		name_label.text = "%s (%s%s)%s" % [member.combatant_name, job_name, level_text, auto_indicator]
		# Color the name based on autobattle state
		if auto_indicator != "":
			name_label.add_theme_color_override("font_color", name_color)
		else:
			name_label.remove_theme_color_override("font_color")

	# Update HP (with KO indicator)
	var hp_bar = box.get_node_or_null("HP")
	if hp_bar:
		hp_bar.max_value = member.max_hp
		hp_bar.value = member.current_hp
		var hp_label = hp_bar.get_node_or_null("HPLabel")
		if hp_label:
			if not member.is_alive:
				hp_label.text = "-- KO --"
				hp_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
			else:
				hp_label.text = "HP: %d/%d" % [member.current_hp, member.max_hp]
				hp_label.remove_theme_color_override("font_color")

	# Gray out the name label if KO'd
	if name_label:
		if not member.is_alive:
			name_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

	# Gray out the sprite if KO'd
	if idx < party_sprite_nodes.size():
		var sprite = party_sprite_nodes[idx]
		if is_instance_valid(sprite):
			if not member.is_alive:
				sprite.modulate = Color(0.3, 0.3, 0.3, 0.7)  # Dark gray, semi-transparent
			else:
				sprite.modulate = Color(1, 1, 1, 1)  # Normal

	# Update MP
	var mp_bar = box.get_node_or_null("MP")
	if mp_bar:
		mp_bar.max_value = member.max_mp
		mp_bar.value = member.current_mp
		var mp_label = mp_bar.get_node_or_null("MPLabel")
		if mp_label:
			mp_label.text = "MP: %d/%d" % [member.current_mp, member.max_mp]

	# Update AP and status - try both RichTextLabel and regular Label
	var ap_label = box.get_node_or_null("AP")
	if ap_label:
		var ap_color = "white"
		if member.current_ap > 0:
			ap_color = "lime"
		elif member.current_ap < 0:
			ap_color = "red"

		var ap_value = member.current_ap

		# Check if this member is currently selecting and has queued actions in menu
		var queued_count = 0
		var committed_count = 0
		var is_current_selecting = (member == BattleManager.current_combatant and
			BattleManager.current_state == BattleManager.BattleState.PLAYER_SELECTING and
			active_win98_menu and is_instance_valid(active_win98_menu))
		if is_current_selecting:
			queued_count = active_win98_menu.get_queue_count()

		# Check for committed actions in BattleManager.pending_actions
		var is_deferring = false
		for action in BattleManager.pending_actions:
			if action.get("combatant") == member:
				if action.get("type") == "advance":
					# Advance has multiple sub-actions
					var sub_actions = action.get("actions", [])
					committed_count = sub_actions.size()
				elif action.get("type") in ["attack", "ability", "item"]:
					committed_count = 1
				elif action.get("type") == "defer":
					# Defer keeps the +1 natural gain
					is_deferring = true
				break

		if ap_label is RichTextLabel:
			# Ensure BBCode is enabled
			ap_label.bbcode_enabled = true

			var status_text: String
			if queued_count > 0:
				# Currently selecting with queue: "AP: +1→-2 [3]"
				var new_ap = ap_value - queued_count
				var new_color = "yellow" if new_ap >= 0 else "orange"
				status_text = "[color=%s]AP: %+d[/color][color=%s]→%+d[/color] [color=aqua][%d][/color]" % [ap_color, ap_value, new_color, new_ap, queued_count]
			elif is_deferring:
				# Deferring keeps +1 natural gain: "AP: +1 (+1)"
				status_text = "[color=%s]AP: %+d[/color] [color=cyan](+1)[/color]" % [ap_color, ap_value]
			elif committed_count > 0:
				# Already committed actions: "AP: +1 (-4)"
				status_text = "[color=%s]AP: %+d[/color] [color=gray](-%d)[/color]" % [ap_color, ap_value, committed_count]
			else:
				status_text = "[color=%s]AP: %+d[/color]" % [ap_color, ap_value]

			# Add status effects
			if member.status_effects.size() > 0:
				status_text += " ["
				for si in range(member.status_effects.size()):
					if si > 0:
						status_text += ", "
					status_text += "[color=yellow]%s[/color]" % member.status_effects[si].capitalize()
				status_text += "]"

			# Set BBCode text directly
			ap_label.text = status_text
		else:
			# Fallback for regular Label
			if queued_count > 0:
				var new_ap = ap_value - queued_count
				ap_label.text = "AP: %+d→%+d [%d]" % [ap_value, new_ap, queued_count]
			elif is_deferring:
				ap_label.text = "AP: %+d (+1)" % ap_value
			elif committed_count > 0:
				ap_label.text = "AP: %+d (-%d)" % [ap_value, committed_count]
			else:
				ap_label.text = "AP: %+d" % ap_value


func _update_enemy_status() -> void:
	"""Update enemy status display for all enemies"""
	if test_enemies.size() == 0:
		return

	# Create status boxes if needed
	_ensure_enemy_status_boxes()

	# Update each enemy's status
	for i in range(test_enemies.size()):
		if i >= _enemy_status_boxes.size():
			break
		_update_enemy_member_status(i, test_enemies[i])


func _ensure_enemy_status_boxes() -> void:
	"""Ensure we have status boxes for all enemies"""
	var container = get_node_or_null("UI/EnemyStatusPanel/VBoxContainer")
	if not container:
		return

	# Skip if already created for this enemy count
	if _enemy_status_boxes.size() == test_enemies.size():
		var all_valid = true
		for box in _enemy_status_boxes:
			if not is_instance_valid(box):
				all_valid = false
				break
		if all_valid:
			return

	# Clear existing dynamic boxes
	for box in _enemy_status_boxes:
		if is_instance_valid(box):
			box.queue_free()
	_enemy_status_boxes.clear()

	# Create status boxes for each enemy
	for i in range(test_enemies.size()):
		var enemy = test_enemies[i]
		var box = _create_enemy_status_box(i, enemy)
		container.add_child(box)
		_enemy_status_boxes.append(box)


func _create_enemy_status_box(idx: int, enemy: Combatant) -> VBoxContainer:
	"""Create a status box for an enemy"""
	var box = VBoxContainer.new()
	box.name = "Enemy%d" % (idx + 1)

	# Name label
	var name_label = RichTextLabel.new()
	name_label.name = "Name"
	name_label.bbcode_enabled = true
	name_label.fit_content = true
	name_label.custom_minimum_size = Vector2(0, 18)
	name_label.text = enemy.combatant_name
	box.add_child(name_label)

	# AP/Status label (always visible)
	var ap_label = RichTextLabel.new()
	ap_label.name = "AP"
	ap_label.bbcode_enabled = true
	ap_label.fit_content = true
	ap_label.custom_minimum_size = Vector2(0, 16)
	ap_label.text = "AP: 0"
	box.add_child(ap_label)

	# HP label (hidden until revealed)
	var hp_label = RichTextLabel.new()
	hp_label.name = "HP"
	hp_label.bbcode_enabled = true
	hp_label.fit_content = true
	hp_label.custom_minimum_size = Vector2(0, 14)
	hp_label.text = "[color=gray]HP: ???[/color]"
	box.add_child(hp_label)

	# Add separator after each enemy except last
	if idx < test_enemies.size() - 1:
		var sep = HSeparator.new()
		sep.custom_minimum_size = Vector2(0, 4)
		box.add_child(sep)

	return box


func _update_enemy_member_status(idx: int, enemy: Combatant) -> void:
	"""Update a single enemy's status display"""
	if idx >= _enemy_status_boxes.size():
		return

	var box = _enemy_status_boxes[idx]
	if not is_instance_valid(box):
		return

	var is_revealed = _revealed_enemies.get(enemy, false)
	var is_dead = not enemy.is_alive

	# Update name with status indicator
	var name_label = box.get_node_or_null("Name")
	if name_label and name_label is RichTextLabel:
		var name_color = "red" if is_dead else "white"
		var status_indicator = " [color=gray]✗[/color]" if is_dead else ""
		name_label.text = "[color=%s]%s[/color]%s" % [name_color, enemy.combatant_name, status_indicator]

	# Update AP
	var ap_label = box.get_node_or_null("AP")
	if ap_label and ap_label is RichTextLabel:
		var ap_color = "white"
		if enemy.current_ap > 0:
			ap_color = "lime"
		elif enemy.current_ap < 0:
			ap_color = "red"

		if is_dead:
			ap_label.text = "[color=gray]---[/color]"
		else:
			ap_label.text = "[color=%s]AP: %+d[/color]" % [ap_color, enemy.current_ap]

	# Update HP (hidden unless revealed or dead)
	var hp_label = box.get_node_or_null("HP")
	if hp_label and hp_label is RichTextLabel:
		if is_dead:
			hp_label.text = "[color=red]DEFEATED[/color]"
		elif is_revealed:
			var hp_percent = float(enemy.current_hp) / float(enemy.max_hp)
			var hp_color = "lime" if hp_percent > 0.5 else ("yellow" if hp_percent > 0.25 else "red")
			hp_label.text = "[color=%s]HP: %d/%d[/color]" % [hp_color, enemy.current_hp, enemy.max_hp]
		else:
			# Show vague HP indicator based on percentage
			var hp_percent = float(enemy.current_hp) / float(enemy.max_hp)
			var hp_hint = "Healthy" if hp_percent > 0.75 else ("Wounded" if hp_percent > 0.5 else ("Hurt" if hp_percent > 0.25 else "Critical"))
			var hp_color = "lime" if hp_percent > 0.5 else ("yellow" if hp_percent > 0.25 else "red")
			hp_label.text = "[color=%s]%s[/color]" % [hp_color, hp_hint]


func reveal_enemy_stats(enemy: Combatant) -> void:
	"""Reveal an enemy's HP/MP (called by scan abilities)"""
	_revealed_enemies[enemy] = true
	_update_enemy_status()


func _update_action_buttons() -> void:
	"""Enable/disable action buttons based on battle state"""
	var is_player_selecting = BattleManager.current_state == BattleManager.BattleState.PLAYER_SELECTING
	var current = BattleManager.current_combatant

	btn_attack.disabled = not is_player_selecting
	btn_ability.disabled = not is_player_selecting
	btn_item.disabled = not is_player_selecting
	btn_default.disabled = not is_player_selecting

	# Bide requires non-negative AP
	if current and is_player_selecting:
		btn_bide.disabled = current.current_ap < 0
	else:
		btn_bide.disabled = true


func _update_turn_info() -> void:
	"""Update turn information display for CTB system"""
	var state = BattleManager.current_state
	var current = BattleManager.current_combatant

	if state == BattleManager.BattleState.SELECTION_PHASE or state == BattleManager.BattleState.PLAYER_SELECTING or state == BattleManager.BattleState.ENEMY_SELECTING:
		if current:
			turn_info.text = "Round %d - SELECT: %s (AP: %+d)" % [
				BattleManager.current_round,
				current.combatant_name,
				current.current_ap
			]
		else:
			turn_info.text = "Round %d - Selection Phase" % BattleManager.current_round
	elif state == BattleManager.BattleState.EXECUTION_PHASE or state == BattleManager.BattleState.PROCESSING_ACTION:
		if current:
			turn_info.text = "Round %d - EXECUTE: %s" % [
				BattleManager.current_round,
				current.combatant_name
			]
		else:
			turn_info.text = "Round %d - Execution Phase" % BattleManager.current_round
	else:
		turn_info.text = "Round %d" % BattleManager.current_round


func log_message(message: String) -> void:
	"""Add a message to the battle log"""
	print(message)

	if battle_log:
		battle_log.append_text(message + "\n")
		battle_log.scroll_to_line(battle_log.get_line_count())


## Button handlers
func _on_attack_pressed() -> void:
	"""Handle Attack button"""
	var alive_enemies = _get_alive_enemies()

	if alive_enemies.size() == 0:
		log_message("No enemies to attack!")
		return

	if alive_enemies.size() == 1:
		# Single target - attack immediately
		_execute_attack(alive_enemies[0])
	else:
		# Multiple targets - show target selection
		pending_action = {"type": "attack"}
		_show_target_selection(alive_enemies)


func _get_alive_enemies() -> Array[Combatant]:
	"""Get all alive enemies"""
	var alive: Array[Combatant] = []
	for enemy in test_enemies:
		if is_instance_valid(enemy) and enemy.is_alive:
			alive.append(enemy)
	return alive


func _show_target_selection(targets: Array[Combatant]) -> void:
	"""Show popup menu for target selection"""
	is_selecting_target = true

	var popup = PopupMenu.new()
	popup.name = "TargetMenu"
	add_child(popup)

	for i in range(targets.size()):
		var target = targets[i]
		var label = "%s (HP: %d/%d)" % [target.combatant_name, target.current_hp, target.max_hp]
		popup.add_item(label, i)

	popup.id_pressed.connect(_on_target_selected.bind(targets))
	popup.close_requested.connect(func(): is_selecting_target = false)
	popup.popup_centered()


func _on_target_selected(idx: int, targets: Array[Combatant]) -> void:
	"""Handle target selection"""
	is_selecting_target = false

	if idx < 0 or idx >= targets.size():
		return

	var target = targets[idx]

	match pending_action.get("type", ""):
		"attack":
			_execute_attack(target)
		"ability":
			_execute_ability(pending_action.get("ability_id", ""), target)

	pending_action = {}


func _get_current_combatant_animator() -> BattleAnimatorClass:
	"""Get the animator for the current combatant"""
	var current = BattleManager.current_combatant
	if not current:
		return null
	var idx = party_members.find(current)
	if idx >= 0 and idx < party_animators.size():
		return party_animators[idx]
	return null


func _execute_attack(target: Combatant) -> void:
	"""Queue attack on target (animation plays during execution phase)"""
	BattleManager.player_attack(target)


func _on_ability_pressed() -> void:
	"""Handle Ability button"""
	var current = BattleManager.current_combatant
	if not current or not current.job:
		log_message("No job assigned!")
		return

	var abilities = current.job.get("abilities", [])
	if abilities.size() == 0:
		log_message("No abilities available!")
		return

	# Show ability selection menu
	_show_ability_menu(abilities)


func _show_ability_menu(ability_ids: Array) -> void:
	"""Show popup menu for ability selection"""
	var current = BattleManager.current_combatant
	if not current:
		return

	var popup = PopupMenu.new()
	popup.name = "AbilityMenu"
	add_child(popup)

	for i in range(ability_ids.size()):
		var ability_id = ability_ids[i]
		var ability = JobSystem.get_ability(ability_id)
		if ability.is_empty():
			continue

		var mp_cost = ability.get("mp_cost", 0)
		var can_afford = current.current_mp >= mp_cost
		var label = "%s (MP: %d)" % [ability["name"], mp_cost]

		popup.add_item(label, i)
		if not can_afford:
			popup.set_item_disabled(i, true)

	popup.id_pressed.connect(_on_ability_selected.bind(ability_ids))
	popup.popup_centered()


func _on_ability_selected(idx: int, ability_ids: Array) -> void:
	"""Handle ability selection from menu"""
	if idx < 0 or idx >= ability_ids.size():
		return

	var ability_id = ability_ids[idx]
	var ability = JobSystem.get_ability(ability_id)
	var target_type = ability.get("target_type", "single_enemy")
	var alive_enemies = _get_alive_enemies()

	var current = BattleManager.current_combatant

	match target_type:
		"single_enemy":
			if alive_enemies.size() == 1:
				_execute_ability(ability_id, alive_enemies[0])
			elif alive_enemies.size() > 1:
				pending_action = {"type": "ability", "ability_id": ability_id}
				_show_target_selection(alive_enemies)
			else:
				log_message("No valid targets!")
		"all_enemies":
			if alive_enemies.size() > 0:
				_execute_ability(ability_id, alive_enemies[0], true)
			else:
				log_message("No valid targets!")
		"single_ally", "all_allies", "self":
			_execute_ability(ability_id, current if current else party_members[0])


func _execute_ability(ability_id: String, target: Combatant, target_all: bool = false) -> void:
	"""Queue ability (animation plays during execution phase)"""
	var targets = []
	if target_all:
		targets = _get_alive_enemies()
	else:
		targets = [target]

	BattleManager.player_use_ability(ability_id, targets)


func _spawn_ability_effects(ability_id: String, targets: Array) -> void:
	"""Spawn visual effects for an ability on all targets"""
	var canvas_transform = get_viewport().get_canvas_transform()

	for target in targets:
		if not is_instance_valid(target):
			continue

		# Find target sprite position
		var target_pos = Vector2.ZERO

		# Check if target is an enemy
		var enemy_idx = test_enemies.find(target)
		if enemy_idx >= 0 and enemy_idx < enemy_sprite_nodes.size():
			var sprite = enemy_sprite_nodes[enemy_idx]
			if is_instance_valid(sprite):
				target_pos = sprite.global_position

		# Check if target is a party member
		var party_idx = party_members.find(target)
		if party_idx >= 0 and party_idx < party_sprite_nodes.size():
			var sprite = party_sprite_nodes[party_idx]
			if is_instance_valid(sprite):
				target_pos = sprite.global_position

		if target_pos != Vector2.ZERO:
			EffectSystem.spawn_ability_effect(ability_id, target_pos)


func _play_ability_animation(anim_type: String, animator: BattleAnimatorClass = null) -> void:
	"""Play animation based on ability animation type"""
	if not animator:
		animator = _get_current_combatant_animator()
	if not animator:
		return

	match anim_type:
		"attack":
			animator.play_attack()
		"backstab":
			# Quick diagonal lunge from behind
			animator.play_backstab()
		"steal":
			# Quick in-and-out grab animation
			animator.play_steal()
		"mug":
			# Attack + steal combo
			animator.play_mug()
		"skill":
			# Generic physical skill (power strike, etc.)
			animator.play_skill()
		"heal", "buff":
			# Healing/buff - use cast with green/blue tint effect
			animator.play_cast()
		"cast_fire", "cast_ice", "cast_lightning", "cast_dark", "cast_time", "cast_meta":
			# All magic types use cast animation
			animator.play_cast()
		"special":
			# Special abilities use item animation
			animator.play_item()
		_:
			# Default to cast
			animator.play_cast()


func _on_item_pressed() -> void:
	"""Handle Item button"""
	var current = BattleManager.current_combatant
	if not current:
		return

	if current.inventory.is_empty():
		log_message("No items in inventory!")
		return

	# Show item selection menu
	_show_item_menu()


func _show_item_menu() -> void:
	"""Show popup menu for item selection"""
	var current = BattleManager.current_combatant
	if not current:
		return

	var popup = PopupMenu.new()
	popup.name = "ItemMenu"
	add_child(popup)

	var item_ids = []
	var idx = 0

	for item_id in current.inventory.keys():
		var item = ItemSystem.get_item(item_id)
		if item.is_empty():
			continue

		var quantity = current.inventory[item_id]
		var label = "%s x%d" % [item["name"], quantity]

		popup.add_item(label, idx)
		item_ids.append(item_id)
		idx += 1

	if item_ids.size() == 0:
		popup.queue_free()
		log_message("No valid items!")
		return

	popup.id_pressed.connect(_on_item_selected.bind(item_ids))
	popup.popup_centered()


func _on_item_selected(idx: int, item_ids: Array) -> void:
	"""Handle item selection from menu"""
	if idx < 0 or idx >= item_ids.size():
		return

	var item_id = item_ids[idx]
	var item = ItemSystem.get_item(item_id)
	var current = BattleManager.current_combatant

	# Determine targets
	var targets = []
	var target_type = item.get("target_type", ItemSystem.TargetType.SINGLE_ALLY)
	var alive_enemies = _get_alive_enemies()

	match target_type:
		ItemSystem.TargetType.SINGLE_ENEMY:
			if alive_enemies.size() > 0:
				targets = [alive_enemies[0]]  # Default to first alive enemy
		ItemSystem.TargetType.ALL_ENEMIES:
			targets = alive_enemies
		ItemSystem.TargetType.SINGLE_ALLY, ItemSystem.TargetType.ALL_ALLIES, ItemSystem.TargetType.SELF:
			targets = [current if current else party_members[0]]

	if targets.size() > 0:
		BattleManager.player_item(item_id, targets)
	else:
		log_message("No valid targets!")


func _on_default_pressed() -> void:
	"""Handle Default button (Defer)"""
	BattleManager.player_defer()
	_update_ui()


func _on_bide_pressed() -> void:
	"""Handle Bide/Advance button - queues multiple attacks"""
	var alive_enemies = _get_alive_enemies()

	if alive_enemies.size() == 0:
		log_message("No enemies to attack!")
		return

	log_message("[color=yellow]Advancing![/color]")

	# Target first alive enemy for now (could add multi-target selection later)
	var target = alive_enemies[0]
	var actions: Array[Dictionary] = [
		{"type": "attack", "target": target},
		{"type": "attack", "target": target}
	]

	BattleManager.player_advance(actions)
	_update_ui()


func _on_autobattle_toggled(enabled: bool) -> void:
	"""Handle autobattle toggle"""
	BattleManager.toggle_autobattle(enabled)
	if enabled:
		log_message("[color=green]Autobattle enabled - AI will control your turns[/color]")
	else:
		log_message("[color=gray]Autobattle disabled - manual control[/color]")


## Autobattle system functions
func _enable_all_autobattle() -> void:
	"""Enable autobattle for ALL players and immediately execute all remaining turns"""
	_all_autobattle_enabled = true
	AutobattleSystem.cancel_all_next_turn = false

	# Enable autobattle for every party member
	for member in party_members:
		var char_id = member.combatant_name.to_lower().replace(" ", "_")
		AutobattleSystem.set_autobattle_enabled(char_id, true)

	# Play enable sound
	SoundManager.play_ui("autobattle_on")
	log_message("[color=lime]>>> AUTOBATTLE: ALL PLAYERS ENABLED[/color]")

	# Close any open menu
	_close_win98_menu()

	# If we're currently on a player's turn, execute their autobattle and let BattleManager continue
	if BattleManager.current_state == BattleManager.BattleState.PLAYER_SELECTING:
		BattleManager.execute_autobattle_for_current()

	_update_ui()


func _toggle_cancel_all_autobattle() -> void:
	"""Toggle autobattle cancel state (Select button during execution).
	If autobattle is on, queue cancel. If already pending cancel, revoke it."""
	if AutobattleSystem.cancel_all_next_turn:
		# Already pending cancel - re-enable autobattle instead
		AutobattleSystem.cancel_all_next_turn = false
		SoundManager.play_ui("autobattle_on")
		log_message("[color=lime]>>> AUTOBATTLE: Cancel revoked - staying enabled[/color]")
		_update_ui()
		return

	AutobattleSystem.cancel_all_next_turn = true

	# Play disable sound
	SoundManager.play_ui("autobattle_off")
	log_message("[color=orange]>>> AUTOBATTLE: Will disable for all players next turn[/color]")
	_update_ui()


func _cancel_autobattle_during_execution() -> void:
	"""Cancel autobattle during execution (B button). One-way cancel, no toggle."""
	if not AutobattleSystem.cancel_all_next_turn:
		AutobattleSystem.cancel_all_next_turn = true
		SoundManager.play_ui("autobattle_off")
		log_message("[color=orange]>>> AUTOBATTLE: Will disable for all players next turn[/color]")
		_update_ui()


func _cancel_all_autobattle() -> void:
	"""Immediately cancel autobattle for all players"""
	_all_autobattle_enabled = false
	AutobattleSystem.cancel_all_next_turn = false

	# Disable autobattle for every party member
	for member in party_members:
		var char_id = member.combatant_name.to_lower().replace(" ", "_")
		AutobattleSystem.set_autobattle_enabled(char_id, false)

	log_message("[color=gray]>>> AUTOBATTLE: Disabled for all players[/color]")
	_update_ui()


func _cancel_single_player_autobattle(combatant: Combatant) -> void:
	"""Cancel autobattle for a single player (when they press B after selecting Auto)"""
	var char_id = combatant.combatant_name.to_lower().replace(" ", "_")
	AutobattleSystem.set_autobattle_enabled(char_id, false)

	# Check if any player still has autobattle - if none, clear the global flag
	var any_autobattle = false
	for member in party_members:
		var member_id = member.combatant_name.to_lower().replace(" ", "_")
		if AutobattleSystem.is_autobattle_enabled(member_id):
			any_autobattle = true
			break

	if not any_autobattle:
		_all_autobattle_enabled = false

	SoundManager.play_ui("autobattle_off")
	log_message("[color=gray]%s: Autobattle disabled[/color]" % combatant.combatant_name)


func _flash_sprite(sprite: Sprite2D, flash_color: Color) -> void:
	"""Flash sprite with color effect"""
	if not sprite:
		return

	var original_modulate = sprite.modulate
	sprite.modulate = flash_color

	# Reset after delay
	await get_tree().create_timer(0.2).timeout
	if sprite:
		sprite.modulate = original_modulate


## Battle event handlers
func _on_battle_started() -> void:
	"""Handle battle start"""
	log_message("[color=yellow]>>> Battle commenced![/color]")

	# Apply any pending autobattle cancellation from previous battle
	if AutobattleSystem.cancel_all_next_turn:
		_cancel_all_autobattle()

	_update_ui()
	# Start battle music - use boss music if fighting a miniboss
	var is_boss_fight = _check_for_boss()
	var boss_type = _get_boss_type()
	if is_boss_fight:
		if boss_type == "cave_rat_king":
			_base_music_track = "boss_rat_king"
			SoundManager.play_music("boss_rat_king")
			print("[MUSIC] Playing sneaky Rat King theme")
		else:
			_base_music_track = "boss"
			SoundManager.play_music("boss")
	else:
		# Play monster-specific music based on dominant enemy type
		var dominant_monster = _get_dominant_monster_type()
		if dominant_monster != "":
			_base_music_track = "battle_" + dominant_monster
			SoundManager.play_music("battle_" + dominant_monster)
			print("[MUSIC] Playing %s battle theme" % dominant_monster)
		else:
			_base_music_track = "battle"
			SoundManager.play_music("battle")
	_is_danger_music = false


func _get_dominant_monster_type() -> String:
	"""Get the most common monster type in the current battle"""
	var type_counts: Dictionary = {}

	for enemy in test_enemies:
		if enemy and is_instance_valid(enemy):
			var monster_id = enemy.get_meta("monster_type", "")
			if monster_id != "":
				type_counts[monster_id] = type_counts.get(monster_id, 0) + 1

	if type_counts.is_empty():
		return ""

	# Find the type with the highest count
	var max_count = 0
	var dominant_type = ""
	for monster_type in type_counts:
		if type_counts[monster_type] > max_count:
			max_count = type_counts[monster_type]
			dominant_type = monster_type

	return dominant_type


func _check_for_boss() -> bool:
	"""Check if any enemy is a boss/miniboss"""
	for enemy in test_enemies:
		if enemy and is_instance_valid(enemy):
			if enemy.has_meta("is_miniboss") and enemy.get_meta("is_miniboss"):
				return true
	return force_miniboss


func _get_boss_type() -> String:
	"""Get the monster_type of the boss enemy if any"""
	for enemy in test_enemies:
		if enemy and is_instance_valid(enemy):
			if enemy.has_meta("is_miniboss") and enemy.get_meta("is_miniboss"):
				return enemy.get_meta("monster_type", "")
	return ""


func _on_battle_ended(victory: bool) -> void:
	"""Handle battle end"""
	# Clean up any open menus
	if active_win98_menu and is_instance_valid(active_win98_menu):
		active_win98_menu.queue_free()
		active_win98_menu = null

	if victory:
		log_message("\n[color=lime]=== VICTORY ===[/color]")
		# Show one-shot bonus in battle log if achieved
		if BattleManager.get_one_shot_achieved():
			var rank = BattleManager.get_one_shot_rank()
			var exp_mult = BattleManager.get_one_shot_exp_multiplier()
			log_message("[color=yellow]ONE-SHOT! Rank: %s - EXP x%.1f![/color]" % [rank, exp_mult])
		# Show autobattle bonus in battle log if achieved
		if BattleManager.get_autobattle_achieved():
			var auto_mult = BattleManager.get_autobattle_exp_multiplier()
			var auto_turns = BattleManager.get_autobattle_turns()
			log_message("[color=cyan]FULL AUTOBATTLE! %d turns - EXP x%.1f![/color]" % [auto_turns, auto_mult])
		# Show combined multiplier if both bonuses active
		if BattleManager.get_one_shot_achieved() and BattleManager.get_autobattle_achieved():
			var combined = BattleManager.get_one_shot_exp_multiplier() * BattleManager.get_autobattle_exp_multiplier()
			log_message("[color=magenta]COMBINED BONUS: EXP x%.1f![/color]" % combined)
		log_message("[color=gray]Press ENTER to continue...[/color]")
		# Play victory animation for all party members
		for animator in party_animators:
			if animator:
				animator.play_victory()
		# Switch to victory music
		SoundManager.play_music("victory")
	else:
		log_message("\n[color=red]=== DEFEAT ===[/color]")
		log_message("[color=gray]Press ENTER to restart...[/color]")
		# Play defeat animation for all party members
		for animator in party_animators:
			if animator:
				animator.play_defeat()
		# Play game over ditty
		SoundManager.play_music("game_over")

	_update_ui()
	_battle_ended = true
	_battle_victory = victory


func _process(delta: float) -> void:
	"""Handle post-battle input, hold-A detection, and danger music"""
	# Handle hold-A for autobattle editor
	_process_hold_a(delta)

	# Check for danger music (player about to die)
	_check_danger_music()

	if _battle_ended and not managed_by_game_loop:
		if Input.is_action_just_pressed("ui_accept"):
			_battle_ended = false
			if _battle_victory:
				# Victory - could transition to next scene, for now restart
				log_message("[color=cyan]Starting new battle...[/color]")
				_restart_battle()
			else:
				# Defeat - restart
				log_message("[color=cyan]Retrying battle...[/color]")
				_restart_battle()


func _process_hold_a(delta: float) -> void:
	"""Track hold-A on Auto menu item to open editor"""
	# Check if menu is active and we're on "autobattle" item
	if active_win98_menu and is_instance_valid(active_win98_menu) and active_win98_menu.visible:
		var selected_id = active_win98_menu.get_selected_item_id()
		var selected_data = active_win98_menu.get_selected_item_data()

		if selected_id == "autobattle" and Input.is_action_pressed("ui_accept"):
			if not _holding_auto:
				# Start tracking hold
				_holding_auto = true
				_hold_timer = 0.0
				if selected_data is Dictionary:
					_auto_combatant = selected_data.get("combatant", null)

			_hold_timer += delta

			# Check if held long enough
			if _hold_timer >= HOLD_DURATION and _auto_combatant:
				_open_autobattle_editor_for(_auto_combatant)
				_holding_auto = false
				_hold_timer = 0.0
				_auto_combatant = null
		else:
			# Reset hold tracking
			_holding_auto = false
			_hold_timer = 0.0
	else:
		_holding_auto = false
		_hold_timer = 0.0


func _open_autobattle_editor_for(combatant: Combatant) -> void:
	"""Open autobattle editor for a specific combatant"""
	if not combatant:
		return

	var char_id = combatant.combatant_name.to_lower().replace(" ", "_")
	var char_name = combatant.combatant_name

	# Hide the battle menu
	set_command_menu_visible(false)

	# Load and create editor
	var AutobattleGridEditorClass = load("res://src/ui/autobattle/AutobattleGridEditor.gd")
	var editor = AutobattleGridEditorClass.new()
	editor.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(editor)
	editor.setup(char_id, char_name, combatant)
	editor.closed.connect(_on_inline_autobattle_editor_closed.bind(editor))
	print("Autobattle editor opened for %s (hold-A)" % char_name)


func _on_inline_autobattle_editor_closed(editor: Control) -> void:
	"""Handle inline autobattle editor closing"""
	if editor and is_instance_valid(editor):
		editor.queue_free()
	# Show menu again
	set_command_menu_visible(true)


func _restart_battle() -> void:
	"""Restart the battle"""
	# Stop any playing music (will restart when battle starts)
	SoundManager.stop_music()

	# Clean up any stray menus
	if active_win98_menu and is_instance_valid(active_win98_menu):
		active_win98_menu.queue_free()
		active_win98_menu = null

	# Clear old enemies
	for enemy in test_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	test_enemies.clear()

	# Clear enemy sprites
	for sprite in enemy_sprite_nodes:
		if is_instance_valid(sprite):
			sprite.queue_free()
	enemy_sprite_nodes.clear()

	for animator in enemy_animators:
		if is_instance_valid(animator):
			animator.queue_free()
	enemy_animators.clear()

	# Clear enemy status UI
	for box in _enemy_status_boxes:
		if is_instance_valid(box):
			box.queue_free()
	_enemy_status_boxes.clear()
	_revealed_enemies.clear()

	# Reset party HP/MP
	for member in party_members:
		member.current_hp = member.max_hp
		member.current_mp = member.max_mp
		member.current_ap = 0
		member.is_alive = true
		member.is_defending = false
		member.status_effects.clear()

	# Reset party sprite visibility
	for sprite in party_sprite_nodes:
		if is_instance_valid(sprite):
			sprite.modulate.a = 1.0

	# Spawn new enemies and start battle
	_spawn_enemies()
	_create_battle_sprites()
	BattleManager.start_battle(party_members, test_enemies)


## CTB Phase Handlers
func _on_selection_phase_started() -> void:
	"""Handle selection phase start"""
	log_message("\n[color=yellow]>>> Selection Phase[/color]")

	# Check if autobattle cancellation was queued during last execution phase
	if AutobattleSystem.cancel_all_next_turn:
		_cancel_all_autobattle()

	_update_turn_info()
	_update_ui()


func _on_selection_turn_started(combatant: Combatant) -> void:
	"""Handle selection turn start - show menu for player"""
	log_message("[color=aqua]%s selecting...[/color]" % combatant.combatant_name)
	_update_turn_info()
	_update_ui()

	# Show Win98 menu for player selection (use BattleManager.player_party for correct object identity)
	var is_player = combatant in BattleManager.player_party
	if is_player:
		# Play da-ding sound for player turn
		SoundManager.play_ui("player_turn")
	if use_win98_menus and is_player:
		_show_win98_command_menu(combatant)


func _on_selection_turn_ended(combatant: Combatant) -> void:
	"""Handle selection turn end"""
	_close_win98_menu()
	_update_ui()


func _on_execution_phase_started() -> void:
	"""Handle execution phase start - all actions now execute"""
	log_message("\n[color=yellow]>>> Execution Phase[/color]")
	_update_turn_info()
	_update_ui()


func _on_action_executing(combatant: Combatant, action: Dictionary) -> void:
	"""Handle action executing - play animations here"""
	_update_turn_info()

	# Get combatant's animator and sprite
	var animator = _get_combatant_animator(combatant)
	var attacker_sprite = _get_combatant_sprite(combatant)
	if not animator:
		return

	var action_type = action.get("type", "")
	match action_type:
		"attack":
			var target = action.get("target") as Combatant
			var target_sprite = _get_combatant_sprite(target)
			var target_animator = _get_combatant_animator(target)

			# Move attacker toward target, attack, then return
			if attacker_sprite and target_sprite:
				_animate_melee_attack(attacker_sprite, target_sprite, animator, target_animator)
			else:
				# Fallback if no sprites
				animator.play_attack(func():
					if target_animator:
						target_animator.play_hit()
				)
		"ability":
			var ability_id = action.get("ability_id", "")
			var targets = action.get("targets", [])
			var ability = JobSystem.get_ability(ability_id)
			var ability_type = ability.get("type", "magic")
			var anim_type = ability.get("animation", "cast")

			# Physical abilities move to target
			if ability_type == "physical" and targets.size() > 0:
				var target_sprite = _get_combatant_sprite(targets[0])
				var target_animator = _get_combatant_animator(targets[0])
				if attacker_sprite and target_sprite:
					_animate_melee_attack(attacker_sprite, target_sprite, animator, target_animator)
				else:
					_play_ability_animation(anim_type, animator)
					_spawn_ability_effects(ability_id, targets)
			else:
				_play_ability_animation(anim_type, animator)
				_spawn_ability_effects(ability_id, targets)
		"item":
			animator.play_item()
		"defer":
			animator.play_defend()


func _animate_melee_attack(attacker_sprite: Node2D, target_sprite: Node2D, attacker_anim: BattleAnimatorClass, target_anim: BattleAnimatorClass) -> void:
	"""Animate attacker moving to target, attacking, then returning"""
	# Store home position as metadata to ensure we can always return
	if not attacker_sprite.has_meta("home_position"):
		attacker_sprite.set_meta("home_position", attacker_sprite.position)
	var home_pos = attacker_sprite.get_meta("home_position")
	var target_pos = target_sprite.position

	# Kill any existing tween on this sprite to prevent conflicts
	if attacker_sprite.has_meta("attack_tween"):
		var old_tween = attacker_sprite.get_meta("attack_tween")
		if old_tween and old_tween.is_valid():
			old_tween.kill()

	# Calculate attack position (close to target but not overlapping)
	var direction = (target_pos - home_pos).normalized()
	var attack_pos = target_pos - direction * 40  # Stop 40 pixels from target

	# Create movement tween
	var tween = create_tween()
	attacker_sprite.set_meta("attack_tween", tween)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)

	# Move to target (fast)
	tween.tween_property(attacker_sprite, "position", attack_pos, 0.15)

	# Play attack animation and hit on target
	tween.tween_callback(func():
		if attacker_anim:
			attacker_anim.play_attack()
		# Brief delay then play hit
		get_tree().create_timer(0.1).timeout.connect(func():
			if target_anim and is_instance_valid(target_sprite):
				target_anim.play_hit()
				# Spawn physical hit effect
				EffectSystem.spawn_effect(EffectSystem.EffectType.PHYSICAL, target_sprite.global_position)
		)
	)

	# Wait for attack animation
	tween.tween_interval(0.3)

	# Return to home position (use stored home, not where we started this attack)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(attacker_sprite, "position", home_pos, 0.2)


func _get_combatant_sprite(combatant: Combatant) -> Node2D:
	"""Get sprite node for any combatant"""
	if not combatant:
		return null
	# Check party (use BattleManager's array for consistency)
	var party_idx = BattleManager.player_party.find(combatant)
	if party_idx >= 0 and party_idx < party_sprite_nodes.size():
		return party_sprite_nodes[party_idx]
	# Check enemies
	var enemy_idx = BattleManager.enemy_party.find(combatant)
	if enemy_idx >= 0 and enemy_idx < enemy_sprite_nodes.size():
		return enemy_sprite_nodes[enemy_idx]
	return null


func _get_combatant_animator(combatant: Combatant) -> BattleAnimatorClass:
	"""Get animator for any combatant (party or enemy)"""
	# Check party
	var party_idx = BattleManager.player_party.find(combatant)
	if party_idx >= 0 and party_idx < party_animators.size():
		return party_animators[party_idx]
	# Check enemies (use BattleManager's array for consistency)
	var enemy_idx = BattleManager.enemy_party.find(combatant)
	if enemy_idx >= 0 and enemy_idx < enemy_animators.size():
		return enemy_animators[enemy_idx]
	return null


func _on_round_ended(round_num: int) -> void:
	"""Handle round end"""
	log_message("[color=gray]--- Round %d complete ---[/color]" % round_num)
	_update_ui()


func _on_action_executed(combatant: Combatant, action: Dictionary, targets: Array) -> void:
	"""Handle action execution"""
	_update_ui()


## Combatant event handlers
func _on_party_hp_changed(old_value: int, new_value: int, member_idx: int) -> void:
	"""Handle party member HP change"""
	_update_ui()
	if new_value < old_value and member_idx < party_animators.size():
		# Play hit animation when taking damage
		party_animators[member_idx].play_hit()


func _on_party_ap_changed(old_value: int, new_value: int, member_idx: int) -> void:
	"""Handle party member AP change"""
	_update_ui()


# Legacy aliases for backwards compatibility
func _on_player_hp_changed(old_value: int, new_value: int) -> void:
	_on_party_hp_changed(old_value, new_value, 0)


func _on_player_ap_changed(old_value: int, new_value: int) -> void:
	_on_party_ap_changed(old_value, new_value, 0)


func _on_enemy_hp_changed(old_value: int, new_value: int, enemy_idx: int) -> void:
	"""Handle enemy HP change"""
	if new_value < old_value and enemy_idx < enemy_animators.size():
		# Play hit animation when taking damage
		enemy_animators[enemy_idx].play_hit()


func _on_enemy_died(enemy_idx: int) -> void:
	"""Handle enemy death"""
	if enemy_idx < test_enemies.size():
		var enemy = test_enemies[enemy_idx]
		log_message("[color=yellow]%s has been defeated![/color]" % enemy.combatant_name)

		if enemy_idx < enemy_animators.size() and enemy_idx < enemy_sprite_nodes.size():
			var animator = enemy_animators[enemy_idx]
			var sprite = enemy_sprite_nodes[enemy_idx]
			# Play defeat animation and start fade immediately (don't wait for callback)
			animator.play_defeat()
			# Fade out sprite
			if is_instance_valid(sprite):
				var tween = create_tween()
				tween.tween_property(sprite, "modulate:a", 0.0, 0.8)
				# Hide sprite completely after fade
				tween.tween_callback(func():
					if is_instance_valid(sprite):
						sprite.visible = false
				)


## Win98 Menu Functions

func _input(event: InputEvent) -> void:
	"""Handle high-priority inputs: Select button, battle speed toggle, and repeat actions"""
	# Handle autobattle toggle with highest priority (Select button)
	var is_select_pressed = event.is_action_pressed("battle_toggle_auto") and not event.is_echo()

	if is_select_pressed:
		var is_player_selecting = BattleManager.current_state == BattleManager.BattleState.PLAYER_SELECTING
		var is_in_selection_phase = BattleManager.current_state == BattleManager.BattleState.SELECTION_PHASE or \
									BattleManager.current_state == BattleManager.BattleState.PLAYER_SELECTING or \
									BattleManager.current_state == BattleManager.BattleState.ENEMY_SELECTING
		var is_executing = BattleManager.current_state == BattleManager.BattleState.EXECUTION_PHASE or \
						   BattleManager.current_state == BattleManager.BattleState.PROCESSING_ACTION

		if is_player_selecting or is_in_selection_phase:
			# During selection: Enable autobattle for ALL players
			_enable_all_autobattle()
			get_viewport().set_input_as_handled()
			return
		elif is_executing:
			# During execution: Toggle autobattle
			_toggle_cancel_all_autobattle()
			get_viewport().set_input_as_handled()
			return

	# Battle speed toggle (Tab or ` key)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_QUOTELEFT:
			_toggle_battle_speed()
			get_viewport().set_input_as_handled()
			return
		# Y key to repeat previous actions
		elif event.keycode == KEY_Y:
			_repeat_previous_actions()
			get_viewport().set_input_as_handled()
			return

	# Gamepad buttons (Nintendo layout: Y=left, X=top)
	if event is InputEventJoypadButton and event.pressed:
		# Y button - toggle battle speed
		if event.button_index == JOY_BUTTON_Y:
			_toggle_battle_speed()
			get_viewport().set_input_as_handled()
			return
		# X button - repeat previous actions
		elif event.button_index == JOY_BUTTON_X:
			_repeat_previous_actions()
			get_viewport().set_input_as_handled()
			return


func _unhandled_input(event: InputEvent) -> void:
	"""Handle input for menu and Advance/Defer controls"""
	var current = BattleManager.current_combatant
	var is_player_selecting = BattleManager.current_state == BattleManager.BattleState.PLAYER_SELECTING
	var is_executing = BattleManager.current_state == BattleManager.BattleState.EXECUTION_PHASE or \
					   BattleManager.current_state == BattleManager.BattleState.PROCESSING_ACTION
	var is_in_selection_phase = BattleManager.current_state == BattleManager.BattleState.SELECTION_PHASE or \
								BattleManager.current_state == BattleManager.BattleState.PLAYER_SELECTING or \
								BattleManager.current_state == BattleManager.BattleState.ENEMY_SELECTING

	# Handle B/Cancel button during execution to cancel autobattle
	# Use ui_cancel action which maps correctly across controller types
	var is_cancel_pressed = event.is_action_pressed("ui_cancel") and not event.is_echo()

	if is_cancel_pressed and is_executing:
		# During execution: B ONLY cancels autobattle (one-way, no toggle)
		_cancel_autobattle_during_execution()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		# R key = Defer (skip turn, gain AP) during selection
		if event.keycode == KEY_R and is_player_selecting and current:
			_close_win98_menu()
			log_message("[color=cyan]%s defers![/color]" % current.combatant_name)
			BattleManager.player_defer()
			get_viewport().set_input_as_handled()
			return

		# L key = Advance hint (actual advancing handled by menu)
		if event.keycode == KEY_L and is_player_selecting:
			log_message("[color=yellow]Use R to queue actions (Advance)![/color]")
			get_viewport().set_input_as_handled()
			return

		# Reopen menu on Space/Enter/Z if menu is closed
		if use_win98_menus and is_player_selecting and current:
			if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_Z]:
				if not active_win98_menu or not is_instance_valid(active_win98_menu):
					_show_win98_command_menu(current)
					get_viewport().set_input_as_handled()


func _show_win98_command_menu(combatant: Combatant) -> void:
	"""Show retro command menu for the combatant"""
	# Close any existing menu
	_close_win98_menu()

	# Get character's sprite position (use BattleManager.player_party for correct object identity)
	var combatant_idx = BattleManager.player_party.find(combatant)
	if combatant_idx < 0 or combatant_idx >= party_sprite_nodes.size():
		return

	var sprite = party_sprite_nodes[combatant_idx]
	if not is_instance_valid(sprite):
		return

	var viewport_size = get_viewport_rect().size

	# Convert sprite position to screen coordinates
	# The sprite is in 2D world space, need to get its screen position
	var canvas_transform = get_viewport().get_canvas_transform()
	var screen_pos = canvas_transform * sprite.global_position

	# Position menu to the LEFT of the character sprite (menu expands left)
	# Menu width is ~140, place it so the right edge is near the sprite
	var menu_x = clamp(screen_pos.x - 150, 10, viewport_size.x - 150)
	var menu_y = clamp(screen_pos.y - 40, 10, viewport_size.y - 120)
	var menu_pos = Vector2(menu_x, menu_y)

	# Get character class for styling
	var job_id = combatant.job.get("id", "fighter") if combatant.job else "fighter"

	# Build menu items with enemy targets as submenus
	var menu_items = _build_command_menu_items_with_targets(combatant)

	# Create menu directly as child with high z_index
	active_win98_menu = Win98MenuClass.new()
	active_win98_menu.expand_left = true  # Expand submenus to the left
	active_win98_menu.expand_up = true  # Expand submenus upward
	active_win98_menu.is_root_menu = true  # Root menu can't be closed
	active_win98_menu.z_index = 100  # Render on top
	active_win98_menu.visible = true  # Ensure visible
	add_child(active_win98_menu)
	active_win98_menu.setup(combatant.combatant_name, menu_items, menu_pos, job_id)

	# Connect signals
	active_win98_menu.item_selected.connect(_on_win98_menu_selection)
	active_win98_menu.menu_closed.connect(_on_win98_menu_closed)
	active_win98_menu.actions_submitted.connect(_on_win98_actions_submitted)
	active_win98_menu.defer_requested.connect(_on_win98_defer_requested)
	active_win98_menu.go_back_requested.connect(_on_win98_go_back_requested)

	# Set max queue size and current AP for display
	# Max 4 actions per advance (like Bravely Default's Brave system)
	# But limited by AP: can't go below -4 debt
	var ap_limit = combatant.current_ap + 4  # How many actions AP allows (can go to -4)
	var max_queue = mini(4, maxi(1, ap_limit))  # Cap at 4, minimum 1
	active_win98_menu.set_max_queue_size(max_queue)
	active_win98_menu.set_current_ap(combatant.current_ap)

	# Allow going back if not the first player in selection order
	var can_go_back = BattleManager.selection_index > 0
	active_win98_menu.set_can_go_back(can_go_back)

	# Apply command memory if enabled
	if command_memory_enabled and combatant.last_menu_selection != "":
		print("[CMD MEM] Applying %s -> %s" % [combatant.combatant_name, combatant.last_menu_selection])
		var submenu_memory = {}
		if combatant.last_attack_selection != "":
			submenu_memory["attack_menu"] = combatant.last_attack_selection
		if combatant.last_ability_selection != "":
			submenu_memory["ability_menu"] = combatant.last_ability_selection
		if combatant.last_item_selection != "":
			submenu_memory["item_menu"] = combatant.last_item_selection
		print("[CMD MEM] Submenu memory: %s" % str(submenu_memory))
		active_win98_menu.set_command_memory(combatant.last_menu_selection, submenu_memory)


func _build_command_menu_items_with_targets(combatant: Combatant) -> Array:
	"""Build command menu with enemy targets as submenus"""
	var items = []
	var alive_enemies = _get_alive_enemies()
	var canvas_transform = get_viewport().get_canvas_transform()

	# Autobattle option at the top
	items.append({
		"id": "autobattle",
		"label": "Auto",
		"data": {"action": "autobattle", "combatant": combatant}
	})

	# Attack -> submenu of enemy targets
	if alive_enemies.size() > 0:
		var enemy_targets = []
		for enemy in alive_enemies:
			var enemy_idx = test_enemies.find(enemy)
			var target_pos = Vector2.ZERO
			if enemy_idx >= 0 and enemy_idx < enemy_sprite_nodes.size():
				var sprite = enemy_sprite_nodes[enemy_idx]
				if is_instance_valid(sprite):
					target_pos = canvas_transform * sprite.global_position
			enemy_targets.append({
				"id": "attack_" + str(enemy_idx),
				"label": "%s (%d HP)" % [enemy.combatant_name, enemy.current_hp],
				"data": {"target_idx": enemy_idx, "action": "attack", "target_pos": target_pos}
			})
		items.append({
			"id": "attack_menu",
			"label": "Attack",
			"submenu": enemy_targets
		})
	else:
		items.append({
			"id": "attack",
			"label": "Attack",
			"data": null,
			"disabled": true
		})

	# Abilities -> submenu, each ability has enemy targets if offensive
	var abilities = combatant.job.get("abilities", []) if combatant.job else []
	if abilities.size() > 0:
		var ability_items = []
		for ability_id in abilities:
			var ability = JobSystem.get_ability(ability_id)
			if ability.is_empty():
				continue
			var mp_cost = ability.get("mp_cost", 0)
			var can_afford = combatant.current_mp >= mp_cost
			var target_type = ability.get("target_type", "single_enemy")

			# For enemy-targeting abilities, add enemy submenu
			if target_type == "single_enemy" and alive_enemies.size() > 0 and can_afford:
				var enemy_targets = []
				for enemy in alive_enemies:
					var enemy_idx = test_enemies.find(enemy)
					var target_pos = Vector2.ZERO
					if enemy_idx >= 0 and enemy_idx < enemy_sprite_nodes.size():
						var sprite = enemy_sprite_nodes[enemy_idx]
						if is_instance_valid(sprite):
							target_pos = canvas_transform * sprite.global_position
					enemy_targets.append({
						"id": "ability_" + ability_id + "_enemy_" + str(enemy_idx),
						"label": "%s (%d HP)" % [enemy.combatant_name, enemy.current_hp],
						"data": {"ability_id": ability_id, "target_idx": enemy_idx, "target_type": "enemy", "target_pos": target_pos}
					})
				ability_items.append({
					"id": "ability_menu_" + ability_id,
					"label": "%s (%d)" % [ability["name"], mp_cost],
					"submenu": enemy_targets,
					"disabled": not can_afford
				})
			# For ally-targeting abilities (heal, buff), add party submenu
			elif target_type == "single_ally" and can_afford:
				var ally_targets = []
				for i in range(party_members.size()):
					var member = party_members[i]
					if not is_instance_valid(member) or not member.is_alive:
						continue
					var target_pos = Vector2.ZERO
					if i < party_sprite_nodes.size():
						var sprite = party_sprite_nodes[i]
						if is_instance_valid(sprite):
							target_pos = canvas_transform * sprite.global_position
					ally_targets.append({
						"id": "ability_" + ability_id + "_ally_" + str(i),
						"label": "%s (%d/%d HP)" % [member.combatant_name, member.current_hp, member.max_hp],
						"data": {"ability_id": ability_id, "target_idx": i, "target_type": "ally", "target_pos": target_pos}
					})
				ability_items.append({
					"id": "ability_menu_" + ability_id,
					"label": "%s (%d)" % [ability["name"], mp_cost],
					"submenu": ally_targets,
					"disabled": not can_afford
				})
			# For dead ally targeting (Raise, Phoenix Down), show only dead party members
			elif target_type == "dead_ally" and can_afford:
				var dead_targets = []
				for i in range(party_members.size()):
					var member = party_members[i]
					if not is_instance_valid(member) or member.is_alive:
						continue  # Skip alive members
					var target_pos = Vector2.ZERO
					if i < party_sprite_nodes.size():
						var sprite = party_sprite_nodes[i]
						if is_instance_valid(sprite):
							target_pos = canvas_transform * sprite.global_position
					dead_targets.append({
						"id": "ability_" + ability_id + "_dead_" + str(i),
						"label": "%s (KO)" % member.combatant_name,
						"data": {"ability_id": ability_id, "target_idx": i, "target_type": "dead_ally", "target_pos": target_pos}
					})
				# Only show if there are dead allies to revive
				if dead_targets.size() > 0:
					ability_items.append({
						"id": "ability_menu_" + ability_id,
						"label": "%s (%d)" % [ability["name"], mp_cost],
						"submenu": dead_targets,
						"disabled": not can_afford
					})
				else:
					# Show disabled if no dead allies
					ability_items.append({
						"id": "ability_" + ability_id,
						"label": "%s (%d)" % [ability["name"], mp_cost],
						"data": {"ability_id": ability_id},
						"disabled": true
					})
			else:
				ability_items.append({
					"id": "ability_" + ability_id,
					"label": "%s (%d)" % [ability["name"], mp_cost],
					"data": {"ability_id": ability_id},
					"disabled": not can_afford
				})

		if ability_items.size() > 0:
			items.append({
				"id": "ability_menu",
				"label": "Ability",
				"submenu": ability_items
			})

	# Items submenu
	if not combatant.inventory.is_empty():
		var item_items = []
		for item_id in combatant.inventory.keys():
			var item = ItemSystem.get_item(item_id)
			if item.is_empty():
				continue
			var quantity = combatant.inventory[item_id]
			var target_type = item.get("target_type", ItemSystem.TargetType.SINGLE_ALLY)

			# For SINGLE_ALLY items, add party member target submenu
			if target_type == ItemSystem.TargetType.SINGLE_ALLY:
				var ally_targets = []
				for i in range(party_members.size()):
					var member = party_members[i]
					if not is_instance_valid(member) or not member.is_alive:
						continue
					var target_pos = Vector2.ZERO
					if i < party_sprite_nodes.size():
						var sprite = party_sprite_nodes[i]
						if is_instance_valid(sprite):
							target_pos = canvas_transform * sprite.global_position
					ally_targets.append({
						"id": "item_" + item_id + "_ally_" + str(i),
						"label": "%s (%d/%d HP)" % [member.combatant_name, member.current_hp, member.max_hp],
						"data": {"item_id": item_id, "target_idx": i, "target_type": "ally", "target_pos": target_pos}
					})
				if ally_targets.size() > 0:
					item_items.append({
						"id": "item_menu_" + item_id,
						"label": "%s x%d" % [item["name"], quantity],
						"submenu": ally_targets
					})
			# For SINGLE_ENEMY items, add enemy target submenu
			elif target_type == ItemSystem.TargetType.SINGLE_ENEMY and alive_enemies.size() > 0:
				var enemy_targets = []
				for enemy in alive_enemies:
					var enemy_idx = test_enemies.find(enemy)
					var target_pos = Vector2.ZERO
					if enemy_idx >= 0 and enemy_idx < enemy_sprite_nodes.size():
						var sprite = enemy_sprite_nodes[enemy_idx]
						if is_instance_valid(sprite):
							target_pos = canvas_transform * sprite.global_position
					enemy_targets.append({
						"id": "item_" + item_id + "_enemy_" + str(enemy_idx),
						"label": "%s (%d HP)" % [enemy.combatant_name, enemy.current_hp],
						"data": {"item_id": item_id, "target_idx": enemy_idx, "target_type": "enemy", "target_pos": target_pos}
					})
				item_items.append({
					"id": "item_menu_" + item_id,
					"label": "%s x%d" % [item["name"], quantity],
					"submenu": enemy_targets
				})
			else:
				# Other target types (ALL_ALLIES, ALL_ENEMIES, SELF) don't need submenu
				item_items.append({
					"id": "item_" + item_id,
					"label": "%s x%d" % [item["name"], quantity],
					"data": {"item_id": item_id}
				})
		if item_items.size() > 0:
			items.append({
				"id": "item_menu",
				"label": "Item",
				"submenu": item_items
			})

	# Defer - skip turn, gain +1 AP (only available if AP < 4)
	items.append({
		"id": "defer",
		"label": "Defer",
		"data": null,
		"disabled": combatant.current_ap >= 4
	})

	# Note: Advance (queue another action) is R key or Shift+Enter

	return items


func _build_command_menu_items(combatant: Combatant) -> Array:
	"""Build the command menu items for a combatant (legacy)"""
	var items = []

	# Attack
	items.append({
		"id": "attack",
		"label": "Attack",
		"data": null
	})

	# Abilities submenu
	var abilities = combatant.job.get("abilities", []) if combatant.job else []
	if abilities.size() > 0:
		var ability_items = []
		for ability_id in abilities:
			var ability = JobSystem.get_ability(ability_id)
			if ability.is_empty():
				continue
			var mp_cost = ability.get("mp_cost", 0)
			var can_afford = combatant.current_mp >= mp_cost
			ability_items.append({
				"id": "ability_" + ability_id,
				"label": "%s (%d MP)" % [ability["name"], mp_cost],
				"data": {"ability_id": ability_id},
				"disabled": not can_afford
			})
		if ability_items.size() > 0:
			items.append({
				"id": "ability_menu",
				"label": "Ability",
				"submenu": ability_items
			})

	# Items submenu
	if not combatant.inventory.is_empty():
		var item_items = []
		for item_id in combatant.inventory.keys():
			var item = ItemSystem.get_item(item_id)
			if item.is_empty():
				continue
			var quantity = combatant.inventory[item_id]
			item_items.append({
				"id": "item_" + item_id,
				"label": "%s x%d" % [item["name"], quantity],
				"data": {"item_id": item_id}
			})
		if item_items.size() > 0:
			items.append({
				"id": "item_menu",
				"label": "Item",
				"submenu": item_items
			})

	# Defer - skip turn, gain +1 AP (only if AP < 4)
	items.append({
		"id": "defer",
		"label": "Defer",
		"data": null,
		"disabled": combatant.current_ap >= 4
	})

	# Note: Advance is R key or Shift+Enter

	return items


func _on_win98_menu_selection(item_id: String, item_data: Variant) -> void:
	"""Handle Win98 menu item selection"""
	# Force close menu first before processing action
	_close_win98_menu()

	var alive_enemies = _get_alive_enemies()
	var current = BattleManager.current_combatant

	# Save command memory for next turn
	if current and command_memory_enabled:
		if item_id.begins_with("attack_"):
			current.last_menu_selection = "attack_menu"
			# Store the specific attack target (e.g., "attack_0")
			current.last_attack_selection = item_id
			print("[CMD MEM] %s -> attack_menu / %s (single action)" % [current.combatant_name, item_id])
		elif item_id.begins_with("ability_") or (item_data is Dictionary and item_data.has("ability_id")):
			current.last_menu_selection = "ability_menu"
			if item_data is Dictionary and item_data.has("ability_id"):
				var ability_id = item_data.get("ability_id", "")
				# Store the ability submenu item ID (ability_menu_X or ability_X)
				if item_id.begins_with("ability_menu_"):
					current.last_ability_selection = item_id.substr(0, item_id.find("_enemy_") if "_enemy_" in item_id else item_id.length())
				elif "_enemy_" in item_id or "_ally_" in item_id:
					# This is a target selection - find the parent ability menu item
					current.last_ability_selection = "ability_menu_" + ability_id
				else:
					current.last_ability_selection = item_id
			print("[CMD MEM] %s -> ability_menu / %s (single action)" % [current.combatant_name, current.last_ability_selection])
		elif item_id.begins_with("item_"):
			current.last_menu_selection = "item_menu"
			if item_data is Dictionary and item_data.has("item_id"):
				var i_id = item_data.get("item_id", "")
				# Store the item submenu item ID
				if "_ally_" in item_id or "_enemy_" in item_id:
					current.last_item_selection = "item_menu_" + i_id
				else:
					current.last_item_selection = item_id
			print("[CMD MEM] %s -> item_menu / %s (single action)" % [current.combatant_name, current.last_item_selection])

	# Autobattle - toggle autobattle ON for this player and execute their turn
	if item_id == "autobattle" and item_data is Dictionary:
		var combatant_for_auto = item_data.get("combatant", null)
		if combatant_for_auto:
			var char_id = combatant_for_auto.combatant_name.to_lower().replace(" ", "_")
			# Enable autobattle for this character
			AutobattleSystem.set_autobattle_enabled(char_id, true)
			SoundManager.play_ui("autobattle_on")
			log_message("[color=lime]%s: Autobattle enabled[/color]" % combatant_for_auto.combatant_name)
			print("[AUTOBATTLE] %s enabled - executing auto turn" % combatant_for_auto.combatant_name)
			# Let BattleManager handle the autobattle action
			BattleManager.execute_autobattle_for_current()
			_update_ui()
		return

	# Attack with target from menu tree (attack_0, attack_1, etc)
	if item_id.begins_with("attack_") and item_data is Dictionary:
		var target_idx = item_data.get("target_idx", -1)
		if target_idx >= 0 and target_idx < test_enemies.size():
			var target = test_enemies[target_idx]
			if is_instance_valid(target) and target.is_alive:
				_execute_attack(target)
			else:
				log_message("Target no longer valid!")
		return

	# Ability with target from menu tree (enemy or ally)
	if item_data is Dictionary and item_data.has("ability_id") and item_data.has("target_idx"):
		var ability_id = item_data.get("ability_id", "")
		var target_idx = item_data.get("target_idx", -1)
		var target_type = item_data.get("target_type", "enemy")

		if ability_id != "" and target_idx >= 0:
			var target: Combatant = null

			if target_type == "ally" or target_type == "dead_ally":
				# Ally target (party member) - alive or dead depending on ability
				if target_idx < party_members.size():
					target = party_members[target_idx]
			else:
				# Enemy target
				if target_idx < test_enemies.size():
					target = test_enemies[target_idx]

			# Check target validity based on ability type
			var is_valid_target = false
			if is_instance_valid(target):
				if target_type == "dead_ally":
					# Resurrection abilities need dead targets
					is_valid_target = not target.is_alive
				else:
					# Normal abilities need alive targets
					is_valid_target = target.is_alive

			if is_valid_target:
				_execute_ability(ability_id, target)
			else:
				log_message("Target no longer valid!")
		return

	# Ability without pre-selected target (self/ally targeting or all enemies)
	if item_id.begins_with("ability_") and item_data is Dictionary:
		var ability_id = item_data.get("ability_id", "")
		if ability_id != "":
			var ability = JobSystem.get_ability(ability_id)
			var target_type = ability.get("target_type", "single_enemy")

			match target_type:
				"all_enemies":
					if alive_enemies.size() > 0:
						_execute_ability(ability_id, alive_enemies[0], true)
					else:
						log_message("No valid targets!")
				"single_ally", "all_allies", "self":
					_execute_ability(ability_id, current if current else party_members[0])
				_:
					# Fallback for single_enemy if somehow no target submenu
					if alive_enemies.size() > 0:
						_execute_ability(ability_id, alive_enemies[0])
		return

	# Item usage with target from menu tree (ally or enemy)
	if item_id.begins_with("item_") and item_data is Dictionary:
		var i_id = item_data.get("item_id", "")
		if i_id == "":
			return

		# Check if item has pre-selected target from submenu
		if item_data.has("target_idx"):
			var target_idx = item_data.get("target_idx", -1)
			var target_type_str = item_data.get("target_type", "ally")
			var target: Combatant = null

			if target_type_str == "ally" and target_idx >= 0 and target_idx < party_members.size():
				target = party_members[target_idx]
			elif target_type_str == "enemy" and target_idx >= 0 and target_idx < test_enemies.size():
				target = test_enemies[target_idx]

			if is_instance_valid(target) and target.is_alive:
				BattleManager.player_item(i_id, [target])
			else:
				log_message("Target no longer valid!")
			return

		# Fallback: no pre-selected target, use default behavior
		var item = ItemSystem.get_item(i_id)
		var targets = []
		var target_type = item.get("target_type", ItemSystem.TargetType.SINGLE_ALLY)

		match target_type:
			ItemSystem.TargetType.SINGLE_ENEMY:
				if alive_enemies.size() > 0:
					targets = [alive_enemies[0]]
			ItemSystem.TargetType.ALL_ENEMIES:
				targets = alive_enemies
			ItemSystem.TargetType.SINGLE_ALLY, ItemSystem.TargetType.ALL_ALLIES, ItemSystem.TargetType.SELF:
				targets = [current if current else party_members[0]]

		if targets.size() > 0:
			BattleManager.player_item(i_id, targets)
		else:
			log_message("No valid targets!")
		return

	# Defer - skip turn, gain +1 AP
	if item_id == "defer":
		log_message("[color=cyan]%s defers![/color]" % current.combatant_name)
		BattleManager.player_defer()
		_update_ui()
		return


func _on_win98_menu_closed() -> void:
	"""Handle Win98 menu being closed"""
	active_win98_menu = null


func _on_win98_actions_submitted(actions: Array) -> void:
	"""Handle multiple actions submitted via Advance mode (Brave)"""
	active_win98_menu = null
	var current = BattleManager.current_combatant
	if not current:
		return

	# Store command memory from first action (for next turn)
	if actions.size() > 0 and command_memory_enabled:
		var first_action = actions[0]
		var mem_action_id: String = first_action.get("id", "")
		var mem_action_data = first_action.get("data", null)

		if mem_action_id.begins_with("attack_"):
			current.last_menu_selection = "attack_menu"
			current.last_attack_selection = mem_action_id
			print("[CMD MEM] %s -> attack_menu / %s (advance)" % [current.combatant_name, mem_action_id])
		elif mem_action_id.begins_with("ability_"):
			current.last_menu_selection = "ability_menu"
			if mem_action_data is Dictionary:
				var ability_id = mem_action_data.get("ability_id", "")
				if mem_action_id.begins_with("ability_menu_"):
					current.last_ability_selection = mem_action_id.substr(0, mem_action_id.find("_enemy_") if "_enemy_" in mem_action_id else mem_action_id.length())
				elif "_enemy_" in mem_action_id or "_ally_" in mem_action_id:
					current.last_ability_selection = "ability_menu_" + ability_id
				else:
					current.last_ability_selection = mem_action_id
			print("[CMD MEM] %s -> ability_menu / %s (advance)" % [current.combatant_name, current.last_ability_selection])
		elif mem_action_id.begins_with("item_"):
			current.last_menu_selection = "item_menu"
			if mem_action_data is Dictionary:
				var i_id = mem_action_data.get("item_id", "")
				if "_ally_" in mem_action_id or "_enemy_" in mem_action_id:
					current.last_item_selection = "item_menu_" + i_id
				else:
					current.last_item_selection = mem_action_id
			print("[CMD MEM] %s -> item_menu / %s (advance)" % [current.combatant_name, current.last_item_selection])

	# Convert menu actions to battle actions
	var battle_actions: Array[Dictionary] = []
	for action in actions:
		var action_id: String = action.get("id", "")
		var action_data = action.get("data", null)

		# Handle attack actions
		if action_id.begins_with("attack_") and action_data is Dictionary:
			var target_idx = action_data.get("target_idx", -1)
			if target_idx >= 0 and target_idx < test_enemies.size():
				var target = test_enemies[target_idx]
				# Skip dead enemies
				if is_instance_valid(target) and target.is_alive:
					battle_actions.append({"type": "attack", "target": target})
				else:
					log_message("[color=gray]Target no longer valid, skipping action[/color]")

		# Handle ability actions (enemy, ally, or dead ally targets)
		elif action_id.begins_with("ability_") and action_data is Dictionary:
			var ability_id = action_data.get("ability_id", "")
			var target_idx = action_data.get("target_idx", -1)
			var target_type = action_data.get("target_type", "enemy")

			if target_idx >= 0:
				var target: Combatant = null
				if (target_type == "ally" or target_type == "dead_ally") and target_idx < party_members.size():
					target = party_members[target_idx]
				elif target_idx < test_enemies.size():
					target = test_enemies[target_idx]

				if is_instance_valid(target):
					battle_actions.append({"type": "ability", "ability_id": ability_id, "targets": [target]})

		# Handle item actions (enemy or ally targets)
		elif action_id.begins_with("item_") and action_data is Dictionary:
			var item_id = action_data.get("item_id", "")
			var target_idx = action_data.get("target_idx", -1)
			var target_type = action_data.get("target_type", "ally")

			if target_idx >= 0:
				var target: Combatant = null
				if target_type == "ally" and target_idx < party_members.size():
					target = party_members[target_idx]
				elif target_idx < test_enemies.size():
					target = test_enemies[target_idx]

				if is_instance_valid(target):
					battle_actions.append({"type": "item", "item_id": item_id, "targets": [target]})

	if battle_actions.size() > 0:
		log_message("[color=yellow]%s advances with %d actions![/color]" % [current.combatant_name, battle_actions.size()])
		BattleManager.player_advance(battle_actions)
		_update_ui()


func _on_win98_defer_requested() -> void:
	"""Handle L button defer request (no queue)"""
	active_win98_menu = null
	var current = BattleManager.current_combatant
	if not current:
		return

	log_message("[color=cyan]%s defers![/color]" % current.combatant_name)
	BattleManager.player_defer()
	_update_ui()


func _on_win98_go_back_requested() -> void:
	"""Handle B button request to go back to previous player"""
	# Force close the current menu immediately
	if active_win98_menu and is_instance_valid(active_win98_menu):
		active_win98_menu.force_close()
		active_win98_menu = null
	BattleManager.go_back_to_previous_player()

	# Disable autobattle for the player we went back to (they're taking manual control)
	var new_current = BattleManager.current_combatant
	if new_current and new_current in party_members:
		var char_id = new_current.combatant_name.to_lower().replace(" ", "_")
		if AutobattleSystem.is_autobattle_enabled(char_id):
			AutobattleSystem.set_autobattle_enabled(char_id, false)
			SoundManager.play_ui("autobattle_off")
			log_message("[color=gray]%s: Autobattle disabled (manual control)[/color]" % new_current.combatant_name)
			_update_ui()


func _close_win98_menu() -> void:
	"""Close the active Win98 menu"""
	if active_win98_menu and is_instance_valid(active_win98_menu):
		active_win98_menu.force_close()
		active_win98_menu = null


## Damage Numbers

func _on_damage_dealt(target: Combatant, amount: int, is_crit: bool) -> void:
	"""Show floating damage number near target"""
	var pos = _get_combatant_sprite_position(target)
	if pos != Vector2.ZERO:
		_spawn_damage_number(pos, amount, false, is_crit)
	else:
		print("[DMG NUM] Could not find sprite position for %s" % target.combatant_name)


func _on_healing_done(target: Combatant, amount: int) -> void:
	"""Show floating heal number near target"""
	var pos = _get_combatant_sprite_position(target)
	if pos != Vector2.ZERO:
		_spawn_damage_number(pos, amount, true, false)


func _on_battle_log_message(message: String) -> void:
	"""Display battle log message from BattleManager"""
	if battle_log:
		battle_log.append_text(message + "\n")
		battle_log.scroll_to_line(battle_log.get_line_count())


func _on_one_shot_achieved(rank: String, setup_turns: int) -> void:
	"""Display one-shot visual feedback when all enemies are defeated in a single execution phase"""
	var exp_mult = BattleManager.get_one_shot_exp_multiplier()
	print("[ONE-SHOT UI] Displaying one-shot flash! Rank: %s, Setup: %d, EXP x%.1f" % [rank, setup_turns, exp_mult])

	# Create the one-shot flash overlay
	var flash_container = Control.new()
	flash_container.name = "OneShotFlash"
	flash_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash_container)

	# Screen flash effect (brief white overlay)
	var flash_bg = ColorRect.new()
	flash_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_bg.color = Color(1.0, 1.0, 0.8, 0.6)
	flash_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_container.add_child(flash_bg)

	# Flash out quickly
	var flash_tween = create_tween()
	flash_tween.tween_property(flash_bg, "color:a", 0.0, 0.4)
	flash_tween.tween_callback(func(): flash_bg.queue_free())

	# "ONE-SHOT!" text label
	var one_shot_label = Label.new()
	one_shot_label.text = "ONE-SHOT!"
	one_shot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	one_shot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	one_shot_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	one_shot_label.offset_top = -60
	one_shot_label.offset_bottom = 0
	one_shot_label.offset_left = -200
	one_shot_label.offset_right = 200
	one_shot_label.add_theme_font_size_override("font_size", 48)
	one_shot_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.0))
	one_shot_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	one_shot_label.add_theme_constant_override("shadow_offset_x", 3)
	one_shot_label.add_theme_constant_override("shadow_offset_y", 3)
	one_shot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_container.add_child(one_shot_label)

	# Rank text below
	var rank_label = Label.new()
	rank_label.text = "Rank: %s" % rank
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rank_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	rank_label.offset_top = 0
	rank_label.offset_bottom = 40
	rank_label.offset_left = -200
	rank_label.offset_right = 200
	rank_label.add_theme_font_size_override("font_size", 28)
	var rank_color = Color(1.0, 0.9, 0.0) if rank == "S" else Color(0.6, 1.0, 0.6) if rank == "A" else Color(0.6, 0.8, 1.0)
	rank_label.add_theme_color_override("font_color", rank_color)
	rank_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	rank_label.add_theme_constant_override("shadow_offset_x", 2)
	rank_label.add_theme_constant_override("shadow_offset_y", 2)
	rank_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_container.add_child(rank_label)

	# EXP bonus text
	var bonus_label = Label.new()
	bonus_label.text = "EXP x%.1f!" % exp_mult
	bonus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bonus_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bonus_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	bonus_label.offset_top = 40
	bonus_label.offset_bottom = 75
	bonus_label.offset_left = -200
	bonus_label.offset_right = 200
	bonus_label.add_theme_font_size_override("font_size", 22)
	bonus_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	bonus_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	bonus_label.add_theme_constant_override("shadow_offset_x", 2)
	bonus_label.add_theme_constant_override("shadow_offset_y", 2)
	bonus_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_container.add_child(bonus_label)

	# Animate: scale up from 0, hold, then fade out
	one_shot_label.scale = Vector2(0.1, 0.1)
	one_shot_label.pivot_offset = one_shot_label.size / 2
	rank_label.modulate.a = 0.0
	bonus_label.modulate.a = 0.0

	var text_tween = create_tween()
	# Scale up one-shot text
	text_tween.tween_property(one_shot_label, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Fade in rank
	text_tween.tween_property(rank_label, "modulate:a", 1.0, 0.2)
	# Fade in bonus
	text_tween.tween_property(bonus_label, "modulate:a", 1.0, 0.2)
	# Hold for a moment
	text_tween.tween_interval(1.5)
	# Fade everything out
	text_tween.tween_property(flash_container, "modulate:a", 0.0, 0.5)
	# Clean up
	text_tween.tween_callback(func(): flash_container.queue_free())


func _on_autobattle_victory(multiplier: float, total_turns: int) -> void:
	"""Display autobattle victory visual feedback when entire battle was won on autobattle"""
	var has_one_shot = BattleManager.get_one_shot_achieved()
	print("[AUTOBATTLE UI] Displaying autobattle flash! Turns: %d, EXP x%.1f (stacked: %s)" % [total_turns, multiplier, has_one_shot])

	# Offset down when stacking with one-shot overlay (both show simultaneously)
	# One-shot extends to y=75 from center, add gap so they don't overlap
	var y_offset = 155 if has_one_shot else 0

	# Create the autobattle flash overlay
	var flash_container = Control.new()
	flash_container.name = "AutobattleFlash"
	flash_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash_container)

	# Screen flash effect (cyan tint) — skip if one-shot already flashing
	if not has_one_shot:
		var flash_bg = ColorRect.new()
		flash_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		flash_bg.color = Color(0.4, 0.8, 1.0, 0.5)
		flash_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flash_container.add_child(flash_bg)
		var flash_tween = create_tween()
		flash_tween.tween_property(flash_bg, "color:a", 0.0, 0.4)
		flash_tween.tween_callback(func(): flash_bg.queue_free())

	# "AUTO-BATTLE!" text label
	var auto_label = Label.new()
	auto_label.text = "AUTO-BATTLE!"
	auto_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	auto_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	auto_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	auto_label.offset_top = -60 + y_offset
	auto_label.offset_bottom = 0 + y_offset
	auto_label.offset_left = -200
	auto_label.offset_right = 200
	auto_label.add_theme_font_size_override("font_size", 42)
	auto_label.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
	auto_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	auto_label.add_theme_constant_override("shadow_offset_x", 3)
	auto_label.add_theme_constant_override("shadow_offset_y", 3)
	auto_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_container.add_child(auto_label)

	# Turns label
	var turns_label = Label.new()
	turns_label.text = "%d turns automated" % total_turns
	turns_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turns_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	turns_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	turns_label.offset_top = 0 + y_offset
	turns_label.offset_bottom = 35 + y_offset
	turns_label.offset_left = -200
	turns_label.offset_right = 200
	turns_label.add_theme_font_size_override("font_size", 22)
	turns_label.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	turns_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	turns_label.add_theme_constant_override("shadow_offset_x", 2)
	turns_label.add_theme_constant_override("shadow_offset_y", 2)
	turns_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_container.add_child(turns_label)

	# EXP bonus label
	var bonus_label = Label.new()
	bonus_label.text = "EXP x%.1f!" % multiplier
	bonus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bonus_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bonus_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	bonus_label.offset_top = 35 + y_offset
	bonus_label.offset_bottom = 70 + y_offset
	bonus_label.offset_left = -200
	bonus_label.offset_right = 200
	bonus_label.add_theme_font_size_override("font_size", 22)
	bonus_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	bonus_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	bonus_label.add_theme_constant_override("shadow_offset_x", 2)
	bonus_label.add_theme_constant_override("shadow_offset_y", 2)
	bonus_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_container.add_child(bonus_label)

	# Animate: scale-in, hold, fade out (no delay — shows simultaneously with one-shot)
	auto_label.scale = Vector2(0.1, 0.1)
	auto_label.pivot_offset = auto_label.size / 2
	turns_label.modulate.a = 0.0
	bonus_label.modulate.a = 0.0

	var tween = create_tween()
	# Scale up autobattle text
	tween.tween_property(auto_label, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Fade in turns
	tween.tween_property(turns_label, "modulate:a", 1.0, 0.2)
	# Fade in bonus
	tween.tween_property(bonus_label, "modulate:a", 1.0, 0.2)
	# Hold
	tween.tween_interval(1.5)
	# Fade out
	tween.tween_property(flash_container, "modulate:a", 0.0, 0.5)
	# Clean up
	tween.tween_callback(func(): flash_container.queue_free())


func _on_monster_summoned(monster_type: String, summoner: Combatant) -> void:
	"""Handle monster summon - spawn new enemy mid-battle"""
	# Find the monster type data
	var monster_data = null
	for mt in MONSTER_TYPES:
		if mt["id"] == monster_type:
			monster_data = mt
			break

	if not monster_data:
		push_warning("Unknown monster type for summon: %s" % monster_type)
		return

	# Create the new enemy
	var enemy = Combatant.new()
	var stats = monster_data["stats"].duplicate()

	# Count existing enemies of this type for naming
	var type_count = 0
	for e in test_enemies:
		if e.get_meta("monster_type", "") == monster_type:
			type_count += 1
	if type_count > 0:
		stats["name"] = monster_data["name"] + " " + ["A", "B", "C", "D", "E"][mini(type_count, 4)]
	else:
		stats["name"] = monster_data["name"]

	enemy.initialize(stats)
	add_child(enemy)
	enemy.set_meta("monster_type", monster_type)

	# Add weaknesses/resistances
	for weakness in monster_data.get("weaknesses", []):
		enemy.elemental_weaknesses.append(weakness)
	for resistance in monster_data.get("resistances", []):
		enemy.elemental_resistances.append(resistance)

	# Find a position for the new enemy
	var new_idx = test_enemies.size()
	enemy.hp_changed.connect(_on_enemy_hp_changed.bind(new_idx))
	enemy.died.connect(_on_enemy_died.bind(new_idx))

	test_enemies.append(enemy)

	# Add to BattleManager's enemy party
	BattleManager.enemy_party.append(enemy)
	BattleManager.all_combatants.append(enemy)

	# Create sprite for the new enemy
	var sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = _get_monster_sprite_frames(monster_type)

	# Position near the summoner or in an available slot
	var base_pos = Vector2(200, 300)
	if enemy_positions.size() > new_idx:
		sprite.position = enemy_positions[new_idx].global_position
	else:
		# Calculate position based on existing enemies
		sprite.position = base_pos + Vector2(new_idx * 80, (new_idx % 2) * 50)

	sprite.play("idle")
	sprite.scale = Vector2(0.01, 0.01)  # Start nearly invisible (not ZERO to avoid tween issues)

	$BattleField/EnemySprites.add_child(sprite)
	enemy_sprite_nodes.append(sprite)

	# Create animator
	var animator = BattleAnimatorClass.new()
	animator.setup(sprite)
	add_child(animator)
	enemy_animators.append(animator)

	# Add label
	_add_sprite_label(sprite, enemy.combatant_name.to_upper(), Vector2(-20, 40))

	# Spawn animation - pop in with flash
	var tween = create_tween()
	tween.tween_property(sprite, "scale", Vector2(1.3, 1.3), 0.15)
	tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.1)
	# Guarantee final scale in case tween is interrupted
	tween.finished.connect(func(): sprite.scale = Vector2(1.0, 1.0))

	# Flash effect at spawn position
	EffectSystem.spawn_effect(EffectSystem.EffectType.BUFF, sprite.global_position)

	# Log message
	log_message("[color=red]%s appears![/color]" % stats["name"])

	_update_ui()


func _get_combatant_sprite_position(combatant: Combatant) -> Vector2:
	"""Get the screen position of a combatant's sprite"""
	# Check party members (use BattleManager's array for consistency)
	var party_idx = BattleManager.player_party.find(combatant)
	if party_idx >= 0 and party_idx < party_sprite_nodes.size():
		var sprite = party_sprite_nodes[party_idx]
		if is_instance_valid(sprite):
			return sprite.global_position

	# Check enemies (use BattleManager's array for consistency)
	var enemy_idx = BattleManager.enemy_party.find(combatant)
	if enemy_idx >= 0 and enemy_idx < enemy_sprite_nodes.size():
		var sprite = enemy_sprite_nodes[enemy_idx]
		if is_instance_valid(sprite):
			return sprite.global_position

	return Vector2.ZERO


func _spawn_damage_number(pos: Vector2, amount: int, is_heal: bool, is_crit: bool) -> void:
	"""Spawn a floating damage/heal number"""
	var dmg_num = DamageNumber.new()
	dmg_num.setup(amount, is_heal, is_crit)
	# Offset slightly upward from sprite center
	dmg_num.position = pos + Vector2(randf_range(-10, 10), -30)
	add_child(dmg_num)


func _check_danger_music() -> void:
	"""Switch to danger music if any player is critically low HP or dead"""
	if _battle_ended:
		return

	# Check if any party member is dead or critically low HP
	var any_in_danger = false
	var any_dead = false
	for member in party_members:
		if member and is_instance_valid(member):
			if not member.is_alive:
				any_dead = true
				any_in_danger = true
				break
			else:
				var hp_percent = float(member.current_hp) / float(member.max_hp)
				if hp_percent < DANGER_HP_THRESHOLD:
					any_in_danger = true
					break

	# Switch music if danger state changed
	# Once in danger (dead or critical), stay in danger until healed above threshold
	if any_in_danger and not _is_danger_music:
		_is_danger_music = true
		SoundManager.play_music("danger")
		if any_dead:
			print("[MUSIC] Switched to DANGER music - party member down!")
		else:
			print("[MUSIC] Switched to DANGER music - player critically low!")
	elif not any_in_danger and _is_danger_music:
		_is_danger_music = false
		SoundManager.play_music(_base_music_track)
		print("[MUSIC] Switched back to %s music - party recovered" % _base_music_track)
