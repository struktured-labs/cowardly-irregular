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
const HybridSpriteLoaderClass = preload("res://src/battle/sprites/HybridSpriteLoader.gd")
const BattleEnemySpawnerClass = preload("res://src/battle/BattleEnemySpawner.gd")
const BattleUIManagerClass = preload("res://src/battle/BattleUIManager.gd")
const BattleCommandMenuClass = preload("res://src/battle/BattleCommandMenu.gd")
const BattleResultsDisplayClass = preload("res://src/battle/BattleResultsDisplay.gd")

## Base display height for party sprites. Aseprite frames are ground truth —
## we don't compensate for non-uniform character fill within the artist's
## 256x256 frames. If a job's character occupies less of its frame than
## another (e.g., fighter at 37%, cleric at 71%), that's the artist's choice
## and the battle scene reflects it 1:1 in scale.
## Per BDFFHD-layout design lock (2026-06-03): reduced from 280→210 to
## accommodate the strict-5 party without crowding the screen. User may
## revisit later if they ship larger artist sprites. Effective on-screen
## height with SPRITE_SCALE_BUMP=1.5 is ~315px.
const PARTY_SPRITE_HEIGHT: float = 210.0
## Constant factor applied to ALL party sprite scales (artist and procedural
## paths alike). Bumps everyone uniformly without altering intra-roster ratios.
## 1.5 picked as the visible-but-not-too-big sweet spot after fighter override
## was removed.
const SPRITE_SCALE_BUMP: float = 1.5
const JOB_SCALE_OVERRIDES: Dictionary = {
	"fighter": 1.4,
}

## Bump applied ONLY to artist-style small-frame enemies (<=128px) so they
## don't read as half the size of the proc-gen 256x256 monsters they sit
## next to. Proc-gen monsters at 256 keep depth_scale only (no bump) since
## their native frame already fills the intended battle footprint. The
## threshold is the same one party-side uses to discriminate artist vs
## proc-gen sprite paths.
const ENEMY_SCALE_BUMP: float = 2.5
const ENEMY_SMALL_FRAME_THRESHOLD: int = 128

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

## Watchdog for the "menu never spawned" soft-lock class (msg 2372).
const MENU_WATCHDOG_MS: int = 2500
const MENU_WATCHDOG_MAX_RETRIES: int = 3
var _menu_wd_started_ms: int = 0
var _menu_wd_retries: int = 0

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
	$BattleField/PartyArea/Player4Pos,
	$BattleField/PartyArea/Player5Pos,
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
## Battle speed recalibrated: old 0.5x is now labeled "1x" (the comfortable default)
const BATTLE_SPEEDS: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0]
const BATTLE_SPEED_LABELS: Array[String] = ["1x", "2x", "4x", "8x", "16x", "32x", "64x"]
static var _battle_speed_index: int = 0  # persists across battles; index 0 = label "1x" (engine 0.25) — struktured 2026-07-11: the old 0.5x pacing IS the correct default
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
var _active_inline_editor: Control = null  # 2026-07-14 (cowir-music msg 2539): tracked so battle hotkeys don't leak into open autobattle grid editor

## Danger music state
var _is_danger_music: bool = false

## Idle animation state (sway/breathing)
var _idle_time: float = 0.0
var _enemy_base_positions: Array[Vector2] = []
var _party_base_positions: Array[Vector2] = []

## Party formation system
enum PartyFormation { V_FORMATION, FRONT_LINE, BACK_ROW, DIAMOND, SPREAD }
const FORMATION_NAMES = ["V-Formation", "Front Line", "Back Row", "Diamond", "Spread"]
const FORMATION_DESCRIPTIONS = [
	"Balanced positioning",
	"+10% ATK, -10% DEF",
	"+10% DEF, -10% ATK",
	"Tank absorbs hits",
	"Resist AoE attacks",
]
static var current_formation: int = PartyFormation.V_FORMATION  # Persists across battles

## Dialogue system
var _battle_dialogue: BattleDialogueClass = null
var _boss_dialogue_data: Dictionary = {}  # Stores dialogue for current boss
var _waiting_for_dialogue: bool = false  # Pauses battle during dialogue
var _base_music_track: String = "battle"  # "battle" or "boss"
var _masterite_phase2_swapped: bool = false  # One-shot: latch when phase2 music kicks in
const DANGER_HP_THRESHOLD: float = 0.25  # Switch to danger music below 25% HP

## Tick 428: per-battle latches so the boss `low_hp` and `defeat`
## dialogue lines fire ONCE per battle. Pre-fix monsters.json
## authored intro/low_hp/defeat triples on cave_rat_king, the 4
## dragons, optimization_itself, etc. but only `intro` was wired —
## the other two never spoke regardless of the fight state.
var _boss_low_hp_spoken: bool = false
var _boss_defeat_spoken: bool = false

## Autobattle state
var _all_autobattle_enabled: bool = false  # True when all players are on autobattle
# Note: cancel flag is stored in AutobattleSystem.cancel_all_next_turn for persistence across scenes

## Terrain/background
var _current_terrain: String = "plains"
var _battle_background: BattleBackgroundClass = null

## Mode 7 perspective floor overlay. Disabled by default per BDFFHD-layout
## design lock (2026-06-03) — user found it spatially confusing in regular
## battles. File kept in tree for future revisit on boss arenas + phase-2
## emphasis stack.
const Mode7FloorClass = preload("res://src/battle/BattleMode7Floor.gd")
var _mode7_floor: Mode7FloorClass = null
var _mode7_floor_enabled: bool = false

## Composed subsystems (extracted from BattleScene)
var _enemy_spawner: BattleEnemySpawnerClass = null
var _ui_manager: BattleUIManagerClass = null
var _command_menu: BattleCommandMenuClass = null
var _results_display: BattleResultsDisplayClass = null

## Tutorial hints (persists across battles via static-like save)
static var _hints_shown: Dictionary = {}  # {"hint_id": true}  # Static: persists across scene instances within a session. Intentional — hints show once per game session.

## Status effect icon containers (combatant -> HBoxContainer of icons)
var _status_icon_containers: Dictionary = {}  # {Combatant: HBoxContainer}

## Buff/debuff visual overlay nodes (combatant -> {glow: ColorRect, particles: Array, sigil: Sprite2D})
var _buff_visual_nodes: Dictionary = {}  # {Combatant: Dictionary}

## Buff class_tag values that promote the visual to threat-class read: amber-red glow overrides cyan-green + sigil badge shows above sprite + particles hide. Extend as story lane authors more reprisal-family abilities. cowir-sprites msg 2462: string not bool so future abilities (Reflect, Truth Refuses You, etc.) coalesce under one tag without redecoration.
const THREAT_CLASS_BUFFS: Dictionary = {"reprisal": true}
const THREAT_GLOW_COLOR: Color = Color(1.0, 0.5, 0.15, 1.0)
const THREAT_SIGIL_OFFSET: Vector2 = Vector2(0, -40)

## Enemy floating HP bars (enemy Combatant -> {bar_bg: ColorRect, bar_fill: ColorRect})
var _enemy_hp_bars: Dictionary = {}  # {Combatant: Dictionary}


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

	# own camera or the viewport keeps exploration's (player-world position)
	var _battle_cam := Camera2D.new()
	_battle_cam.name = "BattleCamera"
	_battle_cam.position = Vector2.ZERO
	# FIXED_TOP_LEFT at (0,0) = identity transform; DRAG_CENTER shifts everything by half the viewport
	_battle_cam.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	_battle_cam.zoom = Vector2(1.0, 1.0)
	add_child(_battle_cam)
	_battle_cam.make_current()
	var viewport = get_viewport()
	if viewport:
		var current_camera = viewport.get_camera_2d()
		if current_camera:
			current_camera.zoom = Vector2(1.0, 1.0)

	# Create dynamic battle background (behind everything)
	_create_battle_background()

	# Apply retro font styling
	RetroFontClass.configure_battle_log(battle_log)
	# 2026-07-15 playtest: log viewport was ~4.8 lines tall so the top visible line was permanently half-clipped — snap the panel to a whole line count once layout settles.
	call_deferred("_snap_battle_log_height")
	# 2026-07-16 smoke: the deferred call can still land before PanelContainer layout settles (size 0 → no-op) — the top log line stayed half-clipped. resized fires after REAL layout; re-snap then. Guard flag keeps it one-shot.
	if battle_log:
		battle_log.resized.connect(_snap_battle_log_height)

	# Add padding to PartyStatusPanel so labels don't hug the panel
	# borders. PanelContainer uses its stylebox content_margin_* for
	# inner padding; the default theme has no left/top margin which
	# made character names touch the edges.
	var party_panel = $UI/PartyStatusPanel
	if party_panel:
		var party_style = StyleBoxFlat.new()
		party_style.bg_color = Color(0.08, 0.08, 0.12, 0.85)
		party_style.border_color = Color(0.35, 0.35, 0.5, 0.7)
		party_style.border_width_left = 1
		party_style.border_width_top = 1
		party_style.border_width_right = 1
		party_style.border_width_bottom = 1
		party_style.corner_radius_top_left = 4
		party_style.corner_radius_bottom_left = 4
		party_style.content_margin_left = 10
		party_style.content_margin_right = 8
		party_style.content_margin_top = 8
		party_style.content_margin_bottom = 8
		party_panel.add_theme_stylebox_override("panel", party_style)

	# Permanent input-hint bar at the bottom of the battle UI. Tutorial
	# hints fire once and disappear, leaving players who missed them
	# without any reference for the shoulder shortcuts.
	# (User feedback 2026-05-20: "I dont know what button defers
	# (besides the menu option)".)
	_build_input_hint_bar()

	# Connect to BattleManager signals (CTB system)
	BattleManager.battle_started.connect(_on_battle_started)
	BattleManager.battle_ended.connect(_on_battle_ended)
	BattleManager.selection_phase_started.connect(_on_selection_phase_started)
	BattleManager.selection_turn_started.connect(_on_selection_turn_started)
	BattleManager.selection_turn_ended.connect(_on_selection_turn_ended)
	BattleManager.execution_phase_started.connect(_on_execution_phase_started)
	BattleManager.action_executing.connect(_on_action_executing)
	BattleManager.action_executed.connect(_on_action_executed)
	# Item 19: user report "bard was briefly stuck for a turn next to
	# the monsters on the left he presumably recently attacked" —
	# stray displaced sprite from an interrupted return-home tween.
	# `_snap_party_sprites_home` existed but only fired after group
	# attacks. Wire it to round_started too as a universal safety net
	# so any interrupted tween gets caught at the top of every round.
	BattleManager.round_started.connect(_on_round_started_snap_home)
	BattleManager.round_started.connect(_refresh_all_status_icons)  # tick duration/doom counters down visibly
	BattleManager.round_started.connect(_on_round_started_corruption_glitch)  # save-corruption visual_glitch stutter
	BattleManager.round_ended.connect(_on_round_ended)
	BattleManager.damage_dealt.connect(_on_damage_dealt)
	BattleManager.attack_missed.connect(_on_attack_missed)
	BattleManager.healing_done.connect(_on_healing_done)
	if BattleManager.has_signal("trust_interrupt_window_opened"):
		BattleManager.trust_interrupt_window_opened.connect(_on_trust_interrupt_window_opened)
	if BattleManager.has_signal("trust_interrupt_window_closed"):
		BattleManager.trust_interrupt_window_closed.connect(_on_trust_interrupt_window_closed)
	BattleManager.battle_log_message.connect(_on_battle_log_message)
	BattleManager.monster_summoned.connect(_on_monster_summoned)
	## Tick 409: Scriptweaver's create_autobattle_script meta-ability
	## surfaces the autobattle editor for the caster. Wired via
	## has_signal guard for partial-autoload boot scenarios.
	if BattleManager.has_signal("meta_autobattle_editor_requested"):
		BattleManager.meta_autobattle_editor_requested.connect(_on_meta_autobattle_editor_requested)
	BattleManager.one_shot_achieved.connect(_on_one_shot_achieved)
	BattleManager.autobattle_victory.connect(_on_autobattle_victory)
	BattleManager.group_attack_executing.connect(_on_group_attack_executing)
	BattleManager.advance_trash_talk.connect(_on_advance_trash_talk)
	# Tick 122: party combat dialogue (turn_start/low_hp/big_hit_taken/
	# used_signature_ability/victory) — surface as speech bubbles too,
	# not just as battle-log text. Uses has_signal guard for safety
	# during partial autoload boot scenarios.
	if BattleManager.has_signal("party_combat_line"):
		BattleManager.party_combat_line.connect(_on_party_combat_line)
	# Wave E — Boss dialogue / jailbreak signals.
	if BattleManager.has_signal("boss_taunt"):
		BattleManager.boss_taunt.connect(_on_boss_taunt)
	if BattleManager.has_signal("boss_jailbreak_landed"):
		BattleManager.boss_jailbreak_landed.connect(_on_boss_jailbreak_landed)
	# Wave G — end-of-fight boss gloat line (victory / defeat).
	if BattleManager.has_signal("boss_gloat_line"):
		BattleManager.boss_gloat_line.connect(_on_boss_gloat_line)

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

	# Speed indicator and autobattle toggle removed — functionality handled by BattleUIManager

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
	if BattleManager.round_started.is_connected(_on_round_started_snap_home):
		BattleManager.round_started.disconnect(_on_round_started_snap_home)
	if BattleManager.round_started.is_connected(_refresh_all_status_icons):
		BattleManager.round_started.disconnect(_refresh_all_status_icons)
	if BattleManager.round_started.is_connected(_on_round_started_corruption_glitch):
		BattleManager.round_started.disconnect(_on_round_started_corruption_glitch)
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
	if BattleManager.advance_trash_talk.is_connected(_on_advance_trash_talk):
		BattleManager.advance_trash_talk.disconnect(_on_advance_trash_talk)
	if BattleManager.has_signal("party_combat_line") and BattleManager.party_combat_line.is_connected(_on_party_combat_line):
		BattleManager.party_combat_line.disconnect(_on_party_combat_line)
	if BattleManager.has_signal("boss_gloat_line") and BattleManager.boss_gloat_line.is_connected(_on_boss_gloat_line):
		BattleManager.boss_gloat_line.disconnect(_on_boss_gloat_line)

	# Reset engine time scale in case battle speed was altered
	Engine.time_scale = 1.0

	# Explicitly free victory results overlay to prevent persistence across scenes
	var victory_overlay = get_node_or_null("VictoryResults")
	if victory_overlay and is_instance_valid(victory_overlay):
		victory_overlay.free()

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

	# Mode 7 perspective floor overlay — sits BEHIND sprites but on top of the
	# painted background so the characters appear to be standing on a tilted
	# plane. This is a spike; gate via _mode7_floor_enabled to disable.
	if _mode7_floor_enabled:
		_mode7_floor = Mode7FloorClass.new()
		_mode7_floor.name = "Mode7Floor"
		add_child(_mode7_floor)
		# Place right after the background (index 1) so sprites added later
		# render on top of it. BattleField/EnemySprites/PartySprites containers
		# get added/moved later in setup, which keeps them above the floor.
		move_child(_mode7_floor, 1)


func set_command_menu_visible(visible: bool) -> void:
	"""Public method to show/hide the command menu (called by GameLoop for autobattle editor)"""
	if active_win98_menu and is_instance_valid(active_win98_menu):
		print("[MENU-HIDE] t=%dms visible=%s (called from set_command_menu_visible)" % [Time.get_ticks_msec(), visible])
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
	"""Create battle speed indicator in top-left corner with background panel"""
	# Background panel for readability
	var panel = PanelContainer.new()
	panel.name = "SpeedPanel"
	panel.position = Vector2(8, 8)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", style)
	$UI.add_child(panel)

	_speed_indicator = RichTextLabel.new()
	_speed_indicator.name = "SpeedIndicator"
	_speed_indicator.bbcode_enabled = true
	_speed_indicator.fit_content = true
	_speed_indicator.scroll_active = false
	_speed_indicator.custom_minimum_size = Vector2(80, 24)
	_speed_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Style it
	_speed_indicator.add_theme_font_size_override("normal_font_size", TextScale.scaled(16))

	panel.add_child(_speed_indicator)

	# Battle counter (shown during autogrind)
	_battle_counter_label = RichTextLabel.new()
	_battle_counter_label.name = "BattleCounter"
	_battle_counter_label.bbcode_enabled = true
	_battle_counter_label.fit_content = true
	_battle_counter_label.scroll_active = false
	_battle_counter_label.custom_minimum_size = Vector2(120, 24)
	_battle_counter_label.add_theme_font_size_override("normal_font_size", TextScale.scaled(14))
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
		0:  # 1x - normal (white/cyan) — the default
			text = "[color=#88cccc]▸[/color] [color=#ffffff]%s[/color] [color=#66aaaa]◂[/color]" % speed_label
		1:  # 2x - brisk (green)
			text = "[color=#66cc88]▸▸[/color] [color=#88ffaa]%s[/color] [color=#44aa66]◂◂[/color]" % speed_label
		2:  # 4x - fast (yellow)
			text = "[color=#ccaa44]▸▸[/color] [color=#ffcc00]%s[/color] [color=#aa8822]◂◂[/color]" % speed_label
		3:  # 8x - turbo (orange)
			text = "[color=#cc6622]▸▸▸[/color] [color=#ff6600]%s[/color] [color=#aa4400]◂◂◂[/color]" % speed_label
		4:  # 16x - extreme (red)
			text = "[color=#cc2222]▸▸▸▸[/color] [color=#ff3300]%s[/color] [color=#aa1100]◂◂◂◂[/color]" % speed_label
		5:  # 32x - very extreme (magenta)
			text = "[color=#cc22cc]▸▸▸▸▸[/color] [color=#ff00ff]%s[/color] [color=#aa00aa]◂◂◂◂◂[/color]" % speed_label
		6:  # 64x - maximum (bright magenta)
			text = "[color=#ff22ff]▸▸▸▸▸▸[/color] [color=#ff44ff]%s[/color] [color=#cc00cc]◂◂◂◂◂◂[/color]" % speed_label

	if turbo_mode:
		text += " [color=#ff4444]TURBO[/color]"

	_speed_indicator.text = text

	if turbo_mode:
		if _speed_indicator:
			_speed_indicator.add_theme_font_size_override("normal_font_size", TextScale.scaled(22))
			_speed_indicator.custom_minimum_size = Vector2(160, 32)
	else:
		if _speed_indicator:
			_speed_indicator.add_theme_font_size_override("normal_font_size", TextScale.scaled(16))
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
		_battle_dialogue.show_boss_intro(_get_boss_intro_speaker(), _boss_dialogue_data["intro"])


