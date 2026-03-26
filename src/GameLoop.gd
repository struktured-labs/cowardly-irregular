extends Node

## GameLoop - Controls the exploration → battle → menu game loop
## Manages scene transitions and player persistence

const BattleSceneRes = preload("res://src/battle/BattleScene.tscn")
const BattleSceneScript = preload("res://src/battle/BattleScene.gd")
const OverworldSceneRes = preload("res://src/exploration/OverworldScene.tscn")
const CharacterCreationScreenClass = preload("res://src/ui/CharacterCreationScreen.gd")
const CustomizationScript = preload("res://src/character/CharacterCustomization.gd")
const TitleScreenClass = preload("res://src/ui/TitleScreen.gd")

const HarmoniaVillageRes = preload("res://src/maps/villages/HarmoniaVillage.tscn")
const WhisperingCaveRes = preload("res://src/maps/dungeons/WhisperingCave.tscn")
const TavernInteriorScript = preload("res://src/maps/interiors/TavernInterior.gd")
const FrostholdVillageScript = preload("res://src/maps/villages/FrostholdVillage.gd")
const EldertreeVillageScript = preload("res://src/maps/villages/EldertreeVillage.gd")
const GrimhollowVillageScript = preload("res://src/maps/villages/GrimhollowVillage.gd")
const SandriftVillageScript = preload("res://src/maps/villages/SandriftVillage.gd")
const IronhavenVillageScript = preload("res://src/maps/villages/IronhavenVillage.gd")
const MapleHeightsVillageScript = preload("res://src/maps/villages/MapleHeightsVillage.gd")
const BrasstonVillageScript = preload("res://src/maps/villages/BrasstonVillage.gd")
const RivetRowVillageScript = preload("res://src/maps/villages/RivetRowVillage.gd")
const NodePrimeVillageScript = preload("res://src/maps/villages/NodePrimeVillage.gd")
const VertexVillageScript = preload("res://src/maps/villages/VertexVillage.gd")
const IceDragonCaveScript = preload("res://src/maps/dungeons/IceDragonCave.gd")
const ShadowDragonCaveScript = preload("res://src/maps/dungeons/ShadowDragonCave.gd")
const LightningDragonCaveScript = preload("res://src/maps/dungeons/LightningDragonCave.gd")
const FireDragonCaveScript = preload("res://src/maps/dungeons/FireDragonCave.gd")
const SteampunkOverworldScript = preload("res://src/exploration/SteampunkOverworld.gd")
const SuburbanOverworldScript = preload("res://src/exploration/SuburbanOverworld.gd")
const IndustrialOverworldScript = preload("res://src/exploration/IndustrialOverworld.gd")
const FuturisticOverworldScript = preload("res://src/exploration/FuturisticOverworld.gd")
const AbstractOverworldScript = preload("res://src/exploration/AbstractOverworld.gd")

enum LoopState {
	TITLE,
	BATTLE,
	EXPLORATION,
	AUTOGRIND,
	CUTSCENE
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

## Area transition fade overlay (reused across all area transitions)
var _area_fade_layer: CanvasLayer = null
var _area_fade_rect: ColorRect = null

## Overworld menu
var _overworld_menu: Control = null
var _overworld_menu_layer: CanvasLayer = null

## Autogrind
var _autogrind_controller: Node = null
var _autogrind_ui: Control = null
var _autogrind_ui_layer: CanvasLayer = null
var _is_autogrinding: bool = false
var _autogrind_dashboard: Control = null
var _autogrind_overlay: Control = null
var _autogrind_overlay_layer: CanvasLayer = null
var _autogrind_battle_summaries: Array = []
var _controller_overlay: ControllerOverlay = null
var _controller_overlay_layer: CanvasLayer = null

## Character creation
var _character_creation_screen: Control = null
var _first_launch: bool = true  # True if no save exists

## Title screen
var _title_screen: Control = null
var _title_layer: CanvasLayer = null

func _ready() -> void:
	# Initialize equipment pool with extra items
	_init_equipment_pool()

	# Create the persistent area-transition fade overlay (layer=90, below BattleTransition=100)
	_area_fade_layer = CanvasLayer.new()
	_area_fade_layer.layer = 90
	add_child(_area_fade_layer)
	_area_fade_rect = ColorRect.new()
	_area_fade_rect.color = Color.BLACK
	_area_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_area_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_area_fade_rect.modulate.a = 0.0
	_area_fade_layer.add_child(_area_fade_rect)

	# Gamepad diagnostic overlay (F11)
	var diag_layer = CanvasLayer.new()
	diag_layer.layer = 99
	add_child(diag_layer)
	var diag = GamepadDiagnostic.new()
	diag_layer.add_child(diag)

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
		# Y button toggles turbo mode
		if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_Y:
			if current_scene and current_scene.has_method("set") and "turbo_mode" in current_scene:
				current_scene.turbo_mode = not current_scene.turbo_mode
				BattleManager.turbo_mode = current_scene.turbo_mode
				print("[AUTOGRIND] Turbo mode: %s" % ("ON" if current_scene.turbo_mode else "OFF"))
			get_viewport().set_input_as_handled()
			return
		# Y key (keyboard) toggles turbo mode
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Y:
			if current_scene and "turbo_mode" in current_scene:
				current_scene.turbo_mode = not current_scene.turbo_mode
				BattleManager.turbo_mode = current_scene.turbo_mode
				print("[AUTOGRIND] Turbo mode: %s" % ("ON" if current_scene.turbo_mode else "OFF"))
			get_viewport().set_input_as_handled()
			return
		# T key (keyboard) cycles tier
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T:
			if _autogrind_controller and is_instance_valid(_autogrind_controller):
				_autogrind_controller.cycle_tier()
			get_viewport().set_input_as_handled()
			return
		# L+R shoulder together cycles tier
		if event is InputEventJoypadButton and event.pressed:
			if event.button_index == JOY_BUTTON_LEFT_SHOULDER or event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
				if Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER) and Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER):
					if _autogrind_controller and is_instance_valid(_autogrind_controller):
						_autogrind_controller.cycle_tier()
					get_viewport().set_input_as_handled()
					return
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

	# Start button = context-dependent:
	# - In battle: open autobattle editor
	# - In exploration/village/cave: open settings menu
	if event.is_action_pressed("ui_menu"):
		if current_state == LoopState.BATTLE:
			if not _autobattle_editor or not is_instance_valid(_autobattle_editor):
				_toggle_autobattle_editor()
				get_viewport().set_input_as_handled()
		elif current_state == LoopState.EXPLORATION:
			_open_settings_menu()
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
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
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


