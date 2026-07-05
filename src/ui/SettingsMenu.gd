extends Control
class_name SettingsMenu

## Settings Menu - Game settings including encounter rate selector

signal closed()
signal settings_changed(setting: String, value: Variant)
signal quit_to_title()
signal start_boss_battle(boss_id: String)
signal teleport_requested(map_id: String, spawn_point: String)

## Encounter rate presets (default 100%)
const ENCOUNTER_PRESETS = [0.0, 0.25, 0.50, 0.75, 1.0, 1.5, 2.0]
const ENCOUNTER_LABELS = ["0", "25", "50", "75", "100", "150", "200"]  # % shown in title

## Volume presets (0-100%)
const VOLUME_PRESETS = [0, 25, 50, 75, 100]
const VOLUME_LABELS = ["0", "25", "50", "75", "100"]

## Battle speed presets
const BATTLE_SPEED_PRESETS = [0.25, 0.5, 1.0, 2.0, 4.0]
# labels MUST match the in-battle scale (BattleScene.BATTLE_SPEED_LABELS head) — the old raw-engine labels made Settings "1x" mean twice the battle's "1x"
const BATTLE_SPEED_LABELS = ["0.5x", "1x", "2x", "4x", "8x"]

## Text speed presets
const TEXT_SPEED_PRESETS = ["slow", "normal", "fast", "instant"]
const TEXT_SPEED_LABELS = ["Slow", "Normal", "Fast", "Instant"]

## Tick 222: text size scale presets — accessibility. Consumers multiply base font sizes by the float.
const TEXT_SIZE_PRESETS: Array = [0.8, 1.0, 1.25, 1.5, 2.0]
const TEXT_SIZE_LABELS: Array = ["80%", "100%", "125%", "150%", "200%"]

## Current settings
var encounter_rate: float = 1.0  # Default 100%
var encounter_preset_index: int = 4  # Index into ENCOUNTER_PRESETS (100%)
var debug_log_enabled: bool = true  # Default on
var show_controller_overlay: bool = true  # Default on
var music_volume: int = 100  # 0-100
var music_volume_index: int = 4
var sfx_volume: int = 100  # 0-100
var sfx_volume_index: int = 4
var battle_speed: float = 1.0
var battle_speed_index: int = 2
var text_speed: String = "normal"
var text_speed_index: int = 1
# Tick 222: text size scale (accessibility). Defaults to 100% (index 1).
var text_size_scale: float = 1.0
var text_size_index: int = 1
# Tick 226: color-blind friendly palette for damage popups.
var color_blind_mode: bool = false
var reduce_flashes: bool = false
var screen_shake_enabled: bool = true
var dash_always_on: bool = false  # Item 9: dash without holding the button
var llm_enabled: bool = not OS.has_feature("web")  # Wave C: dynamic dialogue toggle (off by default on web)
var boss_llm_strategy_enabled: bool = false  # Phase 1 boss-AI strategic-intent toggle (opt-in)
var party_llm_dialogue_enabled: bool = false  # Party LLM combat-line toggle (opt-in)
var llm_custom_backend_enabled: bool = false  # tick 40: BYOK master switch (opt-in; web build hides entirely)
var llm_rebalance_enabled: bool = false  # tick 42: LLM-guided rebalance daemon (opt-in)
var debug_all_pcs_unlocked: bool = false  # Bypass spotlight gates; only visible when debug_log_enabled
var dev_full_kits: bool = false  # Item 18: grant all level-gated abilities to the party (testing)


## Persist + apply the dev kit grant/strip to the live party.
func _apply_dev_full_kits() -> void:
	if GameState and "game_constants" in GameState:
		GameState.game_constants["dev_full_kits"] = dev_full_kits
	var game_loop = get_tree().root.get_node_or_null("GameLoop")
	if game_loop and "party" in game_loop and JobSystem and JobSystem.has_method("set_dev_full_kits"):
		JobSystem.set_dev_full_kits(dev_full_kits, game_loop.party)

## UI State
var selected_index: int = 0
var _settings_items: Array = []
## ScrollContainer holding the setting rows; navigation auto-scrolls it so the
## selected row stays visible (mirrors TeleportMenu.gd scroll-follow). Without
## this, the bottom action rows are unreachable and the cursor goes off-screen.
var _scroll: ScrollContainer = null
var _controls_submenu_open: bool = false
var _jukebox_submenu_open: bool = false
var _boss_submenu_open: bool = false
var _teleport_submenu_open: bool = false
var _rebalance_review_open: bool = false  ## tick 49
var _byok_config_open: bool = false  ## tick 50
var _rebalance_history_open: bool = false  ## tick 54
## When true, hides the "Quit to Title" action (we're already on the title screen)
var from_title: bool = false

## Style
const BG_COLOR = Color(0.05, 0.05, 0.1, 0.95)
const PANEL_COLOR = Color(0.1, 0.1, 0.15)
const BORDER_LIGHT = RetroPanel.BORDER_LIGHT
const BORDER_SHADOW = RetroPanel.BORDER_SHADOW
const SELECTED_COLOR = Color(0.2, 0.3, 0.5)
const TEXT_COLOR = Color(1.0, 1.0, 1.0)
const DISABLED_COLOR = Color(0.4, 0.4, 0.4)
const OPTION_BG = Color(0.15, 0.15, 0.2)
const OPTION_SELECTED = Color(0.3, 0.5, 0.8)

## Preloaded for the battle-speed write path. Promoted from the runtime
## load("res://src/battle/BattleScene.gd") in _save_battle_speed (matches
## the SaveSystem.BATTLE_SCENE_SCRIPT pattern). Preload errors at compile
## time instead of silently at runtime, so a transient load failure
## mid-session can no longer drop the battle_speed_index write into the
## `if BattleSceneScript:` defensive else branch.
const BATTLE_SCENE_SCRIPT := preload("res://src/battle/BattleScene.gd")


func _ready() -> void:
	# Load current settings from GameState
	if GameState:
		if "encounter_rate_multiplier" in GameState:
			encounter_rate = GameState.encounter_rate_multiplier
			encounter_preset_index = _find_closest_preset(encounter_rate)
		if "debug_log_enabled" in GameState:
			debug_log_enabled = GameState.debug_log_enabled
		if "show_controller_overlay" in GameState:
			show_controller_overlay = GameState.show_controller_overlay
		if "music_volume" in GameState:
			music_volume = GameState.music_volume
			music_volume_index = _find_volume_preset(music_volume)
		if "sfx_volume" in GameState:
			sfx_volume = GameState.sfx_volume
			sfx_volume_index = _find_volume_preset(sfx_volume)
		if "default_battle_speed" in GameState:
			battle_speed = GameState.default_battle_speed
			battle_speed_index = _find_battle_speed_preset(battle_speed)
		if "text_speed" in GameState:
			text_speed = GameState.text_speed
			text_speed_index = TEXT_SPEED_PRESETS.find(text_speed)
			if text_speed_index < 0:
				text_speed_index = 1
		# Tick 222: text size scale (accessibility).
		if "text_size_scale" in GameState:
			text_size_scale = float(GameState.text_size_scale)
			text_size_index = TEXT_SIZE_PRESETS.find(text_size_scale)
			if text_size_index < 0:
				text_size_index = 1
		# Tick 226: color-blind friendly damage colors (accessibility).
		if "color_blind_mode" in GameState:
			color_blind_mode = bool(GameState.color_blind_mode)
		if "reduce_flashes" in GameState:
			reduce_flashes = bool(GameState.reduce_flashes)
		if "screen_shake_enabled" in GameState:
			screen_shake_enabled = GameState.screen_shake_enabled
		if "dash_always_on" in GameState:
			dash_always_on = GameState.dash_always_on
		if "llm_enabled" in GameState:
			llm_enabled = GameState.llm_enabled
		if "boss_llm_strategy_enabled" in GameState:
			boss_llm_strategy_enabled = GameState.boss_llm_strategy_enabled
		if "party_llm_dialogue_enabled" in GameState:
			party_llm_dialogue_enabled = GameState.party_llm_dialogue_enabled
		if "llm_custom_backend_enabled" in GameState:
			llm_custom_backend_enabled = GameState.llm_custom_backend_enabled
		if "llm_rebalance_enabled" in GameState:
			llm_rebalance_enabled = GameState.llm_rebalance_enabled
		if "debug_all_pcs_unlocked" in GameState:
			debug_all_pcs_unlocked = GameState.debug_all_pcs_unlocked
		if "game_constants" in GameState:
			dev_full_kits = bool(GameState.game_constants.get("dev_full_kits", false))
	_build_ui()
	_play_open_animation()


func _find_closest_preset(value: float) -> int:
	"""Find the closest preset index to the given value"""
	var best_index = 4  # Default to 100%
	var best_diff = 999.0
	for i in range(ENCOUNTER_PRESETS.size()):
		var diff = abs(ENCOUNTER_PRESETS[i] - value)
		if diff < best_diff:
			best_diff = diff
			best_index = i
	return best_index


func _find_volume_preset(value: int) -> int:
	"""Find the closest volume preset index"""
	var best_index = 4  # Default to 100
	var best_diff = 999
	for i in range(VOLUME_PRESETS.size()):
		var diff = abs(VOLUME_PRESETS[i] - value)
		if diff < best_diff:
			best_diff = diff
			best_index = i
	return best_index


func _find_battle_speed_preset(value: float) -> int:
	"""Find the closest battle speed preset index"""
	var best_index = 2  # Default to 1x
	var best_diff = 999.0
	for i in range(BATTLE_SPEED_PRESETS.size()):
		var diff = abs(BATTLE_SPEED_PRESETS[i] - value)
		if diff < best_diff:
			best_diff = diff
			best_index = i
	return best_index