func _get_boss_intro_speaker() -> String:
	# Prefer the actual boss combatant name over the generic "Boss" placeholder.
	for enemy in test_enemies:
		if enemy and is_instance_valid(enemy) and enemy.has_meta("is_boss"):
			return enemy.combatant_name
	if test_enemies.size() > 0 and is_instance_valid(test_enemies[0]):
		return test_enemies[0].combatant_name
	return "Boss"


func _start_battle_after_dialogue() -> void:
	"""Start the battle after dialogue is finished"""
	BattleManager.start_battle(party_members, test_enemies)


func _toggle_battle_speed() -> void:
	"""Cycle through battle speeds"""
	_battle_speed_index = (_battle_speed_index + 1) % BATTLE_SPEEDS.size()
	var speed = BATTLE_SPEEDS[_battle_speed_index]
	Engine.time_scale = speed
	_update_speed_indicator()
	_animate_speed_change()
	SoundManager.play_ui("speed_change")
	log_message("[color=gray]Battle speed: %s[/color]" % BATTLE_SPEED_LABELS[_battle_speed_index])
	_show_hint("speed_toggle", "Press +/- to change battle speed. Higher speeds skip animations for faster grinding.")


func _animate_speed_change() -> void:
	"""Pop animation on the speed indicator when toggled"""
	var panel = $UI.get_node_or_null("SpeedPanel")
	if not panel:
		return
	# Scale pop: 1.0 -> 1.25 -> 1.0
	var tween = create_tween()
	tween.tween_property(panel, "scale", Vector2(1.25, 1.25), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.12)
	# Ensure full opacity when changed
	panel.modulate.a = 1.0
	# Auto-fade at normal speed (1x) after 3 seconds
	if _battle_speed_index == 0:  # label "1x" = normal, matches the indicator's per-index colors
		var fade_tween = create_tween()
		fade_tween.tween_property(panel, "modulate:a", 0.3, 0.5).set_delay(3.0)
	else:
		panel.modulate.a = 1.0


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
		if not member.status_added.is_connected(_on_status_added):
			member.status_added.connect(_on_status_added.bind(member))
		if not member.status_removed.is_connected(_on_status_removed):
			member.status_removed.connect(_on_status_removed.bind(member))
		## Tick 143: spawn damage/heal popups on status-effect ticks
		## (poison/burn/regen). Without this the HP bar dropped but no
		## floating number appeared, so status ticks felt invisible.
		if not member.status_tick_damage.is_connected(_on_status_tick_damage):
			member.status_tick_damage.connect(_on_status_tick_damage.bind(member))
		if not member.status_tick_heal.is_connected(_on_status_tick_heal):
			member.status_tick_heal.connect(_on_status_tick_heal.bind(member))

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
	mira.autobattle_locked = true
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
	zack.autobattle_locked = true
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
	vex.autobattle_locked = true
	party_members.append(vex)

	var bard = Combatant.new()
	bard.initialize({
		"name": "Bard",
		"max_hp": 95,
		"max_mp": 90,
		"attack": 12,
		"defense": 9,
		"magic": 22,
		"speed": 16
	})
	add_child(bard)
	JobSystem.assign_job(bard, "bard")
	EquipmentSystem.equip_weapon(bard, "piano_scythe")
	EquipmentSystem.equip_armor(bard, "cloth_robe")
	EquipmentSystem.equip_accessory(bard, "magic_ring")
	bard.learn_passive("magic_boost")
	bard.learn_passive("mp_boost")
	PassiveSystem.equip_passive(bard, "magic_boost")
	PassiveSystem.equip_passive(bard, "mp_boost")
	bard.autobattle_locked = true
	party_members.append(bard)


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
		# PARTY_SPRITE_HEIGHT is the strict-5 base (210px, lowered from 280
		# per BDFFHD layout design). No further density scaling — the base
		# was tuned for the strict-5 layout directly.
		var target_height = PARTY_SPRITE_HEIGHT
		var proc_target_height = 108.0  # was 144 — proportional shrink with target_height

		# Auto-scale based on frame height and per-job target
		var _sprite_scale = 3.0
		if sprite.sprite_frames and sprite.sprite_frames.has_animation(&"idle"):
			if sprite.sprite_frames.get_frame_count(&"idle") > 0:
				var _ftex = sprite.sprite_frames.get_frame_texture(&"idle", 0)
				if _ftex and _ftex.get_height() > 128:
					_sprite_scale = target_height / float(_ftex.get_height())
				elif _ftex and _ftex.get_height() > 48:
					_sprite_scale = proc_target_height / float(_ftex.get_height())
		# Apply per-job scale override (currently empty — kept as a hook)
		var scale_mult = JOB_SCALE_OVERRIDES.get(job_id, 1.0)
		_sprite_scale *= scale_mult
		# Constant uniform bump — applies to artist + procedural paths alike.
		_sprite_scale *= SPRITE_SCALE_BUMP
		sprite.scale = Vector2(_sprite_scale, _sprite_scale)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

		# Position based on current formation
		var base_pos = party_positions[i].global_position if i < party_positions.size() else Vector2(600, 100 + i * 100)
		var offset = _get_formation_offset(i, party_members.size())
		base_pos += offset
		sprite.position = base_pos
		sprite.set_meta("home_position", base_pos)  # 2026-07-14: attack tweens target this so a party-attack against a monster still in its lunge-return tween lands where the monster WILL be (not chases its transient position, playtest bug)
		_party_base_positions.append(base_pos)

		# Procedural sprites are drawn facing right and need flip_h to face the
		# enemy line; artist sheets are already authored facing left and the
		# flip rotates them BACK to wrong-way. Detect via the same large-frame
		# heuristic used for scale (>128 px frame height = artist sheet).
		var _is_artist_sheet := false
		if sprite.sprite_frames and sprite.sprite_frames.has_animation(&"idle"):
			if sprite.sprite_frames.get_frame_count(&"idle") > 0:
				var _ft = sprite.sprite_frames.get_frame_texture(&"idle", 0)
				_is_artist_sheet = _ft != null and _ft.get_height() > 128
		sprite.flip_h = not _is_artist_sheet
		sprite.play("idle")
		party_sprites.add_child(sprite)
		party_sprite_nodes.append(sprite)

		var animator = BattleAnimatorClass.new()
		animator.setup(sprite)
		add_child(animator)
		party_animators.append(animator)

		# Add label with character name
		_add_sprite_label(sprite, member.combatant_name.to_upper(), Vector2(-20, 40))

		# Setup status icons for this party member
		_setup_status_icons(member, sprite)

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
		# Per-frame-size bump: artist drops at <=128px get ENEMY_SCALE_BUMP so
		# they don't read as tiny next to proc-gen 256-frame monsters.
		var size_bump = 1.0
		var _is_artist_monster := false
		if sprite.sprite_frames and sprite.sprite_frames.has_animation(&"idle"):
			if sprite.sprite_frames.get_frame_count(&"idle") > 0:
				var _enemy_ftex = sprite.sprite_frames.get_frame_texture(&"idle", 0)
				if _enemy_ftex and _enemy_ftex.get_height() <= ENEMY_SMALL_FRAME_THRESHOLD:
					size_bump = ENEMY_SCALE_BUMP
					_is_artist_monster = true
		# Artist monsters (slime/bat/goblin) are authored facing LEFT; flip so they face the party on the right. Procedurals already face right.
		sprite.flip_h = _is_artist_monster
		var base_enemy_pos = enemy_positions[i].global_position if i < enemy_positions.size() else Vector2(200 + i * 100, 300)
		base_enemy_pos.y += enemy_y_stagger
		sprite.position = base_enemy_pos
		sprite.set_meta("home_position", base_enemy_pos)  # 2026-07-14: attack tweens read this so a hit landing while target is mid-return still aims for the settled home
		sprite.scale = Vector2(depth_scale * size_bump, depth_scale * size_bump)
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

		# Setup status icons for this enemy
		_setup_status_icons(enemy, sprite)

		# Add floating HP bar below enemy name
		_create_enemy_hp_bar(enemy, sprite)

		# Mouse click-to-target accessibility (added 2026-05-03 per a11y audit).
		# Wraps the sprite in an Area2D + RectangleShape2D so the user can click
		# directly on the enemy in addition to the popup menu. Only fires during
		# target selection (`is_selecting_target`); ignored otherwise. Uses
		# input_pickable for cleanest event routing.
		_add_enemy_click_target(sprite, i)


func _add_enemy_click_target(sprite: AnimatedSprite2D, enemy_idx: int) -> void:
	"""Wrap an enemy sprite in an Area2D so mouse clicks can pick it as a
	target during the target-selection phase. Click is ignored outside
	target selection (so wandering clicks during animations don't fire
	stale target selections).

	Sizing: clip to ~70% of the actual sprite frame (so adjacent staggered
	enemies don't have overlapping click areas) and let the parent sprite's
	scale transform apply. Pre-2026-05-04 the box was a fixed 100x110 which
	worked OK for the 144px proc-gen sprites (~70% fill) but felt cramped
	on 256px sprites (~40% fill of the visible silhouette).
	(Per accessibility audit: 'mouse + keyboard fully accessible'.)"""
	var area = Area2D.new()
	area.name = "ClickTarget"
	area.input_pickable = true
	# Layer 16 = a fresh, non-conflicting bit. We only care about input
	# pickability; Area2D collision_layer/mask aren't used here.
	area.collision_layer = 0
	area.collision_mask = 0
	sprite.add_child(area)

	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	# Read the frame size from the sprite's idle texture if available;
	# fall back to 100x110 if we can't introspect.
	var frame_w := 100.0
	var frame_h := 110.0
	if sprite.sprite_frames and sprite.sprite_frames.has_animation("idle"):
		var tex = sprite.sprite_frames.get_frame_texture("idle", 0)
		if tex:
			frame_w = float(tex.get_width()) * 0.70
			frame_h = float(tex.get_height()) * 0.78
	rect.size = Vector2(frame_w, frame_h)
	shape.shape = rect
	# Centered on the sprite (Sprite2D/AnimatedSprite2D are centered by default)
	shape.position = Vector2(0, 0)
	area.add_child(shape)

	# Click handler — fires only during target selection
	area.input_event.connect(func(_viewport, event: InputEvent, _shape_idx: int) -> void:
		if not is_selecting_target:
			return
		if not (event is InputEventMouseButton):
			return
		var mb := event as InputEventMouseButton
		if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
			return
		# Build the same alive-enemies array the popup uses, then resolve
		# enemy_idx through it. (PopupMenu items are keyed by index in the
		# alive subset, not the full test_enemies array.)
		var alive_enemies := _get_alive_enemies()
		if enemy_idx >= test_enemies.size():
			return
		var clicked_enemy: Combatant = test_enemies[enemy_idx]
		if not clicked_enemy or not clicked_enemy.is_alive:
			return
		var alive_idx := alive_enemies.find(clicked_enemy)
		if alive_idx < 0:
			return
		# Close any popup menu we opened, then route through the same handler
		_cleanup_popup()
		is_selecting_target = false
		_on_target_selected(alive_idx, alive_enemies)
		get_viewport().set_input_as_handled()
	)

	# Hover feedback — highlight the enemy with a yellow tint when the
	# user hovers during target selection, so they can see which enemy
	# they'd hit before clicking. Restored on mouse_exited.
	# (Mild a11y polish 2026-05-04: helps users who can't easily see
	# the popup-menu's text-based highlight while their cursor is over
	# a sprite.)
	area.mouse_entered.connect(func() -> void:
		if not is_selecting_target:
			return
		if not is_instance_valid(sprite):
			return
		# Save original modulate once, then apply yellow tint
		if not sprite.has_meta("orig_modulate"):
			sprite.set_meta("orig_modulate", sprite.modulate)
		sprite.modulate = Color(1.4, 1.4, 0.7)
	)
	area.mouse_exited.connect(func() -> void:
		if not is_instance_valid(sprite):
			return
		if sprite.has_meta("orig_modulate"):
			sprite.modulate = sprite.get_meta("orig_modulate")
			sprite.remove_meta("orig_modulate")
	)


func _create_enemy_hp_bar(enemy: Combatant, sprite: AnimatedSprite2D) -> void:
	"""Create a small HP bar below the enemy sprite name label"""
	var bar_bg = ColorRect.new()
	bar_bg.color = Color(0.2, 0.1, 0.1, 0.7)
	bar_bg.size = Vector2(40, 4)
	bar_bg.position = Vector2(-20, 52)  # Below the name label
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.add_child(bar_bg)

	var bar_fill = ColorRect.new()
	bar_fill.color = Color(0.8, 0.2, 0.2)  # Red for enemies
	bar_fill.size = Vector2(40, 4)
	bar_fill.position = Vector2(-20, 52)
	bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.add_child(bar_fill)

	_enemy_hp_bars[enemy] = {"bar_bg": bar_bg, "bar_fill": bar_fill}


func _update_enemy_hp_bars() -> void:
	"""Update all enemy floating HP bars"""
	for enemy in _enemy_hp_bars:
		if not is_instance_valid(enemy):
			continue
		var bars = _enemy_hp_bars[enemy]
		var bar_fill: ColorRect = bars.get("bar_fill")
		if not bar_fill or not is_instance_valid(bar_fill):
			continue
		var ratio = float(enemy.current_hp) / float(max(1, enemy.max_hp))
		bar_fill.size.x = 40.0 * ratio
		# Tick 230: floating enemy HP bar via AccessibilityPalette — color-blind mode swaps green/red to cyan/magenta, matching the SaveScreen + StatusMenu HP bar palette.
		if ratio > 0.5:
			bar_fill.color = AccessibilityPalette.hp_high()
		elif ratio > 0.25:
			bar_fill.color = AccessibilityPalette.hp_mid()
		else:
			bar_fill.color = AccessibilityPalette.hp_low()


func _get_monster_sprite_frames(monster_id: String) -> SpriteFrames:
	"""Get the appropriate sprite frames for a monster type.

	Looks for a per-world variant first (e.g. slime_suburban when world
	suffix == "suburban"), falls back to the bare monster id, then to the
	procedural _MonsterSprites factory functions. Generic — any monster
	with <id>_<world> registered in sprite_manifest.json gets the variant
	automatically. Currently used by the 5 slime palette variants
	(suburban/steampunk/industrial/digital/abstract); base medieval skips
	the suffix branch since "slime_medieval" isn't registered.
	(2026-05-07: wire-up for cowir-sprites' feature/slime-world-variants.)"""
	var world_suffix = SoundManager._get_current_world_suffix()
	if world_suffix != "" and world_suffix != "medieval":
		var variant_id = "%s_%s" % [monster_id, world_suffix]
		var variant_frames = HybridSpriteLoaderClass.load_monster_sprite_frames(variant_id)
		if variant_frames:
			return variant_frames

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
		"chancellor_mordaine":
			# Placeholder: reuse shadow_knight humanoid silhouette until
			# an artist sheet lands. Mordaine is a sorceress-usurper —
			# shadow_knight is the closest humanoid in MonsterSprites
			# (dark robes, vaguely armored). Falling back to slime via
			# the default branch would be visually nonsensical for the
			# W1 final boss. Re-tag for artist replacement: tier T1.
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
	# a fixed +40 lands mid-body on 256px artist frames (SKELETON KNIGHT read at the waist) — drop below the frame
	var half_h: float = offset.y
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(&"idle") \
			and sprite.sprite_frames.get_frame_count(&"idle") > 0:
		var idle_tex = sprite.sprite_frames.get_frame_texture(&"idle", 0)
		if idle_tex:
			half_h = maxf(offset.y, idle_tex.get_height() / 2.0 + 6.0)
	label.position = Vector2(offset.x, half_h)
	label.add_theme_font_size_override("font_size", TextScale.scaled(10))
	# Tick 219: 1px outline + shadow — name labels sit below sprites on the Mode 7 floor and need edge protection vs grid lines (matches tick 218 contrast scheme, scaled down for 10pt).
	label.add_theme_constant_override("outline_size", 1)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	sprite.add_child(label)


## Status effect icon display system
const STATUS_ICON_CONFIG = {
	# Crowd control / debuffs
	"exposed": {"label": "EXP", "color": Color(1.0, 0.3, 0.3)},
	"cannot_defer": {"label": "LOCK", "color": Color(0.8, 0.2, 0.2)},
	"stun": {"label": "STUN", "color": Color(1.0, 1.0, 0.2)},
	"sleep": {"label": "ZZZ", "color": Color(0.5, 0.5, 1.0)},
	"confuse": {"label": "CONF", "color": Color(0.9, 0.5, 0.9)},
	"fear": {"label": "FEAR", "color": Color(0.6, 0.3, 0.8)},
	"charm": {"label": "CHRM", "color": Color(1.0, 0.5, 0.7)},
	"blind": {"label": "BLND", "color": Color(0.4, 0.4, 0.4)},
	"curse": {"label": "CURS", "color": Color(0.5, 0.0, 0.5)},
	"regen": {"label": "REGN", "color": Color(0.3, 1.0, 0.3)},
	"permakilled": {"label": "DEAD", "color": Color(0.3, 0.0, 0.0)},
	# Tick 129: common stat buffs/debuffs from abilities.json. Pre-fix,
	# 25+ distinct statuses fell through to the `status.substr(0, 3).to_upper()`
	# fallback, giving the player vague "ATT" both for attack_up AND
	# attack_down — same icon for opposite effects. Buffs get green
	# (+suffix), debuffs get red (-suffix).
	"attack_up": {"label": "ATK+", "color": Color(0.3, 1.0, 0.3)},
	"attack_down": {"label": "ATK-", "color": Color(1.0, 0.3, 0.3)},
	"defense_up": {"label": "DEF+", "color": Color(0.3, 1.0, 0.3)},
	"defense_down": {"label": "DEF-", "color": Color(1.0, 0.3, 0.3)},
	"magic_up": {"label": "MAG+", "color": Color(0.3, 1.0, 0.3)},
	"magic_down": {"label": "MAG-", "color": Color(1.0, 0.3, 0.3)},
	"speed_up": {"label": "SPD+", "color": Color(0.3, 1.0, 0.3)},
	"speed_down": {"label": "SPD-", "color": Color(1.0, 0.3, 0.3)},
	# Standalone damage-over-time + utility effects
	"burn": {"label": "BURN", "color": Color(1.0, 0.5, 0.1)},
	"poison": {"label": "PSN", "color": Color(0.6, 0.9, 0.3)},
	"silence": {"label": "SLNC", "color": Color(0.6, 0.6, 0.6)},
	"barrier": {"label": "BARR", "color": Color(0.4, 0.8, 1.0)},
	"haste": {"label": "HAST", "color": Color(0.3, 1.0, 0.5)},
	"slow": {"label": "SLOW", "color": Color(0.7, 0.3, 0.8)},
}