func _sync_party_to_game_state() -> void:
	"""Sync runtime Combatant party into GameState.player_party for leader lookup"""
	GameState.player_party.clear()
	for member in party:
		var job_id = "fighter"
		if member.job and member.job is Dictionary:
			job_id = member.job.get("id", "fighter")
		GameState.player_party.append({"job_id": job_id, "name": member.combatant_name})
	# Clamp leader index in case party size changed
	if not GameState.player_party.is_empty():
		GameState.party_leader_index = clampi(GameState.party_leader_index, 0, GameState.player_party.size() - 1)


func _open_overworld_menu() -> void:
	"""Open the overworld/pause menu"""
	if _overworld_menu and is_instance_valid(_overworld_menu):
		return  # Already open

	# Sync party data into GameState so leader cycling has job info
	_sync_party_to_game_state()

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
	if _overworld_menu.has_signal("teleport_requested"):
		_overworld_menu.teleport_requested.connect(_on_teleport_requested)
	if _overworld_menu.has_signal("party_leader_changed"):
		_overworld_menu.party_leader_changed.connect(_on_party_leader_changed)
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


func _on_party_leader_changed(new_index: int) -> void:
	"""Update the overworld player sprite when the party leader changes"""
	if party.is_empty() or new_index >= party.size():
		return
	var leader = party[new_index]
	print("[LEADER] Party leader changed to index %d: %s" % [new_index, leader.combatant_name])
	if _exploration_scene:
		if _exploration_scene.has_method("set_player_appearance"):
			_exploration_scene.set_player_appearance(leader)
		elif _exploration_scene.has_method("set_player_job"):
			var job_id = "fighter"
			if leader.job and leader.job is Dictionary:
				job_id = leader.job.get("id", "fighter")
			_exploration_scene.set_player_job(job_id)


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


## Cutscene system
var _cutscene_director: Node = null

func _on_title_new_game() -> void:
	"""Handle new game selected from title screen"""
	print("[GAME] New Game selected")
	_close_title_screen()
	# Wait for title screen to actually be removed before starting cutscene
	await get_tree().process_frame
	await get_tree().process_frame
	# Skip character creation — use default party (fighter/cleric/rogue/mage)
	_create_party()
	# Play prologue cutscene, then start exploration
	_play_new_game_cutscenes()


func _play_new_game_cutscenes() -> void:
	"""Play prologue cutscene on new game, then start exploration."""
	current_state = LoopState.CUTSCENE
	if not _cutscene_director:
		_cutscene_director = CutsceneDirector.new()
		add_child(_cutscene_director)
	_cutscene_director.cutscene_finished.connect(_on_prologue_finished, CONNECT_ONE_SHOT)
	_cutscene_director.play_cutscene("world1_prologue")


func _on_prologue_finished(_cutscene_id: String) -> void:
	"""After prologue, start exploration."""
	current_state = LoopState.EXPLORATION
	_start_exploration()


func _on_title_continue() -> void:
	"""Handle continue selected from title screen"""
	print("[GAME] Continue selected")
	_close_title_screen()
	# Load saved party and start exploration
	_create_party()
	_start_exploration()


func _open_settings_menu() -> void:
	"""Open settings menu during exploration (Start button)"""
	print("[GAME] Settings menu opened from exploration")
	var SettingsMenuClass = load("res://src/ui/SettingsMenu.gd")
	if SettingsMenuClass:
		var settings_layer = CanvasLayer.new()
		settings_layer.layer = 110
		add_child(settings_layer)
		var settings_menu = SettingsMenuClass.new()
		settings_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
		settings_layer.add_child(settings_menu)
		if _exploration_scene and _exploration_scene.has_method("pause"):
			_exploration_scene.pause()
		settings_menu.closed.connect(func():
			settings_layer.queue_free()
			if _exploration_scene and _exploration_scene.has_method("resume"):
				_exploration_scene.resume()
		)


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

	# Create Hero (Fighter / secondary: Rogue)
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
	JobSystem.assign_secondary_job(hero, "rogue")
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

	# Create Mira (Cleric / secondary: Bard)
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
	JobSystem.assign_job(mira, "cleric")
	JobSystem.assign_secondary_job(mira, "bard")
	EquipmentSystem.equip_weapon(mira, "oak_staff")
	EquipmentSystem.equip_armor(mira, "cloth_robe")
	EquipmentSystem.equip_accessory(mira, "magic_ring")
	mira.learn_passive("magic_boost")
	mira.learn_passive("mp_boost")
	PassiveSystem.equip_passive(mira, "magic_boost")
	PassiveSystem.equip_passive(mira, "mp_boost")
	party.append(mira)

	# Create Zack (Rogue / secondary: Fighter)
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
	JobSystem.assign_job(zack, "rogue")
	JobSystem.assign_secondary_job(zack, "fighter")
	EquipmentSystem.equip_weapon(zack, "iron_dagger")
	EquipmentSystem.equip_armor(zack, "thief_garb")
	EquipmentSystem.equip_accessory(zack, "speed_boots")
	zack.learn_passive("critical_strike")
	zack.learn_passive("speed_boost")
	PassiveSystem.equip_passive(zack, "critical_strike")
	PassiveSystem.equip_passive(zack, "speed_boost")
	party.append(zack)

	# Create Vex (Mage / secondary: Cleric)
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
	JobSystem.assign_job(vex, "mage")
	JobSystem.assign_secondary_job(vex, "cleric")
	EquipmentSystem.equip_weapon(vex, "shadow_rod")
	EquipmentSystem.equip_armor(vex, "dark_robe")
	EquipmentSystem.equip_accessory(vex, "mp_amulet")
	vex.learn_passive("magic_boost")
	vex.learn_passive("mp_efficiency")
	PassiveSystem.equip_passive(vex, "magic_boost")
	PassiveSystem.equip_passive(vex, "mp_efficiency")
	party.append(vex)


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
	"""Wait for the player to press confirm (A/Z/Enter/mouse click) before continuing"""
	# Small delay so the press that ended the battle doesn't immediately confirm
	await get_tree().create_timer(0.5).timeout
	while true:
		await get_tree().process_frame
		if Input.is_action_just_pressed("ui_accept"):
			break
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			break


## Exploration Management