func _build_ui() -> void:
	"""Build the settings UI.

	Layout overview (overflow-safe):
	  panel
	  ├── panel_bg       (ColorRect, full-rect)
	  ├── border         (RetroPanel beveled edge)
	  ├── title          (Label, pinned at y=8, outside scroll)
	  ├── scroll         (ScrollContainer, fills panel between title and footer)
	  │   └── vbox       (VBoxContainer — all rows grow downward freely)
	  │       ├── encounter_item
	  │       ├── debug_item
	  │       ├── … (all setting rows)
	  │       └── actions_box (VBoxContainer for action buttons)
	  └── footer         (Label, pinned at bottom, outside scroll)

	The ScrollContainer clips and scrolls only the inner VBox, so no
	matter how many debug action buttons are added the panel never overflows.
	"""
	for child in get_children():
		child.queue_free()
	_settings_items.clear()

	# Full screen background
	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Main panel — fixed frame; content scrolls inside it.
	var panel = Control.new()
	panel.position = Vector2(size.x * 0.2, size.y * 0.04)
	panel.size = Vector2(size.x * 0.6, size.y * 0.92)
	add_child(panel)

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)

	# Beveled retro border
	RetroPanel.add_border(panel, panel.size, BORDER_LIGHT, BORDER_SHADOW)

	# Title — pinned above the scroll area
	const TITLE_H: int = 40
	# FOOTER_H enlarged from 36 → 52 so "Quit to Title" / "Return to title
	# screen" action button has full breathing room above the footer label
	# and no longer clips at the bottom of the scroll region.
	const FOOTER_H: int = 52
	var title = Label.new()
	title.text = "SETTINGS"
	title.position = Vector2(16, 8)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)

	# ── ScrollContainer ──────────────────────────────────────────────────
	# Occupies the space between title and footer; vertical scroll only.
	# Cached on _scroll so _update_selection can auto-scroll to the selected row.
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(0, TITLE_H)
	scroll.size = Vector2(panel.size.x, panel.size.y - TITLE_H - FOOTER_H)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(scroll)
	_scroll = scroll

	# Inner VBoxContainer — rows stack top-to-bottom, no manual y positions.
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 0)
	scroll.add_child(vbox)

	# ── Setting rows — added in display order to vbox ────────────────────

	# Encounter Rate setting
	var encounter_item = _create_option_setting(
		"Encounter Rate (%)",
		"Controls random battle frequency",
		ENCOUNTER_LABELS,
		encounter_preset_index,
		0
	)
	vbox.add_child(encounter_item)
	_settings_items.append({"control": encounter_item, "type": "option", "id": "encounter_rate"})
	MenuMouseHelper.make_clickable(encounter_item, 0, 400, 80,
		_on_setting_click.bind(0), _on_setting_hover.bind(0))

	# Debug Log toggle
	var debug_item = _create_toggle_setting(
		"Debug Log",
		"Show debug messages on screen",
		debug_log_enabled,
		1
	)
	vbox.add_child(debug_item)
	_settings_items.append({"control": debug_item, "type": "toggle", "id": "debug_log"})
	MenuMouseHelper.make_clickable(debug_item, 1, 400, 60,
		_on_setting_click.bind(1), _on_setting_hover.bind(1))

	# Controller Overlay toggle
	var overlay_item = _create_toggle_setting(
		"Controller Overlay",
		"Show button hints during autogrind/battle",
		show_controller_overlay,
		2
	)
	vbox.add_child(overlay_item)
	_settings_items.append({"control": overlay_item, "type": "toggle", "id": "controller_overlay"})
	MenuMouseHelper.make_clickable(overlay_item, 2, 400, 60,
		_on_setting_click.bind(2), _on_setting_hover.bind(2))

	# Music Volume
	var music_item = _create_volume_setting(
		"Music Volume",
		"Background music volume",
		VOLUME_LABELS,
		music_volume_index,
		3
	)
	vbox.add_child(music_item)
	_settings_items.append({"control": music_item, "type": "volume", "id": "music_volume"})
	MenuMouseHelper.make_clickable(music_item, 3, 400, 60,
		_on_setting_click.bind(3), _on_setting_hover.bind(3))

	# SFX Volume
	var sfx_item = _create_volume_setting(
		"SFX Volume",
		"Sound effects volume",
		VOLUME_LABELS,
		sfx_volume_index,
		4
	)
	vbox.add_child(sfx_item)
	_settings_items.append({"control": sfx_item, "type": "volume", "id": "sfx_volume"})
	MenuMouseHelper.make_clickable(sfx_item, 4, 400, 60,
		_on_setting_click.bind(4), _on_setting_hover.bind(4))

	# Battle Speed Default
	var speed_item = _create_option_setting_small(
		"Battle Speed Default",
		"Default battle animation speed",
		BATTLE_SPEED_LABELS,
		battle_speed_index,
		5
	)
	vbox.add_child(speed_item)
	_settings_items.append({"control": speed_item, "type": "battle_speed", "id": "battle_speed"})
	MenuMouseHelper.make_clickable(speed_item, 5, 400, 60,
		_on_setting_click.bind(5), _on_setting_hover.bind(5))

	# Text Speed
	var text_item = _create_option_setting_small(
		"Text Speed",
		"Dialogue text display speed",
		TEXT_SPEED_LABELS,
		text_speed_index,
		6
	)
	vbox.add_child(text_item)
	_settings_items.append({"control": text_item, "type": "text_speed", "id": "text_speed"})
	MenuMouseHelper.make_clickable(text_item, 6, 400, 60,
		_on_setting_click.bind(6), _on_setting_hover.bind(6))

	# Screen Shake toggle
	var shake_item = _create_toggle_setting(
		"Screen Shake",
		"Enable camera shake on hits and effects",
		screen_shake_enabled,
		7
	)
	vbox.add_child(shake_item)
	_settings_items.append({"control": shake_item, "type": "toggle", "id": "screen_shake"})
	MenuMouseHelper.make_clickable(shake_item, 7, 400, 60,
		_on_setting_click.bind(7), _on_setting_hover.bind(7))

	# Item 9: dash always-on (testing/accessibility) — hold-to-dash works regardless.
	var dash_idx: int = _settings_items.size()
	var dash_item = _create_toggle_setting(
		"Dash: Always On",
		"Move at dash speed without holding the dash button (Shift / X)",
		dash_always_on,
		dash_idx
	)
	vbox.add_child(dash_item)
	_settings_items.append({"control": dash_item, "type": "toggle", "id": "dash_always_on"})
	MenuMouseHelper.make_clickable(dash_item, dash_idx, 400, 60,
		_on_setting_click.bind(dash_idx), _on_setting_hover.bind(dash_idx))

	# Tick 222: text size scale (accessibility). Append with dynamic idx so the LLM section below stays a clean append. Consumers (CutsceneDialogue etc.) multiply base font sizes by GameState.text_size_scale.
	var text_size_idx: int = _settings_items.size()
	var text_size_item = _create_option_setting_small(
		"Text Size",
		"Scale dialogue text size (accessibility)",
		TEXT_SIZE_LABELS,
		text_size_index,
		text_size_idx
	)
	vbox.add_child(text_size_item)
	_settings_items.append({"control": text_size_item, "type": "text_size", "id": "text_size"})
	MenuMouseHelper.make_clickable(text_size_item, text_size_idx, 400, 60,
		_on_setting_click.bind(text_size_idx), _on_setting_hover.bind(text_size_idx))

	# Tick 226: color-blind friendly palette toggle (accessibility). Swaps damage popup colors to deuteranopia-safe alternatives (cyan heal, yellow crit).
	var cb_idx: int = _settings_items.size()
	var cb_item = _create_toggle_setting(
		"Color-blind Friendly",
		"Cyan/yellow damage popups (vs green/orange)",
		color_blind_mode,
		cb_idx
	)
	vbox.add_child(cb_item)
	_settings_items.append({"control": cb_item, "type": "toggle", "id": "color_blind_mode"})
	MenuMouseHelper.make_clickable(cb_item, cb_idx, 400, 60,
		_on_setting_click.bind(cb_idx), _on_setting_hover.bind(cb_idx))

	# Reduce screen flashes (accessibility / photosensitivity). Suppresses the
	# battle-layer full-screen flashes: crits, group-attack combos, the corruption
	# visual_glitch stutter, level-up. Default off (flashes on).
	var flash_idx: int = _settings_items.size()
	var flash_item = _create_toggle_setting(
		"Reduce Flashes",
		"Suppress full-screen flash effects in battle",
		reduce_flashes,
		flash_idx
	)
	vbox.add_child(flash_item)
	_settings_items.append({"control": flash_item, "type": "toggle", "id": "reduce_flashes"})
	MenuMouseHelper.make_clickable(flash_item, flash_idx, 400, 60,
		_on_setting_click.bind(flash_idx), _on_setting_hover.bind(flash_idx))

	# Wave C: Dynamic Dialogue (experimental) — gates the LLMService master
	# enable flag. Default ON on desktop, OFF on web (no HTTP backend reachable
	# inside the WASM sandbox). Even when ON, the HTTPBackend probe must
	# succeed before any actual LLM call goes out — so toggling this with no
	# server reachable is harmless (every dialogue silently falls back).
	var llm_idx: int = _settings_items.size()
	var llm_item = _create_toggle_setting(
		"Dynamic Dialogue (experimental)",
		"Let an LLM steer NPC conversation lines",
		llm_enabled,
		llm_idx
	)
	vbox.add_child(llm_item)
	_settings_items.append({"control": llm_item, "type": "toggle", "id": "llm_enabled"})
	MenuMouseHelper.make_clickable(llm_item, llm_idx, 400, 60,
		_on_setting_click.bind(llm_idx), _on_setting_hover.bind(llm_idx))

	# Phase 1: LLM-strategic-boss toggle. Defaults OFF — opt-in for first
	# plays so vanilla Mordaine stays deterministic. When ON AND
	# Dynamic Dialogue is also on AND a backend is reachable, the boss's
	# strategic posture per phase is LLM-picked (intent only — abilities
	# still come from the existing weighted ladders).
	var boss_llm_idx: int = _settings_items.size()
	var boss_llm_item = _create_toggle_setting(
		"LLM Boss Strategy (experimental)",
		"W1 bosses pick phase posture via LLM (needs Dynamic Dialogue ON)",
		boss_llm_strategy_enabled,
		boss_llm_idx
	)
	vbox.add_child(boss_llm_item)
	_settings_items.append({"control": boss_llm_item, "type": "toggle", "id": "boss_llm_strategy_enabled"})
	MenuMouseHelper.make_clickable(boss_llm_item, boss_llm_idx, 400, 60,
		_on_setting_click.bind(boss_llm_idx), _on_setting_hover.bind(boss_llm_idx))

	var party_llm_idx: int = _settings_items.size()
	var party_llm_item = _create_toggle_setting(
		"LLM Party Dialogue (experimental)",
		"Party speaks in-character battle lines via LLM (needs Dynamic Dialogue ON)",
		party_llm_dialogue_enabled,
		party_llm_idx
	)
	vbox.add_child(party_llm_item)
	_settings_items.append({"control": party_llm_item, "type": "toggle", "id": "party_llm_dialogue_enabled"})
	MenuMouseHelper.make_clickable(party_llm_item, party_llm_idx, 400, 60,
		_on_setting_click.bind(party_llm_idx), _on_setting_hover.bind(party_llm_idx))

	# tick 40: BYOK toggle — hidden entirely on web build (browser
	# sandbox can't safely hold the key). Subtitle directs power users
	# to settings.json until the field-input UI lands in a follow-up.
	if not OS.has_feature("web"):
		var byok_idx: int = _settings_items.size()
		var byok_item = _create_toggle_setting(
			"Custom LLM Backend / BYOK (experimental)",
			"Use a custom HTTPBackend (OpenAI / Ollama). Set URL + model + key in settings.json for now.",
			llm_custom_backend_enabled,
			byok_idx
		)
		vbox.add_child(byok_item)
		_settings_items.append({"control": byok_item, "type": "toggle", "id": "llm_custom_backend_enabled"})
		MenuMouseHelper.make_clickable(byok_item, byok_idx, 400, 60,
			_on_setting_click.bind(byok_idx), _on_setting_hover.bind(byok_idx))

	# tick 42: Rebalance Daemon master switch. Per user directive
	# 2026-06-22 — the game self-tunes difficulty using LLM guidance.
	# Off by default; the daemon proposes small game_constants nudges
	# on party-wipe / boss-defeat triggers. UI for reviewing pending
	# proposals lands later — for now this just gates the trigger calls.
	var reb_idx: int = _settings_items.size()
	var reb_item = _create_toggle_setting(
		"LLM Auto-Rebalance (experimental)",
		"Game proposes difficulty nudges after wipes / boss wins (needs Dynamic Dialogue ON)",
		llm_rebalance_enabled,
		reb_idx
	)
	vbox.add_child(reb_item)
	_settings_items.append({"control": reb_item, "type": "toggle", "id": "llm_rebalance_enabled"})
	MenuMouseHelper.make_clickable(reb_item, reb_idx, 400, 60,
		_on_setting_click.bind(reb_idx), _on_setting_hover.bind(reb_idx))

	# Debug: Unlock All Party toggle — bypasses every PC's autobattle_locked
	# spotlight gate. Honored at BattleManager / BattleCommandMenu / UI gates,
	# not by mutating Combatant state, so flips here take effect immediately.
	# Always visible (was gated behind debug_log_enabled but users couldn't
	# find it; user feedback 2026-06-04 "couldn't find settings/debug menu
	# where to unlock entire party"). The Jukebox / Fight Boss / Debug Teleport
	# actions below remain debug-gated.
	var debug_unlock_idx: int = _settings_items.size()
	var debug_unlock_item = _create_toggle_setting(
		"Debug: Unlock All Party",
		"Bypass spotlight gates — every PC is player-controlled",
		debug_all_pcs_unlocked,
		debug_unlock_idx
	)
	vbox.add_child(debug_unlock_item)
	_settings_items.append({"control": debug_unlock_item, "type": "toggle", "id": "debug_all_pcs_unlocked"})
	MenuMouseHelper.make_clickable(debug_unlock_item, debug_unlock_idx, 400, 60,
		_on_setting_click.bind(debug_unlock_idx), _on_setting_hover.bind(debug_unlock_idx))

	# Queue #4 (2026-07-03): per-PC Party Trust rows. Answers "how do I
	# untrust a PC without debug mode?" — settings-side surface for the
	# player_trust field split from autobattle_locked. Rows always shown
	# so untrust doesn't require reaching for the debug flag. When the
	# party is empty (main-menu / no save loaded) the section skips.
	_build_party_trust_rows(vbox)

	# Item 18 (user ask): "we can toggle that in settings though as
	# 'developer mode' for me to test things easier." ON grants every
	# level-gated ability to the party; OFF strips only above-level
	# unlocks (earned spells stay). Persists via game_constants.
	var dev_kits_idx: int = _settings_items.size()
	var dev_kits_item = _create_toggle_setting(
		"Dev: Full Job Kits",
		"Grant all level-gated abilities to the party for testing",
		dev_full_kits,
		dev_kits_idx
	)
	vbox.add_child(dev_kits_item)
	_settings_items.append({"control": dev_kits_item, "type": "toggle", "id": "dev_full_kits"})
	MenuMouseHelper.make_clickable(dev_kits_item, dev_kits_idx, 400, 60,
		_on_setting_click.bind(dev_kits_idx), _on_setting_hover.bind(dev_kits_idx))

	# ── Action buttons ───────────────────────────────────────────────────
	# Stacked in their own VBoxContainer inside the scroll area so any
	# future debug actions automatically extend the scrollable content
	# without needing panel-height or y-offset tuning.
	var actions_box = VBoxContainer.new()
	actions_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_box.add_theme_constant_override("separation", 0)
	vbox.add_child(actions_box)

	# Helper local lambda — append one action button into the VBox and
	# wire mouse on the index it gets in _settings_items.
	var add_action := func(label: String, desc: String, id: String, primary: bool = false) -> void:
		var idx = _settings_items.size()
		var item = (_create_action_button(label, desc, idx)
			if primary else _create_action_button_neutral(label, desc, idx))
		item.custom_minimum_size = Vector2(400, 56)  # Action row with breathing room
		actions_box.add_child(item)
		_settings_items.append({"control": item, "type": "action", "id": id})
		MenuMouseHelper.make_clickable(item, idx, 400, 56,
			_on_setting_click.bind(idx), _on_setting_hover.bind(idx))

	# Controls (always shown)
	# Tick 234: dynamic subtitle shows current ui_accept / ui_cancel / ui_menu key binds at a glance — players don't have to open the submenu just to remember which key opens the menu.
	add_action.call("Controls", _get_controls_subtitle(), "controls")
	# tick 49: Review Pending Rebalances — shown only when there's
	# something waiting. Subtitle includes the live count so the
	# player can see at a glance how many proposals need attention.
	var rebalance_count: int = _get_rebalance_needs_review_count()
	if rebalance_count > 0:
		add_action.call(
			"Review Rebalance Proposals",
			"%d proposal(s) waiting for your review" % rebalance_count,
			"rebalance_review")
	# tick 50: Configure BYOK — always available on desktop, hidden
	# on web (browser sandbox can't safely hold keys).
	if not OS.has_feature("web"):
		add_action.call(
			"Configure BYOK",
			"URL + model + API key for a custom LLM backend",
			"byok_config")
	# tick 54: Rebalance History — shown only when there's something
	# in the applied[] log. Read-only diegetic surface.
	var history_count: int = _get_rebalance_applied_count()
	if history_count > 0:
		add_action.call(
			"Rebalance History",
			"View what the daemon has done (%d entries)" % history_count,
			"rebalance_history")
	# Debug-only batch
	if debug_log_enabled:
		# Tick 235: live subtitles. Jukebox shows the currently-playing track; Debug Teleport shows the current map. Both surface useful at-a-glance state without entering the submenu.
		add_action.call("Jukebox", _get_jukebox_subtitle(), "jukebox")
		add_action.call("Fight Boss", "[DEBUG] Battle a Masterite boss", "fight_boss")
		if not from_title:
			# Title-screen has no map context, teleport would be a no-op there.
			add_action.call("Debug Teleport", _get_debug_teleport_subtitle(), "debug_teleport")
	# Quit to Title (hidden when opened from title screen)
	if not from_title:
		add_action.call("Quit to Title", "Return to the title screen", "quit_to_title", true)

	# Right-click cancel
	MenuMouseHelper.add_right_click_cancel(bg, _close_settings)

	# Footer — pinned at the very bottom of the panel, outside the scroll area
	# so it is always visible regardless of scroll position.
	var footer = Label.new()
	footer.text = "←→: Adjust  A/Click: Select  B/RClick: Back"
	footer.position = Vector2(16, panel.size.y - FOOTER_H + 18)
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(footer)

	_update_selection()


