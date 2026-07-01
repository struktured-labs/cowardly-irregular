extends RefCounted
class_name BattleUIManager

## BattleUIManager - Handles battle UI status display (party/enemy status boxes, action buttons, log)
## Extracted from BattleScene to reduce god class complexity

const CharacterPortraitClass = preload("res://src/ui/CharacterPortrait.gd")

var _scene  # Reference to parent BattleScene (untyped to avoid circular dependency)

## Dynamic party status UI elements
var _party_status_boxes: Array = []

## Dynamic enemy status UI elements
var _enemy_status_boxes: Array = []

## Track which enemies have been "scanned" to reveal HP/MP
var _revealed_enemies: Dictionary = {}


var _panels_themed: bool = false  # one-shot guard for transparency theming
var _auto_toggle_button: Button = null  # Clickable global autobattle toggle (mouse path)


func _init(scene) -> void:
	_scene = scene


func update_ui() -> void:
	"""Update all UI elements"""
	if not _panels_themed:
		_apply_panel_transparency()
		_panels_themed = true
	if not _auto_toggle_button:
		_create_auto_toggle_button()
	update_character_status()
	update_enemy_status()
	update_action_buttons()
	_update_auto_toggle_button()
	_scene._update_danger_music()


func _apply_panel_transparency() -> void:
	"""Apply semi-transparent backgrounds to EnemyStatusPanel + PartyStatusPanel.
	Without this the opaque default PanelContainer styling overlapped enemy
	sprites awkwardly (panels live in the same screen zone as the BattleField
	enemy markers, which can't easily move without rebalancing combat
	choreography). Transparency lets the sprite show through.
	(User feedback 2026-05-02: 'monster stat screen overlays awkwardly on
	the monster sprites'.)"""
	for panel_path in ["UI/EnemyStatusPanel", "UI/PartyStatusPanel"]:
		var panel = _scene.get_node_or_null(panel_path)
		if not panel:
			continue
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.04, 0.10, 0.72)  # deep purple, ~72% alpha
		sb.border_color = Color(0.4, 0.35, 0.6, 0.5)
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.corner_radius_top_left = 4
		sb.corner_radius_top_right = 4
		sb.corner_radius_bottom_left = 4
		sb.corner_radius_bottom_right = 4
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		panel.add_theme_stylebox_override("panel", sb)


func _create_auto_toggle_button() -> void:
	"""Mouse-clickable global autobattle toggle. Pure mouse-path access
	to the same sticky toggle Minus/F6 trigger from the keyboard/gamepad.
	Positioned at top-center of the viewport so it's always visible
	regardless of which battle UI panels are showing. Click to toggle."""
	var ui = _scene.get_node_or_null("UI")
	if not ui:
		return
	_auto_toggle_button = Button.new()
	_auto_toggle_button.name = "AutoToggleButton"
	_auto_toggle_button.text = "AUTO: …"  # Filled in by _update_auto_toggle_button
	_auto_toggle_button.flat = false
	_auto_toggle_button.focus_mode = Control.FOCUS_NONE  # Don't steal kb focus
	_auto_toggle_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	# Sit above the PartyStatusPanel (which starts at y=40, offset_left=-200).
	# Slightly bigger now (was 100×24) for discoverability — wide enough
	# for "AUTO: OFF" without text clipping at 14pt.
	_auto_toggle_button.offset_left = -340
	_auto_toggle_button.offset_top = 6
	_auto_toggle_button.offset_right = -210
	_auto_toggle_button.offset_bottom = 36
	_auto_toggle_button.add_theme_font_size_override("font_size", 14)
	# Themed background so it doesn't fade into the battlefield. Two
	# styleboxes — one for normal/hover, one for pressed.
	var sb_normal := StyleBoxFlat.new()
	sb_normal.bg_color = Color(0.10, 0.10, 0.18, 0.85)
	sb_normal.border_color = Color(0.5, 0.55, 0.75, 0.9)
	sb_normal.border_width_left = 1
	sb_normal.border_width_top = 1
	sb_normal.border_width_right = 1
	sb_normal.border_width_bottom = 1
	sb_normal.corner_radius_top_left = 4
	sb_normal.corner_radius_top_right = 4
	sb_normal.corner_radius_bottom_left = 4
	sb_normal.corner_radius_bottom_right = 4
	var sb_hover := sb_normal.duplicate()
	sb_hover.bg_color = Color(0.18, 0.22, 0.32, 0.95)
	sb_hover.border_color = Color(0.7, 0.78, 1.0, 1.0)
	var sb_pressed := sb_normal.duplicate()
	sb_pressed.bg_color = Color(0.22, 0.28, 0.42, 1.0)
	_auto_toggle_button.add_theme_stylebox_override("normal", sb_normal)
	_auto_toggle_button.add_theme_stylebox_override("hover", sb_hover)
	_auto_toggle_button.add_theme_stylebox_override("pressed", sb_pressed)
	_auto_toggle_button.tooltip_text = "Toggle global autobattle (sticky). Same as Minus / F6."
	_auto_toggle_button.pressed.connect(_on_auto_toggle_pressed)
	ui.add_child(_auto_toggle_button)