func _setup_status_icons(combatant: Combatant, sprite: AnimatedSprite2D) -> void:
	"""Create status icon container above a combatant's sprite and connect signals"""
	var container = HBoxContainer.new()
	container.add_theme_constant_override("separation", 2)
	container.position = Vector2(-30, -55)  # Above sprite
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.add_child(container)
	_status_icon_containers[combatant] = container

	# Connect signals for reactive updates
	if not combatant.status_added.is_connected(_on_combatant_status_changed):
		combatant.status_added.connect(_on_combatant_status_changed.bind(combatant))
	if not combatant.status_removed.is_connected(_on_combatant_status_changed):
		combatant.status_removed.connect(_on_combatant_status_changed.bind(combatant))

	# Show any existing statuses
	_refresh_status_icons(combatant)


func _on_combatant_status_changed(_status: String, combatant: Combatant) -> void:
	"""Refresh status icons when a status is added or removed"""
	_refresh_status_icons(combatant)


func _refresh_status_icons(combatant: Combatant, animate: bool = true) -> void:
	"""Rebuild the status icon row for a combatant"""
	if combatant not in _status_icon_containers:
		return
	var container: HBoxContainer = _status_icon_containers[combatant]
	if not is_instance_valid(container):
		return

	# Clear existing icons
	for child in container.get_children():
		child.queue_free()

	# Add icon for each active status (skip internal-only ones)
	for status in combatant.status_effects:
		# Skip taunted_* variants (internal targeting, not visual)
		if status.begins_with("taunted_"):
			continue

		var config = STATUS_ICON_CONFIG.get(status, {"label": status.substr(0, 3).to_upper(), "color": Color(0.7, 0.7, 0.7)})
		var turns_left: int = combatant.status_durations.get(status, -1)
		var display_text: String = config["label"]
		if turns_left > 0:
			display_text += " %d" % turns_left  # e.g. "STUN 2"
		var icon = _create_status_icon_label(display_text, config["color"])
		container.add_child(icon)
		if animate:
			_animate_status_icon_pop_in(icon)

	# doom_counter is a Combatant int field, not a status_effect — surface the lethal countdown so it's trackable after the initial log scrolls away
	if "doom_counter" in combatant and combatant.doom_counter > 0:
		var doom_icon = _create_status_icon_label("☠ %d" % combatant.doom_counter, Color(0.6, 0.1, 0.7))
		container.add_child(doom_icon)
		if animate:
			_animate_status_icon_pop_in(doom_icon)


func _refresh_all_status_icons(_round_num: int = 0) -> void:
	"""Per-round refresh (no pop animation) so duration counters + doom visibly tick down."""
	for combatant in _status_icon_containers.keys():
		if is_instance_valid(combatant):
			_refresh_status_icons(combatant, false)


func _animate_status_icon_pop_in(icon: Control) -> void:
	# Defer one frame so the PanelContainer has a real size for pivot_offset
	# (mirrors the deferred-pivot pattern noted in CLAUDE.md polish item #24).
	await get_tree().process_frame
	if not is_instance_valid(icon):
		return
	icon.pivot_offset = icon.size / 2.0
	icon.scale = Vector2(0.55, 0.55)
	var tween := create_tween()
	tween.tween_property(icon, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)


func _create_status_icon_label(text: String, color: Color) -> PanelContainer:
	"""Create a small colored status badge"""
	var panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	style.border_color = color
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_width_left = 1
	style.border_width_right = 1
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.content_margin_left = 2
	style.content_margin_right = 2
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	panel.add_theme_stylebox_override("panel", style)

	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", TextScale.scaled(8))
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)

	return panel


func _update_ui() -> void:
	_ui_manager.update_ui()
	_update_enemy_hp_bars()


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

	# Apply to music system (SoundManager is a guaranteed autoload).
	SoundManager.set_danger_intensity(intensity)



func reveal_enemy_stats(enemy: Combatant) -> void:
	_ui_manager.reveal_enemy_stats(enemy)


func _update_turn_info() -> void:
	_ui_manager.update_turn_info()


## Shrink the BattleLogPanel by the fractional line so the scrolled-to-bottom log never shows a half-clipped top line (playtest 2026-07-15). Measures the REAL label size post-layout instead of guessing theme metrics.
func _snap_battle_log_height() -> void:
	if not battle_log or not is_instance_valid(battle_log):
		return
	var f := battle_log.get_theme_font("normal_font")
	var fs: int = battle_log.get_theme_font_size("normal_font_size")
	if f == null or fs <= 0:
		return
	var line_h: float = f.get_height(fs) + float(battle_log.get_theme_constant("line_separation"))
	if line_h <= 0.0:
		return
	var sb := battle_log.get_theme_stylebox("normal")
	var inset: float = (sb.get_margin(SIDE_TOP) + sb.get_margin(SIDE_BOTTOM)) if sb else 0.0
	var text_h: float = battle_log.size.y - inset
	var frac: float = fmod(text_h, line_h)
	if frac > 1.0:
		var log_panel = get_node_or_null("UI/BattleLogPanel")
		if log_panel:
			log_panel.offset_top += frac


func log_message(message: String) -> void:
	_ui_manager.log_message(message)


func _show_hint(hint_id: String, text: String) -> void:
	"""Show a one-time tutorial hint in the battle log"""
	if _hints_shown.has(hint_id):
		return
	_hints_shown[hint_id] = true
	log_message("[color=gray][i]Tip: %s[/i][/color]" % text)


func _build_input_hint_bar() -> void:
	"""Permanent input-hint bar at the bottom-center of the battle UI.
	   Shows L1/R1 shoulder shortcuts so players who missed the
	   transient tutorial hint still know how to Defer/Advance."""
	var ui_root := get_node_or_null("UI")
	if not ui_root:
		return

	var hint_panel := PanelContainer.new()
	hint_panel.name = "InputHintBar"
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchor bottom-center
	hint_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM, true)
	hint_panel.offset_left = -260
	hint_panel.offset_right = 260
	hint_panel.offset_top = -34
	hint_panel.offset_bottom = -6

	# Subtle dark style — present but not dominating.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.10, 0.70)
	style.border_color = Color(0.35, 0.35, 0.50, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	hint_panel.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.name = "HintLabel"
	# Keep the hint text concise; pipe-separated reads quickly.
	# Use [L]/[R] notation that works for both gamepad (shoulder)
	# and keyboard (L/R keys per InputMap).
	label.text = "[L] Defer  ·  [R] Advance  ·  [+/-] Speed  ·  [Select] Auto"
	label.add_theme_font_size_override("font_size", TextScale.scaled(12))
	label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95, 0.95))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_panel.add_child(label)

	ui_root.add_child(hint_panel)


func enable_autogrind_console() -> void:
	autogrind_console_mode = true

	if battle_log:
		battle_log.visible = false

	if turn_info and is_instance_valid(turn_info.get_parent()):
		turn_info.get_parent().visible = false

	# Hide the input hint bar — it advertises shortcuts that don't
	# apply during the autogrind autopilot (player isn't selecting).
	var hint = get_node_or_null("UI/InputHintBar")
	if hint and is_instance_valid(hint):
		hint.visible = false

	var log_panel = get_node_or_null("UI/BattleLogPanel")
	if not log_panel:
		return

	_autogrind_console = RichTextLabel.new()
	_autogrind_console.name = "AutogrindConsole"
	_autogrind_console.bbcode_enabled = true
	_autogrind_console.scroll_active = true
	_autogrind_console.scroll_following = true
	_autogrind_console.set_anchors_preset(Control.PRESET_FULL_RECT)
	_autogrind_console.add_theme_font_size_override("normal_font_size", TextScale.scaled(13))
	_autogrind_console.add_theme_font_size_override("bold_font_size", TextScale.scaled(14))
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
	var time_mult = stats.get("time_multiplier", 1.0)
	var turbo = " [color=#ff4444]TURBO[/color]" if turbo_mode else ""

	_autogrind_console.append_text("[color=#666677]─────────────────────────────[/color]\n")
	_autogrind_console.append_text("[color=#ffff66]Battle #%d[/color] | EXP: %d | Streak: %d | Eff: %.1fx | Time: %.1fx%s\n" % [battles, exp, streak, eff, time_mult, turbo])
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
		# Tick 239: bonus BBCode (autobattle-enabled feedback).
		log_message("[color=%s]Autobattle enabled - AI will control your turns[/color]" % AccessibilityPalette.bonus_bbcode())
	else:
		log_message("[color=gray]Autobattle disabled - manual control[/color]")


## Autobattle system functions
func _enable_all_autobattle() -> void:
	"""Enable autobattle for ALL players and immediately execute all remaining turns"""
	_all_autobattle_enabled = true
	AutobattleSystem.cancel_all_next_turn = false
	TutorialHints.show(self, "autobattle_toggle")

	# Enable autobattle for every party member
	for member in party_members:
		var char_id = member.combatant_name.to_lower().replace(" ", "_")
		AutobattleSystem.set_autobattle_enabled(char_id, true)

	# Play enable sound
	SoundManager.play_ui("autobattle_on")
	# Tick 239: bonus BBCode (all-players autobattle announcement).
	log_message("[color=%s]>>> AUTOBATTLE: ALL PLAYERS ENABLED[/color]" % AccessibilityPalette.bonus_bbcode())

	# Close any open menu
	_close_win98_menu()

	# If we're currently on a player's turn, execute their autobattle and let BattleManager continue
	if BattleManager.current_state == BattleManager.BattleState.PLAYER_SELECTING:
		BattleManager.execute_autobattle_for_current()

	_update_ui()


func _toggle_cancel_all_autobattle() -> void:
	"""Disable autobattle IMMEDIATELY when Select is pressed during execution.

	Pre-2026-05-03 behavior was 'queue cancel for next turn' which felt
	unresponsive — autobattle would keep running through already-queued
	actions for the rest of the round before disabling. User feedback:
	'why cant I disable autobattle anymore — the usual ones dont work'.

	Now: instantly clears autobattle_enabled[char_id] for every party
	member. Any action currently animating still finishes (we don't
	interrupt mid-tween), and any actions ALREADY queued for this round
	still execute (they're committed in BattleManager's action queue).
	But no new autobattle decisions fire after this point — next
	selection phase the player is fully back in manual control."""
	_cancel_all_autobattle()  # Immediate, sets per-character disabled
	SoundManager.play_ui("autobattle_off")


func _cancel_autobattle_during_execution() -> void:
	"""Cancel autobattle IMMEDIATELY when B is pressed during execution.
	Same instant-disable semantics as _toggle_cancel_all_autobattle —
	mirrored here so both Select and B do the same thing during execution
	(matches user expectation 'press cancel = stop the auto fight')."""
	_cancel_all_autobattle()
	SoundManager.play_ui("autobattle_off")


func _cancel_all_autobattle() -> void:
	"""Immediately cancel autobattle for all players AND clear any queued
	auto-actions, so the disable feels snappy regardless of whether the
	user was mid-execution or in selection phase.
	(Audit-fix 2026-05-04: previously this only flipped state, leaving
	queued auto-actions in BattleManager.execution_order to play out the
	rest of the round. Felt unresponsive vs. the GameLoop._toggle_all_
	autobattle path — consistency fix.)"""
	_all_autobattle_enabled = false
	AutobattleSystem.cancel_all_next_turn = false

	# Disable autobattle for every party member
	for member in party_members:
		var char_id = member.combatant_name.to_lower().replace(" ", "_")
		AutobattleSystem.set_autobattle_enabled(char_id, false)

	# Strip remaining player auto-actions — same behavior as the
	# GameLoop._toggle_all_autobattle path, so all disable surfaces feel
	# identical to the user.
	if BattleManager and BattleManager.has_method("clear_pending_player_actions"):
		BattleManager.clear_pending_player_actions()

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

	# Tutorial popups (fire once per save)
	TutorialHints.show(self, "first_battle")
	if _check_for_boss():
		TutorialHints.show(self, "first_boss")

	# Restore persisted battle speed
	Engine.time_scale = BATTLE_SPEEDS[_battle_speed_index]
	_update_speed_indicator()

	# Apply any pending autobattle cancellation from previous battle
	if AutobattleSystem.cancel_all_next_turn:
		_cancel_all_autobattle()

	_update_ui()
	# Battle start quips — party members react to encounters
	_show_battle_quip()
	# Start battle music - use boss music if fighting a miniboss
	var is_boss_fight = _check_for_boss()
	var boss_type = _get_boss_type()
	var masterite_type = _get_masterite_type()
	if is_boss_fight:
		if masterite_type != "":
			# Masterite bosses have per-role, per-world music tracks
			var world_suffix = SoundManager._get_current_world_suffix()
			var music_track = "boss_%s_%s" % [masterite_type, world_suffix]
			_base_music_track = music_track
			SoundManager.play_music(music_track)
			print("[MUSIC] Playing Masterite %s theme (%s)" % [masterite_type, world_suffix])
		elif boss_type == "cave_rat_king":
			_base_music_track = "boss_rat_king"
			SoundManager.play_music("boss_rat_king")
			print("[MUSIC] Playing sneaky Rat King theme")
		elif boss_type == "chancellor_mordaine":
			# Mordaine has a dedicated track ("The Usurper's Shadow"
			# / boss_medieval) authored for the W1 final encounter.
			# Without this branch she would play the generic boss
			# theme — same audio as random minibosses, blunting the
			# climax of her cutscene-driven confrontation.
			_base_music_track = "boss_medieval"
			SoundManager.play_music("boss_medieval")
			print("[MUSIC] Playing Mordaine theme — 'The Usurper's Shadow'")
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
	_masterite_phase2_swapped = false
	## Tick 428: reset per-battle boss-dialogue latches.
	_boss_low_hp_spoken = false
	_boss_defeat_spoken = false


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


func _get_masterite_type() -> String:
	"""Get the Masterite role (warden/arbiter/tempo/curator) if fighting a Masterite boss"""
	for enemy in test_enemies:
		if enemy and is_instance_valid(enemy):
			if enemy.has_meta("masterite") and enemy.get_meta("masterite"):
				return enemy.get_meta("masterite_type", "")
	return ""


func _get_terrain_battle_track() -> String:
	"""Get terrain-specific battle music track, or 'battle' for generic.
	   Areas with unique battle themes return 'battle_<terrain>'.
	   Tick 91: added 'steampunk' arm — W3 SteampunkOverworld emits
	   'steampunk' as the terrain string, which previously fell
	   through to generic 'battle' music despite SoundManager having
	   a dedicated _start_urban_battle_music helper that DID play the
	   manifest's battle_steampunk.ogg."""
	match _current_terrain:
		"suburban":
			return "battle_suburban"
		"steampunk":
			return "battle_steampunk"
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
	## Tick 428: boss defeat dialogue line. Pre-fix only `intro` was
	## wired — cave_rat_king, the dragons, etc. never spoke their
	## "you've bested me" beat. Fires on player victory ONLY if the
	## dialogue["defeat"] array is present. Find the boss combatant
	## (first enemy with is_boss meta) for the speaker name.
	if victory and not _boss_defeat_spoken and _boss_dialogue_data.has("defeat") and _boss_dialogue_data["defeat"].size() > 0:
		_boss_defeat_spoken = true
		var boss_name: String = "Boss"
		for enemy in test_enemies:
			if enemy and is_instance_valid(enemy) and enemy.has_meta("is_boss"):
				boss_name = enemy.combatant_name
				break
		if _battle_dialogue and _battle_dialogue.has_method("show_boss_intro"):
			_battle_dialogue.show_boss_intro(boss_name, _boss_dialogue_data["defeat"])

	# Clean up any open menus
	if active_win98_menu and is_instance_valid(active_win98_menu):
		print("[MENU-NULL] t=%dms path=battle_ended_cleanup" % Time.get_ticks_msec())
		active_win98_menu.queue_free()
		active_win98_menu = null

	# Clear any pending autobattle cancel — if the user queued a "cancel
	# next turn" via Select during execution but the battle ended before
	# the next turn fired, the queue would otherwise persist into the
	# next battle and surprise-disable autobattle on the first turn.
	# (User feedback 2026-05-03: "make sure autobattle state is sticky
	# between battles". Per-character `autobattle_enabled[char_id]` is
	# already sticky via the global AutobattleSystem dict; this clear
	# fixes the cancel-queue leak that was undermining stickiness.)
	AutobattleSystem.cancel_all_next_turn = false

	# Clear formation stat buffs (duration 999 shouldn't persist across battles)
	for member in party_members:
		if not is_instance_valid(member):
			continue
		for buff_idx in range(member.active_buffs.size() - 1, -1, -1):
			if member.active_buffs[buff_idx].get("effect", "").begins_with("formation_"):
				member.active_buffs.remove_at(buff_idx)
		for debuff_idx in range(member.active_debuffs.size() - 1, -1, -1):
			if member.active_debuffs[debuff_idx].get("effect", "").begins_with("formation_"):
				member.active_debuffs.remove_at(debuff_idx)

	if victory:
		# Tick 239: bonus BBCode (victory header).
		log_message("\n[color=%s]=== VICTORY ===[/color]" % AccessibilityPalette.bonus_bbcode())
		_battle_victory = true
		if not turbo_mode:
			log_message("[color=gray]Z / A / Click to continue...[/color]")
			SoundManager.play_battle("victory_stinger")
			_play_staggered_victory_animations()
			_show_victory_quip()
			if _check_for_boss():
				SoundManager.play_music("stinger_boss_defeated")
			else:
				SoundManager.play_music("victory")
			_show_victory_results()
	else:
		# Tick 239: penalty BBCode (defeat header).
		log_message("\n[color=%s]=== DEFEAT ===[/color]" % AccessibilityPalette.penalty_bbcode())
		log_message("[color=gray]Z / A / Click to restart...[/color]")
		# Play defeat animation for all party members
		for animator in party_animators:
			if animator:
				animator.play_defeat()
		# Spotlight duels have their own retry loop and the game_over ditty
		# stacks over every cycle, so skip it — retry-entry battle music
		# transitions cleanly. Non-spotlight defeats keep the ditty.
		var gl: Node = get_node_or_null("/root/GameLoop")
		var in_spotlight: bool = gl != null and "_spotlight_duel_active" in gl and bool(gl._spotlight_duel_active)
		if not in_spotlight:
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

	_tick_menu_watchdog()

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