func _create_option_setting(label_text: String, description: String, options: Array, current_index: int, index: int) -> Control:
	"""Create an option selector setting control"""
	var container = Control.new()
	container.custom_minimum_size = Vector2(400, 80)

	# Selection highlight
	var highlight = ColorRect.new()
	highlight.color = SELECTED_COLOR if index == selected_index else Color.TRANSPARENT
	highlight.size = Vector2(400, 80)
	highlight.name = "Highlight"
	container.add_child(highlight)

	# Label
	var label = Label.new()
	label.text = label_text
	label.position = Vector2(8, 4)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	container.add_child(label)

	# Description
	var desc = Label.new()
	desc.text = description
	desc.position = Vector2(8, 22)
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", DISABLED_COLOR)
	container.add_child(desc)

	# Options row
	var options_container = HBoxContainer.new()
	options_container.position = Vector2(8, 44)
	options_container.name = "OptionsContainer"
	container.add_child(options_container)

	for i in range(options.size()):
		var option_bg = ColorRect.new()
		option_bg.custom_minimum_size = Vector2(40, 24)  # Smaller boxes to fit all 7
		option_bg.color = OPTION_SELECTED if i == current_index else OPTION_BG
		option_bg.name = "OptionBG_%d" % i
		options_container.add_child(option_bg)

		var option_label = Label.new()
		option_label.text = options[i]
		option_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		option_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		option_label.size = Vector2(40, 24)
		option_label.position = Vector2(0, 0)
		option_label.add_theme_font_size_override("font_size", 10)  # Smaller font
		option_label.add_theme_color_override("font_color", Color.YELLOW if i == current_index else TEXT_COLOR)
		option_label.name = "OptionLabel_%d" % i
		option_bg.add_child(option_label)

		# Add spacing between options
		if i < options.size() - 1:
			var spacer = Control.new()
			spacer.custom_minimum_size = Vector2(2, 1)  # Less spacing
			options_container.add_child(spacer)

	return container


