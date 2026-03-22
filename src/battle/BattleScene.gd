extends Control

## BattleScene - FF-style battle UI with sprites
## Enemies on left, party on right, classic JRPG layout

# Preload class dependencies to ensure they're registered before use
const BattleAnimatorClass = preload("res://src/battle/BattleAnimator.gd")
const RetroFontClass = preload("res://src/ui/RetroFont.gd")
const Win98MenuClass = preload("res://src/ui/Win98Menu.gd")
const AutobattleToggleUIClass = preload("res://src/ui/autobattle/AutobattleToggleUI.gd")
const BattleDialogueClass = preload("res://src/ui/BattleDialogue.gd")
const BattleBackgroundClass = preload("res://src/battle/BattleBackground.gd")
const SnesPartySprites = preload("res://src/battle/sprites/SnesPartySprites.gd")
const HybridSpriteLoaderClass = preload("res://src/battle/sprites/HybridSpriteLoader.gd")
const BattleEnemySpawnerClass = preload("res://src/battle/BattleEnemySpawner.gd")
const BattleUIManagerClass = preload("res://src/battle/BattleUIManager.gd")
const BattleCommandMenuClass = preload("res://src/battle/BattleCommandMenu.gd")
const BattleResultsDisplayClass = preload("res://src/battle/BattleResultsDisplay.gd")

const JOB_DISPLAY_HEIGHTS: Dictionary = {
	"fighter": 375.0,
	"cleric": 180.0,
	"mage": 300.0,
	"rogue": 300.0,
	"bard": 300.0,
}

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
var _current_popup: PopupMenu = null  # Store popup reference for cleanup

## External party flag
var _has_external_party: bool = false

## Battle end state
var _battle_ended: bool = false
var _battle_victory: bool = false
var managed_by_game_loop: bool = false  # When true, don't handle restart internally
var command_memory_enabled: bool = true  # Remember last command per character
var force_miniboss: bool = false  # When true, spawn a miniboss instead of regular enemies
var forced_enemies: Array = []  # When set, spawn these specific enemies (e.g., ["cave_rat_king"])
var encounter_enemies: Array = []  # When set, spawn these encounter enemies from exploration (e.g., ["clockwork_sentinel", "steam_rat"])
var autogrind_enemy_data: Array = []  # When set, spawn pre-configured enemies from autogrind system

## Battle speed settings
const BATTLE_SPEEDS: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0]
const BATTLE_SPEED_LABELS: Array[String] = ["0.25x", "0.5x", "1x", "2x", "4x", "8x", "16x"]
static var _battle_speed_index: int = 1  # Persists across battles (default 0.5x)
var _speed_indicator: RichTextLabel = null
var _battle_counter_label: RichTextLabel = null

## Turbo mode - skip animations and delays for fastest possible battles
var turbo_mode: bool = false

## Track current ability being executed so damage callback plays the right sound
var _current_ability_id: String = ""

## Autogrind console mode — replaces battle log with grind stats feed
var autogrind_console_mode: bool = false
var _autogrind_console: RichTextLabel = null

## Autobattle toggle UI
var _autobattle_toggle_ui: AutobattleToggleUIClass = null

## Danger music state
var _is_danger_music: bool = false

## Idle animation state (sway/breathing)
var _idle_time: float = 0.0
var _enemy_base_positions: Array[Vector2] = []
var _party_base_positions: Array[Vector2] = []

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

## Composed subsystems (extracted from BattleScene)
var _enemy_spawner: BattleEnemySpawnerClass = null
var _ui_manager: BattleUIManagerClass = null
var _command_menu: BattleCommandMenuClass = null
var _results_display: BattleResultsDisplayClass = null

## Tutorial hints (persists across battles via static-like save)
static var _hints_shown: Dictionary = {}  # {"hint_id": true}


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
	# Initialize composed subsystems
	_enemy_spawner = BattleEnemySpawnerClass.new(self)
	_ui_manager = BattleUIManagerClass.new(self)
	_command_menu = BattleCommandMenuClass.new(self)
	_results_display = BattleResultsDisplayClass.new(self)

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
	BattleManager.attack_missed.connect(_on_attack_missed)
	BattleManager.healing_done.connect(_on_healing_done)
	BattleManager.battle_log_message.connect(_on_battle_log_message)
	BattleManager.monster_summoned.connect(_on_monster_summoned)
	BattleManager.one_shot_achieved.connect(_on_one_shot_achieved)
	BattleManager.autobattle_victory.connect(_on_autobattle_victory)
	BattleManager.group_attack_executing.connect(_on_group_attack_executing)

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