func _update_auto_toggle_button() -> void:
	"""Refresh the AUTO toggle button label + colors based on current state."""
	if not _auto_toggle_button:
		return
	var any_on := false
	var members = BattleManager.player_party if BattleManager.player_party.size() > 0 else _scene.party_members
	for member in members:
		var char_id: String = member.combatant_name.to_lower().replace(" ", "_")
		if AutobattleSystem.is_autobattle_enabled(char_id):
			any_on = true
			break
	if any_on:
		_auto_toggle_button.text = "AUTO: ON"
		_auto_toggle_button.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	else:
		_auto_toggle_button.text = "AUTO: OFF"
		_auto_toggle_button.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))


func _on_auto_toggle_pressed() -> void:
	"""Mouse click on AUTO toggle — same effect as Minus/F6/Plus-when-on.
	Reuses GameLoop._toggle_all_autobattle so the path is identical to
	gamepad/keyboard: clears pending player actions on disable, plays
	the autobattle_on/off SFX, and shows a Toast in non-battle states."""
	if not _auto_toggle_button or not is_instance_valid(_auto_toggle_button):
		return
	var gl = _scene.get_tree().root.get_node_or_null("GameLoop")
	if gl and gl.has_method("_toggle_all_autobattle"):
		gl._toggle_all_autobattle()
	else:
		# Fallback path — should never fire since GameLoop is the main scene.
		var any_on: bool = false
		for member in _scene.party_members:
			var char_id: String = member.combatant_name.to_lower().replace(" ", "_")
			if AutobattleSystem.is_autobattle_enabled(char_id):
				any_on = true
				break
		for member in _scene.party_members:
			var char_id: String = member.combatant_name.to_lower().replace(" ", "_")
			AutobattleSystem.set_autobattle_enabled(char_id, not any_on)
		if SoundManager:
			SoundManager.play_ui("autobattle_off" if any_on else "autobattle_on")
	# Full UI refresh — updates the [A] indicators in PartyStatusPanel
	# AND the AUTO button label. Without this, the [A] indicators were
	# stale until the next battle event triggered _update_ui.
	update_ui()


func update_character_status() -> void:
	"""Update character status display for all party members"""
	# Use BattleManager's player_party for accurate current state
	var members = BattleManager.player_party if BattleManager.player_party.size() > 0 else _scene.party_members
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
	var members = BattleManager.player_party if BattleManager.player_party.size() > 0 else _scene.party_members

	# Skip if already created for this party
	if _party_status_boxes.size() == members.size():
		var all_valid = true
		for box in _party_status_boxes:
			if not is_instance_valid(box):
				all_valid = false
				break
		if all_valid:
			return

	var container = _scene.get_node("UI/PartyStatusPanel/VBoxContainer")

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
	"""Create a status box for a party member.

	HP/MP bar heights shrink slightly when the party has 5+ members so all
	status boxes fit inside the PartyStatusPanel's fixed 420px tall slot.
	Pre-fix: 4-shaped heights at 5-PC overflowed the panel and clipped the
	Bard box (or pushed it over the CTB timeline). The PartyStatusPanel
	offset_bottom=460 is pinned by test_battle_4bug_22bd71e_regression to
	prevent CTB overlap, so the fix has to be on the per-box side."""
	var party_size: int = BattleManager.player_party.size() if BattleManager.player_party.size() > 0 else _scene.party_members.size()
	## Live playtest 2026-07-01: with 5 boxes + portrait header rows the
	## content exceeded the panel's 420px slot; grow_vertical=BOTH then
	## expanded the panel ABOVE the screen top, decapitating the Fighter
	## (first box) header. Scene now grows downward only (grow_vertical=1)
	## and the 5-party heights below are tightened further so the stack
	## actually fits the slot instead of relying on overflow.
	var hp_bar_h: int = 22 if party_size <= 4 else 16
	var mp_bar_h: int = 18 if party_size <= 4 else 12
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
	hp_bar.custom_minimum_size = Vector2(0, hp_bar_h)
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
	mp_bar.custom_minimum_size = Vector2(0, mp_bar_h)
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

	# Equipment/Buff stat modifiers line
	var stat_label = RichTextLabel.new()
	stat_label.name = "StatMods"
	stat_label.bbcode_enabled = true
	stat_label.fit_content = true
	stat_label.custom_minimum_size = Vector2(0, 16)
	stat_label.add_theme_font_size_override("normal_font_size", 10)
	stat_label.text = ""
	box.add_child(stat_label)
	_update_stat_mods_label(stat_label, member)

	return box