func _create_volume_setting(label_text: String, description: String, options: Array, current_index: int, index: int) -> Control:
	"""Create a volume slider setting control"""
	var container = Control.new()
	container.custom_minimum_size = Vector2(400, 60)

	# Selection highlight
	var highlight = ColorRect.new()
	highlight.color = SELECTED_COLOR if index == selected_index else Color.TRANSPARENT
	highlight.size = Vector2(400, 60)
	highlight.name = "Highlight"
	container.add_child(highlight)

	# Label
	var label = Label.new()
	label.text = label_text
	label.position = Vector2(8, 4)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	container.add_child(label)

	# Description
	var desc = Label.new()
	desc.text = description
	desc.position = Vector2(8, 22)
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", DISABLED_COLOR)
	container.add_child(desc)

	# Options row
	var options_container = HBoxContainer.new()
	options_container.position = Vector2(8, 38)
	options_container.name = "OptionsContainer"
	container.add_child(options_container)

	for i in range(options.size()):
		var option_bg = ColorRect.new()
		option_bg.custom_minimum_size = Vector2(50, 20)
		option_bg.color = OPTION_SELECTED if i == current_index else OPTION_BG
		option_bg.name = "OptionBG_%d" % i
		options_container.add_child(option_bg)

		var option_label = Label.new()
		option_label.text = options[i] + "%"
		option_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		option_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		option_label.size = Vector2(50, 20)
		option_label.add_theme_font_size_override("font_size", 10)
		option_label.add_theme_color_override("font_color", Color.YELLOW if i == current_index else TEXT_COLOR)
		option_label.name = "OptionLabel_%d" % i
		option_bg.add_child(option_label)

		if i < options.size() - 1:
			var spacer = Control.new()
			spacer.custom_minimum_size = Vector2(2, 1)
			options_container.add_child(spacer)

	return container


func _create_option_setting_small(label_text: String, description: String, options: Array, current_index: int, index: int) -> Control:
	"""Create a smaller option selector setting control"""
	var container = Control.new()
	container.custom_minimum_size = Vector2(400, 60)

	# Selection highlight
	var highlight = ColorRect.new()
	highlight.color = SELECTED_COLOR if index == selected_index else Color.TRANSPARENT
	highlight.size = Vector2(400, 60)
	highlight.name = "Highlight"
	container.add_child(highlight)

	# Label
	var label = Label.new()
	label.text = label_text
	label.position = Vector2(8, 4)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	container.add_child(label)

	# Description
	var desc = Label.new()
	desc.text = description
	desc.position = Vector2(8, 22)
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", DISABLED_COLOR)
	container.add_child(desc)

	# Options row
	var options_container = HBoxContainer.new()
	options_container.position = Vector2(8, 38)
	options_container.name = "OptionsContainer"
	container.add_child(options_container)

	for i in range(options.size()):
		var option_bg = ColorRect.new()
		option_bg.custom_minimum_size = Vector2(60, 20)
		option_bg.color = OPTION_SELECTED if i == current_index else OPTION_BG
		option_bg.name = "OptionBG_%d" % i
		options_container.add_child(option_bg)

		var option_label = Label.new()
		option_label.text = options[i]
		option_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		option_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		option_label.size = Vector2(60, 20)
		option_label.add_theme_font_size_override("font_size", 10)
		option_label.add_theme_color_override("font_color", Color.YELLOW if i == current_index else TEXT_COLOR)
		option_label.name = "OptionLabel_%d" % i
		option_bg.add_child(option_label)

		if i < options.size() - 1:
			var spacer = Control.new()
			spacer.custom_minimum_size = Vector2(2, 1)
			options_container.add_child(spacer)

	return container


func _create_toggle_setting(label_text: String, description: String, is_on: bool, index: int) -> Control:
	"""Create a toggle (on/off) setting control"""
	var container = Control.new()
	container.custom_minimum_size = Vector2(400, 60)

	# Selection highlight
	var highlight = ColorRect.new()
	highlight.color = SELECTED_COLOR if index == selected_index else Color.TRANSPARENT
	highlight.size = Vector2(400, 60)
	highlight.name = "Highlight"
	container.add_child(highlight)

	# Label
	var label = Label.new()
	label.text = label_text
	label.position = Vector2(8, 4)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	container.add_child(label)

	# Description
	var desc = Label.new()
	desc.text = description
	desc.position = Vector2(8, 22)
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", DISABLED_COLOR)
	container.add_child(desc)

	# Toggle display
	var toggle_container = HBoxContainer.new()
	toggle_container.position = Vector2(8, 40)
	toggle_container.name = "ToggleContainer"
	container.add_child(toggle_container)

	# OFF option
	var off_bg = ColorRect.new()
	off_bg.custom_minimum_size = Vector2(50, 20)
	off_bg.color = OPTION_BG if is_on else OPTION_SELECTED
	off_bg.name = "OffBG"
	toggle_container.add_child(off_bg)

	var off_label = Label.new()
	off_label.text = "OFF"
	off_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	off_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	off_label.size = Vector2(50, 20)
	off_label.add_theme_font_size_override("font_size", 11)
	off_label.add_theme_color_override("font_color", TEXT_COLOR if is_on else Color.YELLOW)
	off_label.name = "OffLabel"
	off_bg.add_child(off_label)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(4, 1)
	toggle_container.add_child(spacer)

	# ON option
	var on_bg = ColorRect.new()
	on_bg.custom_minimum_size = Vector2(50, 20)
	on_bg.color = OPTION_SELECTED if is_on else OPTION_BG
	on_bg.name = "OnBG"
	toggle_container.add_child(on_bg)

	var on_label = Label.new()
	on_label.text = "ON"
	on_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	on_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	on_label.size = Vector2(50, 20)
	on_label.add_theme_font_size_override("font_size", 11)
	on_label.add_theme_color_override("font_color", Color.YELLOW if is_on else TEXT_COLOR)
	on_label.name = "OnLabel"
	on_bg.add_child(on_label)

	return container


func _create_action_button_neutral(label_text: String, description: String, index: int) -> Control:
	"""Create a neutral action button (non-destructive, like Controls)"""
	var container = Control.new()
	container.custom_minimum_size = Vector2(400, 56)

	var highlight = ColorRect.new()
	highlight.color = SELECTED_COLOR if index == selected_index else Color.TRANSPARENT
	highlight.size = Vector2(400, 56)
	highlight.name = "Highlight"
	container.add_child(highlight)

	var label = Label.new()
	label.text = label_text
	label.position = Vector2(8, 4)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	container.add_child(label)

	var desc = Label.new()
	desc.text = description
	desc.position = Vector2(8, 22)
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", DISABLED_COLOR)
	container.add_child(desc)

	var hint = Label.new()
	hint.text = "[Press A]"
	hint.position = Vector2(310, 16)
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color.YELLOW)
	hint.name = "ActionHint"
	container.add_child(hint)

	return container


func _create_action_button(label_text: String, description: String, index: int) -> Control:
	"""Create an action button setting (press A to activate)"""
	var container = Control.new()
	container.custom_minimum_size = Vector2(400, 56)

	# Selection highlight
	var highlight = ColorRect.new()
	highlight.color = SELECTED_COLOR if index == selected_index else Color.TRANSPARENT
	highlight.size = Vector2(400, 56)
	highlight.name = "Highlight"
	container.add_child(highlight)

	# Label
	var label = Label.new()
	label.text = label_text
	label.position = Vector2(8, 4)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))  # Reddish for quit action
	container.add_child(label)

	# Description
	var desc = Label.new()
	desc.text = description
	desc.position = Vector2(8, 22)
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", DISABLED_COLOR)
	container.add_child(desc)

	# Action hint — right-aligned with the title row, no vertical overlap
	var hint = Label.new()
	hint.text = "[Press A]"
	hint.position = Vector2(310, 16)
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color.YELLOW)
	hint.name = "ActionHint"
	container.add_child(hint)

	return container


func _update_toggle_display(index: int, is_on: bool) -> void:
	"""Update toggle visual"""
	if index >= _settings_items.size():
		return
	var item = _settings_items[index]
	var control = item["control"]

	var off_bg = control.get_node_or_null("ToggleContainer/OffBG")
	var on_bg = control.get_node_or_null("ToggleContainer/OnBG")
	var off_label = control.get_node_or_null("ToggleContainer/OffBG/OffLabel")
	var on_label = control.get_node_or_null("ToggleContainer/OnBG/OnLabel")

	if off_bg:
		off_bg.color = OPTION_BG if is_on else OPTION_SELECTED
	if on_bg:
		on_bg.color = OPTION_SELECTED if is_on else OPTION_BG
	if off_label:
		off_label.add_theme_color_override("font_color", TEXT_COLOR if is_on else Color.YELLOW)
	if on_label:
		on_label.add_theme_color_override("font_color", Color.YELLOW if is_on else TEXT_COLOR)


func _update_selection() -> void:
	"""Update visual selection state and keep the selected row scrolled into view.

	The ScrollContainer clips content but does NOT follow keyboard/gamepad
	selection on its own — so without the scroll-follow below the bottom rows
	(Debug Unlock / Controls / Jukebox / Fight Boss / Debug Teleport / Quit)
	scroll out of view and the cursor disappears. We mirror TeleportMenu's
	scroll-follow, using ensure_control_visible() since the VBox rows have
	variable heights (no fixed ROW_HEIGHT to do scroll math against)."""
	var selected_control: Control = null
	for i in range(_settings_items.size()):
		var item = _settings_items[i]
		var control: Control = item["control"]
		var highlight = control.get_node_or_null("Highlight")
		if highlight:
			highlight.color = SELECTED_COLOR if i == selected_index else Color.TRANSPARENT
		if i == selected_index:
			selected_control = control
	# Auto-scroll so the selected row stays inside the viewport.
	if _scroll and is_instance_valid(_scroll) and selected_control:
		_scroll.ensure_control_visible(selected_control)