func _exit_tree() -> void:
	"""Cleanup signal connections when scene is freed"""
	# Disconnect from BattleManager signals to prevent memory leaks
	if BattleManager.battle_started.is_connected(_on_battle_started):
		BattleManager.battle_started.disconnect(_on_battle_started)
	if BattleManager.battle_ended.is_connected(_on_battle_ended):
		BattleManager.battle_ended.disconnect(_on_battle_ended)
	if BattleManager.selection_phase_started.is_connected(_on_selection_phase_started):
		BattleManager.selection_phase_started.disconnect(_on_selection_phase_started)
	if BattleManager.selection_turn_started.is_connected(_on_selection_turn_started):
		BattleManager.selection_turn_started.disconnect(_on_selection_turn_started)
	if BattleManager.selection_turn_ended.is_connected(_on_selection_turn_ended):
		BattleManager.selection_turn_ended.disconnect(_on_selection_turn_ended)
	if BattleManager.execution_phase_started.is_connected(_on_execution_phase_started):
		BattleManager.execution_phase_started.disconnect(_on_execution_phase_started)
	if BattleManager.action_executing.is_connected(_on_action_executing):
		BattleManager.action_executing.disconnect(_on_action_executing)
	if BattleManager.action_executed.is_connected(_on_action_executed):
		BattleManager.action_executed.disconnect(_on_action_executed)
	if BattleManager.round_ended.is_connected(_on_round_ended):
		BattleManager.round_ended.disconnect(_on_round_ended)
	if BattleManager.damage_dealt.is_connected(_on_damage_dealt):
		BattleManager.damage_dealt.disconnect(_on_damage_dealt)
	if BattleManager.attack_missed.is_connected(_on_attack_missed):
		BattleManager.attack_missed.disconnect(_on_attack_missed)
	if BattleManager.healing_done.is_connected(_on_healing_done):
		BattleManager.healing_done.disconnect(_on_healing_done)
	if BattleManager.battle_log_message.is_connected(_on_battle_log_message):
		BattleManager.battle_log_message.disconnect(_on_battle_log_message)
	if BattleManager.monster_summoned.is_connected(_on_monster_summoned):
		BattleManager.monster_summoned.disconnect(_on_monster_summoned)
	if BattleManager.one_shot_achieved.is_connected(_on_one_shot_achieved):
		BattleManager.one_shot_achieved.disconnect(_on_one_shot_achieved)
	if BattleManager.autobattle_victory.is_connected(_on_autobattle_victory):
		BattleManager.autobattle_victory.disconnect(_on_autobattle_victory)
	if BattleManager.group_attack_executing.is_connected(_on_group_attack_executing):
		BattleManager.group_attack_executing.disconnect(_on_group_attack_executing)

	# Reset engine time scale in case battle speed was altered
	Engine.time_scale = 1.0

	# Cleanup popup menu if open
	_cleanup_popup()


func _create_battle_background() -> void:
	"""Create the dynamic battle background based on terrain"""
	_battle_background = BattleBackgroundClass.new()
	_battle_background.name = "BattleBackground"
	# Insert at index 0 to be behind everything
	add_child(_battle_background)
	move_child(_battle_background, 0)
	# Apply current terrain
	_battle_background.set_terrain_from_string(_current_terrain)
	# Give EffectSystem a reference so it can tint the background during spells
	EffectSystem.battle_background = _battle_background


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

	# Battle counter (shown during autogrind)
	_battle_counter_label = RichTextLabel.new()
	_battle_counter_label.name = "BattleCounter"
	_battle_counter_label.bbcode_enabled = true
	_battle_counter_label.fit_content = true
	_battle_counter_label.scroll_active = false
	_battle_counter_label.custom_minimum_size = Vector2(120, 24)
	_battle_counter_label.add_theme_font_size_override("normal_font_size", 14)
	_battle_counter_label.position = Vector2(8, 34)
	_battle_counter_label.visible = false
	$UI.add_child(_battle_counter_label)

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
		5:  # 8x - extreme (red)
			text = "[color=#cc2222]▸▸▸▸[/color] [color=#ff3300]%s[/color] [color=#aa1100]◂◂◂◂[/color]" % speed_label
		6:  # 16x - maximum (magenta)
			text = "[color=#cc22cc]▸▸▸▸▸[/color] [color=#ff00ff]%s[/color] [color=#aa00aa]◂◂◂◂◂[/color]" % speed_label

	if turbo_mode:
		text += " [color=#ff4444]TURBO[/color]"

	_speed_indicator.text = text

	if turbo_mode:
		if _speed_indicator:
			_speed_indicator.add_theme_font_size_override("normal_font_size", 22)
			_speed_indicator.custom_minimum_size = Vector2(160, 32)
	else:
		if _speed_indicator:
			_speed_indicator.add_theme_font_size_override("normal_font_size", 16)
			_speed_indicator.custom_minimum_size = Vector2(80, 24)