func _start_exploration() -> void:
	"""Start exploration mode (overworld or interior)"""
	current_state = LoopState.EXPLORATION
	InputLockManager.pop_all()  # Clear any leaked locks from previous state

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
			exploration_scene = FrostholdVillageScript.new()
		"eldertree_village":
			exploration_scene = EldertreeVillageScript.new()
		"grimhollow_village":
			exploration_scene = GrimhollowVillageScript.new()
		"sandrift_village":
			exploration_scene = SandriftVillageScript.new()
		"ironhaven_village":
			exploration_scene = IronhavenVillageScript.new()
		"ice_dragon_cave":
			exploration_scene = _create_dragon_cave_from_script(IceDragonCaveScript)
		"shadow_dragon_cave":
			exploration_scene = _create_dragon_cave_from_script(ShadowDragonCaveScript)
		"lightning_dragon_cave":
			exploration_scene = _create_dragon_cave_from_script(LightningDragonCaveScript)
		"fire_dragon_cave":
			exploration_scene = _create_dragon_cave_from_script(FireDragonCaveScript)
		"steampunk_overworld":
			exploration_scene = SteampunkOverworldScript.new()
		"suburban_overworld":
			exploration_scene = SuburbanOverworldScript.new()
		"industrial_overworld":
			exploration_scene = IndustrialOverworldScript.new()
		"futuristic_overworld":
			exploration_scene = FuturisticOverworldScript.new()
		"abstract_overworld":
			exploration_scene = AbstractOverworldScript.new()
		"maple_heights_village":
			exploration_scene = MapleHeightsVillageScript.new()
		"brasston_village":
			exploration_scene = BrasstonVillageScript.new()
		"rivet_row_village":
			exploration_scene = RivetRowVillageScript.new()
		"node_prime_village":
			exploration_scene = NodePrimeVillageScript.new()
		"vertex_village":
			exploration_scene = VertexVillageScript.new()
		_:
			exploration_scene = OverworldSceneRes.instantiate()

	add_child(exploration_scene)
	current_scene = exploration_scene
	_exploration_scene = exploration_scene

	# Spawn player at correct position
	if exploration_scene.has_method("spawn_player_at"):
		exploration_scene.spawn_player_at(_spawn_point)

	# Set player appearance based on party leader (respects party_leader_index)
	if party.size() > 0:
		var leader_idx = clampi(GameState.party_leader_index, 0, party.size() - 1)
		var leader = party[leader_idx]
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
		if enemy is String:
			if enemy not in monster_ids:
				monster_ids.append(enemy)
		elif enemy is Dictionary:
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
			common_enemies = ["clockwork_sentinel", "steam_rat", "brass_golem", "cog_swarm", "pipe_phantom"]
		"suburban_overworld":
			common_enemies = ["new_age_retro_hippie", "spiteful_crow", "skate_punk"]
		"industrial_overworld":
			common_enemies = ["assembly_line_automaton", "rust_elemental", "toxic_sludge"]
		"futuristic_overworld":
			common_enemies = ["rogue_process", "memory_leak", "firewall_sentinel"]
		"abstract_overworld":
			common_enemies = ["null_entity", "forgotten_variable", "empty_set"]
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
	print("[GAMELOOP] _on_exploration_battle_triggered called! state=%s enemies=%s" % [current_state, enemies])
	# Guard against battle triggers during non-exploration states
	if current_state != LoopState.EXPLORATION:
		print("[GAMELOOP] BLOCKED — state is %s, not EXPLORATION" % current_state)
		return
	# Guard against battles while menus/UIs are open
	if _overworld_menu and is_instance_valid(_overworld_menu):
		print("[GAMELOOP] BLOCKED — overworld menu is open")
		return
	if _autogrind_ui and is_instance_valid(_autogrind_ui):
		print("[GAMELOOP] BLOCKED — autogrind UI is open")
		return

	# LoopState.BATTLE blocks player movement — no need to pause exploration.
	# Pausing here without guaranteed resume caused the 2s freeze bug.

	# NOTE: Do NOT hide the exploration scene here — BattleTransition needs one rendered
	# frame to capture the overworld screenshot. We hide it at transition_midpoint instead,
	# right before instantiating the battle scene behind the overlay.

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
			# Movement blocked by LoopState.BATTLE — no manual freeze needed

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

	if BattleTransition:
		print("[GAMELOOP] Starting battle transition")

		# Run the transition effect (captures screen, plays animation, ends on black)
		await BattleTransition.play_battle_transition(enemy_types)
		print("[GAMELOOP] Battle transition effect complete")

		# Hide exploration scene (screenshot already taken)
		if _exploration_scene and is_instance_valid(_exploration_scene):
			_exploration_scene.visible = false

		# Load battle scene (uses preloaded resource, always available)
		await _start_battle_async(enemies, true)
		print("[GAMELOOP] Battle started")

		# Reveal the battle scene
		await BattleTransition.fade_out()
		print("[GAMELOOP] Fade out complete - battle should be visible")
	else:
		# No transition — load battle directly
		await _start_battle_async(enemies, true)



func _start_battle_async(specific_enemies: Array = [], is_encounter: bool = false) -> void:
	"""Start battle using async-loaded scene"""
	current_state = LoopState.BATTLE

	# Remove old scene
	if current_scene and is_instance_valid(current_scene):
		current_scene.queue_free()
		await current_scene.tree_exited

	# Clear stale exploration reference (scene is freed)
	_exploration_scene = null

	# Reset viewport camera to prevent exploration zoom from contaminating battle
	var viewport = get_viewport()
	if viewport:
		var cam = viewport.get_camera_2d()
		if cam and is_instance_valid(cam):
			cam.zoom = Vector2(1.0, 1.0)

	# Extract enemy IDs from mixed formats (String or Dict)
	var enemy_ids: Array = []
	for entry in specific_enemies:
		if entry is String:
			enemy_ids.append(entry)
		elif entry is Dictionary:
			enemy_ids.append(entry.get("type", entry.get("id", "slime")))

	var has_enemies = enemy_ids.size() > 0

	# Check if this is a miniboss battle (every 3rd battle), but not if forced enemies
	var is_miniboss_battle = not has_enemies and (battles_won + 1) % 3 == 0 and battles_won > 0

	# Use preloaded battle scene (always available, no race conditions)
	var battle_scene = BattleSceneRes.instantiate()

	# Set flags and party BEFORE adding to tree (since _ready() uses these)
	battle_scene.managed_by_game_loop = true
	battle_scene.set_party(party)

	# Route enemies to the correct BattleScene property
	if has_enemies and is_encounter:
		# Random encounter from exploration — use encounter_enemies path
		battle_scene.encounter_enemies = enemy_ids
		print("[ENCOUNTER] Spawning encounter enemies: %s" % [enemy_ids])
		battle_scene.set_terrain(_current_terrain)
	elif has_enemies:
		# Boss/scripted battle — use forced_enemies path
		battle_scene.forced_enemies = enemy_ids
		print("[BOSS] Forcing specific enemies: %s" % [enemy_ids])
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