func _update_option_display(index: int, option_index: int) -> void:
	"""Update option selector visual"""
	if index >= _settings_items.size():
		return
	var item = _settings_items[index]
	var control = item["control"]

	var options_container = control.get_node_or_null("OptionsContainer")
	if not options_container:
		return

	# Update all option backgrounds and labels
	for i in range(ENCOUNTER_PRESETS.size()):
		var bg = control.get_node_or_null("OptionsContainer/OptionBG_%d" % i)
		if bg:
			bg.color = OPTION_SELECTED if i == option_index else OPTION_BG
			var label = bg.get_node_or_null("OptionLabel_%d" % i)
			if label:
				label.add_theme_color_override("font_color", Color.YELLOW if i == option_index else TEXT_COLOR)


func _input(event: InputEvent) -> void:
	"""Handle settings input"""
	if not visible:
		return
	var confirm_dialog = get_node_or_null("QuitConfirmDialog")
	if confirm_dialog and confirm_dialog.has_meta("_input_func"):
		confirm_dialog.get_meta("_input_func").call(event)
		return
	if _controls_submenu_open or _jukebox_submenu_open or _boss_submenu_open or _teleport_submenu_open or _rebalance_review_open or _byok_config_open or _rebalance_history_open:
		# Failsafe: if any submenu flag is set but NO actual submenu child
		# exists in the tree, the flag is stale (script load failed, signal
		# never fired, dialog freed by a different path). Reset all flags
		# and continue processing input — otherwise ui_cancel gets swallowed
		# forever and the player is stuck (playtest bug 2026-06-30).
		if not _has_live_submenu_child():
			_reset_submenu_flags()
		else:
			return

	# Navigation - check echo to prevent rapid-fire when holding keys
	if event.is_action_pressed("ui_up") and not event.is_echo():
		selected_index = max(0, selected_index - 1)
		_update_selection()
		if SoundManager:
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down") and not event.is_echo():
		selected_index = min(_settings_items.size() - 1, selected_index + 1)
		_update_selection()
		if SoundManager:
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	# Adjust value - allow echo for left/right to make adjusting sliders easier
	elif event.is_action_pressed("ui_left"):
		_adjust_setting(-1)
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_right"):
		_adjust_setting(1)
		get_viewport().set_input_as_handled()

	# Confirm/Activate
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_activate_setting()
		get_viewport().set_input_as_handled()

	# Close
	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		_close_settings()
		get_viewport().set_input_as_handled()


func _adjust_setting(delta: int) -> void:
	"""Adjust the currently selected setting"""
	if selected_index >= _settings_items.size():
		return

	var item = _settings_items[selected_index]
	if item["id"] == "encounter_rate":
		encounter_preset_index = clampi(encounter_preset_index + delta, 0, ENCOUNTER_PRESETS.size() - 1)
		encounter_rate = ENCOUNTER_PRESETS[encounter_preset_index]
		_update_option_display(selected_index, encounter_preset_index)
		_save_encounter_rate()
		if SoundManager:
			SoundManager.play_ui("menu_move")
	elif item["id"] == "debug_log":
		debug_log_enabled = not debug_log_enabled
		_update_toggle_display(selected_index, debug_log_enabled)
		_save_debug_log_setting()
		if SoundManager:
			SoundManager.play_ui("menu_move")
	elif item["id"] == "controller_overlay":
		show_controller_overlay = not show_controller_overlay
		_update_toggle_display(selected_index, show_controller_overlay)
		_save_controller_overlay_setting()
		if SoundManager:
			SoundManager.play_ui("menu_move")
	elif item["id"] == "screen_shake":
		screen_shake_enabled = not screen_shake_enabled
		_update_toggle_display(selected_index, screen_shake_enabled)
		_save_screen_shake_setting()
		if SoundManager:
			SoundManager.play_ui("menu_move")
	elif item["id"] == "dash_always_on":
		dash_always_on = not dash_always_on
		_update_toggle_display(selected_index, dash_always_on)
		_save_dash_always_on_setting()
		if SoundManager:
			SoundManager.play_ui("menu_move")
	elif item["id"] == "color_blind_mode":
		# Tick 226: accessibility palette toggle.
		color_blind_mode = not color_blind_mode
		_update_toggle_display(selected_index, color_blind_mode)
		_save_color_blind_mode_setting()
		if SoundManager:
			SoundManager.play_ui("menu_move")
	elif item["id"] == "reduce_flashes":
		reduce_flashes = not reduce_flashes
		_update_toggle_display(selected_index, reduce_flashes)
		_save_reduce_flashes_setting()
		if SoundManager:
			SoundManager.play_ui("menu_move")
	elif item["id"] == "llm_enabled":
		llm_enabled = not llm_enabled
		_update_toggle_display(selected_index, llm_enabled)
		_save_llm_enabled_setting()
		if SoundManager:
			SoundManager.play_ui("menu_move")
	elif item["id"] == "boss_llm_strategy_enabled":
		boss_llm_strategy_enabled = not boss_llm_strategy_enabled
		_update_toggle_display(selected_index, boss_llm_strategy_enabled)
		_save_boss_llm_strategy_setting()
		if SoundManager:
			SoundManager.play_ui("menu_move")
	elif item["id"] == "party_llm_dialogue_enabled":
		party_llm_dialogue_enabled = not party_llm_dialogue_enabled
		_update_toggle_display(selected_index, party_llm_dialogue_enabled)
		_save_party_llm_dialogue_setting()
		if SoundManager:
			SoundManager.play_ui("menu_move")
	elif item["id"] == "llm_custom_backend_enabled":
		llm_custom_backend_enabled = not llm_custom_backend_enabled
		_update_toggle_display(selected_index, llm_custom_backend_enabled)
		_save_llm_custom_backend_setting()
		if SoundManager:
			SoundManager.play_ui("menu_move")
	elif item["id"] == "llm_rebalance_enabled":
		llm_rebalance_enabled = not llm_rebalance_enabled
		_update_toggle_display(selected_index, llm_rebalance_enabled)
		_save_llm_rebalance_setting()
		if SoundManager:
			SoundManager.play_ui("menu_move")
	elif item["id"] == "debug_all_pcs_unlocked":
		debug_all_pcs_unlocked = not debug_all_pcs_unlocked
		_update_toggle_display(selected_index, debug_all_pcs_unlocked)
		_save_debug_all_pcs_unlocked_setting()
		if SoundManager:
			SoundManager.play_ui("menu_move")
	elif item["id"] == "dev_full_kits":
		dev_full_kits = not dev_full_kits
		_update_toggle_display(selected_index, dev_full_kits)
		_apply_dev_full_kits()
		if SoundManager:
			SoundManager.play_ui("menu_move")
	elif str(item["id"]).begins_with("party_trust:"):
		_toggle_party_trust(str(item["id"]).substr("party_trust:".length()), selected_index)
	elif item["id"] == "music_volume":
		music_volume_index = clampi(music_volume_index + delta, 0, VOLUME_PRESETS.size() - 1)
		music_volume = VOLUME_PRESETS[music_volume_index]
		_update_volume_display(selected_index, music_volume_index)
		_save_music_volume()
		if SoundManager:
			SoundManager.play_ui("menu_move")
	elif item["id"] == "sfx_volume":
		sfx_volume_index = clampi(sfx_volume_index + delta, 0, VOLUME_PRESETS.size() - 1)
		sfx_volume = VOLUME_PRESETS[sfx_volume_index]
		_update_volume_display(selected_index, sfx_volume_index)
		_save_sfx_volume()
		if SoundManager:
			SoundManager.play_ui("menu_move")
	elif item["id"] == "battle_speed":
		battle_speed_index = clampi(battle_speed_index + delta, 0, BATTLE_SPEED_PRESETS.size() - 1)
		battle_speed = BATTLE_SPEED_PRESETS[battle_speed_index]
		_update_small_option_display(selected_index, battle_speed_index, BATTLE_SPEED_PRESETS.size())
		_save_battle_speed()
		if SoundManager:
			SoundManager.play_ui("menu_move")
	elif item["id"] == "text_speed":
		text_speed_index = clampi(text_speed_index + delta, 0, TEXT_SPEED_PRESETS.size() - 1)
		text_speed = TEXT_SPEED_PRESETS[text_speed_index]
		_update_small_option_display(selected_index, text_speed_index, TEXT_SPEED_PRESETS.size())
		_save_text_speed()
		if SoundManager:
			SoundManager.play_ui("menu_move")
	elif item["id"] == "text_size":
		# Tick 222: accessibility text scale.
		text_size_index = clampi(text_size_index + delta, 0, TEXT_SIZE_PRESETS.size() - 1)
		text_size_scale = TEXT_SIZE_PRESETS[text_size_index]
		_update_small_option_display(selected_index, text_size_index, TEXT_SIZE_PRESETS.size())
		_save_text_size_scale()
		if SoundManager:
			SoundManager.play_ui("menu_move")


func _persist_settings() -> void:
	"""Write all settings to user://settings.json via SaveSystem."""
	# Engine.has_singleton("SaveSystem") is ALWAYS FALSE for autoloads in Godot 4
	# — the autoload lives on the scene tree root.
	var ss: Node = get_node_or_null("/root/SaveSystem")
	if ss and ss.has_method("save_settings"):
		ss.save_settings()


func _save_encounter_rate() -> void:
	"""Save encounter rate to GameState"""
	if GameState:
		GameState.encounter_rate_multiplier = encounter_rate
	settings_changed.emit("encounter_rate", encounter_rate)
	DebugLogOverlay.log("[SETTINGS] Encounter rate set to %d%%" % int(encounter_rate * 100))
	_persist_settings()