func _update_member_status(idx: int, member: Combatant) -> void:
	"""Update a single party member's status display"""
	if idx >= _party_status_boxes.size():
		return

	var box = _party_status_boxes[idx]
	if not is_instance_valid(box):
		return

	# Update name with autobattle indicator
	var name_label = box.get_node_or_null("Header/Name")
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

	# Gray out the sprite if KO'd; otherwise apply status tint (or reset to white)
	if idx < _scene.party_sprite_nodes.size():
		var sprite = _scene.party_sprite_nodes[idx]
		if is_instance_valid(sprite):
			if not member.is_alive:
				sprite.modulate = Color(0.3, 0.3, 0.3, 0.7)  # Dark gray, semi-transparent
			else:
				sprite.modulate = _get_status_modulate(member.status_effects)

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
			_scene.active_win98_menu and is_instance_valid(_scene.active_win98_menu))
		if is_current_selecting:
			queued_count = _scene.active_win98_menu.get_queue_count()

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

	# Update equipment/buff stat modifiers
	var stat_label = box.get_node_or_null("StatMods")
	if stat_label:
		_update_stat_mods_label(stat_label, member)


func _update_stat_mods_label(label: RichTextLabel, member: Combatant) -> void:
	"""Build compact equipment + buff stat modifier display"""
	var parts: Array[String] = []

	# Equipment bonuses (flat numbers)
	if EquipmentSystem:
		var equip_mods = EquipmentSystem.get_equipment_mods(member)
		var equip_parts: Array[String] = []
		for stat in ["attack", "defense", "magic", "speed"]:
			var val = equip_mods.get(stat, 0)
			if val != 0:
				# Tick 211: shared StatNames map.
				var abbrev: String = StatNames.short_code(stat)
				var color = "lime" if val > 0 else "red"
				equip_parts.append("[color=%s]%s%+d[/color]" % [color, abbrev, val])
		if equip_parts.size() > 0:
			parts.append(" ".join(equip_parts))

	# Active buff/debuff indicators (multipliers with turn counters)
	if "active_buffs" in member and member.active_buffs.size() > 0:
		for buff in member.active_buffs:
			var stat_name: String = buff.get("stat", "")
			var modifier: float = buff.get("modifier", 1.0)
			var turns: int = buff.get("remaining_turns", 0)
			if stat_name == "" or modifier == 1.0:
				continue
			# Tick 211: shared StatNames map adds HP/MP coverage the inline dict missed.
			var abbrev: String = StatNames.short_code(stat_name)
			var pct = int((modifier - 1.0) * 100)
			var color = "aqua" if pct > 0 else "orange"
			parts.append("[color=%s]%s%+d%%(%d)[/color]" % [color, abbrev, pct, turns])

	if "active_debuffs" in member and member.active_debuffs.size() > 0:
		for debuff in member.active_debuffs:
			var stat_name: String = debuff.get("stat", "")
			var modifier: float = debuff.get("modifier", 1.0)
			var turns: int = debuff.get("remaining_turns", 0)
			if stat_name == "" or modifier == 1.0:
				continue
			# Tick 211: shared StatNames map adds HP/MP coverage the inline dict missed.
			var abbrev: String = StatNames.short_code(stat_name)
			var pct = int((modifier - 1.0) * 100)
			parts.append("[color=%s]%s%+d%%(%d)[/color]" % [AccessibilityPalette.penalty_bbcode(), abbrev, pct, turns])

	label.text = " ".join(parts) if parts.size() > 0 else ""


func _get_status_modulate(status_effects: Array) -> Color:
	"""Return sprite modulate color for the highest-priority active status effect.
	Returns Color.WHITE when no relevant statuses are present."""
	for effect in status_effects:
		match effect:
			"poison":
				return Color(0.7, 1.0, 0.7)   # Green tint
			"burning":
				return Color(1.0, 0.6, 0.4)   # Orange-red
			"curse":
				return Color(0.7, 0.4, 0.8)   # Purple
			"stun":
				return Color(1.0, 1.0, 0.5)   # Yellow
			"sleep":
				return Color(0.8, 0.8, 1.0)   # Pale blue
			"blind":
				return Color(0.6, 0.6, 0.7)   # Dark blue-gray
	return Color.WHITE