func set_battle_counter(battle_num: int) -> void:
	if _battle_counter_label:
		_battle_counter_label.visible = true
		_battle_counter_label.text = "[color=#aaaacc]#%d[/color]" % battle_num


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
	SoundManager.play_ui("speed_change")
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

	# Create Mira (Cleric)
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
	JobSystem.assign_job(mira, "cleric")
	EquipmentSystem.equip_weapon(mira, "oak_staff")
	EquipmentSystem.equip_armor(mira, "cloth_robe")
	EquipmentSystem.equip_accessory(mira, "magic_ring")
	mira.learn_passive("magic_boost")
	mira.learn_passive("mp_boost")
	PassiveSystem.equip_passive(mira, "magic_boost")
	PassiveSystem.equip_passive(mira, "mp_boost")
	party_members.append(mira)

	# Create Zack (Rogue)
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
	JobSystem.assign_job(zack, "rogue")
	EquipmentSystem.equip_weapon(zack, "iron_dagger")
	EquipmentSystem.equip_armor(zack, "thief_garb")
	EquipmentSystem.equip_accessory(zack, "speed_boots")
	zack.learn_passive("critical_strike")
	zack.learn_passive("speed_boost")
	PassiveSystem.equip_passive(zack, "critical_strike")
	PassiveSystem.equip_passive(zack, "speed_boost")
	party_members.append(zack)

	# Create Vex (Mage)
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
	JobSystem.assign_job(vex, "mage")
	EquipmentSystem.equip_weapon(vex, "shadow_rod")
	EquipmentSystem.equip_armor(vex, "dark_robe")
	EquipmentSystem.equip_accessory(vex, "mp_amulet")
	vex.learn_passive("magic_boost")
	vex.learn_passive("mp_efficiency")
	PassiveSystem.equip_passive(vex, "magic_boost")
	PassiveSystem.equip_passive(vex, "mp_efficiency")
	party_members.append(vex)


## Monster type constants (delegated to BattleEnemySpawner)
var MONSTER_TYPES: Array:
	get: return BattleEnemySpawnerClass.MONSTER_TYPES


## Spawn methods (delegated to BattleEnemySpawner)
func _spawn_enemies() -> void:
	_enemy_spawner.spawn_enemies()

func _spawn_from_data(enemy_data_array: Array) -> void:
	_enemy_spawner.spawn_from_data(enemy_data_array)

func _spawn_forced_enemies() -> void:
	_enemy_spawner.spawn_forced_enemies()

func _spawn_encounter_enemies() -> void:
	_enemy_spawner.spawn_encounter_enemies()

func _load_monsters_data() -> Dictionary:
	return _enemy_spawner.load_monsters_data()