func _save_debug_log_setting() -> void:
	"""Save debug log setting to GameState and update overlay"""
	if GameState:
		GameState.debug_log_enabled = debug_log_enabled
	# Update the overlay visibility
	if DebugLogOverlay:
		DebugLogOverlay.set_enabled(debug_log_enabled)
	settings_changed.emit("debug_log", debug_log_enabled)
	print("[SETTINGS] Debug log %s" % ("enabled" if debug_log_enabled else "disabled"))
	_persist_settings()


func _save_controller_overlay_setting() -> void:
	if GameState:
		GameState.show_controller_overlay = show_controller_overlay
	settings_changed.emit("controller_overlay", show_controller_overlay)
	print("[SETTINGS] Controller overlay %s" % ("enabled" if show_controller_overlay else "disabled"))
	_persist_settings()


func _save_screen_shake_setting() -> void:
	if GameState:
		GameState.screen_shake_enabled = screen_shake_enabled
	settings_changed.emit("screen_shake", screen_shake_enabled)
	print("[SETTINGS] Screen shake %s" % ("enabled" if screen_shake_enabled else "disabled"))
	_persist_settings()


## Item 9: flip the always-dash flag; OverworldPlayer reads it per-frame.
func _save_dash_always_on_setting() -> void:
	if GameState:
		GameState.dash_always_on = dash_always_on
	settings_changed.emit("dash_always_on", dash_always_on)
	print("[SETTINGS] Dash always-on %s" % ("enabled" if dash_always_on else "disabled"))
	_persist_settings()


## Wave C: flip the LLMService master enable flag and persist it on GameState.
## Engine.has_singleton(...) is ALWAYS FALSE for autoloads in Godot 4 — we look
## up /root/LLMService directly instead. When the autoload is missing (unit
## tests, fresh worktree pre-import) we still persist the choice so it sticks
## the next launch.
func _save_llm_enabled_setting() -> void:
	if GameState:
		GameState.llm_enabled = llm_enabled
	var svc: Node = get_node_or_null("/root/LLMService")
	if svc and "llm_enabled" in svc:
		svc.llm_enabled = llm_enabled
	settings_changed.emit("llm_enabled", llm_enabled)
	print("[SETTINGS] Dynamic dialogue %s" % ("enabled" if llm_enabled else "disabled"))
	_persist_settings()


## Flip the LLM-picks-boss-intent flag; gated also by llm_enabled at runtime.
func _save_boss_llm_strategy_setting() -> void:
	if GameState:
		GameState.boss_llm_strategy_enabled = boss_llm_strategy_enabled
	settings_changed.emit("boss_llm_strategy_enabled", boss_llm_strategy_enabled)
	print("[SETTINGS] LLM boss strategy %s" % ("enabled" if boss_llm_strategy_enabled else "disabled"))
	_persist_settings()


## Flip the party LLM-dialogue flag; gated also by llm_enabled at runtime.
func _save_party_llm_dialogue_setting() -> void:
	if GameState:
		GameState.party_llm_dialogue_enabled = party_llm_dialogue_enabled
	settings_changed.emit("party_llm_dialogue_enabled", party_llm_dialogue_enabled)
	print("[SETTINGS] LLM party dialogue %s" % ("enabled" if party_llm_dialogue_enabled else "disabled"))
	_persist_settings()


## tick 42: rebalance daemon master-switch save handler. Just mirrors
## the bit + persists; no immediate-apply call needed because the
## daemon's consider() is gated on the flag at the GameLoop call sites
## (every call checks GameState.llm_rebalance_enabled before firing).
func _save_llm_rebalance_setting() -> void:
	if GameState:
		GameState.llm_rebalance_enabled = llm_rebalance_enabled
	settings_changed.emit("llm_rebalance_enabled", llm_rebalance_enabled)
	print("[SETTINGS] LLM auto-rebalance %s" % ("enabled" if llm_rebalance_enabled else "disabled"))
	_persist_settings()


## tick 40: BYOK master-switch save handler. Mirrors the persisted bit
## to GameState, persists, then calls LLMService.apply_byok_config so
## the HTTPBackend swap takes effect immediately — without that call,
## the toggle's effect would wait until the next game restart. Logs
## with the masked-key value via GameState's helper so a settings dump
## doesn't leak the raw key.
func _save_llm_custom_backend_setting() -> void:
	if GameState:
		GameState.llm_custom_backend_enabled = llm_custom_backend_enabled
	settings_changed.emit("llm_custom_backend_enabled", llm_custom_backend_enabled)
	var svc: Node = get_node_or_null("/root/LLMService")
	if svc and svc.has_method("apply_byok_config"):
		svc.apply_byok_config()
	var masked_key := "<empty>"
	if GameState and GameState.has_method("get_llm_custom_api_key_masked"):
		var m: String = GameState.get_llm_custom_api_key_masked()
		masked_key = m if m != "" else "<empty>"
	print("[SETTINGS] BYOK %s (key=%s)" % [
		"enabled" if llm_custom_backend_enabled else "disabled",
		masked_key])
	_persist_settings()


func _save_debug_all_pcs_unlocked_setting() -> void:
	if GameState:
		GameState.debug_all_pcs_unlocked = debug_all_pcs_unlocked
	settings_changed.emit("debug_all_pcs_unlocked", debug_all_pcs_unlocked)
	print("[SETTINGS] Debug unlock all party %s" % ("enabled" if debug_all_pcs_unlocked else "disabled"))
	_persist_settings()


func _update_volume_display(index: int, option_index: int) -> void:
	"""Update volume selector visual"""
	if index >= _settings_items.size():
		return
	var item = _settings_items[index]
	var control = item["control"]

	for i in range(VOLUME_PRESETS.size()):
		var bg = control.get_node_or_null("OptionsContainer/OptionBG_%d" % i)
		if bg:
			bg.color = OPTION_SELECTED if i == option_index else OPTION_BG
			var label = bg.get_node_or_null("OptionLabel_%d" % i)
			if label:
				label.add_theme_color_override("font_color", Color.YELLOW if i == option_index else TEXT_COLOR)


func _update_small_option_display(index: int, option_index: int, count: int) -> void:
	"""Update small option selector visual"""
	if index >= _settings_items.size():
		return
	var item = _settings_items[index]
	var control = item["control"]

	for i in range(count):
		var bg = control.get_node_or_null("OptionsContainer/OptionBG_%d" % i)
		if bg:
			bg.color = OPTION_SELECTED if i == option_index else OPTION_BG
			var label = bg.get_node_or_null("OptionLabel_%d" % i)
			if label:
				label.add_theme_color_override("font_color", Color.YELLOW if i == option_index else TEXT_COLOR)


func _save_music_volume() -> void:
	"""Save music volume setting"""
	if GameState:
		GameState.music_volume = music_volume
	if SoundManager:
		SoundManager.set_music_volume(music_volume / 100.0)
	settings_changed.emit("music_volume", music_volume)
	print("[SETTINGS] Music volume set to %d%%" % music_volume)
	_persist_settings()


func _save_sfx_volume() -> void:
	"""Save SFX volume setting"""
	if GameState:
		GameState.sfx_volume = sfx_volume
	if SoundManager:
		SoundManager.set_sfx_volume(sfx_volume / 100.0)
	settings_changed.emit("sfx_volume", sfx_volume)
	print("[SETTINGS] SFX volume set to %d%%" % sfx_volume)
	_persist_settings()


func _save_battle_speed() -> void:
	"""Save battle speed default setting + push to BattleScene static."""
	if GameState:
		GameState.default_battle_speed = battle_speed
	# Use the preloaded class const (BATTLE_SCENE_SCRIPT) — preload errors
	# at compile time, so no defensive `if BattleSceneScript:` skip is
	# possible. Mirrors SaveSystem's BATTLE_SCENE_SCRIPT setup.
	BATTLE_SCENE_SCRIPT._battle_speed_index = battle_speed_index
	settings_changed.emit("battle_speed", battle_speed)
	print("[SETTINGS] Default battle speed set to %.2fx" % battle_speed)
	_persist_settings()


func _save_text_speed() -> void:
	"""Save text speed setting"""
	if GameState:
		GameState.text_speed = text_speed
	settings_changed.emit("text_speed", text_speed)
	print("[SETTINGS] Text speed set to %s" % text_speed)
	_persist_settings()


# Tick 222: text size scale (accessibility). Consumers read GameState.text_size_scale live.
func _save_text_size_scale() -> void:
	"""Save text size scale setting"""
	if GameState:
		GameState.text_size_scale = text_size_scale
	settings_changed.emit("text_size_scale", text_size_scale)
	print("[SETTINGS] Text size scale set to %s%%" % int(text_size_scale * 100))
	_persist_settings()


# Tick 234: build a live "A:Z  B:X  Menu:Esc" subtitle for the Controls action button. Falls back to the static text when InputProfileManager isn't reachable (test bootstrap, very early init).
func _get_controls_subtitle() -> String:
	var ipm: Node = get_node_or_null("/root/InputProfileManager")
	if not ipm or not ipm.has_method("get_action_key_label"):
		return "Remap gamepad buttons"
	var a: String = str(ipm.get_action_key_label("ui_accept"))
	var b: String = str(ipm.get_action_key_label("ui_cancel"))
	var m: String = str(ipm.get_action_key_label("ui_menu"))
	# Compact "A:Z  B:X  Menu:Esc" — preserves the cross-input intent of the original subtitle but surfaces the live binds.
	return "A:%s  B:%s  Menu:%s" % [a, b, m]


# Tick 235: live "Now: <track>" subtitle for the Jukebox debug button — players see which track is playing without entering the submenu.
func _get_jukebox_subtitle() -> String:
	var sm: Node = get_node_or_null("/root/SoundManager")
	if not sm or not ("_current_music" in sm):
		return "[DEBUG] Play any music track"
	var track: String = str(sm._current_music)
	if track == "":
		return "[DEBUG] Now: (silence)"
	return "[DEBUG] Now: %s" % track.replace("_", " ").capitalize()