func update_enemy_status() -> void:
	"""Update enemy status display for all enemies"""
	if _scene.test_enemies.size() == 0:
		return

	# Create status boxes if needed
	_ensure_enemy_status_boxes()

	# Update each enemy's status
	for i in range(_scene.test_enemies.size()):
		if i >= _enemy_status_boxes.size():
			break
		_update_enemy_member_status(i, _scene.test_enemies[i])


func _ensure_enemy_status_boxes() -> void:
	"""Ensure we have status boxes for all enemies"""
	var container = _scene.get_node_or_null("UI/EnemyStatusPanel/VBoxContainer")
	if not container:
		return

	# Skip if already created for this enemy count
	if _enemy_status_boxes.size() == _scene.test_enemies.size():
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
	for i in range(_scene.test_enemies.size()):
		var enemy = _scene.test_enemies[i]
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
	if idx < _scene.test_enemies.size() - 1:
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

	# Update AP and status effects
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
			var ap_text = "[color=%s]AP: %+d[/color]" % [ap_color, enemy.current_ap]
			if enemy.status_effects.size() > 0:
				ap_text += " ["
				for si in range(enemy.status_effects.size()):
					if si > 0:
						ap_text += ", "
					ap_text += "[color=yellow]%s[/color]" % enemy.status_effects[si].capitalize()
				ap_text += "]"
			ap_label.text = ap_text

	# Update HP (hidden unless revealed or dead)
	var hp_label = box.get_node_or_null("HP")
	if hp_label and hp_label is RichTextLabel:
		if is_dead:
			hp_label.text = "[color=%s]DEFEATED[/color]" % AccessibilityPalette.penalty_bbcode()
		elif is_revealed:
			var hp_percent = float(enemy.current_hp) / float(enemy.max_hp)
			# Tick 230: BBCode color via AccessibilityPalette so the enemy HP tooltip matches the colorblind-aware visual HP bar palette (cyan/yellow/magenta in accessibility mode).
			var hp_color = AccessibilityPalette.hp_bbcode_for_pct(hp_percent)
			hp_label.text = "[color=%s]HP: %d/%d[/color]" % [hp_color, enemy.current_hp, enemy.max_hp]
		else:
			# Show vague HP indicator based on percentage
			var hp_percent = float(enemy.current_hp) / float(enemy.max_hp)
			var hp_hint = "Healthy" if hp_percent > 0.75 else ("Wounded" if hp_percent > 0.5 else ("Hurt" if hp_percent > 0.25 else "Critical"))
			# Tick 230: BBCode color via AccessibilityPalette (matches the revealed-HP branch above).
			var hp_color = AccessibilityPalette.hp_bbcode_for_pct(hp_percent)
			hp_label.text = "[color=%s]%s[/color]" % [hp_color, hp_hint]


func reveal_enemy_stats(enemy: Combatant) -> void:
	"""Reveal an enemy's HP/MP (called by scan abilities)"""
	_revealed_enemies[enemy] = true
	update_enemy_status()


func update_action_buttons() -> void:
	"""Enable/disable action buttons based on battle state"""
	var is_player_selecting = BattleManager.current_state == BattleManager.BattleState.PLAYER_SELECTING
	var current = BattleManager.current_combatant

	_scene.btn_attack.disabled = not is_player_selecting
	_scene.btn_ability.disabled = not is_player_selecting
	_scene.btn_item.disabled = not is_player_selecting
	_scene.btn_default.disabled = not is_player_selecting

	# Bide requires non-negative AP
	if current and is_player_selecting:
		_scene.btn_bide.disabled = current.current_ap < 0
	else:
		_scene.btn_bide.disabled = true


func update_turn_info() -> void:
	"""Update turn information display for CTB system"""
	var state = BattleManager.current_state
	var current = BattleManager.current_combatant

	if state == BattleManager.BattleState.SELECTION_PHASE or state == BattleManager.BattleState.PLAYER_SELECTING or state == BattleManager.BattleState.ENEMY_SELECTING:
		if current:
			_scene.turn_info.text = "Round %d - SELECT: %s (AP: %+d)" % [
				BattleManager.current_round,
				current.combatant_name,
				current.current_ap
			]
		else:
			_scene.turn_info.text = "Round %d - Selection Phase" % BattleManager.current_round
	elif state == BattleManager.BattleState.EXECUTION_PHASE or state == BattleManager.BattleState.PROCESSING_ACTION:
		if current:
			_scene.turn_info.text = "Round %d - EXECUTE: %s" % [
				BattleManager.current_round,
				current.combatant_name
			]
		else:
			_scene.turn_info.text = "Round %d - Execution Phase" % BattleManager.current_round
	else:
		_scene.turn_info.text = "Round %d" % BattleManager.current_round

	# Update turn order strip
	_update_turn_order_strip()


