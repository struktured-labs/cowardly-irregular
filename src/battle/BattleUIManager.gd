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


func _init(scene) -> void:
	_scene = scene


func update_ui() -> void:
	"""Update all UI elements"""
	update_character_status()
	update_enemy_status()
	update_action_buttons()
	_scene._update_danger_music()


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

	# Gray out the sprite if KO'd
	if idx < _scene.party_sprite_nodes.size():
		var sprite = _scene.party_sprite_nodes[idx]
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


func log_message(message: String) -> void:
	"""Add a message to the battle log"""
	print(message)

	if _scene.battle_log:
		_scene.battle_log.append_text(message + "\n")
