extends Control
class_name BattleBDFFHDHudStrip

## BattleBDFFHDHudStrip - BDFFHD Bottom HUD Strip UI Scene Controller
## A persistent HUD strip spanning the bottom of the battle screen.
## Structured for a 5-PC party.
## Components per PC: Name, Health bar (HP), AP indicator, and Trust / Manual indicator.

const PANEL_BG = Color(0.06, 0.05, 0.11, 0.90) # Dark rich blue/purple
const BORDER_LIGHT = Color(0.40, 0.35, 0.55, 0.80)
const BORDER_SHADOW = Color(0.15, 0.10, 0.22, 0.90)

const COLOR_HEALTH = Color(0.25, 0.80, 0.25)
const COLOR_HEALTH_WARN = Color(0.90, 0.75, 0.15)
const COLOR_HEALTH_CRIT = Color(0.85, 0.20, 0.20)

# 5-PC Columns
var _party_columns: Array[VBoxContainer] = []

func _ready() -> void:
	custom_minimum_size = Vector2(0, 72)
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	_build_hud_strip()

func _build_hud_strip() -> void:
	# Clear existing children
	for child in get_children():
		child.queue_free()
	_party_columns.clear()

	# Background Panel
	var bg = ColorRect.new()
	bg.color = PANEL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	# Borders
	_add_borders()

	# Columns Container for 5 PCs
	var h_box = HBoxContainer.new()
	h_box.name = "PartyHBox"
	h_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	h_box.add_theme_constant_override("separation", 12)
	
	# Add margins
	var margin_container = MarginContainer.new()
	margin_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin_container.add_theme_constant_override("margin_left", 16)
	margin_container.add_theme_constant_override("margin_right", 16)
	margin_container.add_theme_constant_override("margin_top", 6)
	margin_container.add_theme_constant_override("margin_bottom", 6)
	add_child(margin_container)
	margin_container.add_child(h_box)

	# Generate 5 columns (for 5 party members)
	for i in range(5):
		var col = VBoxContainer.new()
		col.name = "CombatantCol_%d" % i
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		
		# Row 1: Name and Trust/AI Status
		var row_name = HBoxContainer.new()
		row_name.name = "HeaderRow"
		
		var name_lbl = Label.new()
		name_lbl.name = "NameLabel"
		name_lbl.text = "---"
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_name.add_child(name_lbl)
		
		var trust_lbl = Label.new()
		trust_lbl.name = "TrustLabel"
		trust_lbl.text = "Manual"
		trust_lbl.add_theme_font_size_override("font_size", 10)
		trust_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row_name.add_child(trust_lbl)
		
		col.add_child(row_name)

		# Row 2: HP Bar with HP label overlay
		var hp_bar = ProgressBar.new()
		hp_bar.name = "HPBar"
		hp_bar.custom_minimum_size = Vector2(0, 16)
		hp_bar.show_percentage = false
		hp_bar.max_value = 100
		hp_bar.value = 100
		
		# Overlay Label for HP text
		var hp_text = Label.new()
		hp_text.name = "HPLabel"
		hp_text.text = "HP: 0/0"
		hp_text.add_theme_font_size_override("font_size", 10)
		hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hp_text.set_anchors_preset(Control.PRESET_FULL_RECT)
		hp_bar.add_child(hp_text)
		
		col.add_child(hp_bar)

		# Row 3: AP Indicator
		var ap_lbl = RichTextLabel.new()
		ap_lbl.name = "APLabel"
		ap_lbl.bbcode_enabled = true
		ap_lbl.fit_content = true
		ap_lbl.scroll_active = false
		ap_lbl.custom_minimum_size = Vector2(0, 16)
		ap_lbl.add_theme_font_size_override("normal_font_size", 11)
		ap_lbl.add_theme_font_size_override("bold_font_size", 11)
		ap_lbl.text = "AP: 0"
		col.add_child(ap_lbl)

		h_box.add_child(col)
		_party_columns.append(col)

func _add_borders() -> void:
	var top = ColorRect.new()
	top.color = BORDER_LIGHT
	top.custom_minimum_size = Vector2(0, 2)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(top)

	var bottom = ColorRect.new()
	bottom.color = BORDER_SHADOW
	bottom.custom_minimum_size = Vector2(0, 2)
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	add_child(bottom)

## Update state bindings from BattleManager.player_party
func update_hud(party_members: Array) -> void:
	for i in range(5):
		var col = _party_columns[i]
		if i >= party_members.size() or party_members[i] == null:
			col.visible = false
			continue
		
		col.visible = true
		var member = party_members[i]
		
		# Update Name
		var name_lbl = col.get_node("HeaderRow/NameLabel") as Label
		name_lbl.text = member.combatant_name
		
		# Update HP Bar and Text
		var hp_bar = col.get_node("HPBar") as ProgressBar
		var hp_lbl = hp_bar.get_node("HPLabel") as Label
		hp_bar.max_value = member.max_hp
		hp_bar.value = member.current_hp
		
		if not member.is_alive:
			hp_lbl.text = "KO"
			hp_bar.self_modulate = COLOR_HEALTH_CRIT
			name_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		else:
			hp_lbl.text = "HP: %d/%d" % [member.current_hp, member.max_hp]
			name_lbl.remove_theme_color_override("font_color")
			
			# Dynamic color shift
			var hp_pct = float(member.current_hp) / float(member.max_hp)
			if hp_pct > 0.5:
				hp_bar.self_modulate = COLOR_HEALTH
			elif hp_pct > 0.25:
				hp_bar.self_modulate = COLOR_HEALTH_WARN
			else:
				hp_bar.self_modulate = COLOR_HEALTH_CRIT

		# Update Trust / Manual Status
		var trust_lbl = col.get_node("HeaderRow/TrustLabel") as Label
		# Check combatant.autobattle_locked
		var locked = false
		if "autobattle_locked" in member:
			locked = member.autobattle_locked
		
		if locked:
			trust_lbl.text = "Trust / AI"
			trust_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0)) # AI teal
		else:
			trust_lbl.text = "Manual"
			trust_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9)) # Plain white/gray

		# Update AP Indicator (styled like BattleUIManager with selecting/queued/committed/deferring logic)
		var ap_lbl = col.get_node("APLabel") as RichTextLabel
		var ap_value = member.current_ap
		var ap_color = "white"
		if ap_value > 0:
			ap_color = "lime"
		elif ap_value < 0:
			ap_color = "red"

		# Simple presentation matching standard HUD needs
		ap_lbl.text = "[color=%s]AP: %+d[/color]" % [ap_color, ap_value]