func _spawn_miniboss() -> void:
	_enemy_spawner.spawn_miniboss()


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

	# Clear idle position caches when rebuilding sprites
	_enemy_base_positions.clear()
	_party_base_positions.clear()
	_idle_time = 0.0

	# Create party member sprites
	for i in range(party_members.size()):
		var member = party_members[i]
		var sprite = AnimatedSprite2D.new()

		# Choose sprite based on job - SNES-style 32x48 sprites for all jobs
		var job_id = member.job.get("id", "fighter") if member.job else "fighter"
		var sec_job_id = member.secondary_job_id if member.secondary_job_id else ""
		var weapon_id = member.equipped_weapon if member.equipped_weapon else ""
		var armor_id = member.equipped_armor if member.equipped_armor else ""
		var accessory_id = member.equipped_accessory if member.equipped_accessory else ""
		var custom = member.get("customization") if "customization" in member else null
		sprite.sprite_frames = HybridSpriteLoaderClass.load_sprite_frames(
			custom, job_id, sec_job_id, weapon_id, armor_id, accessory_id)
		# Per-job display height targets (in pixels) for battle sprites.
		# Tune these to align characters visually despite different art sizes within frames.
		var target_height = JOB_DISPLAY_HEIGHTS.get(job_id, 300.0)

		# Auto-scale based on frame height and per-job target
		var _sprite_scale = 3.0
		if sprite.sprite_frames and sprite.sprite_frames.has_animation(&"idle"):
			if sprite.sprite_frames.get_frame_count(&"idle") > 0:
				var _ftex = sprite.sprite_frames.get_frame_texture(&"idle", 0)
				if _ftex and _ftex.get_height() > 128:
					_sprite_scale = target_height / float(_ftex.get_height())
				elif _ftex and _ftex.get_height() > 48:
					_sprite_scale = 144.0 / float(_ftex.get_height())
		sprite.scale = Vector2(_sprite_scale, _sprite_scale)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

		# V-formation depth stagger: front members (index 0,1) lower, back members higher
		# Stagger: i=0 -> +10px, i=1 -> +5px, i=2 -> -5px, i=3 -> -10px
		var party_y_offsets: Array[float] = [10.0, 5.0, -5.0, -10.0]
		var base_pos = party_positions[i].global_position if i < party_positions.size() else Vector2(600, 100 + i * 100)
		var party_y_stagger = party_y_offsets[i] if i < party_y_offsets.size() else 0.0
		base_pos.y += party_y_stagger
		sprite.position = base_pos
		_party_base_positions.append(base_pos)

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

		# Depth stagger: index 0 is closer (lower/larger), higher indices are farther
		# Y stagger: 0->+0px, 1->-15px, 2->-30px
		var enemy_y_stagger = float(i) * -15.0
		# Scale stagger: 0->1.0x, 1->0.95x, 2->0.9x
		var depth_scale = 1.0 - float(i) * 0.05
		var base_enemy_pos = enemy_positions[i].global_position if i < enemy_positions.size() else Vector2(200 + i * 100, 300)
		base_enemy_pos.y += enemy_y_stagger
		sprite.position = base_enemy_pos
		sprite.scale = Vector2(depth_scale, depth_scale)
		_enemy_base_positions.append(base_enemy_pos)

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
	var external_frames = HybridSpriteLoaderClass.load_monster_sprite_frames(monster_id)
	if external_frames:
		return external_frames

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
		"fire_dragon":
			return BattleAnimatorClass.create_fire_dragon_sprite_frames()
		"ice_dragon":
			return BattleAnimatorClass.create_ice_dragon_sprite_frames()
		"lightning_dragon":
			return BattleAnimatorClass.create_lightning_dragon_sprite_frames()
		"shadow_dragon":
			return BattleAnimatorClass.create_shadow_dragon_sprite_frames()
		"clockwork_sentinel":
			return BattleAnimatorClass.create_clockwork_sentinel_sprite_frames()
		"steam_rat":
			return BattleAnimatorClass.create_steam_rat_sprite_frames()
		"brass_golem":
			return BattleAnimatorClass.create_brass_golem_sprite_frames()
		"cog_swarm":
			return BattleAnimatorClass.create_cog_swarm_sprite_frames()
		"pipe_phantom":
			return BattleAnimatorClass.create_pipe_phantom_sprite_frames()
		"assembly_line_automaton":
			return BattleAnimatorClass.create_assembly_line_automaton_sprite_frames()
		"shift_supervisor":
			return BattleAnimatorClass.create_shift_supervisor_sprite_frames()
		"rust_elemental":
			return BattleAnimatorClass.create_rust_elemental_sprite_frames()
		"toxic_sludge":
			return BattleAnimatorClass.create_toxic_sludge_sprite_frames()
		"conveyor_gremlin":
			return BattleAnimatorClass.create_conveyor_gremlin_sprite_frames()
		# Suburban monsters (MonsterSpritesExtra)
		"new_age_retro_hippie":
			return MonsterSpritesExtra.create_new_age_retro_hippie_sprite_frames()
		"spiteful_crow":
			return MonsterSpritesExtra.create_spiteful_crow_sprite_frames()
		"skate_punk":
			return MonsterSpritesExtra.create_skate_punk_sprite_frames()
		"unassuming_dog":
			return MonsterSpritesExtra.create_unassuming_dog_sprite_frames()
		"cranky_lady":
			return MonsterSpritesExtra.create_cranky_lady_sprite_frames()
		"abstract_art":
			return MonsterSpritesExtra.create_abstract_art_sprite_frames()
		"runaway_dog":
			return MonsterSpritesExtra.create_runaway_dog_sprite_frames()
		"couch_potato":
			return MonsterSpritesExtra.create_couch_potato_sprite_frames()
		"mall_cop":
			return MonsterSpritesExtra.create_mall_cop_sprite_frames()
		"prank_caller":
			return MonsterSpritesExtra.create_prank_caller_sprite_frames()
		# Meta/Glitch monsters (MonsterSpritesExtra)
		"corrupted_sprite":
			return MonsterSpritesExtra.create_corrupted_sprite_sprite_frames()
		"glitch_entity":
			return MonsterSpritesExtra.create_glitch_entity_sprite_frames()
		"script_error":
			return MonsterSpritesExtra.create_script_error_sprite_frames()
		"null_entity":
			return MonsterSpritesExtra.create_null_entity_sprite_frames()
		"rogue_process":
			return MonsterSpritesExtra.create_rogue_process_sprite_frames()
		"memory_leak":
			return MonsterSpritesExtra.create_memory_leak_sprite_frames()
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


func _update_ui() -> void:
	_ui_manager.update_ui()


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



func reveal_enemy_stats(enemy: Combatant) -> void:
	_ui_manager.reveal_enemy_stats(enemy)


func _update_turn_info() -> void:
	_ui_manager.update_turn_info()


func log_message(message: String) -> void:
	_ui_manager.log_message(message)


func _show_hint(hint_id: String, text: String) -> void:
	"""Show a one-time tutorial hint in the battle log"""
	if _hints_shown.has(hint_id):
		return
	_hints_shown[hint_id] = true
	log_message("[color=gray][i]Tip: %s[/i][/color]" % text)