## Menu-never-spawned self-heal (msg 2372/2379): force-spawn after MENU_WATCHDOG_MS, terminal-fallback to autobattle after MAX_RETRIES.
func _tick_menu_watchdog() -> void:
	var bm = BattleManager
	if bm == null:
		_reset_menu_watchdog()
		return
	if bm.current_state != bm.BattleState.PLAYER_SELECTING:
		_reset_menu_watchdog()
		return
	if bm.has_method("is_trust_interrupt_window_open") and bm.is_trust_interrupt_window_open():
		_reset_menu_watchdog()
		return
	var pc = bm.current_combatant
	if pc == null or not is_instance_valid(pc) or not pc.is_alive:
		_reset_menu_watchdog()
		return
	if not (pc in bm.player_party):
		_reset_menu_watchdog()
		return
	if is_instance_valid(active_win98_menu) and active_win98_menu.visible:
		_reset_menu_watchdog()
		return
	var now: int = Time.get_ticks_msec()
	if _menu_wd_started_ms == 0:
		_menu_wd_started_ms = now
		return
	if now - _menu_wd_started_ms < MENU_WATCHDOG_MS:
		return
	# A spotlight-locked PC can't hold a manual menu — skip the 3x force-spawn ladder (~10s) and autobattle-resolve now. EXCEPT its own solo duel: the duelist plays manually there, so keep retrying rather than stealing the turn.
	var own_solo_duel: bool = bm.player_party.size() == 1 and pc in bm.player_party
	if "autobattle_locked" in pc and pc.autobattle_locked and not own_solo_duel:
		log_message("[color=orange]⚠ %s auto-resolving turn (spotlight-locked, no manual menu)[/color]" % pc.combatant_name)
		_reset_menu_watchdog()
		if bm.has_method("execute_autobattle_for_current"):
			bm.execute_autobattle_for_current()
		return
	var elapsed: int = now - _menu_wd_started_ms
	if _menu_wd_retries >= MENU_WATCHDOG_MAX_RETRIES:
		# Terminal fallback (msg 2379): the menu is genuinely wedged; route via autobattle so the battle continues.
		push_error("[MENU-WATCHDOG] %s force-spawn failed %dx — routing via autobattle terminal fallback%s" % [pc.combatant_name, _menu_wd_retries, _menu_wd_diag(pc)])
		log_message("[color=red]⚠ Menu wedged after %d retries — routing via autobattle[/color]" % _menu_wd_retries)
		_reset_menu_watchdog()
		if bm.has_method("execute_autobattle_for_current"):
			bm.execute_autobattle_for_current()
		return
	push_warning("[MENU-WATCHDOG] %s PLAYER_SELECTING sat %dms without menu — force-spawn attempt %d/%d%s" % [pc.combatant_name, elapsed, _menu_wd_retries + 1, MENU_WATCHDOG_MAX_RETRIES, _menu_wd_diag(pc)])
	log_message("[color=orange]⚠ Menu recovery — spawning command menu for %s (attempt %d/%d)[/color]" % [pc.combatant_name, _menu_wd_retries + 1, MENU_WATCHDOG_MAX_RETRIES])
	_menu_wd_started_ms = now
	_menu_wd_retries += 1
	_show_win98_command_menu(pc)


## Diagnostic string dumped on watchdog trip (msg 2400 root-hunt): why the menu didn't spawn on the last _show_win98_command_menu call, plus known contributing state.
func _menu_wd_diag(pc: Combatant) -> String:
	var reason: String = "unknown"
	if _command_menu and "last_silent_return_reason" in _command_menu:
		reason = _command_menu.last_silent_return_reason
		if reason == "":
			reason = "spawn_ok_then_closed"
	var char_id: String = pc.combatant_name.to_lower().replace(" ", "_") if pc else "?"
	var ab_locked: bool = "autobattle_locked" in pc and pc.autobattle_locked
	var ab_enabled: bool = AutobattleSystem.is_autobattle_enabled(char_id) if AutobattleSystem else false
	var dbg_unlocked: bool = GameState.debug_all_pcs_unlocked if (GameState and "debug_all_pcs_unlocked" in GameState) else false
	var in_party: bool = pc in BattleManager.player_party if BattleManager else false
	var sprite_ct: int = party_sprite_nodes.size()
	# msg 2472 bonus: dump the per-job loss counter so tuning caps see the current tier at trip time. Reads pc.job.id; empty if the combatant has no job dict.
	var pc_job_id: String = ""
	if pc and pc.job is Dictionary:
		pc_job_id = str((pc.job as Dictionary).get("id", ""))
	var spotlight_losses: int = 0
	if pc_job_id != "" and GameState and "game_constants" in GameState:
		spotlight_losses = int(GameState.game_constants.get("spotlight_losses_" + pc_job_id, 0))
	# msg 2503 diagnostic — distinguish "menu freed" (invalid) from "menu valid but hidden" (someone called set_command_menu_visible(false) or set .visible=false directly). "valid-but-invisible" fingerprints the autobattle-editor-still-open / hidden-menu class specifically.
	var menu_status: String
	if not is_instance_valid(active_win98_menu):
		menu_status = "invalid"
	elif not active_win98_menu.visible:
		menu_status = "valid_but_invisible"
	else:
		menu_status = "valid_visible"  # should be unreachable — watchdog would have reset
	return " [reason=%s menu=%s ab_locked=%s ab_enabled=%s dbg_unlocked=%s in_party=%s sprite_ct=%d spotlight_losses=%d]" % [reason, menu_status, ab_locked, ab_enabled, dbg_unlocked, in_party, sprite_ct, spotlight_losses]


func _reset_menu_watchdog() -> void:
	_menu_wd_started_ms = 0
	_menu_wd_retries = 0


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


func _get_formation_offset(member_idx: int, party_size: int) -> Vector2:
	"""Calculate position offset for a party member based on current formation.

	Offset arrays are sized for the strict-5 party (Fighter/Cleric/Rogue/Mage/Bard).
	Member-index out-of-range cases fall through to Vector2.ZERO so a future
	temporarily-smaller party (debug scenario) doesn't crash, but for >5 the
	5th-slot offset is reused — adjust the constants here if the design ever
	grows past 5."""
	match current_formation:
		PartyFormation.V_FORMATION:
			# Classic JRPG V-shape: front members lower, back higher.
			# Offsets scaled to 110px Y-gap so the stagger reads cleanly
			# at the wider party spacing (previously ±12 at 75px gap).
			var y_offsets = [18.0, 9.0, 0.0, -9.0, -18.0]
			return Vector2(0, y_offsets[member_idx] if member_idx < y_offsets.size() else 0.0)

		PartyFormation.FRONT_LINE:
			# All in a row, pushed forward (left toward enemies).
			# y-spread widened from ±20 to ±30 to match 110px base gap.
			var y_spread = [-30.0, -15.0, 0.0, 15.0, 30.0]
			var y = y_spread[member_idx] if member_idx < y_spread.size() else 0.0
			return Vector2(-30, y)

		PartyFormation.BACK_ROW:
			# All pushed back (right away from enemies).
			# y-spread widened from ±20 to ±30 to match 110px base gap.
			var y_spread = [-30.0, -15.0, 0.0, 15.0, 30.0]
			var y = y_spread[member_idx] if member_idx < y_spread.size() else 0.0
			return Vector2(30, y)

		PartyFormation.DIAMOND:
			# 1 front, 2 mid, 2 back — tank formation expanded for strict-5.
			# y offsets scaled to 110px gap (±20→±30, ±12→±18).
			match member_idx:
				0: return Vector2(-25, 0)    # Front (tank)
				1: return Vector2(0, -30)    # Mid-top
				2: return Vector2(0, 30)     # Mid-bottom
				3: return Vector2(25, -18)   # Back-top
				4: return Vector2(25, 18)    # Back-bottom
				_: return Vector2.ZERO

		PartyFormation.SPREAD:
			# Wide spacing to resist AoE — 5-member staggered pattern.
			# y-spread widened from ±40 to ±55 to match 110px base gap.
			var y_offsets = [-55.0, -27.0, 0.0, 27.0, 55.0]
			var x_offsets = [-15.0, 0.0, -15.0, 0.0, -15.0]
			var y = y_offsets[member_idx] if member_idx < y_offsets.size() else 0.0
			var x = x_offsets[member_idx] if member_idx < x_offsets.size() else 0.0
			return Vector2(x, y)

	return Vector2.ZERO