func _on_teleport_requested(target_map: String, spawn_point: String) -> void:
	"""Handle debug teleport from overworld menu"""
	# Close the overworld menu first
	_on_overworld_menu_closed()
	# Then transition
	_on_area_transition(target_map, spawn_point)


func _area_fade_to_black() -> void:
	"""Fade the area-transition overlay to opaque black (0.3s). Generic fallback."""
	if not _area_fade_rect:
		return
	var tween = create_tween()
	tween.tween_property(_area_fade_rect, "modulate:a", 1.0, 0.3)
	await tween.finished


func _area_fade_from_black() -> void:
	"""Fade the area-transition overlay back to transparent (0.3s). Generic fallback."""
	if not _area_fade_rect:
		return
	var tween = create_tween()
	tween.tween_property(_area_fade_rect, "modulate:a", 0.0, 0.3)
	await tween.finished


func _get_transition_type(map_id: String) -> String:
	"""Classify destination into cave, village, overworld, or generic."""
	var t = map_id.to_lower()
	if "cave" in t or "dungeon" in t:
		return "cave"
	if "village" in t or "town" in t or "heights" in t or "row" in t \
			or "prime" in t or "vertex" in t or "brasston" in t \
			or "harmonia" in t or "tavern" in t or "frosthold" in t \
			or "eldertree" in t or "grimhollow" in t or "sandrift" in t \
			or "ironhaven" in t:
		return "village"
	if "overworld" in t or t == "overworld":
		return "overworld"
	return "generic"


func _get_location_display_name(map_id: String) -> String:
	"""Return the human-readable name from locations.json, or a formatted fallback."""
	var file = FileAccess.open("res://data/locations.json", FileAccess.READ)
	if file:
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			var data = json.data
			if data is Dictionary:
				for key in data:
					var entry = data[key]
					if entry is Dictionary and entry.get("map_id", key) == map_id:
						return entry.get("name", map_id.replace("_", " ").capitalize())
		file.close()
	return map_id.replace("_", " ").capitalize()


func _make_location_label(text: String, layer: CanvasLayer) -> Label:
	"""Create a centred location-name label styled to the game aesthetic."""
	var lbl = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.78))
	lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.modulate.a = 0.0
	layer.add_child(lbl)
	return lbl