func enable_autogrind_console() -> void:
	autogrind_console_mode = true

	if battle_log:
		battle_log.visible = false

	if turn_info and is_instance_valid(turn_info.get_parent()):
		turn_info.get_parent().visible = false

	var log_panel = get_node_or_null("UI/BattleLogPanel")
	if not log_panel:
		return

	_autogrind_console = RichTextLabel.new()
	_autogrind_console.name = "AutogrindConsole"
	_autogrind_console.bbcode_enabled = true
	_autogrind_console.scroll_active = true
	_autogrind_console.scroll_following = true
	_autogrind_console.set_anchors_preset(Control.PRESET_FULL_RECT)
	_autogrind_console.add_theme_font_size_override("normal_font_size", 13)
	_autogrind_console.add_theme_font_size_override("bold_font_size", 14)
	_autogrind_console.add_theme_color_override("default_color", Color(0.8, 0.8, 0.9))

	var margin = log_panel.get_node_or_null("MarginContainer")
	if margin:
		var vbox = margin.get_node_or_null("VBoxContainer")
		if vbox:
			vbox.visible = false
		margin.add_child(_autogrind_console)
	else:
		log_panel.add_child(_autogrind_console)


func autogrind_console_log(text: String) -> void:
	if _autogrind_console and is_instance_valid(_autogrind_console):
		_autogrind_console.append_text(text + "\n")


func update_autogrind_console_stats(stats: Dictionary) -> void:
	if not _autogrind_console or not is_instance_valid(_autogrind_console):
		return

	var battles = stats.get("battles_won", 0)
	var exp = stats.get("total_exp", 0)
	var streak = stats.get("consecutive_wins", 0)
	var eff = stats.get("efficiency", 1.0)
	var corruption = stats.get("corruption", 0.0)
	var turbo = " [color=#ff4444]TURBO[/color]" if turbo_mode else ""

	_autogrind_console.append_text("[color=#666677]─────────────────────────────[/color]\n")
	_autogrind_console.append_text("[color=#ffff66]Battle #%d[/color] | EXP: %d | Streak: %d | Eff: %.1fx%s\n" % [battles, exp, streak, eff, turbo])
	_autogrind_console.append_text("[color=#6666aa]Corruption: %.2f | Y:Turbo +/-:Speed T:Tier B:Exit[/color]\n" % corruption)


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
	return _command_menu.get_alive_enemies()


func _show_target_selection(targets: Array[Combatant]) -> void:
	"""Show popup menu for target selection"""
	is_selecting_target = true

	# Clean up any existing popup
	_cleanup_popup()

	_current_popup = PopupMenu.new()
	_current_popup.name = "TargetMenu"
	add_child(_current_popup)

	for i in range(targets.size()):
		var target = targets[i]
		var label = "%s (HP: %d/%d)" % [target.combatant_name, target.current_hp, target.max_hp]
		_current_popup.add_item(label, i)

	_current_popup.id_pressed.connect(_on_target_selected.bind(targets))
	_current_popup.close_requested.connect(func():
		is_selecting_target = false
		_cleanup_popup()
	)
	_current_popup.popup_centered()


func _cleanup_popup() -> void:
	"""Free the current popup menu if it exists"""
	if _current_popup and is_instance_valid(_current_popup):
		_current_popup.queue_free()
		_current_popup = null


func _on_target_selected(idx: int, targets: Array[Combatant]) -> void:
	"""Handle target selection"""
	is_selecting_target = false
	_cleanup_popup()

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
	popup.close_requested.connect(popup.queue_free)
	popup.popup_centered()


func _on_ability_selected(idx: int, ability_ids: Array) -> void:
	"""Handle ability selection from menu"""
	var popup = get_node_or_null("AbilityMenu")
	if popup and is_instance_valid(popup):
		popup.queue_free()

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
			var ally_target = current if current else (party_members[0] if party_members.size() > 0 else null)
			if ally_target:
				_execute_ability(ability_id, ally_target)


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
	animator.play_named_animation(anim_type)


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
	popup.close_requested.connect(popup.queue_free)
	popup.popup_centered()


func _on_item_selected(idx: int, item_ids: Array) -> void:
	"""Handle item selection from menu"""
	if idx < 0 or idx >= item_ids.size():
		return

	var item_id = item_ids[idx]
	var item = ItemSystem.get_item(item_id)
	var current = BattleManager.current_combatant

	# Check if this is a revival item (e.g. Phoenix Down)
	var item_effects = item.get("effects", {})
	var is_revival_item = item_effects.get("revive", false)

	# Determine targets
	var targets = []
	var target_type = item.get("target_type", ItemSystem.TargetType.SINGLE_ALLY)
	var alive_enemies = _get_alive_enemies()

	match target_type:
		ItemSystem.TargetType.SINGLE_ENEMY:
			if alive_enemies.size() > 0:
				targets = [alive_enemies[0]]
		ItemSystem.TargetType.ALL_ENEMIES:
			targets = alive_enemies
		ItemSystem.TargetType.SINGLE_ALLY, ItemSystem.TargetType.ALL_ALLIES, ItemSystem.TargetType.SELF:
			if is_revival_item:
				# Revival items target fallen allies
				var dead_allies = party_members.filter(func(m): return m is Combatant and not m.is_alive)
				if dead_allies.size() > 0:
					targets = [dead_allies[0]]
				else:
					log_message("No fallen allies to revive!")
					return
			else:
				var item_target = current if current else (party_members[0] if party_members.size() > 0 else null)
				if item_target:
					targets = [item_target]

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
	if not is_instance_valid(self):
		return
	if is_instance_valid(sprite):
		sprite.modulate = original_modulate