func cycle_formation() -> void:
	"""Cycle to the next party formation and reposition sprites"""
	current_formation = (current_formation + 1) % PartyFormation.size()
	var fname = FORMATION_NAMES[current_formation]
	var desc = FORMATION_DESCRIPTIONS[current_formation]
	log_message("[color=cyan]Formation: %s — %s[/color]" % [fname, desc])
	SoundManager.play_ui("menu_move")
	TutorialHints.show(self, "first_formation")

	# Smoothly reposition party sprites
	for i in range(party_sprite_nodes.size()):
		if i >= party_positions.size():
			break
		var sprite = party_sprite_nodes[i]
		if not is_instance_valid(sprite):
			continue
		var base_pos = party_positions[i].global_position
		var offset = _get_formation_offset(i, party_members.size())
		var new_pos = base_pos + offset
		_party_base_positions[i] = new_pos

		var tween = create_tween()
		tween.tween_property(sprite, "position", new_pos, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Apply formation stat modifiers via BattleManager
	_apply_formation_stats()


func _apply_formation_stats() -> void:
	"""Apply stat modifiers based on current formation"""
	# Clear previous formation buffs and debuffs
	for member in party_members:
		if not is_instance_valid(member):
			continue
		for buff_idx in range(member.active_buffs.size() - 1, -1, -1):
			if member.active_buffs[buff_idx].get("effect", "").begins_with("formation_"):
				member.active_buffs.remove_at(buff_idx)
		for debuff_idx in range(member.active_debuffs.size() - 1, -1, -1):
			if member.active_debuffs[debuff_idx].get("effect", "").begins_with("formation_"):
				member.active_debuffs.remove_at(debuff_idx)

	match current_formation:
		PartyFormation.FRONT_LINE:
			for member in party_members:
				if is_instance_valid(member) and member.is_alive:
					member.add_buff("formation_atk", "attack", 1.1, 999)
					member.add_debuff("formation_def", "defense", 0.9, 999)
		PartyFormation.BACK_ROW:
			for member in party_members:
				if is_instance_valid(member) and member.is_alive:
					member.add_buff("formation_def", "defense", 1.1, 999)
					member.add_debuff("formation_atk", "attack", 0.9, 999)
		# V_FORMATION, DIAMOND, SPREAD: no flat stat modifiers (effects are situational)


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

	# Update buff/debuff visual overlays for all combatants
	_update_buff_debuff_visuals(delta)


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
	_active_inline_editor = editor
	print("Autobattle editor opened for %s (hold-A)" % char_name)


## Tick 409: Scriptweaver's create_autobattle_script meta-ability fires
## this. Opens the editor for the caster (target_type=self per ability
## data) and clears the meta_autobattle_editor_requested flag so a
## subsequent in-battle save doesn't re-trigger the editor.
func _on_meta_autobattle_editor_requested(caster: Combatant) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	_open_autobattle_editor_for(caster)
	if GameState and "game_constants" in GameState:
		GameState.game_constants["meta_autobattle_editor_requested"] = false


func _on_inline_autobattle_editor_closed(editor: Control) -> void:
	"""Handle inline autobattle editor closing"""
	if editor and is_instance_valid(editor):
		editor.queue_free()
	if _active_inline_editor == editor:
		_active_inline_editor = null
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
		print("[MENU-NULL] t=%dms path=restart_battle_cleanup" % Time.get_ticks_msec())
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


## BDFFHD signature: the active PC sprite slides slightly toward the
## enemies (left, since the party is anchored on the right) at the start
## of their selection turn, then slides back into formation when the
## turn ends. Clear who's-up signal without needing a portrait highlight
## or arrow indicator. Per cowir-battle's design lock 2026-06-04.
const ACTIVE_PC_STEP_OUT_OFFSET: float = -80.0
const ACTIVE_PC_STEP_TWEEN_TIME: float = 0.18
const ACTIVE_PC_DIM_COLOR: Color = Color(0.55, 0.55, 0.65, 1.0)


func _step_active_pc(combatant: Combatant, step_out: bool) -> void:
	if combatant == null or not (combatant in BattleManager.player_party):
		return
	var idx: int = BattleManager.player_party.find(combatant)
	if idx < 0 or idx >= party_sprite_nodes.size() or idx >= _party_base_positions.size():
		return
	var sprite = party_sprite_nodes[idx]
	if not is_instance_valid(sprite):
		return
	var base: Vector2 = _party_base_positions[idx]
	var target: Vector2 = base + Vector2(ACTIVE_PC_STEP_OUT_OFFSET, 0.0) if step_out else base
	var tween = create_tween()
	tween.tween_property(sprite, "position", target, ACTIVE_PC_STEP_TWEEN_TIME) \
		.set_trans(Tween.TRANS_QUAD) \
		.set_ease(Tween.EASE_OUT if step_out else Tween.EASE_IN)
	_dim_inactive_party(idx, step_out)


func _dim_inactive_party(active_idx: int, dim_others: bool) -> void:
	for i in party_sprite_nodes.size():
		var s = party_sprite_nodes[i]
		if not is_instance_valid(s):
			continue
		var target_mod: Color = Color.WHITE
		if dim_others and i != active_idx:
			target_mod = ACTIVE_PC_DIM_COLOR
		var t = create_tween()
		t.tween_property(s, "modulate", target_mod, ACTIVE_PC_STEP_TWEEN_TIME)


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
			TutorialHints.show(self, "advance_defer")
		# BDFFHD signature step-out toward the enemies — clear who's-up cue.
		_step_active_pc(combatant, true)
	if use_win98_menus and is_player:
		_show_win98_command_menu(combatant)


func _on_selection_turn_ended(combatant: Combatant) -> void:
	"""Handle selection turn end"""
	_close_win98_menu()
	# Return the active PC to formation (no-op for enemies).
	_step_active_pc(combatant, false)
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
		"advance":
			pass  # Advance sub-actions handle their own animations
		"item":
			animator.play_item()
		"defer":
			animator.play_named_animation("defer")


func _on_group_attack_executing(participants: Array, group_type: String, targets: Array, formation_id: String = "") -> void:
	"""Play simultaneous attack animations on all party members for group actions"""
	_update_turn_info()
	TutorialHints.show(self, "group_attacks")

	# Group attack SFX — per-formation sounds when available
	if group_type == "formation" and formation_id != "":
		var formation_key = "formation_" + formation_id
		if not _try_play_formation_sfx(formation_key):
			SoundManager.play_battle("group_formation")
	else:
		match group_type:
			"limit_break":
				SoundManager.play_battle("group_limit_break")
				# Play job stinger for party leader on limit break
				if participants.size() > 0 and participants[0] is Combatant:
					var job_id = participants[0].job.get("id", "fighter") if participants[0].job else "fighter"
					var stinger_path = "res://assets/audio/music/job_%s_special.ogg" % job_id
					if ResourceLoader.exists(stinger_path):
						SoundManager.play_music("job_%s_special" % job_id)
			"combo_magic":
				SoundManager.play_battle("group_combo_magic")
			_:
				SoundManager.play_battle("group_all_out")

	# Screen shake — intensity scales with group type
	var shake_intensity: float
	var shake_duration: float
	match group_type:
		"limit_break":
			shake_intensity = 18.0
			shake_duration = 0.6
		"combo_magic":
			shake_intensity = 14.0
			shake_duration = 0.5
		"formation":
			shake_intensity = 12.0
			shake_duration = 0.45
		_:
			shake_intensity = 10.0
			shake_duration = 0.35
	EffectSystem._trigger_screen_shake(shake_intensity, shake_duration)

	# Flash the whole battlefield — distinct color per group type
	var flash_color: Color
	match group_type:
		"limit_break":
			flash_color = Color(1.0, 0.85, 0.0, 0.55)  # Gold
		"combo_magic":
			flash_color = Color(0.7, 0.2, 1.0, 0.5)     # Purple
		"formation":
			flash_color = Color(0.2, 0.9, 1.0, 0.45)     # Cyan
		_:
			flash_color = Color(1.0, 0.5, 0.0, 0.4)      # Orange
	_spawn_screen_flash(flash_color, 0.55 if group_type == "combo_magic" else 0.45)

	# Limit Break: second brighter gold flash for drama
	if group_type == "limit_break":
		_spawn_screen_flash(Color(1.0, 1.0, 0.7, 0.4), 0.3, 0.1)

	# Combo Magic: second pulsing cyan flash
	if group_type == "combo_magic":
		_spawn_screen_flash(Color(0.2, 0.8, 1.0, 0.35), 0.4, 0.15)

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

		# Limit Break: each party member lunges at a different enemy (or wraps around)
		if group_type == "limit_break" and targets.size() > 0 and sprite:
			var target_idx = BattleManager.player_party.find(participant) % targets.size()
			var target_combatant = targets[target_idx] as Combatant
			var target_sprite = _get_combatant_sprite(target_combatant)
			if target_sprite:
				# Stagger lunges slightly for visual impact
				var target_anim: BattleAnimatorClass = null
				var enemy_idx = BattleManager.enemy_party.find(target_combatant)
				if enemy_idx >= 0 and enemy_idx < enemy_animators.size():
					target_anim = enemy_animators[enemy_idx]
				_animate_melee_attack(sprite, target_sprite, anim, target_anim)
				# Spawn physical hit effect on impact (msg 2569 #1: stable anchor so mid-tween targets don't drag the effect off)
				EffectSystem.spawn_effect(EffectSystem.EffectType.PHYSICAL, _stable_sprite_anchor(target_sprite))
				continue
		# Combo Magic: casters step forward, cast animation, converging spell effects
		if group_type == "combo_magic":
			if sprite:
				# Store home and step forward
				if not sprite.has_meta("home_position"):
					sprite.set_meta("home_position", sprite.position)
				var home = sprite.get_meta("home_position")
				var step_pos = home + Vector2(-30, 0)  # Step toward enemies

				var cast_tween = create_tween()
				sprite.set_meta("attack_tween", cast_tween)

				# Staggered step forward
				cast_tween.tween_interval(idx * 0.08)
				cast_tween.tween_property(sprite, "position", step_pos, 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

				# Cast animation
				cast_tween.tween_callback(func():
					if anim and is_instance_valid(anim):
						anim.play_named_animation("cast")
				)

				# Spawn spell effects on targets — each caster contributes one element type
				var combo_effects = [EffectSystem.EffectType.FIRE, EffectSystem.EffectType.ICE, EffectSystem.EffectType.LIGHTNING]
				var my_effect = combo_effects[idx % combo_effects.size()]
				cast_tween.tween_interval(0.15)
				cast_tween.tween_callback(func():
					for target in targets:
						var t_sprite2 = _get_combatant_sprite(target as Combatant)
						if t_sprite2 and is_instance_valid(t_sprite2):
							# Spawn from caster's position toward target for "converging" feel — stable anchor + scatter offset (msg 2569 #1)
							var offset = Vector2(randf_range(-15, 15), randf_range(-15, 15))
							EffectSystem.spawn_effect(my_effect, _stable_sprite_anchor(t_sprite2) + offset, Callable(), 1.5)
				)

				# Hold then return
				cast_tween.tween_interval(0.3)
				cast_tween.tween_property(sprite, "position", home, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
			else:
				anim.play_named_animation("cast")
			continue
		# All-Out Attack: party rushes in together toward enemies
		if group_type == "all_out_attack" and sprite and targets.size() > 0:
			# Calculate center of enemy formation as rush target
			var enemy_center = Vector2.ZERO
			var enemy_count = 0
			for t in targets:
				var ts = _get_combatant_sprite(t as Combatant)
				if ts:
					enemy_center += ts.position
					enemy_count += 1
			if enemy_count > 0:
				enemy_center /= enemy_count

			# Store home position
			if not sprite.has_meta("home_position"):
				sprite.set_meta("home_position", sprite.position)
			var home = sprite.get_meta("home_position")

			# Each member lunges to a slightly offset position near enemy center
			var direction = (enemy_center - home).normalized()
			var rush_pos = enemy_center - direction * (50 + idx * 15)  # Stagger depth

			var rush_tween = create_tween()
			sprite.set_meta("attack_tween", rush_tween)

			# Staggered start (0-0.1s per member)
			var stagger = idx * 0.05
			rush_tween.tween_interval(stagger)

			# Rush forward
			rush_tween.tween_property(sprite, "position", rush_pos, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

			# Attack animation + hit effects on all enemies
			rush_tween.tween_callback(func():
				if not is_instance_valid(self): return
				if anim and is_instance_valid(anim):
					anim.play_attack()
				for t in targets:
					var ts2 = _get_combatant_sprite(t as Combatant)
					if ts2 and is_instance_valid(ts2):
						# Scattered impact bursts on all enemies at rush moment — anchor to stable rest so mid-hit knockback doesn't drag them (msg 2569 #1)
						EffectSystem.spawn_effect(EffectSystem.EffectType.PHYSICAL, _stable_sprite_anchor(ts2) + Vector2(randf_range(-8, 8), randf_range(-8, 8)))
						var eidx = BattleManager.enemy_party.find(t)
						if eidx >= 0 and eidx < enemy_animators.size():
							enemy_animators[eidx].play_hit()
			)

			# Hold briefly at impact
			rush_tween.tween_interval(0.2)

			# Return home
			rush_tween.tween_property(sprite, "position", home, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
			continue

		# Formation/fallback: play attack animation in place + physical effects (stable anchor per msg 2569 #1)
		anim.play_attack()
		for target in targets:
			var t_sprite = _get_combatant_sprite(target as Combatant)
			if t_sprite:
				EffectSystem.spawn_effect(EffectSystem.EffectType.PHYSICAL, _stable_sprite_anchor(t_sprite))

	# Safety net: force-reset all party sprites to home positions after rush animations
	# This catches any case where a return-home tween gets interrupted or killed
	if group_type in ["all_out_attack", "combo_magic", "limit_break", "formation"]:
		# Bound method (not lambda): auto-disconnects when self frees — lambda captures logged "capture was freed" engine errors at battle teardown.
		get_tree().create_timer(1.5).timeout.connect(_snap_party_sprites_home)


## Safety-net reset for a single attacker after their action resolves.
## Restores the sprite to home_position and returns the animator to
## idle so monsters (or players) can't get stuck frozen at the attack
## frame/position when the return tween was interrupted.
func _reset_attacker_home(combatant: Combatant) -> void:
	if not combatant or not is_instance_valid(combatant):
		return
	var sprite = _get_combatant_sprite(combatant)
	var animator = _get_combatant_animator(combatant)
	# Give the existing return-home tween a bit of time to complete before
	# we forcibly snap — otherwise we fight it and look jittery.
	get_tree().create_timer(0.7).timeout.connect(_delayed_snap_and_idle.bind(sprite, animator))


## Timer-safe helpers: bound methods auto-disconnect when self frees, so battle teardown can't fire them with freed captures (smoke-log engine-error class, 2026-07-11).
func _delayed_snap_and_idle(sprite, animator) -> void:
	if sprite and is_instance_valid(sprite) and sprite.has_meta("home_position"):
		var home = sprite.get_meta("home_position")
		if sprite.position.distance_to(home) > 2.0:
			sprite.position = home
	if animator and is_instance_valid(animator):
		animator.set_idle()


func _delayed_play_hit_fx(target_anim, target_sprite) -> void:
	if target_anim and is_instance_valid(target_anim) and is_instance_valid(target_sprite):
		target_anim.play_hit()
		# Stable anchor: multi-hit chains can arrive while target is still tweening back from the previous hit (msg 2569 #1)
		EffectSystem.spawn_effect(EffectSystem.EffectType.PHYSICAL, _stable_sprite_anchor(target_sprite))
		var kb_dir = -1.0 if enemy_sprite_nodes.has(target_sprite) else 1.0
		_apply_hit_knockback(target_sprite, kb_dir)
		_apply_hit_flash(target_sprite)


func _delayed_play_victory(animator) -> void:
	if is_instance_valid(animator):
		animator.play_victory()


func _snap_party_sprites_home() -> void:
	"""Force all party sprites to their stored home positions — safety net after group attacks"""
	for i in range(party_sprite_nodes.size()):
		var sprite = party_sprite_nodes[i]
		if not is_instance_valid(sprite):
			continue
		if sprite.has_meta("home_position"):
			var home = sprite.get_meta("home_position")
			# Only snap if significantly displaced (>20px from home)
			if sprite.position.distance_to(home) > 20:
				var tween = create_tween()
				tween.tween_property(sprite, "position", home, 0.15).set_trans(Tween.TRANS_CUBIC)


## Item 19: round-start universal sprite snap. Extends the existing
## group-attack safety net to run on EVERY round_started so a stray
## displaced sprite from an interrupted single-attacker return-home
## tween (user report: Bard "stuck for a turn next to the monsters
## on the left") gets caught at the top of the next round instead of
## rendering wrong for a full turn. Covers party AND enemies since
## monsters can also step out and get interrupted.
func _on_round_started_snap_home(_round_num: int) -> void:
	_snap_party_sprites_home()
	for i in range(enemy_sprite_nodes.size()):
		var sprite = enemy_sprite_nodes[i]
		if not is_instance_valid(sprite):
			continue
		if sprite.has_meta("home_position"):
			var home = sprite.get_meta("home_position")
			if sprite.position.distance_to(home) > 20:
				var tween = create_tween()
				tween.tween_property(sprite, "position", home, 0.15).set_trans(Tween.TRANS_CUBIC)


func _try_play_formation_sfx(formation_key: String) -> bool:
	"""Try to play a formation-specific SFX. Returns true if found in manifest."""
	if SoundManager._sfx_manifest.has(formation_key):
		SoundManager.play_battle(formation_key)
		return true
	return false


## Accessibility (photosensitivity): the "Reduce Flashes" setting suppresses the
## full-screen battle flashes. Static so the gate is unit-testable without a scene.
static func _flashes_suppressed() -> bool:
	return GameState.reduce_flashes if ("reduce_flashes" in GameState) else false


func _spawn_screen_flash(color: Color, fade_duration: float, delay: float = 0.0) -> void:
	"""Spawn a full-screen color flash that fades out"""
	if _flashes_suppressed():
		return
	var flash = ColorRect.new()
	flash.color = color
	flash.anchors_preset = Control.PRESET_FULL_RECT
	flash.z_index = 50
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	var t = create_tween()
	if delay > 0.0:
		t.tween_interval(delay)
	t.tween_property(flash, "modulate:a", 0.0, fade_duration)
	t.tween_callback(flash.queue_free)


func _animate_melee_attack(attacker_sprite: Node2D, target_sprite: Node2D, attacker_anim: BattleAnimatorClass, target_anim: BattleAnimatorClass) -> void:
	"""Animate attacker moving to target, attacking, then returning"""
	# Store home position as metadata to ensure we can always return
	if not attacker_sprite.has_meta("home_position"):
		attacker_sprite.set_meta("home_position", attacker_sprite.position)
	var home_pos = attacker_sprite.get_meta("home_position")
	# 2026-07-14 playtest: don't chase the target's transient tween position — if the target is still returning home from its own attack, aim at where it settles.
	var target_pos = target_sprite.get_meta("home_position", target_sprite.position)

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

	# Play lunge/dash windup animation in parallel with the position tween below.
	# Falls back gracefully: if no 'lunge' animation exists in SpriteFrames,
	# play_animation invokes on_complete synchronously (commit 0a02aed) and the
	# attack chain continues unchanged. We probe directly for the animation to
	# avoid even firing the warning push when sprites lack lunge frames.
	if attacker_anim and is_instance_valid(attacker_anim):
		var attacker_animated_sprite: AnimatedSprite2D = attacker_anim.sprite
		if attacker_animated_sprite \
				and attacker_animated_sprite.sprite_frames \
				and attacker_animated_sprite.sprite_frames.has_animation("lunge"):
			attacker_anim.play_lunge()

	# Move to target (fast)
	tween.tween_property(attacker_sprite, "position", attack_pos, 0.15)

	# Play attack animation and hit on target
	tween.tween_callback(func():
		if not is_instance_valid(self):
			return
		if attacker_anim and is_instance_valid(attacker_anim):
			attacker_anim.play_attack()
		# Brief delay then play hit
		get_tree().create_timer(0.1).timeout.connect(_delayed_play_hit_fx.bind(target_anim, target_sprite))
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


## Stable rest anchor for effect/popup spawn positions — same class of fix as v3.33.158/167/170 (msg 2569 #1). Prefers _party_base_positions / _enemy_base_positions (idle rest, stamped at sprite spawn) when the sprite is in one of the tracked arrays; falls back to live global_position for orphan sprites or pre-append states. Fixes the "hit effect drags with target during mid-tween" class the same way BattleResultsDisplay._get_combatant_sprite_position was fixed in v3.33.178.
func _stable_sprite_anchor(sprite: Node2D) -> Vector2:
	if not is_instance_valid(sprite):
		return Vector2.ZERO
	var party_idx: int = party_sprite_nodes.find(sprite)
	if party_idx >= 0 and party_idx < _party_base_positions.size():
		return _party_base_positions[party_idx]
	var enemy_idx: int = enemy_sprite_nodes.find(sprite)
	if enemy_idx >= 0 and enemy_idx < _enemy_base_positions.size():
		return _enemy_base_positions[enemy_idx]
	return sprite.global_position


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
	# Refresh status icons to update turn counters after duration ticks
	for combatant in _status_icon_containers.keys():
		if is_instance_valid(combatant) and combatant.is_alive:
			_refresh_status_icons(combatant)
	# struktured 2026-07-16: "should be more obvious when a round ends and AP +1 is granted, bravely default makes that quite obv" — banner + gold AP flash.
	_show_round_banner(round_num)


## Bravely Default-style round boundary: brief centered banner + AP-label gold flash on the party panel. Suppressed at 4x+ (same convention as speech bubbles); duration scales with battle speed.
func _show_round_banner(round_num: int) -> void:
	if turbo_mode or autogrind_console_mode or Engine.time_scale >= 1.0:
		return
	var banner := Label.new()
	banner.text = "— ROUND %d —   +1 AP" % (round_num + 1)
	banner.add_theme_font_size_override("font_size", TextScale.scaled(26))
	banner.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35))
	banner.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.02))
	banner.add_theme_constant_override("outline_size", 6)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.z_index = 90
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := get_viewport_rect().size
	banner.position = Vector2(vp.x / 2 - 220, vp.y * 0.30)
	banner.custom_minimum_size = Vector2(440, 40)
	banner.modulate.a = 0.0
	var ui = get_node_or_null("UI")
	(ui if ui else self).add_child(banner)
	SoundManager.play_ui("menu_select")
	var t := create_tween()
	t.tween_property(banner, "modulate:a", 1.0, 0.12)
	t.parallel().tween_property(banner, "position:y", banner.position.y - 14, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.45)
	t.tween_property(banner, "modulate:a", 0.0, 0.25)
	t.tween_callback(banner.queue_free)
	if _ui_manager and _ui_manager.has_method("flash_ap_labels"):
		_ui_manager.flash_ap_labels()


func _on_action_executed(combatant: Combatant, action: Dictionary, targets: Array) -> void:
	"""Handle action execution — play buff/debuff/status sounds based on ability effect"""
	_update_ui()
	_check_masterite_phase2_music_swap()
	# Safety net: if the attacker's melee-attack tween was interrupted
	# (target died mid-animation, scene refresh, battle-speed change,
	# etc.), force the sprite back to its stored home position and
	# reset the animator to idle. Previously monsters could get stuck
	# at the attack_pos + attack frame when the return-home tween died.
	_reset_attacker_home(combatant)
	var action_type = action.get("type", "")
	if action_type == "ability":
		var ability_id = action.get("ability_id", "")
		var ability = JobSystem.get_ability(ability_id)
		if not ability.is_empty():
			var effect = ability.get("effect", "")
			match effect:
				"defense_up", "attack_up", "volatility_up_self", "volatility_down":
					SoundManager.play_battle("buff")
				# stat reductions share the generic debuff cue (cowir-sfx rec) — bespoke cues reserved for the scary/unique statuses
				"defense_down", "volatility_up", "attack_down", "magic_down", "magic_defense_down", "speed_down", "all_stats_down", "random_debuff", "dispel", "pacify", "amplify_poison":
					SoundManager.play_battle("debuff")
				"ability_silence", "silence":
					SoundManager.play_status("silence")
				"":
					pass
				# every other status (poison/sleep/doom/curse/stun/burn/freeze/...) — play_status does status_<name> manifest lookup with a generic fallback, so F1-activated effects can't land silently again
				_:
					SoundManager.play_status(effect)


func _check_masterite_phase2_music_swap() -> void:
	# Latch once per battle when a Masterite boss escalates to phase 2.
	if _masterite_phase2_swapped or _is_danger_music:
		return
	for enemy in test_enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		var phase: int = int(enemy.get_meta("masterite_battle_phase", 1))
		var mtype: String = str(enemy.get_meta("masterite_type", ""))
		if phase >= 2 and mtype != "":
			var track: String = "boss_phase2_%s" % mtype
			_base_music_track = track
			SoundManager.play_music(track)
			_masterite_phase2_swapped = true
			return


## Combatant event handlers
func _on_party_hp_changed(old_value: int, new_value: int, member_idx: int) -> void:
	"""Handle party member HP change"""
	_update_ui()
	if new_value < old_value and member_idx < party_animators.size():
		# Play hit animation when taking damage
		party_animators[member_idx].play_hit()
	# Ally KO quip — when a party member drops to 0 HP, a living ally reacts
	if new_value <= 0 and old_value > 0:
		## Tick 176: announce the KO in the battle log. Pre-fix party
		## member deaths were silent in the log — the HP bar dropped to
		## 0, an optional ally quip fired ("Hero, no!"), but no clear
		## line said "X has fallen!" Enemy deaths emit
		## "X has been defeated!" via _on_enemy_died at line 3296;
		## this closes the parity gap so the player gets the same
		## scannable feedback when one of THEIR members goes down.
		if member_idx < party_members.size():
			var member = party_members[member_idx]
			if member is Combatant:
				# Tick 239: penalty BBCode (party member fallen).
				log_message("[color=%s]✖ %s has fallen![/color]" % [AccessibilityPalette.penalty_bbcode(), member.combatant_name])
		var alive_allies = party_members.filter(func(m): return m is Combatant and m.is_alive and party_members.find(m) != member_idx)
		if alive_allies.size() > 0:
			var reactor = alive_allies[randi() % alive_allies.size()]
			_try_combat_quip(ALLY_KO_QUIPS, reactor)


func _on_party_ap_changed(old_value: int, new_value: int, member_idx: int) -> void:
	"""Handle party member AP change"""
	_update_ui()


func _on_status_added(status: String, combatant: Combatant) -> void:
	"""Apply visual indicator for status effect"""
	var sprite = _get_combatant_sprite(combatant)
	if not sprite:
		return
	_apply_status_visual(sprite, combatant)


func _on_status_removed(status: String, combatant: Combatant) -> void:
	"""Remove visual indicator for status effect"""
	var sprite = _get_combatant_sprite(combatant)
	if not sprite:
		return
	_apply_status_visual(sprite, combatant)


func _apply_status_visual(sprite: Node2D, combatant: Combatant) -> void:
	"""Apply or reset sprite modulate based on current active status effects.
	KO state takes priority and is handled by BattleUIManager; this only runs
	for living combatants so we check is_alive before touching modulate."""
	if not combatant.is_alive:
		return
	var effects: Array = combatant.status_effects
	if effects.is_empty():
		sprite.modulate = Color.WHITE
		return
	# Priority order: first matching status wins
	for effect in effects:
		match effect:
			"poison":
				sprite.modulate = Color(0.7, 1.0, 0.7)   # Green tint
				return
			"burning":
				sprite.modulate = Color(1.0, 0.6, 0.4)   # Orange-red
				return
			"curse":
				sprite.modulate = Color(0.7, 0.4, 0.8)   # Purple
				return
			"stun":
				sprite.modulate = Color(1.0, 1.0, 0.5)   # Yellow
				return
			"sleep":
				sprite.modulate = Color(0.8, 0.8, 1.0)   # Pale blue
				return
			"blind":
				sprite.modulate = Color(0.6, 0.6, 0.7)   # Dark blue-gray
				return
			"confuse":
				sprite.modulate = Color(0.9, 0.6, 1.0)  # Light purple
				return
			"fear":
				sprite.modulate = Color(0.6, 0.6, 0.6)  # Desaturated gray
				return
			"charm":
				sprite.modulate = Color(1.0, 0.7, 0.8)  # Pink
				return
			"regen":
				sprite.modulate = Color(0.8, 1.0, 0.9)  # Soft green-white glow
				return
	# Unknown status — leave tint neutral
	sprite.modulate = Color.WHITE


## Buff/debuff visual overlay system
func _update_buff_debuff_visuals(_delta: float) -> void:
	"""Check all combatants for active buffs/debuffs and show/hide visual overlays"""
	var all_combatants: Array = []
	all_combatants.append_array(BattleManager.player_party)
	all_combatants.append_array(BattleManager.enemy_party)

	for combatant in all_combatants:
		if not (combatant is Combatant) or not combatant.is_alive:
			_remove_buff_visual(combatant)
			continue

		var has_buffs = "active_buffs" in combatant and combatant.active_buffs.size() > 0
		var has_debuffs = "active_debuffs" in combatant and combatant.active_debuffs.size() > 0

		if not has_buffs and not has_debuffs:
			_remove_buff_visual(combatant)
			continue

		var sprite = _get_combatant_sprite(combatant)
		if not sprite or not is_instance_valid(sprite):
			continue

		# Create or update visual overlay
		if combatant not in _buff_visual_nodes:
			_create_buff_visual(combatant, sprite)

		var visuals = _buff_visual_nodes.get(combatant, {})
		if visuals.is_empty():
			continue

		# Threat-class check: any buff carrying a class_tag we recognize promotes the read to "reprisal incoming — defer" — amber glow overrides the cyan-green + sigil badge above the head + particles suppressed (they'd fight the sigil's silhouette read). (msg 2455/2462)
		var has_threat: bool = _combatant_has_threat_buff(combatant)
		var pulse = (sin(_idle_time * 3.0) + 1.0) * 0.5  # 0-1 pulse

		# Update glow color based on buff/debuff state (threat wins over all).
		var glow: ColorRect = visuals.get("glow")
		if glow and is_instance_valid(glow):
			if has_threat:
				glow.color = Color(THREAT_GLOW_COLOR.r, THREAT_GLOW_COLOR.g, THREAT_GLOW_COLOR.b, 0.15 + pulse * 0.15)
			elif has_buffs and has_debuffs:
				# Mixed: yellow pulse
				glow.color = Color(0.8, 0.8, 0.0, 0.12 + pulse * 0.1)
			elif has_buffs:
				# Buff: cyan-green pulse
				glow.color = Color(0.2, 0.9, 0.7, 0.1 + pulse * 0.08)
			else:
				# Debuff: red pulse
				glow.color = Color(0.9, 0.2, 0.2, 0.1 + pulse * 0.08)

		# Sigil badge — show above sprite when threat-class buff is active. Pulse-fade modulate alpha 0.6→1.0 on the existing sin drive. Hidden entirely otherwise.
		var sigil: Sprite2D = visuals.get("sigil")
		if sigil and is_instance_valid(sigil):
			sigil.visible = has_threat
			if has_threat:
				sigil.modulate.a = 0.6 + pulse * 0.4

		# Animate particles — suppressed under a threat buff so the sigil owns the "watch this enemy" read.
		var particles: Array = visuals.get("particles", [])
		for p_node in particles:
			if not is_instance_valid(p_node):
				continue
			p_node.visible = not has_threat
			if has_threat:
				continue
			# Drift upward for buffs, downward for debuffs
			var drift_dir = -1.0 if has_buffs else 1.0
			p_node.position.y += drift_dir * 20.0 * _delta
			p_node.modulate.a -= 0.8 * _delta  # Fade out
			# Reset when faded
			if p_node.modulate.a <= 0.0:
				p_node.position.y = 0.0 if has_buffs else -40.0
				p_node.position.x = randf_range(-15.0, 15.0)
				p_node.modulate.a = 0.6 + randf() * 0.4


func _create_buff_visual(combatant: Combatant, sprite: Node2D) -> void:
	"""Create glow + particle overlay for a buffed/debuffed combatant"""
	var has_buffs = "active_buffs" in combatant and combatant.active_buffs.size() > 0

	# Glow rectangle behind sprite
	var glow = ColorRect.new()
	glow.name = "BuffGlow"
	glow.size = Vector2(40, 50)
	glow.position = Vector2(-20, -40)
	glow.color = Color(0.2, 0.9, 0.7, 0.1)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.z_index = -1
	sprite.add_child(glow)

	# Small floating particles (4 total)
	var particles: Array = []
	var p_color = Color(0.3, 1.0, 0.7, 0.7) if has_buffs else Color(1.0, 0.3, 0.3, 0.7)
	for i in range(4):
		var p = ColorRect.new()
		p.size = Vector2(3, 3)
		p.position = Vector2(randf_range(-15, 15), randf_range(-40, 0) if has_buffs else randf_range(-40, 0))
		p.color = p_color
		p.modulate.a = randf_range(0.3, 1.0)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sprite.add_child(p)
		particles.append(p)

	# Threat-class sigil — always created, hidden until _update_buff_debuff_visuals detects a matching class_tag. Loaded once via HybridSpriteLoader.load_battle_effect_texture ("threat_buff_sigil" — cowir-sprites 4ec21a07). Missing texture leaves the sigil node as a no-op so the buff visual still shows the amber glow.
	var sigil: Sprite2D = Sprite2D.new()
	sigil.name = "ThreatSigil"
	sigil.texture = HybridSpriteLoaderClass.load_battle_effect_texture("threat_buff_sigil")
	sigil.position = THREAT_SIGIL_OFFSET
	sigil.z_index = 2
	sigil.visible = false
	sprite.add_child(sigil)

	_buff_visual_nodes[combatant] = {"glow": glow, "particles": particles, "sigil": sigil}


## True when any active_buff on the combatant carries a class_tag in THREAT_CLASS_BUFFS. Non-Combatants and combatants without active_buffs return false.
func _combatant_has_threat_buff(combatant) -> bool:
	if not "active_buffs" in combatant:
		return false
	for buff in combatant.active_buffs:
		if THREAT_CLASS_BUFFS.get(buff.get("class", ""), false):
			return true
	return false


func _remove_buff_visual(combatant) -> void:
	"""Remove buff/debuff visual overlay for a combatant"""
	if combatant not in _buff_visual_nodes:
		return
	var visuals = _buff_visual_nodes[combatant]
	var glow = visuals.get("glow")
	if glow and is_instance_valid(glow):
		glow.queue_free()
	for p in visuals.get("particles", []):
		if is_instance_valid(p):
			p.queue_free()
	var sigil = visuals.get("sigil")
	if sigil and is_instance_valid(sigil):
		sigil.queue_free()
	_buff_visual_nodes.erase(combatant)


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
		# deferred: died fires inside take_damage, before the killing blow's damage line prints
		call_deferred("log_message", "[color=yellow]%s has been defeated![/color]" % enemy.combatant_name)

		# Clean up status icons and buff visuals for dead enemy
		if enemy in _status_icon_containers:
			var container = _status_icon_containers[enemy]
			if is_instance_valid(container):
				container.queue_free()
			_status_icon_containers.erase(enemy)
		_remove_buff_visual(enemy)

		if enemy_idx < enemy_animators.size() and enemy_idx < enemy_sprite_nodes.size():
			var animator = enemy_animators[enemy_idx]
			var sprite = enemy_sprite_nodes[enemy_idx]
			# Play defeat animation
			animator.play_defeat()
			# FF-style dissolve: flash white, flicker, then vanish
			if is_instance_valid(sprite):
				var tween = create_tween()
				# Flash white briefly
				tween.tween_property(sprite, "modulate", Color(3.0, 3.0, 3.0, 1.0), 0.1)
				tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.1)
				# Flicker dissolve (rapid on/off while fading)
				for i in range(6):
					tween.tween_property(sprite, "modulate:a", 0.1, 0.06)
					tween.tween_property(sprite, "modulate:a", 0.7 - i * 0.1, 0.06)
				# Final vanish
				tween.tween_property(sprite, "modulate:a", 0.0, 0.15)
				tween.tween_callback(func():
					if is_instance_valid(sprite):
						sprite.visible = false
				)


## Win98 Menu Functions

func _input(event: InputEvent) -> void:
	"""Handle high-priority inputs: Select button, battle speed toggle, and repeat actions"""
	# Tutorial hint capturing input — its dismiss press must not also toggle autobattle/speed/formation.
	if TutorialHint.is_any_active():
		return
	# 2026-07-14 (cowir-music msg 2539): editor owns its input; battle hotkeys (Y-repeat, X-speed, F-formation) leak through otherwise and fire mid-edit.
	if _active_inline_editor and is_instance_valid(_active_inline_editor) and _active_inline_editor.visible:
		return
	# Trust interrupt: cancel during a trust-window claims the turn back.
	# High priority so nothing else swallows the input while the window
	# is armed. BM tracks the window and no-ops when nothing is armed.
	if event.is_action_pressed("ui_cancel") and not event.is_echo() \
			and BattleManager.is_trust_interrupt_window_open():
		if BattleManager.request_trust_interrupt():
			get_viewport().set_input_as_handled()
			return

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
			# During selection: TOGGLE autobattle for ALL players.
			# Pre-2026-05-03 this branch only ENABLED — pressing Select
			# again did nothing during the same selection phase, so users
			# couldn't turn off autobattle without waiting for execution.
			# Now: if any party member already has autobattle enabled
			# (the global indicator), disable everybody. Otherwise enable.
			var any_on := false
			for member in party_members:
				var char_id := member.combatant_name.to_lower().replace(" ", "_")
				if AutobattleSystem.is_autobattle_enabled(char_id):
					any_on = true
					break
			if any_on:
				_cancel_all_autobattle()
			else:
				_enable_all_autobattle()
			get_viewport().set_input_as_handled()
			return
		elif BattleManager.current_state == BattleManager.BattleState.VICTORY:
			# Victory screen: toggle applies to the NEXT battle — struktured 2026-07-11: "should be able to disable autobattle in the victory sequence... but I cant".
			var any_on_v := false
			for member in party_members:
				var char_id_v := member.combatant_name.to_lower().replace(" ", "_")
				if AutobattleSystem.is_autobattle_enabled(char_id_v):
					any_on_v = true
					break
			if any_on_v:
				_cancel_all_autobattle()
			else:
				_enable_all_autobattle()
			get_viewport().set_input_as_handled()
			return
		elif is_executing:
			# During execution: queue/revoke a cancel for next turn.
			# (Mid-execution flip would race with already-running actions.)
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
		# F key to cycle party formation
		elif event.keycode == KEY_F:
			cycle_formation()
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
			## Tick 174: defer log emit moved into BattleManager.
			## player_defer so every caller path gets it once. Don't
			## re-emit here.
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

func _on_damage_dealt(target: Combatant, amount: int, is_crit: bool, element: String = "", elemental_mod: float = 1.0) -> void:
	_results_display.on_damage_dealt(target, amount, is_crit)
	# deplete the floating enemy HP bar in sync with the damage number — it lagged to the next _update_ui (action boundary)
	_update_enemy_hp_bars()
	if is_crit:
		_crit_visual_burst(target, amount)
		_show_hint("first_crit", "CRITICAL HIT! Fast characters and Rogues crit more often. Equip gear with crit bonuses to increase your chances.")
		# Crit quip from the attacker
		var attacker = BattleManager.current_combatant
		if attacker and attacker in BattleManager.player_party:
			_try_combat_quip(CRIT_QUIPS, attacker)
			# Overkill check (damage > 2x remaining HP)
			if amount > target.max_hp * 0.5:
				_try_combat_quip(OVERKILL_QUIPS, attacker)
	if elemental_mod != 1.0 and element != "":
		_spawn_elemental_indicator(target, element, elemental_mod)
		# Tutorial hints for elemental interactions
		if elemental_mod > 1.0:
			_show_hint("weakness_exploit", "That enemy is WEAK to %s! Elemental weaknesses deal bonus damage. Use Combo Magic to stack multiple elements!" % element.capitalize())
		elif elemental_mod < 1.0 and elemental_mod > 0.0:
			_show_hint("elemental_resist", "That enemy RESISTS %s. Try a different element or use physical attacks." % element.capitalize())
		elif elemental_mod == 0.0:
			_show_hint("elemental_immune", "That enemy is IMMUNE to %s! Switch to a different element or physical attacks." % element.capitalize())
	# Party member taking big damage (>30% max HP) — reaction quip
	if target in BattleManager.player_party and amount > target.max_hp * 0.3:
		_try_combat_quip(TAKE_BIG_DAMAGE_QUIPS, target)
	# Low HP warning (dropped below 25%)
	if target in BattleManager.player_party and target.is_alive and target.get_hp_percentage() < 25.0:
		_try_combat_quip(LOW_HP_QUIPS, target)

	## Tick 428: boss low_hp dialogue line. Authored on cave_rat_king,
	## the 4 dragons, optimization_itself, etc. but pre-fix only
	## `intro` was wired — bosses never spoke their "I'm wounded"
	## line. Fires once per battle when an enemy boss drops below
	## 25%. Same threshold as the player LOW_HP_QUIPS so the moment
	## feels symmetric.
	if not _boss_low_hp_spoken and target in BattleManager.enemy_party and target.is_alive:
		if _boss_dialogue_data.has("low_hp") and _boss_dialogue_data["low_hp"].size() > 0:
			if target.get_hp_percentage() < 25.0 and target.has_meta("is_boss"):
				_boss_low_hp_spoken = true
				if _battle_dialogue and _battle_dialogue.has_method("show_boss_intro"):
					_battle_dialogue.show_boss_intro(target.combatant_name, _boss_dialogue_data["low_hp"])

	# Skip hit sounds for abilities — ability sound already played at cast time
	if _current_ability_id != "":
		return
	var attacker = BattleManager.current_combatant
	var weapon_type = EquipmentSystem.get_weapon_type(attacker)
	SoundManager.play_attack_hit(weapon_type, is_crit)


func _spawn_elemental_indicator(target: Combatant, element: String, modifier: float) -> void:
	"""Spawn a floating WEAK!/RESIST!/IMMUNE! indicator above the damage number"""
	var text: String
	var color: Color
	if modifier == 0.0:
		text = "IMMUNE!"
		color = Color(0.7, 0.7, 0.7)  # Gray (colorblind-safe)
	elif modifier > 1.0:
		text = "WEAK!"
		# Tick 227: WEAK uses a color-blind aware palette. Default red sits in the red-green spectrum that deuteranopia/protanopia (~5% of males) struggles with; accessibility mode swaps to magenta which is distinguishable from blue RESIST, yellow crits, and cyan heals.
		color = _elem_weak_color()
	elif modifier < 1.0:
		text = "RESIST"
		color = Color(0.3, 0.5, 1.0)  # Blue (colorblind-safe)
	else:
		return

	var pos = _results_display._get_combatant_sprite_position(target)
	pos.y -= 30  # Offset above damage number
	# Tick 209: stagger so multi-element hits (formation combos, weakness chains) don't pile labels on top of each other.
	pos.y -= _count_recent_elem_indicators_near(pos) * ELEM_STAGGER_STEP

	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", TextScale.scaled(14))
	label.add_theme_color_override("font_color", color)
	# Tick 218: add full-perimeter outline so RESIST/IMMUNE colors don't blend into the Mode 7 floor grid lines. Shadow alone is offset (lower-right only) — top-left edges go unprotected against busy backgrounds. Matches the contrast scheme DamageNumber uses.
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.position = pos
	label.z_index = 100
	# Tick 209: tag for the stagger counter — bare Labels at BattleScene root would otherwise match generic Label checks.
	label.set_meta("elem_indicator", true)
	add_child(label)

	var tween = create_tween()
	tween.tween_property(label, "position:y", pos.y - 30, 0.8)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.tween_callback(label.queue_free)


# Tick 209: stagger constants for elemental indicator labels. Same insight as tick 205 (Toast) + tick 208 (damage popups), different node type.
const ELEM_STAGGER_STEP := 18.0
const ELEM_STAGGER_RADIUS_SQUARED := 40.0 * 40.0


# Tick 227/228: color-blind-aware WEAK indicator color via shared AccessibilityPalette util.
func _elem_weak_color() -> Color:
	return AccessibilityPalette.elem_weak()


# Tick 209: count live elemental-indicator labels near pos. Tagged via has_meta("elem_indicator") so we don't match unrelated Labels at BattleScene root.
func _count_recent_elem_indicators_near(pos: Vector2) -> int:
	var count: int = 0
	for child in get_children():
		if child is Label and is_instance_valid(child) and child.has_meta("elem_indicator"):
			if child.position.distance_squared_to(pos) < ELEM_STAGGER_RADIUS_SQUARED:
				count += 1
	return count


func _on_attack_missed(target: Combatant) -> void:
	_results_display.on_attack_missed(target)
	SoundManager.play_battle("attack_miss")
	# Dodge quip from the target (if party member dodged an enemy attack)
	if target in BattleManager.player_party:
		_try_combat_quip(DODGE_QUIPS, target)


func _on_healing_done(target: Combatant, amount: int) -> void:
	_results_display.on_healing_done(target, amount)
	SoundManager.play_battle("heal")


## Tick 143: spawn floating damage/healing popups when poison /
## burn / regen ticks fire on a Combatant. Pre-fix only hp_changed
## emitted on these ticks, so the HP bar dropped but no number
## floated up — players couldn't see status effects ticking unless
## they watched the HP bar carefully. The `source` arg distinguishes
## the cause (could drive icon color/text in the future).
func _on_status_tick_damage(amount: int, _source: String, target: Combatant) -> void:
	if not is_instance_valid(target) or not is_instance_valid(_results_display):
		return
	_results_display.on_damage_dealt(target, amount, false)


func _on_status_tick_heal(amount: int, _source: String, target: Combatant) -> void:
	if not is_instance_valid(target) or not is_instance_valid(_results_display):
		return
	_results_display.on_healing_done(target, amount)


func _crit_visual_burst(target: Combatant, _amount: int) -> void:
	"""Full critical hit visual package — screen flash, hitlag, sprite flash, banner"""
	# 1. Bright white-gold screen flash (more dramatic than normal hit)
	_flash_screen(Color(1.0, 0.95, 0.6, 0.5), 0.2)

	# 2. Hitlag — brief time freeze for impact (80ms at 10% speed)
	var prev_scale = Engine.time_scale
	Engine.time_scale = 0.1
	var hitlag_tween = create_tween()
	hitlag_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	hitlag_tween.tween_callback(func(): Engine.time_scale = prev_scale).set_delay(0.008)  # 80ms real time at 0.1x

	# 3. Target sprite white flash
	var sprite = _get_combatant_sprite(target)
	if sprite and is_instance_valid(sprite):
		var orig_modulate = sprite.modulate
		sprite.modulate = Color(3.0, 3.0, 3.0, 1.0)  # Bright white flash (HDR)
		var flash_tween = create_tween()
		flash_tween.tween_property(sprite, "modulate", orig_modulate, 0.15).set_delay(0.05)

	# 4. "CRITICAL!" banner above target
	var pos = _results_display._get_combatant_sprite_position(target)
	if pos != Vector2.ZERO:
		_spawn_crit_banner(pos)


func _spawn_crit_banner(pos: Vector2) -> void:
	"""Spawn a large 'CRITICAL!' text that scales up and fades"""
	var label = Label.new()
	label.text = "CRITICAL!"
	label.add_theme_font_size_override("font_size", TextScale.scaled(22))
	label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.1))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(0.6, 0.2, 0.0))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = pos + Vector2(-45, -70)
	label.z_index = 110
	label.pivot_offset = Vector2(45, 10)  # Center pivot for scale
	label.scale = Vector2(0.3, 0.3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)

	var tween = create_tween()
	# Pop in: scale 0.3 -> 1.2 -> 1.0
	tween.tween_property(label, "scale", Vector2(1.2, 1.2), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.06)
	# Hold, then float up and fade
	tween.tween_property(label, "position:y", pos.y - 100, 0.6).set_delay(0.2)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.4).set_delay(0.4)
	tween.tween_callback(label.queue_free)