# Tick 235: live "Current: <map>" subtitle for the Debug Teleport button — surfaces the active map id so warping is easier to reason about.
func _get_debug_teleport_subtitle() -> String:
	var gl: Node = get_node_or_null("/root/GameLoop")
	if not gl or not gl.has_method("get_current_map_id"):
		return "[DEBUG] Warp to any map"
	var map_id: String = str(gl.get_current_map_id())
	if map_id == "":
		return "[DEBUG] Warp to any map"
	return "[DEBUG] At: %s" % map_id.replace("_", " ").capitalize()


# Tick 226: color-blind friendly palette toggle. DamageNumber reads GameState.color_blind_mode live each spawn.
func _save_color_blind_mode_setting() -> void:
	"""Save color blind mode setting"""
	if GameState:
		GameState.color_blind_mode = color_blind_mode
	settings_changed.emit("color_blind_mode", color_blind_mode)
	print("[SETTINGS] Color-blind friendly mode: %s" % ("ON" if color_blind_mode else "OFF"))
	_persist_settings()


func _save_reduce_flashes_setting() -> void:
	"""Save reduce-flashes accessibility setting"""
	if GameState:
		GameState.reduce_flashes = reduce_flashes
	settings_changed.emit("reduce_flashes", reduce_flashes)
	print("[SETTINGS] Reduce flashes: %s" % ("ON" if reduce_flashes else "OFF"))
	_persist_settings()


func _activate_setting() -> void:
	"""Activate the currently selected setting (for action buttons)"""
	if selected_index >= _settings_items.size():
		return

	var item = _settings_items[selected_index]
	if item["type"] == "action":
		if item["id"] == "controls":
			_open_controls_menu()
		elif item["id"] == "jukebox":
			_open_jukebox_menu()
		elif item["id"] == "fight_boss":
			_open_boss_selector()
		elif item["id"] == "debug_teleport":
			_open_teleport_menu()
		elif item["id"] == "rebalance_review":
			_open_rebalance_review()
		elif item["id"] == "byok_config":
			_open_byok_config()
		elif item["id"] == "rebalance_history":
			_open_rebalance_history()
		elif item["id"] == "quit_to_title":
			if SoundManager:
				SoundManager.play_ui("menu_select")
			_show_quit_confirmation()
	elif item["type"] == "toggle":
		# A button also toggles for convenience
		_adjust_setting(1)


func _on_setting_click(index: int) -> void:
	"""Handle mouse click on a setting"""
	selected_index = index
	_update_selection()
	_activate_setting()


func _on_setting_hover(index: int) -> void:
	"""Handle mouse hover on a setting"""
	if index != selected_index:
		selected_index = index
		_update_selection()
		if SoundManager:
			SoundManager.play_ui("menu_move")


## tick 54: open the rebalance history panel. Read-only diegetic
## surface for the daemon's applied[] log — what the AI has been
## doing since the player started.
func _open_rebalance_history() -> void:
	_rebalance_history_open = true
	var PanelScript = load("res://src/ui/RebalanceHistoryPanel.gd")
	if not PanelScript:
		_rebalance_history_open = false
		return
	var panel = PanelScript.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.closed.connect(_on_rebalance_history_closed)
	add_child(panel)
	if SoundManager:
		SoundManager.play_ui("menu_select")


func _on_rebalance_history_closed() -> void:
	_rebalance_history_open = false


## Convenience: get the daemon's applied[] count. Returns 0 if the
## autoload or field is missing — defensive for boot-edge calls.
func _get_rebalance_applied_count() -> int:
	if not GameState:
		return 0
	if not ("rebalance_daemon" in GameState) or GameState.rebalance_daemon == null:
		return 0
	var d = GameState.rebalance_daemon
	if "applied" in d:
		return d.applied.size()
	return 0


## tick 50: open the BYOK config panel. Hidden on web build —
## SettingsMenu's action-row registration guards there too, but
## belt-and-suspenders here in case some other path calls this.
func _open_byok_config() -> void:
	if OS.has_feature("web"):
		return
	_byok_config_open = true
	var PanelScript = load("res://src/ui/BYOKConfigPanel.gd")
	if not PanelScript:
		_byok_config_open = false
		return
	var panel = PanelScript.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.closed.connect(_on_byok_config_closed)
	add_child(panel)
	if SoundManager:
		SoundManager.play_ui("menu_select")


func _on_byok_config_closed() -> void:
	_byok_config_open = false


## tick 49: open the rebalance review panel. Reads pending NEEDS_REVIEW
## proposals from the daemon and lets the player Apply or Dismiss.
func _open_rebalance_review() -> void:
	_rebalance_review_open = true
	var PanelScript = load("res://src/ui/RebalanceReviewPanel.gd")
	if not PanelScript:
		_rebalance_review_open = false
		return
	var panel = PanelScript.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.closed.connect(_on_rebalance_review_closed)
	add_child(panel)
	if SoundManager:
		SoundManager.play_ui("menu_select")


func _on_rebalance_review_closed() -> void:
	_rebalance_review_open = false
	# Refresh the action button's subtitle so the count reflects any
	# applies/dismisses the player did inside the panel.
	_build_ui()


## Convenience: get the daemon's pending-review count. Returns 0 if
## the autoload or field is missing — defensive for boot-edge calls.
func _get_rebalance_needs_review_count() -> int:
	if not GameState:
		return 0
	if not ("rebalance_daemon" in GameState) or GameState.rebalance_daemon == null:
		return 0
	var d = GameState.rebalance_daemon
	if d.has_method("needs_review_count"):
		return d.needs_review_count()
	return 0


func _open_controls_menu() -> void:
	"""Open the controls remapping submenu"""
	_controls_submenu_open = true
	var ControlsMenuScript = load("res://src/ui/ControlsMenu.gd")
	if not ControlsMenuScript:
		# Failed to load — don't leave the flag stuck true (would swallow
		# ui_cancel forever). Same defensive shape as _open_rebalance_history.
		_controls_submenu_open = false
		return
	var controls = ControlsMenuScript.new()
	controls.set_anchors_preset(Control.PRESET_FULL_RECT)
	controls.closed.connect(_on_controls_closed)
	add_child(controls)
	if SoundManager:
		SoundManager.play_ui("menu_select")


func _on_controls_closed() -> void:
	"""Controls menu closed"""
	_controls_submenu_open = false


func _open_jukebox_menu() -> void:
	"""Open the jukebox debug submenu"""
	_jukebox_submenu_open = true
	var JukeboxMenuScript = load("res://src/ui/JukeboxMenu.gd")
	if not JukeboxMenuScript:
		_jukebox_submenu_open = false
		return
	var jukebox = JukeboxMenuScript.new()
	jukebox.set_anchors_preset(Control.PRESET_FULL_RECT)
	jukebox.closed.connect(_on_jukebox_closed)
	add_child(jukebox)
	if SoundManager:
		SoundManager.play_ui("menu_select")


func _on_jukebox_closed() -> void:
	"""Jukebox menu closed"""
	_jukebox_submenu_open = false


func _open_boss_selector() -> void:
	"""Open the boss selector debug submenu"""
	_boss_submenu_open = true
	var BossSelectorScript = load("res://src/ui/BossSelectorMenu.gd")
	if not BossSelectorScript:
		_boss_submenu_open = false
		return
	var selector = BossSelectorScript.new()
	selector.set_anchors_preset(Control.PRESET_FULL_RECT)
	selector.boss_selected.connect(_on_boss_selected)
	selector.closed.connect(_on_boss_selector_closed)
	add_child(selector)
	if SoundManager:
		SoundManager.play_ui("menu_select")


func _on_boss_selector_closed() -> void:
	"""Boss selector menu closed without selection"""
	_boss_submenu_open = false


func _on_boss_selected(boss_id: String) -> void:
	"""Boss selected - close settings and start battle.
	Bug fix (2026-04-30): emit `closed` BEFORE `start_boss_battle`. The
	upstream listener (OverworldMenu._on_settings_boss_battle) calls
	queue_free on OverworldMenu in response. Emitting closed second meant
	OverworldMenu was already queued-for-free when SettingsMenu fired
	closed → _on_settings_closed ran on a dying node, triggering tweens
	and warnings on a freed instance."""
	_boss_submenu_open = false
	closed.emit()
	start_boss_battle.emit(boss_id)
	queue_free()


func _open_teleport_menu() -> void:
	"""Open the debug teleport submenu (debug-only)."""
	_teleport_submenu_open = true
	var TeleportMenuScript = load("res://src/ui/TeleportMenu.gd")
	if not TeleportMenuScript:
		_teleport_submenu_open = false
		return
	var tp = TeleportMenuScript.new()
	tp.set_anchors_preset(Control.PRESET_FULL_RECT)
	tp.teleport_requested.connect(_on_teleport_chosen)
	tp.closed.connect(_on_teleport_closed)
	add_child(tp)
	if SoundManager:
		SoundManager.play_ui("menu_select")


func _on_teleport_closed() -> void:
	"""Teleport submenu closed without choice — return to settings."""
	_teleport_submenu_open = false


func _on_teleport_chosen(map_id: String, spawn_point: String) -> void:
	"""Teleport destination chosen — close settings and forward signal.
	Same emit-order pattern as _on_boss_selected: close BEFORE re-emit so
	the listener queue_freeing settings doesn't race with the teleport
	transition starting on a half-freed node."""
	_teleport_submenu_open = false
	closed.emit()
	teleport_requested.emit(map_id, spawn_point)
	queue_free()


func _play_open_animation() -> void:
	"""Fade in the settings menu"""
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.15).set_ease(Tween.EASE_OUT)


func _close_settings() -> void:
	"""Close settings menu"""
	if SoundManager:
		SoundManager.play_ui("menu_close")
	closed.emit()
	queue_free()