## Battle event handlers
func _on_battle_started() -> void:
	"""Handle battle start"""
	log_message("[color=yellow]>>> Battle commenced![/color]")
	_show_hint("autobattle", "Press Select or F6 to enable Autobattle for all characters!")
	_show_hint("controls", "L = Defer (skip, +1 AP) | R = Advance (queue extra actions)")

	# Restore persisted battle speed
	Engine.time_scale = BATTLE_SPEEDS[_battle_speed_index]
	_update_speed_indicator()

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
			# Use terrain-specific battle music for areas that have one,
			# otherwise fall back to generic battle music
			var terrain_track = _get_terrain_battle_track()
			_base_music_track = terrain_track
			SoundManager.play_music(terrain_track)
			if terrain_track != "battle":
				print("[MUSIC] Playing %s terrain battle theme" % _current_terrain)
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


func _get_terrain_battle_track() -> String:
	"""Get terrain-specific battle music track, or 'battle' for generic.
	   Areas with unique battle themes return 'battle_<terrain>'."""
	match _current_terrain:
		"suburban":
			return "battle_suburban"
		"urban":
			return "battle_urban"
		"industrial":
			return "battle_industrial"
		"digital":
			return "battle_digital"
		"void":
			return "battle_void"
		_:
			return "battle"


func _on_battle_ended(victory: bool) -> void:
	"""Handle battle end"""
	# Clean up any open menus
	if active_win98_menu and is_instance_valid(active_win98_menu):
		active_win98_menu.queue_free()
		active_win98_menu = null

	if victory:
		log_message("\n[color=lime]=== VICTORY ===[/color]")
		_battle_victory = true
		if not turbo_mode:
			log_message("[color=gray]Press ENTER to continue...[/color]")
			_play_staggered_victory_animations()
			SoundManager.play_music("victory")
			_show_victory_results()
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

	# Idle sway/breathing animations
	_process_idle_animations(delta)

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


func _process_idle_animations(delta: float) -> void:
	"""Apply subtle idle sway to enemies and breathing to party sprites"""
	if _battle_ended:
		return
	_idle_time += delta

	# Enemy idle sway: ±3px Y oscillation at different frequencies per sprite
	for i in range(enemy_sprite_nodes.size()):
		var sprite = enemy_sprite_nodes[i]
		if not is_instance_valid(sprite):
			continue
		if i >= _enemy_base_positions.size():
			continue
		# Each enemy has a slightly different frequency (0.8, 0.95, 1.1 Hz)
		var freq = 0.8 + float(i) * 0.15
		var phase = float(i) * 1.1  # Phase offset so they don't move in sync
		var sway = sin(_idle_time * freq * TAU + phase) * 3.0
		sprite.position.y = _enemy_base_positions[i].y + sway

	# Party idle breathing: ±2px Y oscillation at different rates per character
	for i in range(party_sprite_nodes.size()):
		var sprite = party_sprite_nodes[i]
		if not is_instance_valid(sprite):
			continue
		if i >= _party_base_positions.size():
			continue
		# Party members breathe at slightly different rates (0.4-0.55 Hz, slower = calmer)
		var freq = 0.4 + float(i) * 0.05
		var phase = float(i) * 0.9
		var breathe = sin(_idle_time * freq * TAU + phase) * 2.0
		sprite.position.y = _party_base_positions[i].y + breathe


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
	_battle_ended = false
	_battle_victory = false

	# Remove victory overlay if it persisted from the last battle
	var victory_overlay = get_node_or_null("VictoryResults")
	if victory_overlay:
		victory_overlay.queue_free()

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

	# Clear enemy status UI (managed by _ui_manager)
	if _ui_manager:
		for box in _ui_manager._enemy_status_boxes:
			if is_instance_valid(box):
				box.queue_free()
		_ui_manager._enemy_status_boxes.clear()
		_ui_manager._revealed_enemies.clear()

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
	# Subtle tick to signal the start of the player input window
	SoundManager.play_ui("phase_select")

	# Check if autobattle cancellation was queued during last execution phase
	if AutobattleSystem.cancel_all_next_turn:
		_cancel_all_autobattle()

	_update_turn_info()
	_update_ui()


