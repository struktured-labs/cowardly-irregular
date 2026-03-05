extends RefCounted
class_name BattleResultsDisplay

## BattleResultsDisplay - Handles victory results, damage numbers, and battle feedback overlays
## Extracted from BattleScene to reduce god class complexity

const DamageNumber = preload("res://src/ui/DamageNumber.gd")

var _scene  # Reference to parent BattleScene (untyped to avoid circular dependency)


func _init(scene) -> void:
	_scene = scene


func on_damage_dealt(target: Combatant, amount: int, is_crit: bool) -> void:
	"""Show floating damage number near target and trigger screen shake"""
	var pos = _get_combatant_sprite_position(target)
	if pos != Vector2.ZERO:
		spawn_damage_number(pos, amount, false, is_crit)
	else:
		print("[DMG NUM] Could not find sprite position for %s" % target.combatant_name)

	if is_crit:
		EffectSystem._trigger_screen_shake(9.0, 0.2)
	else:
		EffectSystem._trigger_screen_shake(3.5, 0.1)


func on_healing_done(target: Combatant, amount: int) -> void:
	"""Show floating heal number near target"""
	var pos = _get_combatant_sprite_position(target)
	if pos != Vector2.ZERO:
		spawn_damage_number(pos, amount, true, false)


func on_attack_missed(target: Combatant) -> void:
	"""Show floating MISS text near target"""
	var pos = _get_combatant_sprite_position(target)
	if pos != Vector2.ZERO:
		spawn_miss_number(pos)


func spawn_damage_number(pos: Vector2, amount: int, is_heal: bool, is_crit: bool) -> void:
	"""Spawn a floating damage/heal number"""
	var dmg_num = DamageNumber.new()
	dmg_num.setup(amount, is_heal, is_crit)
	# Offset slightly upward from sprite center
	dmg_num.position = pos + Vector2(randf_range(-10, 10), -30)
	_scene.add_child(dmg_num)


func spawn_miss_number(pos: Vector2) -> void:
	"""Spawn a floating MISS text"""
	var dmg_num = DamageNumber.new()
	dmg_num.setup_miss()
	dmg_num.position = pos + Vector2(randf_range(-10, 10), -30)
	_scene.add_child(dmg_num)


func show_victory_results() -> void:
	"""Display a classic JRPG victory results overlay with EXP and bonuses"""
	var results = BattleManager.get_battle_results()
	if results.is_empty():
		return

	var char_results: Array = results.get("char_results", [])
	var bonuses: Array = results.get("bonuses", [])

	# Create results panel overlay
	var overlay = Control.new()
	overlay.name = "VictoryResults"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene.add_child(overlay)

	# Semi-transparent backdrop
	var backdrop = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.0, 0.05, 0.7)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(backdrop)

	# Results panel (centered, fixed size)
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	var panel_width = 380
	var panel_height = 60 + char_results.size() * 50 + (bonuses.size() * 28 if bonuses.size() > 0 else 0) + 40
	panel.offset_left = -panel_width / 2
	panel.offset_right = panel_width / 2
	panel.offset_top = -panel_height / 2
	panel.offset_bottom = panel_height / 2
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Dark panel style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.15, 0.95)
	style.border_color = Color(0.6, 0.5, 0.2)
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(panel)

	# VBox layout inside panel
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	# "VICTORY" header
	var header = Label.new()
	header.text = "VICTORY"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 24)
	header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(header)

	# Separator
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	# Per-character results
	for cr in char_results:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Name
		var name_label = Label.new()
		name_label.text = cr["name"]
		name_label.custom_minimum_size.x = 90
		name_label.add_theme_font_size_override("font_size", 16)
		var name_color = Color(0.5, 0.5, 0.5) if not cr["is_alive"] else Color(1.0, 1.0, 1.0)
		name_label.add_theme_color_override("font_color", name_color)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(name_label)

		# EXP gained
		var exp_label = Label.new()
		if cr["is_alive"]:
			exp_label.text = "+%d EXP" % cr["exp_gained"]
		else:
			exp_label.text = "KO"
		exp_label.custom_minimum_size.x = 90
		exp_label.add_theme_font_size_override("font_size", 16)
		exp_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5) if cr["is_alive"] else Color(0.8, 0.3, 0.3))
		exp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(exp_label)

		# Job + Level
		var job_label = Label.new()
		job_label.text = "%s Lv.%d" % [cr["job_name"], cr["job_level"]]
		job_label.add_theme_font_size_override("font_size", 14)
		job_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9))
		job_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(job_label)

		vbox.add_child(row)

		# Level up indicator
		if cr["leveled_up"]:
			var lvl_label = Label.new()
			lvl_label.text = "    LEVEL UP!"
			lvl_label.add_theme_font_size_override("font_size", 14)
			lvl_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.3))
			lvl_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vbox.add_child(lvl_label)

	# Bonuses section
	if bonuses.size() > 0:
		var sep2 = HSeparator.new()
		sep2.add_theme_constant_override("separation", 6)
		sep2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(sep2)

		for bonus in bonuses:
			var bonus_row = Label.new()
			bonus_row.add_theme_font_size_override("font_size", 14)
			bonus_row.mouse_filter = Control.MOUSE_FILTER_IGNORE

			if bonus["type"] == "one_shot":
				bonus_row.text = "ONE-SHOT (Rank %s) - EXP x%.1f" % [bonus["rank"], bonus["multiplier"]]
				bonus_row.add_theme_color_override("font_color", Color(1.0, 0.9, 0.0))
			elif bonus["type"] == "autobattle":
				bonus_row.text = "AUTO-BATTLE (%d turns) - EXP x%.1f" % [bonus["turns"], bonus["multiplier"]]
				bonus_row.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))

			vbox.add_child(bonus_row)

	# "Press ENTER" prompt
	var prompt = Label.new()
	prompt.text = "Press ENTER to continue"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 12)
	prompt.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(prompt)

	# Animate: slide up and fade in
	overlay.modulate.a = 0.0
	panel.offset_top += 30
	panel.offset_bottom += 30
	var tween = _scene.create_tween()
	tween.set_parallel(true)
	tween.tween_property(overlay, "modulate:a", 1.0, 0.4)
	tween.tween_property(panel, "offset_top", panel.offset_top - 30, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "offset_bottom", panel.offset_bottom - 30, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Blink the prompt text
	var blink_tween = _scene.create_tween()
	blink_tween.set_loops()
	blink_tween.tween_property(prompt, "modulate:a", 0.3, 0.8)
	blink_tween.tween_property(prompt, "modulate:a", 1.0, 0.8)


func _get_combatant_sprite_position(combatant: Combatant) -> Vector2:
	"""Get the screen position of a combatant's sprite"""
	# Check party members (use BattleManager's array for consistency)
	var party_idx = BattleManager.player_party.find(combatant)
	if party_idx >= 0 and party_idx < _scene.party_sprite_nodes.size():
		var sprite = _scene.party_sprite_nodes[party_idx]
		if is_instance_valid(sprite):
			return sprite.global_position

	# Check enemies (use BattleManager's array for consistency)
	var enemy_idx = BattleManager.enemy_party.find(combatant)
	if enemy_idx >= 0 and enemy_idx < _scene.enemy_sprite_nodes.size():
		var sprite = _scene.enemy_sprite_nodes[enemy_idx]
		if is_instance_valid(sprite):
			return sprite.global_position

	return Vector2.ZERO