func _area_cave_transition_in(location_name: String) -> void:
	"""Stone-door slam effect: dim then two rects close from top and bottom."""
	if not _area_fade_rect or not _area_fade_layer:
		await _area_fade_to_black()
		return

	var screen_size = get_viewport().get_visible_rect().size

	# Dim phase (0.25s)
	var dim_tween = create_tween()
	dim_tween.tween_property(_area_fade_rect, "modulate:a", 0.55, 0.25)
	await dim_tween.finished

	# Create top and bottom stone door rects
	var top_door = ColorRect.new()
	top_door.color = Color(0.08, 0.07, 0.09)
	top_door.size = Vector2(screen_size.x, screen_size.y * 0.5 + 4)
	top_door.position = Vector2(0, -screen_size.y * 0.5 - 4)
	_area_fade_layer.add_child(top_door)

	var bottom_door = ColorRect.new()
	bottom_door.color = Color(0.08, 0.07, 0.09)
	bottom_door.size = Vector2(screen_size.x, screen_size.y * 0.5 + 4)
	bottom_door.position = Vector2(0, screen_size.y)
	_area_fade_layer.add_child(bottom_door)

	# Door slam (0.35s) — ease in for weight
	var slam_tween = create_tween()
	slam_tween.set_parallel(true)
	slam_tween.tween_property(top_door, "position:y", 0.0, 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	slam_tween.tween_property(bottom_door, "position:y", screen_size.y * 0.5, 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await slam_tween.finished

	# Snap base rect to full black so it covers when doors are removed later
	_area_fade_rect.modulate.a = 1.0

	# Location label fade in
	var lbl = _make_location_label("Entering " + location_name + "...", _area_fade_layer)
	var lbl_tween = create_tween()
	lbl_tween.tween_property(lbl, "modulate:a", 1.0, 0.2)
	await lbl_tween.finished
	await get_tree().create_timer(0.35).timeout

	# Clean up doors and label (base rect stays black)
	top_door.queue_free()
	bottom_door.queue_free()
	lbl.queue_free()


func _area_cave_transition_out() -> void:
	"""Stone doors open vertically to reveal the cave."""
	if not _area_fade_rect or not _area_fade_layer:
		await _area_fade_from_black()
		return

	var screen_size = get_viewport().get_visible_rect().size

	# Create doors starting in closed position
	var top_door = ColorRect.new()
	top_door.color = Color(0.08, 0.07, 0.09)
	top_door.size = Vector2(screen_size.x, screen_size.y * 0.5 + 4)
	top_door.position = Vector2(0, 0)
	_area_fade_layer.add_child(top_door)

	var bottom_door = ColorRect.new()
	bottom_door.color = Color(0.08, 0.07, 0.09)
	bottom_door.size = Vector2(screen_size.x, screen_size.y * 0.5 + 4)
	bottom_door.position = Vector2(0, screen_size.y * 0.5)
	_area_fade_layer.add_child(bottom_door)

	_area_fade_rect.modulate.a = 0.0  # Let doors carry the black

	# Open doors (0.45s) — ease out for smooth reveal
	var open_tween = create_tween()
	open_tween.set_parallel(true)
	open_tween.tween_property(top_door, "position:y", -screen_size.y * 0.5 - 4, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	open_tween.tween_property(bottom_door, "position:y", screen_size.y, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	await open_tween.finished

	top_door.queue_free()
	bottom_door.queue_free()


func _area_village_transition_in(location_name: String) -> void:
	"""Warm amber horizontal wipe left-to-right."""
	if not _area_fade_rect or not _area_fade_layer:
		await _area_fade_to_black()
		return

	var screen_size = get_viewport().get_visible_rect().size

	# Amber wipe bar — starts off-screen left
	var wipe = ColorRect.new()
	wipe.color = Color(0.72, 0.48, 0.12)
	wipe.size = Vector2(screen_size.x * 1.1, screen_size.y)
	wipe.position = Vector2(-screen_size.x * 1.1, 0)
	_area_fade_layer.add_child(wipe)

	# Trailing black fill that follows the wipe
	var fill = ColorRect.new()
	fill.color = Color(0.04, 0.03, 0.02)
	fill.size = Vector2(screen_size.x * 1.1, screen_size.y)
	fill.position = Vector2(-screen_size.x * 2.1, 0)
	_area_fade_layer.add_child(fill)

	_area_fade_rect.modulate.a = 0.0

	var wipe_tween = create_tween()
	wipe_tween.set_parallel(true)
	wipe_tween.tween_property(wipe, "position:x", screen_size.x, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	wipe_tween.tween_property(fill, "position:x", 0.0, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	await wipe_tween.finished

	# Snap base rect to full black, remove wipe bar
	_area_fade_rect.modulate.a = 1.0
	wipe.queue_free()
	fill.queue_free()

	# Show location label with animated dots
	var lbl = _make_location_label("Arriving at " + location_name + "...", _area_fade_layer)
	var lbl_tween = create_tween()
	lbl_tween.tween_property(lbl, "modulate:a", 1.0, 0.18)
	await lbl_tween.finished
	await get_tree().create_timer(0.38).timeout
	lbl.queue_free()


func _area_village_transition_out() -> void:
	"""Reverse amber wipe: right-to-left to reveal village."""
	if not _area_fade_rect or not _area_fade_layer:
		await _area_fade_from_black()
		return

	var screen_size = get_viewport().get_visible_rect().size

	var wipe = ColorRect.new()
	wipe.color = Color(0.72, 0.48, 0.12)
	wipe.size = Vector2(screen_size.x * 1.1, screen_size.y)
	wipe.position = Vector2(-screen_size.x * 0.05, 0)
	_area_fade_layer.add_child(wipe)

	_area_fade_rect.modulate.a = 0.0

	var wipe_tween = create_tween()
	wipe_tween.tween_property(wipe, "position:x", screen_size.x * 1.1, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	await wipe_tween.finished

	wipe.queue_free()


func _area_overworld_transition_in() -> void:
	"""Circular iris-out: screen shrinks to a point at center, hold black."""
	if not _area_fade_rect or not _area_fade_layer:
		await _area_fade_to_black()
		return

	# Use a shader-based approach via a SubViewport is complex; instead we approximate
	# an iris with radial segments drawn via a Control's _draw, using a tween on a
	# custom property. As a clean fallback we use a fast vignette fade instead.
	# True circle masking in Godot without shaders needs a CanvasItem shader or
	# a SubViewport which is too heavy for a transition. We use concentric rects
	# growing inward to approximate the iris closing.
	var screen_size = get_viewport().get_visible_rect().size
	var cx = screen_size.x * 0.5
	var cy = screen_size.y * 0.5

	# Four black rects collapsing toward center from all four sides
	var left_r = ColorRect.new()
	left_r.color = Color.BLACK
	left_r.set_anchors_preset(Control.PRESET_FULL_RECT)
	left_r.size = Vector2(cx, screen_size.y)
	left_r.position = Vector2(0, 0)
	left_r.pivot_offset = Vector2(0, 0)

	var right_r = ColorRect.new()
	right_r.color = Color.BLACK
	right_r.size = Vector2(cx, screen_size.y)
	right_r.position = Vector2(screen_size.x, 0)

	var top_r = ColorRect.new()
	top_r.color = Color.BLACK
	top_r.size = Vector2(screen_size.x, cy)
	top_r.position = Vector2(0, 0)

	var bottom_r = ColorRect.new()
	bottom_r.color = Color.BLACK
	bottom_r.size = Vector2(screen_size.x, cy)
	bottom_r.position = Vector2(0, screen_size.y)

	for r in [left_r, right_r, top_r, bottom_r]:
		r.modulate.a = 0.0
		_area_fade_layer.add_child(r)

	_area_fade_rect.modulate.a = 0.0

	var dur = 0.5
	var iris_tween = create_tween()
	iris_tween.set_parallel(true)
	# Fade in all four and slide them inward simultaneously
	iris_tween.tween_property(left_r, "modulate:a", 1.0, dur * 0.3)
	iris_tween.tween_property(right_r, "modulate:a", 1.0, dur * 0.3)
	iris_tween.tween_property(top_r, "modulate:a", 1.0, dur * 0.3)
	iris_tween.tween_property(bottom_r, "modulate:a", 1.0, dur * 0.3)
	iris_tween.tween_property(left_r, "size:x", cx, dur).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	iris_tween.tween_property(right_r, "position:x", cx, dur).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	iris_tween.tween_property(top_r, "size:y", cy, dur).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	iris_tween.tween_property(bottom_r, "position:y", cy, dur).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await iris_tween.finished

	# Snap full black, clean up rects
	_area_fade_rect.modulate.a = 1.0
	left_r.queue_free()
	right_r.queue_free()
	top_r.queue_free()
	bottom_r.queue_free()

	# Hold black briefly
	await get_tree().create_timer(0.2).timeout


func _area_overworld_transition_out() -> void:
	"""Iris opens from center revealing the overworld (0.5s)."""
	if not _area_fade_rect or not _area_fade_layer:
		await _area_fade_from_black()
		return

	var screen_size = get_viewport().get_visible_rect().size
	var cx = screen_size.x * 0.5
	var cy = screen_size.y * 0.5

	var left_r = ColorRect.new()
	left_r.color = Color.BLACK
	left_r.size = Vector2(cx, screen_size.y)
	left_r.position = Vector2(0, 0)

	var right_r = ColorRect.new()
	right_r.color = Color.BLACK
	right_r.size = Vector2(cx, screen_size.y)
	right_r.position = Vector2(cx, 0)

	var top_r = ColorRect.new()
	top_r.color = Color.BLACK
	top_r.size = Vector2(screen_size.x, cy)
	top_r.position = Vector2(0, 0)

	var bottom_r = ColorRect.new()
	bottom_r.color = Color.BLACK
	bottom_r.size = Vector2(screen_size.x, cy)
	bottom_r.position = Vector2(0, cy)

	for r in [left_r, right_r, top_r, bottom_r]:
		_area_fade_layer.add_child(r)

	_area_fade_rect.modulate.a = 0.0

	var dur = 0.5
	var iris_tween = create_tween()
	iris_tween.set_parallel(true)
	iris_tween.tween_property(left_r, "position:x", -cx, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	iris_tween.tween_property(right_r, "position:x", screen_size.x, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	iris_tween.tween_property(top_r, "position:y", -cy, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	iris_tween.tween_property(bottom_r, "position:y", screen_size.y, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	await iris_tween.finished

	left_r.queue_free()
	right_r.queue_free()
	top_r.queue_free()
	bottom_r.queue_free()


var _transition_in_progress: bool = false

func _on_area_transition(target_map: String, spawn_point: String) -> void:
	"""Handle contextual area transition based on destination type."""
	if _transition_in_progress:
		return
	_transition_in_progress = true
	_current_map_id = target_map
	_spawn_point = spawn_point
	_player_position = Vector2.ZERO
	_current_terrain = _get_terrain_for_map(target_map)

	var transition_type = _get_transition_type(target_map)
	var display_name = _get_location_display_name(target_map)

	match transition_type:
		"cave":
			await _area_cave_transition_in(display_name)
			await _start_exploration()
			await _area_cave_transition_out()
		"village":
			await _area_village_transition_in(display_name)
			await _start_exploration()
			await _area_village_transition_out()
		"overworld":
			await _area_overworld_transition_in()
			await _start_exploration()
			await _area_overworld_transition_out()
		_:
			await _area_fade_to_black()
			await _start_exploration()
			await _area_fade_from_black()

	# Safety cleanup: ensure fade overlay is transparent and no stale children remain
	if _area_fade_rect:
		_area_fade_rect.modulate.a = 0.0
	if _area_fade_layer:
		for child in _area_fade_layer.get_children():
			if child != _area_fade_rect:
				child.queue_free()
	_transition_in_progress = false


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
		"suburban_overworld":
			return "suburban"
		"industrial_overworld":
			return "industrial"
		"futuristic_overworld":
			return "digital"
		"abstract_overworld":
			return "void"
		"maple_heights_village":
			return "village"
		"brasston_village":
			return "village"
		"rivet_row_village":
			return "village"
		"node_prime_village":
			return "village"
		"vertex_village":
			return "village"
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
	return HarmoniaVillageRes.instantiate()


func _create_cave_scene() -> Node:
	"""Create Whispering Cave scene and restore floor state"""
	var cave_scene = WhisperingCaveRes.instantiate()
	if _current_cave_floor > 1 and "current_floor" in cave_scene:
		cave_scene.current_floor = _current_cave_floor
		print("[CAVE] Restoring to floor %d" % _current_cave_floor)
	return cave_scene


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


func _create_dragon_cave_from_script(script_res: GDScript) -> Node:
	"""Create a dragon cave scene from a preloaded script and restore floor state"""
	var cave_scene = script_res.new()
	if _current_cave_floor > 1 and "current_floor" in cave_scene:
		cave_scene.current_floor = _current_cave_floor
		print("[CAVE] Restoring to floor %d" % _current_cave_floor)
	return cave_scene


func _create_tavern_scene() -> Node:
	"""Create The Dancing Tonberry tavern interior scene"""
	return TavernInteriorScript.new()


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
	_autogrind_ui.tier_cycle_requested.connect(_on_ui_tier_cycle_requested)

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
	_autogrind_controller.tier_changed.connect(_on_autogrind_tier_changed)

	# Clear battle summary ring buffer for new session
	_autogrind_battle_summaries.clear()

	# Switch to dedicated autogrind ambient music
	SoundManager.reset_corruption()
	SoundManager.play_music("autogrind")

	_show_controller_overlay(ControllerOverlay.autogrind_context())

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

	# Reset turbo mode
	BattleManager.turbo_mode = false

	# Clean up dashboard
	if _autogrind_dashboard and is_instance_valid(_autogrind_dashboard):
		_autogrind_dashboard.queue_free()
		_autogrind_dashboard = null

	# Clean up compact overlay
	_destroy_autogrind_overlay()
	_destroy_controller_overlay()

	# Reset engine speed
	Engine.time_scale = 1.0

	# Restore clean audio state and resume area music
	SoundManager.reset_corruption()
	SoundManager.play_area_music(_current_map_id)

	print("[AUTOGRIND] Session stopped: %s" % reason)

	# Return to exploration if UI is also closed
	if not _autogrind_ui or not is_instance_valid(_autogrind_ui):
		_return_to_exploration()
	else:
		current_state = LoopState.EXPLORATION
		InputLockManager.pop_all()  # Clear any leaked locks


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


func _show_autogrind_transition() -> void:
	var battle_num = 0
	if _autogrind_controller and is_instance_valid(_autogrind_controller):
		var stats = _autogrind_controller.get_grind_stats()
		battle_num = stats.get("battles_won", 0) + 1

	var speed_text = ""
	if BattleManager.turbo_mode:
		speed_text = "TURBO"
	else:
		var speed_idx = BattleSceneScript._battle_speed_index
		var labels = BattleSceneScript.BATTLE_SPEED_LABELS
		if speed_idx < labels.size():
			speed_text = labels[speed_idx]

	var layer = CanvasLayer.new()
	layer.layer = 95
	add_child(layer)

	var overlay = ColorRect.new()
	overlay.color = Color(0.02, 0.01, 0.05, 0.9)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(overlay)

	var battle_label = Label.new()
	battle_label.text = "BATTLE #%d" % battle_num
	battle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	battle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	battle_label.set_anchors_preset(Control.PRESET_CENTER)
	battle_label.add_theme_font_size_override("font_size", 32)
	battle_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.4))
	battle_label.position = Vector2(-100, -30)
	battle_label.size = Vector2(200, 40)
	layer.add_child(battle_label)

	if speed_text != "":
		var speed_label = Label.new()
		speed_label.text = speed_text
		speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		speed_label.set_anchors_preset(Control.PRESET_CENTER)
		speed_label.add_theme_font_size_override("font_size", 20)
		var color = Color(0.9, 0.3, 0.3) if speed_text == "TURBO" else Color(0.4, 0.9, 0.4)
		speed_label.add_theme_color_override("font_color", color)
		speed_label.position = Vector2(-60, 10)
		speed_label.size = Vector2(120, 30)
		layer.add_child(speed_label)

	var tween = create_tween()
	tween.tween_property(overlay, "color:a", 0.0, 0.25).set_delay(0.05)
	tween.parallel().tween_property(battle_label, "modulate:a", 0.0, 0.2).set_delay(0.1)
	tween.tween_callback(layer.queue_free)


func _start_autogrind_battle(enemy_data: Array) -> void:
	"""Start a battle scene with pre-configured autogrind enemies"""
	_show_autogrind_transition()

	# Remove old scene
	if current_scene and is_instance_valid(current_scene):
		current_scene.queue_free()
		await current_scene.tree_exited

	# Create battle scene using preloaded resource (avoids redundant disk load)
	var battle_scene = BattleSceneRes.instantiate()

	# Configure for autogrind
	battle_scene.managed_by_game_loop = true
	battle_scene.set_party(party)
	battle_scene.autogrind_enemy_data = enemy_data
	battle_scene.set_terrain(_current_terrain)

	add_child(battle_scene)
	current_scene = battle_scene

	# Set turbo mode based on tier
	if _autogrind_controller and is_instance_valid(_autogrind_controller):
		var tier = _autogrind_controller.get_current_tier()
		# Both tiers use turbo for fastest execution
		battle_scene.turbo_mode = true
		BattleManager.turbo_mode = true

	# Wait for scene to be ready
	await get_tree().process_frame

	# Enable autogrind console mode (replaces battle log with grind stats feed)
	battle_scene.enable_autogrind_console()

	# Replay recent battle summaries into the new console
	for summary_line in _autogrind_battle_summaries:
		battle_scene.autogrind_console_log(summary_line)

	# Show current stats block
	if _autogrind_controller and is_instance_valid(_autogrind_controller):
		battle_scene.update_autogrind_console_stats(_autogrind_controller.get_grind_stats())

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

		# Feed battle action summary into adaptive AI pattern learning
		var region_id = AutogrindSystem.current_region_id
		if not region_id.is_empty():
			var battle_summary = BattleManager._summarize_battle_actions()
			AutogrindSystem.update_learned_patterns(region_id, battle_summary)

		# Heal party using items (no free healing)
		for member in party:
			member.current_ap = 0
			if member.is_alive and member.current_hp < member.max_hp:
				_autogrind_heal_member(member)
			if member.is_alive and member.current_mp < member.max_mp * 0.5:
				_autogrind_restore_mp(member)

	# Forward to controller
	if _autogrind_controller and is_instance_valid(_autogrind_controller):
		_autogrind_controller.on_battle_ended(victory, exp_gained, items_gained)

		var stats = _autogrind_controller.get_grind_stats()

		# Build one-line battle summary for the console ring buffer
		var rounds = BattleManager.current_round
		var summary_text: String
		if victory:
			summary_text = "[color=#44ff44]#%d Victory[/color] +%d EXP (%d rounds)" % [stats.get("battles_won", 0), exp_gained, rounds]
			if BattleManager._one_shot_achieved:
				summary_text += " [color=#ffaa00]ONE-SHOT![/color]"
		else:
			summary_text = "[color=#ff4444]#%d Defeat[/color] (%d rounds)" % [stats.get("battles_won", 0), rounds]
		_autogrind_battle_summaries.append(summary_text)
		if _autogrind_battle_summaries.size() > 50:
			_autogrind_battle_summaries.remove_at(0)

		# Update UI with latest stats
		if _autogrind_ui and is_instance_valid(_autogrind_ui):
			_autogrind_ui.update_stats(stats)
			_autogrind_ui.update_party_status()

		# Update dashboard if in Tier 2
		if _autogrind_dashboard and is_instance_valid(_autogrind_dashboard):
			var region_id = _current_map_id.replace(" ", "_").to_lower()
			_autogrind_dashboard.refresh(stats, region_id)

		# Update corruption audio degradation based on current meta-corruption level
		var corruption_raw = AutogrindSystem.meta_corruption_level
		var corruption_threshold = AutogrindSystem.corruption_threshold
		var corruption_norm = clamp(corruption_raw / max(corruption_threshold, 0.001), 0.0, 1.0)
		SoundManager.set_corruption_intensity(corruption_norm)


func _on_grind_complete(reason: String) -> void:
	"""Handle autogrind session completion"""
	_is_autogrinding = false
	current_state = LoopState.EXPLORATION
	InputLockManager.pop_all()  # Clear any leaked locks

	# Clean up controller
	if _autogrind_controller and is_instance_valid(_autogrind_controller):
		_autogrind_controller.queue_free()
		_autogrind_controller = null

	# Clean up dashboard
	if _autogrind_dashboard and is_instance_valid(_autogrind_dashboard):
		_autogrind_dashboard.queue_free()
		_autogrind_dashboard = null

	# Clean up compact overlay
	_destroy_autogrind_overlay()
	_destroy_controller_overlay()

	# Reset turbo mode
	BattleManager.turbo_mode = false

	# Reset engine speed
	Engine.time_scale = 1.0

	# Update UI
	if _autogrind_ui and is_instance_valid(_autogrind_ui):
		_autogrind_ui.set_grinding(false)
	else:
		# If UI is closed, return to exploration
		_return_to_exploration()

	print("[AUTOGRIND] Grind complete: %s" % reason)


func _on_autogrind_tier_changed(new_tier: int) -> void:
	if new_tier == 1:  # DASHBOARD
		SoundManager.play_ui("tier_zoom_out")
		_show_autogrind_dashboard()
		if _autogrind_overlay and is_instance_valid(_autogrind_overlay):
			_autogrind_overlay.visible = false
	else:  # ACCELERATED
		SoundManager.play_ui("tier_zoom_in")
		_hide_autogrind_dashboard()
		if _autogrind_overlay and is_instance_valid(_autogrind_overlay):
			_autogrind_overlay.visible = true

	if _autogrind_ui and is_instance_valid(_autogrind_ui):
		_autogrind_ui.on_tier_changed(new_tier)


func _create_autogrind_overlay() -> void:
	if _autogrind_overlay and is_instance_valid(_autogrind_overlay):
		return

	_autogrind_overlay_layer = CanvasLayer.new()
	_autogrind_overlay_layer.layer = 40
	add_child(_autogrind_overlay_layer)

	_autogrind_overlay = Control.new()
	_autogrind_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_autogrind_overlay_layer.add_child(_autogrind_overlay)

	var vp_size = get_viewport().get_visible_rect().size
	if vp_size.x == 0 or vp_size.y == 0:
		vp_size = Vector2(1280, 720)

	var bar_height = 120.0
	var bar_bg = ColorRect.new()
	bar_bg.color = Color(0.03, 0.02, 0.06, 0.85)
	bar_bg.position = Vector2(0, vp_size.y - bar_height)
	bar_bg.size = Vector2(vp_size.x, bar_height)
	_autogrind_overlay.add_child(bar_bg)

	var border = ColorRect.new()
	border.color = Color(0.5, 0.4, 0.6, 0.8)
	border.position = Vector2(0, vp_size.y - bar_height)
	border.size = Vector2(vp_size.x, 2)
	_autogrind_overlay.add_child(border)

	# Summary line — big and readable
	var summary = Label.new()
	summary.name = "SummaryLabel"
	summary.text = "Battle #1 | EXP: 0 | Streak: 0 | Efficiency: 1.0x"
	summary.position = Vector2(16, vp_size.y - bar_height + 8)
	summary.size = Vector2(vp_size.x - 32, 28)
	summary.add_theme_font_size_override("font_size", 18)
	summary.add_theme_color_override("font_color", Color(1.0, 1.0, 0.4))
	_autogrind_overlay.add_child(summary)

	# Stats strip — full width, taller
	var strip = AutogrindStatsStrip.new()
	strip.name = "StatsStrip"
	strip.position = Vector2(4, vp_size.y - bar_height + 38)
	strip.size = Vector2(vp_size.x - 8, 42)
	_autogrind_overlay.add_child(strip)

	# Control hints — clearer
	var hints = Label.new()
	hints.name = "HintsLabel"
	hints.text = "Y: Turbo    +/-: Speed    T: Dashboard    B: Exit"
	hints.position = Vector2(16, vp_size.y - bar_height + 88)
	hints.size = Vector2(vp_size.x - 32, 24)
	hints.add_theme_font_size_override("font_size", 13)
	hints.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_autogrind_overlay.add_child(hints)


func _update_autogrind_overlay(stats: Dictionary) -> void:
	if not _autogrind_overlay or not is_instance_valid(_autogrind_overlay):
		return

	var summary = _autogrind_overlay.get_node_or_null("SummaryLabel")
	if summary:
		var battles = stats.get("battles_won", 0)
		var exp = stats.get("total_exp", 0)
		var wins = stats.get("consecutive_wins", 0)
		var eff = stats.get("efficiency", 1.0)
		var turbo_txt = " TURBO" if BattleManager.turbo_mode else ""
		summary.text = "Battle #%d | EXP: %d | Streak: %d | Efficiency: %.1fx%s" % [battles, exp, wins, eff, turbo_txt]

	var strip = _autogrind_overlay.get_node_or_null("StatsStrip")
	if strip and strip.has_method("refresh"):
		var region_id = _current_map_id.replace(" ", "_").to_lower()
		strip.refresh(stats, region_id)


func _destroy_autogrind_overlay() -> void:
	if _autogrind_overlay and is_instance_valid(_autogrind_overlay):
		_autogrind_overlay.queue_free()
		_autogrind_overlay = null
	if _autogrind_overlay_layer and is_instance_valid(_autogrind_overlay_layer):
		_autogrind_overlay_layer.queue_free()
		_autogrind_overlay_layer = null


func _show_controller_overlay(context: Dictionary) -> void:
	if has_node("/root/GameState"):
		if not GameState.show_controller_overlay:
			return

	if not _controller_overlay:
		_controller_overlay_layer = CanvasLayer.new()
		_controller_overlay_layer.layer = 55  # Above battle scenes and menus
		add_child(_controller_overlay_layer)

		_controller_overlay = ControllerOverlay.new()
		var vp_size = get_viewport().get_visible_rect().size
		if vp_size.x == 0 or vp_size.y == 0:
			vp_size = Vector2(1280, 720)
		_controller_overlay.position = Vector2(vp_size.x - 330, vp_size.y - 200)
		_controller_overlay.size = ControllerOverlay.OVERLAY_SIZE
		_controller_overlay_layer.add_child(_controller_overlay)

	_controller_overlay.set_context(context)
	_controller_overlay.visible = true


func _hide_controller_overlay() -> void:
	if _controller_overlay and is_instance_valid(_controller_overlay):
		_controller_overlay.visible = false


func _destroy_controller_overlay() -> void:
	if _controller_overlay and is_instance_valid(_controller_overlay):
		_controller_overlay.queue_free()
		_controller_overlay = null
	if _controller_overlay_layer and is_instance_valid(_controller_overlay_layer):
		_controller_overlay_layer.queue_free()
		_controller_overlay_layer = null


func _show_autogrind_dashboard() -> void:
	if _autogrind_dashboard and is_instance_valid(_autogrind_dashboard):
		_autogrind_dashboard.visible = true
		return

	var DashboardClass = load("res://src/ui/autogrind/AutogrindDashboard.gd")
	_autogrind_dashboard = DashboardClass.new()
	_autogrind_dashboard.set_anchors_preset(Control.PRESET_FULL_RECT)

	if _autogrind_ui_layer and is_instance_valid(_autogrind_ui_layer):
		_autogrind_ui_layer.add_child(_autogrind_dashboard)
	else:
		add_child(_autogrind_dashboard)

	_autogrind_dashboard.pause_requested.connect(func(): _stop_autogrind("Paused"))
	_autogrind_dashboard.exit_requested.connect(func(): _stop_autogrind("Manual stop"))
	_autogrind_dashboard.tier_cycle_requested.connect(func():
		if _autogrind_controller and is_instance_valid(_autogrind_controller):
			_autogrind_controller.cycle_tier()
	)

	print("[AUTOGRIND] Dashboard shown (Tier 2)")


func _hide_autogrind_dashboard() -> void:
	if _autogrind_dashboard and is_instance_valid(_autogrind_dashboard):
		_autogrind_dashboard.queue_free()
		_autogrind_dashboard = null
	print("[AUTOGRIND] Dashboard hidden (back to Tier 1)")


func _on_ui_tier_cycle_requested() -> void:
	if _autogrind_controller and is_instance_valid(_autogrind_controller):
		_autogrind_controller.cycle_tier()


func _autogrind_heal_member(member: Combatant) -> void:
	var heal_items = [["hi_potion", 200], ["potion", 50]]
	for item_pair in heal_items:
		var item_id = item_pair[0]
		var heal_amount = item_pair[1]
		if member.get_item_count(item_id) > 0:
			member.remove_item(item_id, 1)
			member.heal(heal_amount)
			print("[AUTOGRIND] %s used %s (healed %d HP)" % [member.combatant_name, item_id, heal_amount])
			return


func _autogrind_restore_mp(member: Combatant) -> void:
	var mp_items = [["hi_ether", 100], ["ether", 30]]
	for item_pair in mp_items:
		var item_id = item_pair[0]
		var restore = item_pair[1]
		if member.get_item_count(item_id) > 0:
			member.remove_item(item_id, 1)
			member.restore_mp(restore)
			print("[AUTOGRIND] %s used %s (restored %d MP)" % [member.combatant_name, item_id, restore])
			return


func _exit_tree() -> void:
	"""Disconnect signals on cleanup to prevent dangling connections"""
	if _exploration_scene and is_instance_valid(_exploration_scene):
		if _exploration_scene.has_signal("battle_triggered") and _exploration_scene.is_connected("battle_triggered", _on_exploration_battle_triggered):
			_exploration_scene.disconnect("battle_triggered", _on_exploration_battle_triggered)
		if _exploration_scene.has_signal("area_transition") and _exploration_scene.is_connected("area_transition", _on_area_transition):
			_exploration_scene.disconnect("area_transition", _on_area_transition)
		_exploration_scene.queue_free()
		_exploration_scene = null

	if _title_screen and is_instance_valid(_title_screen):
		if _title_screen.is_connected("new_game_selected", _on_title_new_game):
			_title_screen.disconnect("new_game_selected", _on_title_new_game)
		if _title_screen.is_connected("continue_selected", _on_title_continue):
			_title_screen.disconnect("continue_selected", _on_title_continue)
		if _title_screen.is_connected("settings_selected", _on_title_settings):
			_title_screen.disconnect("settings_selected", _on_title_settings)