func _on_selection_turn_started(combatant: Combatant) -> void:
	"""Handle selection turn start - show menu for player"""
	_command_menu.invalidate_alive_cache()
	log_message("[color=aqua]%s selecting...[/color]" % combatant.combatant_name)
	_update_turn_info()
	_update_ui()

	# Show Win98 menu for player selection (use BattleManager.player_party for correct object identity)
	var is_player = combatant in BattleManager.player_party
	if is_player:
		# Play da-ding sound for player turn
		SoundManager.play_ui("player_turn")
		if combatant.current_ap > 0:
			_show_hint("advance", "You have %d AP! Press R to queue extra actions." % combatant.current_ap)
	if use_win98_menus and is_player:
		_show_win98_command_menu(combatant)


func _on_selection_turn_ended(combatant: Combatant) -> void:
	"""Handle selection turn end"""
	_close_win98_menu()
	_update_ui()


func _on_execution_phase_started() -> void:
	"""Handle execution phase start - all actions now execute"""
	log_message("\n[color=yellow]>>> Execution Phase[/color]")
	# Brief low pulse to signal the action window opening
	SoundManager.play_ui("phase_execute")
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
			_current_ability_id = ""  # Clear — this is a basic attack
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

			# Track ability so damage callback plays element sound instead of generic hit
			_current_ability_id = ability_id

			# Play the ability-specific sound (fire, ice, lightning, etc.)
			SoundManager.play_ability(ability_id)

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
			animator.play_named_animation("defer")


func _on_group_attack_executing(participants: Array, group_type: String, targets: Array) -> void:
	"""Play simultaneous attack animations on all party members for group actions"""
	_update_turn_info()

	# Flash the whole battlefield — gold for Limit Break, orange for All-Out Attack
	var flash_color = Color(1.0, 0.85, 0.0, 0.55) if group_type == "limit_break" else Color(1.0, 0.5, 0.0, 0.4)
	var flash = ColorRect.new()
	flash.color = flash_color
	flash.anchors_preset = Control.PRESET_FULL_RECT
	flash.z_index = 50
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	var tween = create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.45)
	tween.tween_callback(flash.queue_free)

	# Play attack animation on every participating party member simultaneously
	for participant in participants:
		if not (participant is Combatant) or not participant.is_alive:
			continue
		var idx = BattleManager.player_party.find(participant)
		if idx < 0 or idx >= party_animators.size():
			continue
		var anim = party_animators[idx]
		if not anim:
			continue
		var sprite = party_sprite_nodes[idx] if idx < party_sprite_nodes.size() else null

		# For Limit Break, animate each party member lunging at the closest enemy
		if group_type == "limit_break" and targets.size() > 0 and sprite:
			var target_sprite = _get_combatant_sprite(targets[0] as Combatant)
			if target_sprite:
				_animate_melee_attack(sprite, target_sprite, anim, null)
				continue
		# All-Out Attack: play attack animation in place
		anim.play_attack()


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
		if not is_instance_valid(self):
			return
		if attacker_anim and is_instance_valid(attacker_anim):
			attacker_anim.play_attack()
		# Brief delay then play hit
		get_tree().create_timer(0.1).timeout.connect(func():
			if not is_instance_valid(self):
				return
			if target_anim and is_instance_valid(target_anim) and is_instance_valid(target_sprite):
				target_anim.play_hit()
				# Spawn physical hit effect
				EffectSystem.spawn_effect(EffectSystem.EffectType.PHYSICAL, target_sprite.global_position)
				# Knockback: enemies knocked left (-1), party members knocked right (+1)
				var kb_dir = -1.0 if enemy_sprite_nodes.has(target_sprite) else 1.0
				_apply_hit_knockback(target_sprite, kb_dir)
				_apply_hit_flash(target_sprite)
		)
	)

	# Wait for attack animation
	tween.tween_interval(0.3)

	# Return to home position (use stored home, not where we started this attack)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(attacker_sprite, "position", home_pos, 0.2)


func _apply_hit_knockback(sprite: Node2D, direction: float = 1.0) -> void:
	if not is_instance_valid(sprite):
		return
	var original_x = sprite.position.x
	var knockback_x = original_x + (6.0 * direction)
	var tween = create_tween()
	tween.tween_property(sprite, "position:x", knockback_x, 0.05)
	tween.tween_property(sprite, "position:x", original_x, 0.15).set_ease(Tween.EASE_OUT)