## True when the save-corruption "visual_glitch" effect is active. Static so the
## decision is unit-testable without standing up a whole BattleScene.
static func _corruption_glitch_active() -> bool:
	return "visual_glitch" in GameState.corruption_effects


## Save-corruption reality-stutter: a cosmetic chromatic magenta/cyan flash at
## the top of each round when visual_glitch is active. Purely visual — corruption
## you SEE, never a balance change. (GameState._apply_random_corruption_effect
## adds the effect; this is finally its runtime handler.)
func _on_round_started_corruption_glitch(_round_num: int) -> void:
	if not _corruption_glitch_active():
		return
	_flash_screen(Color(1.0, 0.15, 0.9, 0.16), 0.10)   # magenta
	_flash_screen(Color(0.15, 1.0, 0.95, 0.12), 0.14)  # cyan trail


func _flash_screen(color: Color, duration: float) -> void:
	"""Brief screen flash effect for impactful moments"""
	if _flashes_suppressed():
		return
	var flash = ColorRect.new()
	flash.color = color
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	var tween = create_tween()
	tween.tween_property(flash, "color:a", 0.0, duration)
	tween.tween_callback(flash.queue_free)


func _on_battle_log_message(message: String) -> void:
	"""Display battle log message from BattleManager"""
	if battle_log:
		battle_log.append_text(message + "\n")
		battle_log.scroll_to_line(battle_log.get_line_count())