## Return true if a real submenu child is currently in the tree. Used by the
## _input failsafe so a stale `*_open` flag can't block ui_cancel forever.
## Submenus attach as children of SettingsMenu itself (see _open_controls_menu
## + siblings — `add_child(<script>.new())`), so a live-child check reliably
## disambiguates "submenu genuinely modal" from "flag stuck true after a
## failed load or missed signal".
func _has_live_submenu_child() -> bool:
	for child in get_children():
		if not is_instance_valid(child):
			continue
		var script: Script = child.get_script() as Script
		if script == null:
			continue
		var path: String = str(script.resource_path)
		if path == "":
			continue
		# Match the submenu script paths that _open_* funcs instantiate. The
		# QuitConfirmDialog reuses _controls_submenu_open as its flag so we
		# check the node name too — it's a Control without a script but
		# with a distinctive name.
		if path.ends_with("ControlsMenu.gd") \
				or path.ends_with("JukeboxMenu.gd") \
				or path.ends_with("BossSelectorMenu.gd") \
				or path.ends_with("TeleportMenu.gd") \
				or path.ends_with("RebalanceHistoryPanel.gd") \
				or path.ends_with("BYOKConfigPanel.gd") \
				or path.ends_with("RebalanceReviewPanel.gd"):
			return true
	if get_node_or_null("QuitConfirmDialog") != null:
		return true
	return false


func _reset_submenu_flags() -> void:
	## Auto-recovery for stuck-flag states. Called by _input when the flag
	## set says "a submenu is open" but no submenu is actually alive in the
	## tree. Restores the ability to cancel out of the settings menu.
	push_warning("SettingsMenu: submenu flag(s) set but no live submenu found — resetting flags (playtest failsafe)")
	_controls_submenu_open = false
	_jukebox_submenu_open = false
	_boss_submenu_open = false
	_teleport_submenu_open = false
	_rebalance_review_open = false
	_byok_config_open = false
	_rebalance_history_open = false


func _show_quit_confirmation() -> void:
	"""Show a confirmation dialog before quitting to title"""
	_controls_submenu_open = true
	var confirm = Control.new()
	confirm.name = "QuitConfirmDialog"
	confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(confirm)

	var dim = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	confirm.add_child(dim)

	var dialog_w = 280
	var dialog_h = 120
	var vp = get_viewport().get_visible_rect().size
	var dialog = Control.new()
	dialog.size = Vector2(dialog_w, dialog_h)
	dialog.position = Vector2((vp.x - dialog_w) / 2.0, (vp.y - dialog_h) / 2.0)
	confirm.add_child(dialog)

	var dialog_bg = ColorRect.new()
	dialog_bg.color = PANEL_COLOR
	dialog_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(dialog_bg)
	RetroPanel.add_border(dialog, dialog.size, Color(1.0, 0.5, 0.5), Color(0.4, 0.1, 0.1))

	var msg = Label.new()
	msg.text = "Quit to Title Screen?"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.position = Vector2(0, 16)
	msg.size = Vector2(dialog_w, 20)
	msg.add_theme_font_size_override("font_size", 14)
	msg.add_theme_color_override("font_color", TEXT_COLOR)
	dialog.add_child(msg)

	var sub = Label.new()
	sub.text = "Unsaved progress will be lost."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(0, 36)
	sub.size = Vector2(dialog_w, 16)
	sub.add_theme_font_size_override("font_size", 10)
	sub.add_theme_color_override("font_color", DISABLED_COLOR)
	dialog.add_child(sub)

	var yes_btn = _create_confirm_button("Yes, Quit", Color(1.0, 0.5, 0.5))
	yes_btn.position = Vector2(32, 72)
	yes_btn.size = Vector2(96, 28)
	dialog.add_child(yes_btn)

	var no_btn = _create_confirm_button("No, Stay", Color(0.6, 0.85, 1.0))
	no_btn.position = Vector2(152, 72)
	no_btn.size = Vector2(96, 28)
	dialog.add_child(no_btn)

	var confirm_selected: int = 1

	var yes_hl = yes_btn.get_node_or_null("Highlight")
	var no_hl = no_btn.get_node_or_null("Highlight")
	if no_hl:
		no_hl.visible = true
	if yes_hl:
		yes_hl.visible = false

	var close_dialog = func():
		_controls_submenu_open = false
		confirm.queue_free()

	var do_quit = func():
		if SoundManager:
			SoundManager.play_ui("menu_select")
		quit_to_title.emit()
		queue_free()

	MenuMouseHelper.make_clickable(yes_btn, 0, 96, 28,
		func(_i): do_quit.call(), func(_i): pass)
	MenuMouseHelper.make_clickable(no_btn, 1, 96, 28,
		func(_i): close_dialog.call(), func(_i): pass)

	confirm.set_meta("confirm_selected", confirm_selected)
	confirm.set_meta("do_quit", do_quit)
	confirm.set_meta("close_dialog", close_dialog)
	confirm.set_meta("yes_hl", yes_hl)
	confirm.set_meta("no_hl", no_hl)

	confirm.set_process_input(true)

	var slide_from = dialog.position + Vector2(0, 20)
	dialog.position = slide_from
	dialog.modulate.a = 0.0
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(dialog, "position", dialog.position - Vector2(0, 20), 0.15).set_ease(Tween.EASE_OUT)
	tween.tween_property(dialog, "modulate:a", 1.0, 0.12)

	confirm.set_script(null)
	confirm.tree_exiting.connect(func(): _controls_submenu_open = false)

	confirm.set_meta("_input_func", func(event: InputEvent):
		if not confirm.is_inside_tree():
			return
		var sel: int = confirm.get_meta("confirm_selected", 1)
		var dq = confirm.get_meta("do_quit")
		var cd = confirm.get_meta("close_dialog")
		var yh = confirm.get_meta("yes_hl")
		var nh = confirm.get_meta("no_hl")
		var changed = false
		# Bug fix (2026-04-30): echo guards on the Quit confirmation. Holding
		# Left/Right toggled selection per echo; holding Enter could call
		# do_quit/close repeatedly, double-emitting quit_to_title and
		# double-queue_free'ing the confirm dialog.
		if (event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")) and not event.is_echo():
			sel = 1 - sel
			changed = true
		elif event.is_action_pressed("ui_accept") and not event.is_echo():
			if sel == 0:
				dq.call()
			else:
				cd.call()
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("ui_cancel") and not event.is_echo():
			cd.call()
			get_viewport().set_input_as_handled()
			return
		if changed:
			confirm.set_meta("confirm_selected", sel)
			if yh:
				yh.visible = (sel == 0)
			if nh:
				nh.visible = (sel == 1)
			if SoundManager:
				SoundManager.play_ui("menu_move")
			get_viewport().set_input_as_handled()
	)


func _create_confirm_button(label_text: String, text_color: Color) -> Control:
	"""Create a styled button for the confirmation dialog"""
	var btn = Control.new()
	btn.size = Vector2(96, 28)

	var hl = ColorRect.new()
	hl.name = "Highlight"
	hl.color = SELECTED_COLOR
	hl.set_anchors_preset(Control.PRESET_FULL_RECT)
	hl.visible = false
	btn.add_child(hl)

	var lbl = Label.new()
	lbl.text = label_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(0, 6)
	lbl.size = Vector2(96, 20)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", text_color)
	btn.add_child(lbl)

	return btn


## Queue #4: per-PC Party Trust rows. Reads from GameLoop.party (live)
## when available, falls back to GameState.player_party (dict mirror) so
## the section still renders from a save-loaded menu-only state.
func _build_party_trust_rows(vbox: Container) -> void:
	var party: Array = _get_party_snapshot()
	if party.is_empty():
		return
	for entry in party:
		var pc_id: String = str(entry.get("id", entry.get("combatant_name", "")))
		if pc_id == "":
			continue
		var display: String = str(entry.get("name", entry.get("combatant_name", pc_id)))
		var trusted: bool = bool(entry.get("player_trust", false))
		var idx: int = _settings_items.size()
		var item = _create_toggle_setting(
			"%s: Trust" % display,
			"Player-delegates %s's turn to their autoscript (untrust here without debug mode)" % display,
			trusted, idx)
		vbox.add_child(item)
		_settings_items.append({"control": item, "type": "toggle", "id": "party_trust:%s" % pc_id})
		MenuMouseHelper.make_clickable(item, idx, 400, 60,
			_on_setting_click.bind(idx), _on_setting_hover.bind(idx))


func _get_party_snapshot() -> Array:
	# One shape for the row-builder + toggle handler: id + name + player_trust.
	var out: Array = []
	var game_loop = get_tree().root.get_node_or_null("GameLoop") if is_inside_tree() else null
	if game_loop and "party" in game_loop and game_loop.party is Array and not game_loop.party.is_empty():
		for member in game_loop.party:
			if member == null or not "player_trust" in member:
				continue
			out.append({
				"id": str(member.combatant_name).to_lower().replace(" ", "_"),
				"name": str(member.combatant_name),
				"player_trust": bool(member.player_trust),
			})
		return out
	if GameState and not GameState.player_party.is_empty():
		for entry in GameState.player_party:
			if not (entry is Dictionary):
				continue
			out.append({
				"id": str(entry.get("combatant_name", "")).to_lower().replace(" ", "_"),
				"name": str(entry.get("combatant_name", "")),
				"player_trust": bool(entry.get("player_trust", false)),
			})
	return out


func _toggle_party_trust(pc_id: String, selected_index: int) -> void:
	var flipped_to: bool = false
	var game_loop = get_tree().root.get_node_or_null("GameLoop") if is_inside_tree() else null
	if game_loop and "party" in game_loop and game_loop.party is Array:
		for member in game_loop.party:
			if member == null or not "player_trust" in member:
				continue
			var member_id: String = str(member.combatant_name).to_lower().replace(" ", "_")
			if member_id == pc_id:
				member.player_trust = not member.player_trust
				flipped_to = member.player_trust
				break
	if GameState and not GameState.player_party.is_empty():
		for entry in GameState.player_party:
			if not (entry is Dictionary):
				continue
			var entry_id: String = str(entry.get("combatant_name", "")).to_lower().replace(" ", "_")
			if entry_id == pc_id:
				entry["player_trust"] = flipped_to if game_loop else not bool(entry.get("player_trust", false))
				flipped_to = bool(entry["player_trust"])
				break
	_update_toggle_display(selected_index, flipped_to)
	if SoundManager:
		SoundManager.play_ui("menu_move")