func _apply_hit_flash(sprite: Node2D) -> void:
	if not is_instance_valid(sprite):
		return
	sprite.modulate = Color(3.0, 3.0, 3.0, 1.0)
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.12)


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
	"""Handle action execution — play buff/debuff/status sounds based on ability effect"""
	_update_ui()
	var action_type = action.get("type", "")
	if action_type == "ability":
		var ability_id = action.get("ability_id", "")
		var ability = JobSystem.get_ability(ability_id)
		if not ability.is_empty():
			var effect = ability.get("effect", "")
			match effect:
				"defense_up", "attack_up", "volatility_up_self", "volatility_down":
					SoundManager.play_battle("buff")
				"defense_down", "volatility_up":
					SoundManager.play_battle("debuff")
				"poison":
					SoundManager.play_status("poison")
				"sleep":
					SoundManager.play_status("sleep")
				"confuse":
					SoundManager.play_status("confuse")
				"paralyze":
					SoundManager.play_status("paralyze")


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


func _on_summon_hp_changed(enemy: Combatant, old_value: int, new_value: int) -> void:
	var idx = test_enemies.find(enemy)
	if idx >= 0:
		_on_enemy_hp_changed(old_value, new_value, idx)


func _on_summon_died(enemy: Combatant) -> void:
	var idx = test_enemies.find(enemy)
	if idx >= 0:
		_on_enemy_died(idx)


func _on_enemy_hp_changed(old_value: int, new_value: int, enemy_idx: int) -> void:
	"""Handle enemy HP change"""
	if new_value < old_value and enemy_idx < enemy_animators.size():
		# Play hit animation when taking damage
		enemy_animators[enemy_idx].play_hit()


func _on_enemy_died(enemy_idx: int) -> void:
	"""Handle enemy death"""
	_command_menu.invalidate_alive_cache()
	SoundManager.play_battle("enemy_death")
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
	_command_menu.show_win98_command_menu(combatant)


func _close_win98_menu() -> void:
	_command_menu.close_win98_menu()



## Damage Numbers

func _on_damage_dealt(target: Combatant, amount: int, is_crit: bool) -> void:
	_results_display.on_damage_dealt(target, amount, is_crit)
	# Skip hit sounds for abilities — ability sound already played at cast time
	if _current_ability_id != "":
		return
	if is_crit:
		# Critical hit: louder impact with raised pitch for extra punch
		SoundManager.play_battle_scaled("critical_hit", 2.0, 1.3)
	else:
		SoundManager.play_battle("attack_hit")


func _on_attack_missed(target: Combatant) -> void:
	_results_display.on_attack_missed(target)
	SoundManager.play_battle("attack_miss")


func _on_healing_done(target: Combatant, amount: int) -> void:
	_results_display.on_healing_done(target, amount)
	SoundManager.play_battle("heal")


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
	await get_tree().process_frame
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
	await get_tree().process_frame
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


func _play_staggered_victory_animations() -> void:
	"""Stagger party victory animations and briefly brighten the background"""
	# Stagger delays: 0.0s, 0.15s, 0.3s, 0.45s per party member
	var victory_delays: Array[float] = [0.0, 0.15, 0.3, 0.45]
	for i in range(party_animators.size()):
		var animator = party_animators[i]
		if not animator:
			continue
		var delay = victory_delays[i] if i < victory_delays.size() else float(i) * 0.15
		if delay <= 0.0:
			animator.play_victory()
		else:
			get_tree().create_timer(delay).timeout.connect(func():
				if is_instance_valid(animator):
					animator.play_victory()
			)

	# Background brightening on victory (brief warm flash)
	if _battle_background and is_instance_valid(_battle_background):
		var bg_tween = create_tween()
		bg_tween.tween_property(_battle_background, "modulate",
			Color(1.3, 1.25, 1.0, 1.0), 0.35).set_trans(Tween.TRANS_SINE)
		bg_tween.tween_property(_battle_background, "modulate",
			Color(1.0, 1.0, 1.0, 1.0), 0.6).set_trans(Tween.TRANS_SINE)


func _show_victory_results() -> void:
	_results_display.show_victory_results()


func _on_monster_summoned(monster_type: String, summoner: Combatant) -> void:
	"""Handle monster summon - spawn new enemy mid-battle"""
	# Find the monster type data
	var monster_data = null
	for mt in BattleEnemySpawnerClass.MONSTER_TYPES:
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

	# Bind signals using enemy reference — find index at call time to avoid stale index
	enemy.hp_changed.connect(func(old_val, new_val): _on_summon_hp_changed(enemy, old_val, new_val))
	enemy.died.connect(func(): _on_summon_died(enemy))
	var new_idx = test_enemies.size()

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
	tween.finished.connect(func():
		if is_instance_valid(sprite):
			sprite.scale = Vector2(1.0, 1.0)
	)

	# Flash effect at spawn position
	EffectSystem.spawn_effect(EffectSystem.EffectType.BUFF, sprite.global_position)

	# Log message
	log_message("[color=red]%s appears![/color]" % stats["name"])

	_update_ui()


func _spawn_damage_number(pos: Vector2, amount: int, is_heal: bool, is_crit: bool) -> void:
	_results_display.spawn_damage_number(pos, amount, is_heal, is_crit)


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