## CTB Timeline — vertical turn order display (FFX-style) on right side
var _ctb_timeline: VBoxContainer = null
var _ctb_panel: PanelContainer = null

func _update_turn_order_strip() -> void:
	"""Show upcoming turn order as a vertical CTB timeline on the right"""
	# Create timeline panel on first call
	if not _ctb_panel:
		_ctb_panel = PanelContainer.new()
		_ctb_panel.name = "CTBTimeline"
		_ctb_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var panel_style = StyleBoxFlat.new()
		panel_style.bg_color = Color(0.05, 0.03, 0.1, 0.75)
		panel_style.border_color = Color(0.4, 0.35, 0.6, 0.6)
		panel_style.border_width_right = 1
		panel_style.corner_radius_top_right = 4
		panel_style.corner_radius_bottom_right = 4
		panel_style.content_margin_left = 6
		panel_style.content_margin_right = 6
		panel_style.content_margin_top = 4
		panel_style.content_margin_bottom = 4
		_ctb_panel.add_theme_stylebox_override("panel", panel_style)
		# Bottom-LEFT — moved 2026-06-17 to clear the right-side party panel.
		_ctb_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_ctb_panel.offset_left = 5
		_ctb_panel.offset_right = 110
		_ctb_panel.offset_bottom = -10
		_ctb_panel.offset_top = -180
		_ctb_panel.custom_minimum_size = Vector2(100, 0)
		_ctb_panel.grow_horizontal = Control.GROW_DIRECTION_END
		_ctb_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_scene.get_node("UI").add_child(_ctb_panel)

		# Header
		var header = Label.new()
		header.text = "TURN ORDER"
		header.add_theme_font_size_override("font_size", 9)
		header.add_theme_color_override("font_color", Color(0.6, 0.55, 0.8))
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE

		_ctb_timeline = VBoxContainer.new()
		_ctb_timeline.name = "Timeline"
		_ctb_timeline.add_theme_constant_override("separation", 2)
		_ctb_timeline.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(header)
		vbox.add_child(_ctb_timeline)
		_ctb_panel.add_child(vbox)

	# Clear existing entries
	for child in _ctb_timeline.get_children():
		child.queue_free()

	# Build turn order
	var order = BattleManager.selection_order
	var current_idx = BattleManager.selection_index
	if order.is_empty():
		return

	var shown = 0
	for i in range(order.size()):
		if shown >= 8:
			break
		var combatant = order[i]
		if not is_instance_valid(combatant) or not combatant.is_alive:
			continue
		if i < current_idx:
			continue

		var is_current = (i == current_idx)
		var is_player = combatant in BattleManager.player_party
		var entry = _create_ctb_entry(combatant, is_current, is_player, shown)
		_ctb_timeline.add_child(entry)
		shown += 1


func _create_ctb_entry(combatant: Combatant, is_current: bool, is_player: bool, position_idx: int) -> HBoxContainer:
	"""Create a single entry in the CTB timeline"""
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Position indicator (arrow for current, dot for others)
	var indicator = Label.new()
	if is_current:
		indicator.text = "▶"
		indicator.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	elif position_idx == 1:
		indicator.text = "·"
		indicator.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	else:
		indicator.text = "·"
		indicator.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	indicator.add_theme_font_size_override("font_size", 12)
	indicator.custom_minimum_size = Vector2(12, 0)
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(indicator)

	# Name
	var name_label = Label.new()
	var display_name = combatant.combatant_name
	if display_name.length() > 8:
		display_name = display_name.substr(0, 7) + "."
	name_label.text = display_name
	name_label.custom_minimum_size = Vector2(60, 0)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var name_size = 11 if is_current else 10
	name_label.add_theme_font_size_override("font_size", name_size)

	if is_current:
		name_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	elif is_player:
		name_label.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
	else:
		name_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	row.add_child(name_label)

	# Speed value (smaller, right-aligned)
	var spd_label = Label.new()
	spd_label.text = "%d" % combatant.speed
	spd_label.add_theme_font_size_override("font_size", 9)
	spd_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	spd_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spd_label)

	return row


func log_message(message: String) -> void:
	"""Add a message to the battle log"""
	print(message)

	if _scene.battle_log:
		_scene.battle_log.append_text(message + "\n")