## Trust option (a): BM opens a short window before AI takes over on a
## player-trusted PC. The battle log line from BM is the visible cue;
## input capture lives in _input's ui_cancel guard so cancel during the
## window claims the turn. Handlers here are hooks — if a future toast /
## highlight is added, this is the anchor.
func _on_trust_interrupt_window_opened(_pc: Combatant, _seconds: float) -> void:
	pass


func _on_trust_interrupt_window_closed(_pc: Combatant, _interrupted: bool) -> void:
	pass


func _on_advance_trash_talk(combatant: Combatant, line: String) -> void:
	"""Show a brief cocky one-liner before a big Advance combo"""
	if turbo_mode:
		return
	var sprite = _get_combatant_sprite(combatant)
	if sprite and is_instance_valid(sprite):
		_spawn_quip_bubble(sprite, combatant.combatant_name, line, _get_job_quip_color(combatant))
	var job_name = combatant.job.get("name", "Fighter") if combatant.job else "Fighter"
	log_message('[color=yellow]%s: "%s"[/color]' % [combatant.combatant_name, line])


## Tick 122: party combat dialogue lines (turn_start/low_hp/big_hit_taken/
## used_signature_ability/victory). BattleManager._emit_party_line emits
## both this signal AND a battle_log_message, so the log retains the line
## as text scrollback while the bubble plays over the sprite. The
## quip-bubble code auto-suppresses at turbo / 4x+ / autogrind console.
func _on_party_combat_line(combatant: Combatant, line: String, voice_trigger: String = "") -> void:
	if turbo_mode:
		return
	var sprite = _get_combatant_sprite(combatant)
	if sprite and is_instance_valid(sprite):
		# msg 2105: voice key derived as voice_<job>_<trigger>; manifest-gated
		# in SoundManager (silent skip when the voice pack isn't authored).
		var audio_key: String = ""
		if voice_trigger != "" and combatant.job is Dictionary:
			var job_id: String = str(combatant.job.get("id", ""))
			if job_id != "":
				audio_key = "voice_%s_%s" % [job_id, voice_trigger]
		_spawn_quip_bubble(sprite, combatant.combatant_name, line, _get_job_quip_color(combatant), 2.0, audio_key)


# ── Wave E — Boss dialogue surface ───────────────────────────────────────────

func _on_boss_taunt(boss: Combatant, line: String) -> void:
	"""Show a non-blocking taunt bubble above the boss sprite. Reuses the
	existing _spawn_quip_bubble infrastructure (Option A — non-blocking
	autodismiss; preferred over CutsceneDialogue for mid-battle interrupts
	per Wave E plan)."""
	if turbo_mode:
		return
	if not is_instance_valid(boss):
		return
	# Look up the enemy sprite (enemy_party indexing matches enemy_sprite_nodes).
	var sprite: Node2D = null
	var idx = test_enemies.find(boss)
	if idx >= 0 and idx < enemy_sprite_nodes.size():
		sprite = enemy_sprite_nodes[idx]
	if sprite == null or not is_instance_valid(sprite):
		return
	# Crimson border distinguishes boss taunts from party quips.
	_spawn_quip_bubble(sprite, boss.combatant_name, line, Color(0.95, 0.25, 0.25), 2.5)


func _on_boss_jailbreak_landed(_boss: Combatant, _vulnerability_id: String, _consequence: Dictionary) -> void:
	"""Diegetic '⚠ DIRECTIVE OVERRIDE ACCEPTED' banner. Non-blocking
	autodismiss via tween. Triggered after BattleManager has already
	applied the consequence — this is purely visual feedback."""
	_show_address_banner("⚠ DIRECTIVE OVERRIDE ACCEPTED")


func _on_boss_gloat_line(text: String, is_victory: bool) -> void:
	"""Wave G — surface the end-of-fight boss gloat in the battle log. The boss
	(victory) or the party (defeat) may already be dead, so the sprite-bubble
	path is unreliable here — the log is the dependable display surface, sitting
	right alongside the VICTORY/DEFEAT banner. LLM-narrated when available,
	scripted-pool fallback otherwise; this handler treats both identically."""
	if text.strip_edges() == "":
		return
	# Crimson for a triumphant boss gloat (party wiped); muted gold for a boss
	# conceding in defeat (party won). Both are tagged so the line reads as the
	# boss speaking, not narration.
	var color: String = "#cc4444" if not is_victory else "#d8b860"
	log_message('[color=%s]%s: "%s"[/color]' % [color, _gloat_speaker_name(is_victory), text])


func _gloat_speaker_name(_is_victory: bool) -> String:
	"""Best-effort boss display name for the gloat log line. Reads from the live
	boss combatant if one is still around; falls back to a neutral label."""
	for enemy in test_enemies:
		if enemy and is_instance_valid(enemy):
			if (enemy.has_meta("is_boss") and enemy.get_meta("is_boss")) \
					or (enemy.has_meta("is_miniboss") and enemy.get_meta("is_miniboss")):
				if enemy.combatant_name != "":
					return enemy.combatant_name
	return "The Boss"


func _show_address_banner(text: String) -> void:
	"""Spawns a transient banner Label centered at the top of the viewport,
	fades in/holds/fades out via create_tween. Suppressed during turbo /
	autogrind console (no-op for headless tests)."""
	if turbo_mode or autogrind_console_mode:
		return
	if not is_inside_tree():
		return
	var panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.92)
	style.border_color = Color(1.0, 0.85, 0.2)
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	var label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	label.add_theme_font_size_override("font_size", TextScale.scaled(18))
	panel.add_child(label)
	# Anchor at top-center.
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.position = Vector2(-150, 60)
	panel.size = Vector2(300, 0)  # auto-resize via child
	panel.modulate = Color(1, 1, 1, 0)
	panel.z_index = 200
	add_child(panel)
	var tween = create_tween()
	tween.set_parallel(false)
	tween.tween_property(panel, "modulate:a", 1.0, 0.18)
	tween.tween_interval(1.6)
	tween.tween_property(panel, "modulate:a", 0.0, 0.35)
	tween.tween_callback(panel.queue_free)


func _spawn_quip_bubble(sprite: Node2D, speaker_name: String, line: String, border_color: Color = Color(1.0, 0.85, 0.2), hold_time: float = 1.5, audio_key: String = "") -> void:
	"""Speech bubble above a sprite — party lines, boss taunts, quips, trash talk.
	Delegates to BattleSpeechBubble (playtest brief msg 2101): viewport-clamped
	out of the top-right party-panel column, suppressed only at 4x+ (pre-fix
	2x+ silently hid ALL bubbles for anyone playing at 2x battle speed — the
	"I can't see the text" playtest complaint), hold scaled by time_scale,
	optional audio_key voice hook for phase-2 voice acting."""
	if turbo_mode or autogrind_console_mode:
		return
	if sprite == null or not is_instance_valid(sprite):
		return
	# 2026-07-15 playtest: bubbles anchored at sprite CENTER — mid-body on a 300px monster, covering its head and drifting into the command menu. Anchor above the head instead, biased left for enemies (left half of screen) so wide bubbles stay clear of the center menu.
	var anchor: Vector2 = sprite.global_position
	if sprite is AnimatedSprite2D:
		var anim_sprite: AnimatedSprite2D = sprite
		if anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation(anim_sprite.animation):
			var tex: Texture2D = anim_sprite.sprite_frames.get_frame_texture(anim_sprite.animation, anim_sprite.frame)
			if tex:
				anchor.y -= tex.get_height() * absf(anim_sprite.scale.y) * 0.5
	var vp_w: float = get_viewport_rect().size.x
	if anchor.x < vp_w * 0.45:
		anchor.x -= 50.0
	elif anchor.x > vp_w * 0.55:
		anchor.x -= 70.0  # 2026-07-16 smoke: party-side bubbles crowded the right party panel + AUTO button — bias toward open mid-field
	BattleSpeechBubble.spawn(self, anchor, speaker_name, line, border_color, hold_time, audio_key)

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
	one_shot_label.add_theme_font_size_override("font_size", TextScale.scaled(48))
	one_shot_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.0))
	# Tick 219: 2px outline matches the floating-text contrast scheme; flash_bg fades quickly so the label spends most of its life over the Mode 7 floor.
	one_shot_label.add_theme_constant_override("outline_size", 2)
	one_shot_label.add_theme_color_override("font_outline_color", Color.BLACK)
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
	rank_label.add_theme_font_size_override("font_size", TextScale.scaled(28))
	var rank_color = Color(1.0, 0.9, 0.0) if rank == "S" else Color(0.6, 1.0, 0.6) if rank == "A" else Color(0.6, 0.8, 1.0)
	rank_label.add_theme_color_override("font_color", rank_color)
	# Tick 219: floating-text contrast — outline + shadow.
	rank_label.add_theme_constant_override("outline_size", 2)
	rank_label.add_theme_color_override("font_outline_color", Color.BLACK)
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
	bonus_label.add_theme_font_size_override("font_size", TextScale.scaled(22))
	bonus_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	# Tick 219: floating-text contrast — outline + shadow.
	bonus_label.add_theme_constant_override("outline_size", 2)
	bonus_label.add_theme_color_override("font_outline_color", Color.BLACK)
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
	auto_label.add_theme_font_size_override("font_size", TextScale.scaled(42))
	auto_label.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
	# Tick 219: floating-text contrast — outline + shadow.
	auto_label.add_theme_constant_override("outline_size", 2)
	auto_label.add_theme_color_override("font_outline_color", Color.BLACK)
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
	turns_label.add_theme_font_size_override("font_size", TextScale.scaled(22))
	turns_label.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	# Tick 219: floating-text contrast — outline + shadow.
	turns_label.add_theme_constant_override("outline_size", 2)
	turns_label.add_theme_color_override("font_outline_color", Color.BLACK)
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
	bonus_label.add_theme_font_size_override("font_size", TextScale.scaled(22))
	bonus_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	# Tick 219: floating-text contrast — outline + shadow.
	bonus_label.add_theme_constant_override("outline_size", 2)
	bonus_label.add_theme_color_override("font_outline_color", Color.BLACK)
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
			get_tree().create_timer(delay).timeout.connect(_delayed_play_victory.bind(animator))

	# Background brightening on victory (brief warm flash)
	if _battle_background and is_instance_valid(_battle_background):
		var bg_tween = create_tween()
		bg_tween.tween_property(_battle_background, "modulate",
			Color(1.3, 1.25, 1.0, 1.0), 0.35).set_trans(Tween.TRANS_SINE)
		bg_tween.tween_property(_battle_background, "modulate",
			Color(1.0, 1.0, 1.0, 1.0), 0.6).set_trans(Tween.TRANS_SINE)


func _show_victory_quip() -> void:
	"""Show a random party member's victory quip as a speech bubble"""
	var alive = party_members.filter(func(m): return m is Combatant and m.is_alive)
	if alive.is_empty():
		return
	var speaker = alive[randi() % alive.size()]
	var job_id = speaker.job.get("id", "fighter") if speaker.job else "fighter"
	var pool = VICTORY_QUIPS.get(job_id, VICTORY_QUIPS.get("_default", []))
	if pool.is_empty():
		return
	var line = pool[randi() % pool.size()]
	# Tick 239: bonus BBCode (PC dialogue speaker — positive valence by convention).
	log_message("[color=%s]%s:[/color] \"%s\"" % [AccessibilityPalette.bonus_bbcode(), speaker.combatant_name, line])
	var sprite = _get_combatant_sprite(speaker)
	if sprite and is_instance_valid(sprite):
		_spawn_quip_bubble(sprite, speaker.combatant_name, line, _get_job_quip_color(speaker), 2.5)


func _show_victory_results() -> void:
	_results_display.show_victory_results()


static func pick_summon_name(base_name: String, living_same_type: Array) -> String:
	if living_same_type.is_empty():
		return base_name
	var used: Dictionary = {}
	for n in living_same_type:
		used[str(n).trim_prefix(base_name).strip_edges()] = true
	for letter in ["A", "B", "C", "D", "E"]:
		if not used.has(letter):
			return base_name + " " + letter
	return base_name + " F"


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

	# letter must be unique among LIVING same-types — alive-count indexing collided (survivor "B" + new summon → second "B")
	var living_names: Array = []
	for e in test_enemies:
		if is_instance_valid(e) and e.is_alive and e.get_meta("monster_type", "") == monster_type:
			living_names.append(e.combatant_name)
	stats["name"] = pick_summon_name(monster_data["name"], living_names)

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
	enemy.status_added.connect(_on_status_added.bind(enemy))
	enemy.status_removed.connect(_on_status_removed.bind(enemy))
	var new_idx = test_enemies.size()

	test_enemies.append(enemy)

	# Add to BattleManager's enemy party
	BattleManager.enemy_party.append(enemy)
	BattleManager.all_combatants.append(enemy)

	# Create sprite for the new enemy
	var sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = _get_monster_sprite_frames(monster_type)

	# summons must mirror battle-start sizing or artist drops (<=128px) pop in 2.5x small, facing away
	var size_bump: float = 1.0
	var is_artist_monster := false
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(&"idle"):
		if sprite.sprite_frames.get_frame_count(&"idle") > 0:
			var ftex = sprite.sprite_frames.get_frame_texture(&"idle", 0)
			if ftex and ftex.get_height() <= ENEMY_SMALL_FRAME_THRESHOLD:
				size_bump = ENEMY_SCALE_BUMP
				is_artist_monster = true
	sprite.flip_h = is_artist_monster
	var summon_depth_scale: float = 1.0 - float(new_idx) * 0.05
	var final_scale: float = summon_depth_scale * size_bump

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
	# Keep sway bookkeeping aligned — summons were skipped by the idle-sway index guard
	_enemy_base_positions.append(sprite.position)

	# Create animator
	var animator = BattleAnimatorClass.new()
	animator.setup(sprite)
	add_child(animator)
	enemy_animators.append(animator)

	# Add label
	_add_sprite_label(sprite, enemy.combatant_name.to_upper(), Vector2(-20, 40))

	# Setup status icons for summoned enemy
	_setup_status_icons(enemy, sprite)

	# Spawn animation - pop in with flash (overshoot and settle at the computed size, not 1.0)
	var tween = create_tween()
	tween.tween_property(sprite, "scale", Vector2(final_scale * 1.3, final_scale * 1.3), 0.15)
	tween.tween_property(sprite, "scale", Vector2(final_scale, final_scale), 0.1)
	# Guarantee final scale in case tween is interrupted
	tween.finished.connect(func():
		if is_instance_valid(sprite):
			sprite.scale = Vector2(final_scale, final_scale)
	)

	# Flash effect at spawn position (stable anchor per msg 2569 #1 — base was appended above so the helper prefers it over the concurrent scale-tween's live pos)
	EffectSystem.spawn_effect(EffectSystem.EffectType.BUFF, _stable_sprite_anchor(sprite))

	# Log message
	log_message("[color=%s]%s appears![/color]" % [AccessibilityPalette.penalty_bbcode(), stats["name"]])

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
	elif not any_in_danger and (_is_danger_music or str(SoundManager._current_music) == "danger"):
		# Stateless check: a duel-retry rebuilds this scene with the flag fresh while SoundManager still plays danger — the flag-only check left doom music over a full-HP party (struktured 2026-07-11).
		_is_danger_music = false
		SoundManager.play_music(_base_music_track)
		print("[MUSIC] Switched back to %s music - party recovered" % _base_music_track)


## ======================== BATTLE QUIPS ========================
## Party members react to encounters and brave actions with short one-liners.

const BATTLE_START_QUIPS: Dictionary = {
	"fighter": ["Let's do this!", "Steel meets steel!", "I'll take point!", "Another fight? Good."],
	"cleric": ["Stay close, everyone.", "I'll keep us standing.", "Light guide our strikes.", "Be careful..."],
	"mage": ["Fascinating specimens...", "Time for field research!", "Let's see what they're made of.", "Hmm, elemental analysis..."],
	"rogue": ["Easy pickings.", "Watch and learn.", "I call dibs on loot.", "In and out, no sweat."],
	"bard": ["This'll make a great verse!", "Music to fight by!", "♪ Here we go again~ ♪", "I feel a ballad coming on!"],
	"guardian": ["Formation! Now!", "Behind me, all of you.", "Hold the line.", "I won't let them through."],
	"ninja": ["Already behind them.", "Too slow.", "This ends quickly.", "..."],
	"summoner": ["I sense their weakness.", "Spirits, attend me!", "The ether stirs...", "Let's call for backup."],
	"speculator": ["I'm betting on us.", "The odds look good.", "Risk assessment: favorable.", "All in."],
	# Tick 290: meta-job lines (mirrors tick 289's VICTORY_QUIPS extension).
	"scriptweaver": ["Pushing combat-v2 to prod.", "Forking this encounter.", "Stack trace ready.", "git battle origin/main"],
	"time_mage": ["I've seen this fight before.", "Loading the right branch.", "Cue intro music.", "Time's already on our side."],
	"necromancer": ["Their grave is open.", "Add them to the ledger.", "I hear the bones humming.", "Endings rehearse here."],
	"bossbinder": ["Mask up, everyone.", "We answer their script.", "Their pattern is mine to wear.", "Boss music? In my head."],
	"skiptrotter": ["Speedrun start.", "I've got the route.", "Cutscene → skip.", "Next checkpoint, now."],
	# `_default` fallback for unknown jobs (debug, modded, etc.).
	"_default": ["Battle begins!", "Here we go.", "Stay sharp.", "Engage!"],
}

const NEW_MONSTER_QUIPS: Dictionary = {
	"fighter": ["What IS that thing?!", "Never seen one of those before.", "Huh. Ugly."],
	"cleric": ["What manner of creature...?", "I don't recognize this one.", "Be on guard — unknown threat!"],
	"mage": ["Undocumented species! Taking notes.", "Ooh, a new specimen!", "No data on this one... exciting!"],
	"rogue": ["That's new. I don't like new.", "No intel on this thing.", "Great, surprises."],
	"bard": ["Ooh, inspiration!", "I've never written a verse about THAT.", "This'll make a great story!"],
	"guardian": ["Unknown hostile — shields up!", "Unidentified. Stay behind me.", "New threat. Proceed with caution."],
	"ninja": ["Hmm. Unfamiliar.", "No entry in the bestiary.", "...interesting."],
	"summoner": ["The spirits don't recognize it either.", "A new entity... fascinating.", "What plane did YOU come from?"],
	"speculator": ["No market data on this one.", "Unpriced asset. Could be valuable.", "Unknown risk profile."],
	# Tick 290: meta-job lines for first-encounter bestiary triggers.
	"scriptweaver": ["No schema for that.", "404 — monster type unknown.", "Patching bestiary on the fly."],
	"time_mage": ["I haven't seen this one yet.", "Future-me will recognize it.", "A new variable in the timeline."],
	"necromancer": ["A fresh page in the ledger.", "I don't know its name. Yet.", "Its bones will tell me later."],
	"bossbinder": ["A new mask to study.", "Their pattern is unread.", "Catalog it before I wear it."],
	"skiptrotter": ["Wasn't in the route notes.", "Hold up — undocumented spawn.", "Recompiling the speedrun."],
	"_default": ["What's that?", "I don't recognize it.", "Unknown threat!"],
}

## Monster-specific encounter flavor text (shown alongside quips)
const MONSTER_ENCOUNTER_TEXT: Dictionary = {
	"slime": "A gelatinous blob jiggles menacingly.",
	"bat": "Wings flutter in the darkness!",
	"goblin": "The goblin snarls and brandishes a rusty blade.",
	"wolf": "Piercing eyes gleam from the shadows.",
	"spider": "Webs glisten as something skitters closer...",
	"skeleton": "Bones rattle as the undead rises.",
	"ghost": "The air turns cold. Something watches.",
	"snake": "A sinuous shape coils to strike.",
	"mushroom": "Spores drift lazily in the air...",
	"imp": "Cackling laughter echoes from a tiny fireball.",
	"troll": "The ground shakes with heavy footsteps.",
	"cave_rat": "Beady eyes reflect what little light remains.",
	"cave_rat_king": "A crown of refuse sits atop this massive rodent.",
}

const BRAVE_QUIPS: Dictionary = {
	"fighter": ["All out attack!", "No holding back!", "CHARGE!", "Full power!"],
	"cleric": ["Channeling everything!", "By the light — SURGE!", "Maximum output!"],
	"mage": ["Overclocking mana!", "Chain casting!", "UNLIMITED POWER!", "Spell barrage!"],
	"rogue": ["Combo time!", "Rapid strikes!", "They won't see this coming!", "Flurry!"],
	"bard": ["Encore! Encore!", "♪ Grand finale~ ♪", "The crescendo!"],
	"guardian": ["Breaking through!", "FULL ASSAULT!", "No mercy!"],
	"ninja": ["Shadow rush.", "Multi-strike.", "Vanishing barrage."],
	"summoner": ["Spirits, converge!", "All together now!", "Full summoning circle!"],
	"speculator": ["Going all in!", "Double or nothing!", "Maximum leverage!"],
	# Tick 290: meta-job brave lines (advance/pool AP burst).
	"scriptweaver": ["Buffer overflow incoming.", "Unrolled the loop.", "Inlined."],
	"time_mage": ["All my futures, at once.", "Stacked turns.", "Fast-forward."],
	"necromancer": ["Chorus, sing.", "All the dead in one note.", "Open the ledger wide."],
	"bossbinder": ["Boss-phase, NOW.", "Their finisher is mine.", "Mask glows."],
	"skiptrotter": ["Skipping every cooldown.", "Glitch jump.", "OOB combo."],
	"_default": ["Going all out!", "Full force!", "Now!"],
}

## Combat reaction quips — triggered by battle events (30% chance each)
const CRIT_QUIPS: Dictionary = {
	"fighter": ["That's gonna leave a mark!", "DIRECT HIT!", "Right in the weak spot!"],
	"cleric": ["The light strikes true!", "Guided by divine aim!", "Precision!"],
	"mage": ["Critical resonance!", "The formula was perfect!", "Maximum efficiency!"],
	"rogue": ["Bullseye!", "Right where it hurts!", "Too easy."],
	"bard": ["♪ And the crowd goes wild! ♪", "Standing ovation!", "Hit the high note!"],
	# Tick 291: meta-job CRIT lines (continues the 289/290 sweep).
	"scriptweaver": ["Asserted maximum.", "Force-pushed.", "RNG seed: optimal."],
	"time_mage": ["Yes — this branch.", "Saw it. Took it.", "Caught the moment."],
	"necromancer": ["Bones split clean.", "Their record closes loudly.", "The ledger snapped shut."],
	"bossbinder": ["Boss-grade strike.", "Their finisher, returned.", "Through the mask."],
	"skiptrotter": ["Frame-perfect.", "Crit chain — no skip.", "Optimal RNG."],
	"_default": ["Critical hit!", "Nice shot!", "That's a big one!"],
}

const OVERKILL_QUIPS: Dictionary = {
	"fighter": ["Overkill? No such thing.", "Rest in pieces.", "Didn't even need that much."],
	"rogue": ["That was excessive. I love it.", "Wasted resources, but style points.", "Oops. Too hard."],
	"mage": ["Miscalculated... in our favor.", "Excessive force noted.", "The math says: very dead."],
	# Tick 291: meta-job OVERKILL lines.
	"scriptweaver": ["Memory leak — theirs.", "Catastrophic stack overflow.", "Buffer is theirs now."],
	"time_mage": ["Erased from three timelines.", "Won't exist in the next one either.", "Past tense, future tense."],
	"necromancer": ["Their afterlife flinched.", "Ledger marked TWICE.", "Even the bones are gone."],
	"bossbinder": ["Boss-killed twice.", "Their mask shattered in my hand.", "Whatever script they had — gone."],
	"skiptrotter": ["Skipped past dead.", "Out of bounds.", "Cleared. Next."],
	"_default": ["Overkill!", "That was more than enough!", "Obliterated!"],
}

const TAKE_BIG_DAMAGE_QUIPS: Dictionary = {
	"fighter": ["Ugh! That stung!", "I can take it!", "Hit me harder!"],
	"cleric": ["Ouch! I need a moment!", "That really hurt...", "Someone cover me!"],
	"mage": ["My barrier failed!", "Ow! Physical pain! My weakness!", "I need distance!"],
	"rogue": ["Should've dodged that!", "Okay, THAT hurt.", "Lucky shot..."],
	# Tick 291: meta-job TAKE_BIG_DAMAGE lines.
	"scriptweaver": ["Segfault!", "Stack trace incoming.", "Unhandled exception!"],
	"time_mage": ["Roll back, roll back!", "That timeline hurt.", "Wrong branch!"],
	"necromancer": ["Adding myself to the ledger?", "The chorus heard that.", "Not yet, not yet."],
	"bossbinder": ["Boss-level damage.", "Mask cracked.", "Whose pattern WAS that?"],
	"skiptrotter": ["Hitbox bigger than the wiki said.", "Frame skip didn't save me.", "Hold up — that's a phase change."],
	"_default": ["Ow!", "That hurt!", "I'm in trouble!"],
}

const DODGE_QUIPS: Dictionary = {
	"fighter": ["Ha! Missed!", "Too slow!", "I saw that coming!"],
	"rogue": ["Not even close.", "Like I'd stand still.", "You'll have to be faster than THAT."],
	"ninja": ["Already moved.", "Predictable.", "..."],
	# Tick 291: meta-job DODGE lines.
	"scriptweaver": ["Conditional: false.", "Early-return.", "Branch not taken."],
	"time_mage": ["Wasn't there. Already moved.", "Read your past.", "I left the timeline."],
	"necromancer": ["The dead don't predict me.", "Their swing was already over.", "Their ghost mourns the miss."],
	"bossbinder": ["Read your pattern.", "Boss tells, all of them.", "Their script is mine."],
	"skiptrotter": ["i-frames.", "OOB.", "Pixel-perfect skip."],
	"_default": ["Missed me!", "Nice try!", "Dodged!"],
}

const LOW_HP_QUIPS: Dictionary = {
	"fighter": ["I'm not done yet...", "Just a scratch!", "Still standing!"],
	"cleric": ["I need healing... ironic.", "My faith is being tested!", "This isn't good..."],
	"mage": ["Running low on everything...", "My concentration is slipping!", "Need to retreat!"],
	"rogue": ["Things are looking grim.", "Time to get creative...", "Escape plan forming..."],
	# Tick 291: meta-job LOW_HP lines.
	"scriptweaver": ["Memory critical.", "GC me later — finish this.", "OOM warning."],
	"time_mage": ["Time to rewind.", "Need a save point...", "Bad branch — pivoting."],
	"necromancer": ["My own ledger is open.", "I can hear my chorus.", "Soon — but not yet."],
	"bossbinder": ["Mask cracking.", "Phase change coming.", "One more strike — theirs or mine."],
	"skiptrotter": ["One frame from death.", "Need a glitch jump.", "Skip skip skip!"],
	"_default": ["I'm in trouble...", "Someone help!", "Not looking good..."],
}

const ALLY_KO_QUIPS: Dictionary = {
	"fighter": ["No! Get up!", "I'll avenge you!", "You'll pay for that!"],
	"cleric": ["I failed them...", "Hold on! I'll revive you!", "No... not again!"],
	"mage": ["We lost one! Recalculating...", "This changes the equation.", "Focus! We must continue!"],
	"rogue": ["They got one of ours!", "That's gonna cost them.", "Now I'm angry."],
	# Tick 291: meta-job ALLY_KO lines.
	"scriptweaver": ["Process terminated.", "Their thread crashed.", "Reverting their last commit later."],
	"time_mage": ["I can rewind.", "Give me one turn.", "This isn't final."],
	"necromancer": ["I'll keep their voice.", "Their chorus gains a member.", "The ledger grows."],
	"bossbinder": ["They wore the mask too long.", "Their script ran out.", "Boss-phase reversed."],
	"skiptrotter": ["Need a respawn here!", "Save state, load!", "Not in the route notes..."],
	"_default": ["We lost someone!", "No!", "Avenge them!"],
}

const COMBAT_QUIP_CHANCE: float = 0.30  # 30% chance per trigger


const VICTORY_QUIPS: Dictionary = {
	"fighter": ["Another victory!", "They didn't stand a chance.", "Who's next?", "Not even a scratch!"],
	"cleric": ["Everyone's safe... thank goodness.", "The light prevails.", "We made it through!", "Healing always wins."],
	"mage": ["Fascinating data collected.", "As my calculations predicted.", "Hypothesis confirmed.", "The arcane triumphs!"],
	"rogue": ["Easy loot.", "They never saw it coming.", "Dibs on the spoils.", "Too easy."],
	"bard": ["♪ And another one bites the dust~ ♪", "That's going in the ballad!", "Standing ovation!", "Encore? No? Okay."],
	"guardian": ["The line held.", "No casualties on my watch.", "Solid defense.", "Mission accomplished."],
	"ninja": ["Clean.", "Already done.", "Efficient.", "...moving on."],
	"summoner": ["The spirits are pleased.", "A worthy offering.", "The pact grows stronger.", "Well fought, all of us."],
	"speculator": ["Profit margins looking good.", "Return on investment: excellent.", "The market rewards the bold.", "Portfolio up."],
	# Tick 289: meta jobs now have diegetic quips matching their
	# schtick. Pre-fix all 5 fell through to "_default" / "Victory!"
	# which broke the per-job voice for debug-unlocked playthroughs.
	# Mirrors the tick-124 JOB_QUIP_COLORS extension (colors were
	# fixed; lines weren't).
	"scriptweaver": ["return WIN;", "Commit. Push. Merge.", "Patch deployed.", "// TODO: feel something"],
	"time_mage": ["Rewinding for the highlight reel.", "Knew this round before it began.", "Threading the timeline.", "Some battles end before they start."],
	"necromancer": ["The dead are louder than ever.", "Another for the choir.", "Even endings have endings.", "I'll lend their bones a new song."],
	"bossbinder": ["I felt them lose.", "We were them, briefly.", "Mask off. Next.", "Their script is now mine."],
	"skiptrotter": ["Skipped the cutscene, kept the EXP.", "Speed-pace cleared.", "Filing this under: handled.", "Already on the next map."],
	"_default": ["Victory!", "We did it!", "Well fought!"],
}


## Per-job bubble colors for quip identity
const JOB_QUIP_COLORS: Dictionary = {
	# Starter jobs
	"fighter": Color(0.9, 0.5, 0.2),    # Orange — aggressive
	"cleric": Color(1.0, 0.95, 0.6),    # Warm gold — holy
	"mage": Color(0.5, 0.4, 1.0),       # Purple — arcane
	"rogue": Color(0.4, 0.9, 0.4),      # Green — sneaky
	"bard": Color(1.0, 0.6, 0.8),       # Pink — performer
	# Advanced jobs
	"guardian": Color(0.6, 0.55, 0.4),   # Bronze — armored
	"ninja": Color(0.5, 0.5, 0.6),      # Dark gray — shadow
	"summoner": Color(0.3, 0.8, 0.7),   # Teal — ethereal
	"speculator": Color(0.3, 0.7, 0.3), # Money green — market
	# Tick 124: meta jobs — each colored to its diegetic schtick.
	# Pre-fix, all 5 fell through to the default gray Color(0.8, 0.8, 0.8)
	# in _get_job_quip_color, breaking the per-job visual story for
	# anyone unlocking them via debug mode.
	"scriptweaver": Color(0.0, 0.95, 0.55), # Neon green — terminal/code
	"time_mage": Color(0.7, 0.85, 1.0),     # Pale blue — chronal shimmer
	"necromancer": Color(0.45, 0.2, 0.55),  # Deep violet — undeath
	"bossbinder": Color(0.95, 0.25, 0.35),  # Boss-red — they BECOME the boss
	"skiptrotter": Color(0.95, 0.85, 0.35), # Glitchy yellow — frame-skip
}


func _get_job_quip_color(combatant: Combatant) -> Color:
	var job_id = combatant.job.get("id", "fighter") if combatant.job else "fighter"
	return JOB_QUIP_COLORS.get(job_id, Color(0.8, 0.8, 0.8))


func _try_combat_quip(quip_dict: Dictionary, combatant: Combatant) -> void:
	"""Try to show a combat quip — 30% chance, picks from job-specific or default pool"""
	if turbo_mode or randf() >= COMBAT_QUIP_CHANCE:
		return
	var job_id = combatant.job.get("id", "fighter") if combatant.job else "fighter"
	var pool = quip_dict.get(job_id, quip_dict.get("_default", []))
	if pool.is_empty():
		pool = quip_dict.get("_default", [])
	if pool.is_empty():
		return
	var line = pool[randi() % pool.size()]
	var sprite = _get_combatant_sprite(combatant)
	if sprite and is_instance_valid(sprite):
		_spawn_quip_bubble(sprite, combatant.combatant_name, line, _get_job_quip_color(combatant), 1.0)


## Track which monster types the player has encountered (persists in GameState).
## Delegates to BestiarySystem so the discovery dict has a single owner.
## Pre-fix this inlined the same `GameState.game_constants["seen_monsters"]…`
## lines that BestiarySystem.is_seen / mark_seen already implemented byte-for-
## byte; the BestiarySystem versions sat as dead code (zero callers) and would
## have drifted from these inlined copies on any future refactor.
func _is_new_monster(monster_type: String) -> bool:
	return not BestiarySystem.is_seen(monster_type)

func _mark_monster_seen(monster_type: String) -> void:
	# Tick 260: pass current map id so BestiaryMenu can show
	# "Last seen: <location>" — autobattle-planning hint.
	var loc: String = ""
	if MapSystem and "current_map_id" in MapSystem:
		loc = str(MapSystem.current_map_id)
	BestiarySystem.mark_seen(monster_type, loc)

func _show_battle_quip() -> void:
	"""Show a party member quip at battle start."""
	# Pick a random alive party member
	var alive = party_members.filter(func(m): return m is Combatant and m.is_alive)
	if alive.is_empty():
		return
	var speaker = alive[randi() % alive.size()]
	var job_id = speaker.job.get("id", "fighter") if speaker.job else "fighter"

	# Check for new monster encounter
	var has_new = false
	for enemy in test_enemies:
		if enemy and is_instance_valid(enemy):
			var mtype = enemy.get_meta("monster_type", "")
			if mtype != "" and _is_new_monster(mtype):
				has_new = true
				_mark_monster_seen(mtype)

	var quip_pool: Array
	if has_new and NEW_MONSTER_QUIPS.has(job_id):
		quip_pool = NEW_MONSTER_QUIPS[job_id]
	elif BATTLE_START_QUIPS.has(job_id):
		quip_pool = BATTLE_START_QUIPS[job_id]
	else:
		return

	var quip = quip_pool[randi() % quip_pool.size()]

	# Show monster-specific encounter flavor text first
	if has_new:
		var dominant = _get_dominant_monster_type()
		if dominant in MONSTER_ENCOUNTER_TEXT:
			log_message("[color=gray][i]%s[/i][/color]" % MONSTER_ENCOUNTER_TEXT[dominant])

	log_message("[color=#88ccff]%s:[/color] \"%s\"" % [speaker.combatant_name, quip])

	# Show as visible speech bubble above the speaker's sprite
	if not turbo_mode:
		var sprite = _get_combatant_sprite(speaker)
		if sprite and is_instance_valid(sprite):
			var border = Color(0.5, 0.8, 1.0) if has_new else _get_job_quip_color(speaker)
			_spawn_quip_bubble(sprite, speaker.combatant_name, quip, border, 2.0 if has_new else 1.5)

func show_brave_quip(combatant: Combatant, action_count: int) -> void:
	"""Show a quip when a character queues 3+ brave actions."""
	if action_count < 3:
		return
	var job_id = combatant.job.get("id", "fighter") if combatant.job else "fighter"
	if BRAVE_QUIPS.has(job_id):
		var pool = BRAVE_QUIPS[job_id]
		var quip = pool[randi() % pool.size()]
		log_message("[color=#ffcc44]%s:[/color] \"%s\"" % [combatant.combatant_name, quip])
