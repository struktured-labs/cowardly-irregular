extends Control
class_name PartyStatusScreen

## FF-style full-party status screen showing all members with
## portrait, job, level, HP/MP, equipment, abilities, passives.
## Arrow keys / D-pad switch focused member. B/Esc closes.

signal closed()

const BG_COLOR := Color(0.04, 0.05, 0.08, 0.96)
const CARD_COLOR := Color(0.10, 0.10, 0.14)
const CARD_FOCUS := Color(0.16, 0.18, 0.26)
const BORDER_LIGHT := RetroPanel.BORDER_LIGHT
const BORDER_SHADOW := RetroPanel.BORDER_SHADOW
const TEXT := Color(1.0, 1.0, 1.0)
const MUTED := Color(0.55, 0.6, 0.7)
const LABEL := Color(0.7, 0.85, 1.0)
const HP_COLOR := Color(0.4, 0.9, 0.4)
const MP_COLOR := Color(0.4, 0.8, 1.0)
const WEAPON_COLOR := Color(1.0, 0.75, 0.35)
const ARMOR_COLOR := Color(0.55, 0.75, 1.0)
const ACCESSORY_COLOR := Color(0.9, 0.6, 0.95)

var party: Array = []
var focused_index: int = 0
var _cards: Array = []
var _detail_panel: Control = null


func setup(game_party: Array) -> void:
	party = game_party
	focused_index = clampi(focused_index, 0, max(0, party.size() - 1))
	call_deferred("_build_ui")


func _ready() -> void:
	call_deferred("_build_ui")
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.15).set_ease(Tween.EASE_OUT)


func _build_ui() -> void:
	for child in get_children():
		child.queue_free()
	_cards.clear()
	_detail_panel = null

	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)
	MenuMouseHelper.add_right_click_cancel(bg, _close)

	var vp := get_viewport_rect().size
	if vp.x <= 0:
		vp = Vector2(1280, 720)

	var title := Label.new()
	title.text = "PARTY STATUS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 14)
	title.size = Vector2(vp.x, 24)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", TEXT)
	add_child(title)

	# Layout: 4 compact party cards on top, detail panel below
	var card_w := (vp.x - 120.0) / 4.0
	var card_h := 160.0
	var card_y := 48.0

	for i in party.size():
		var member = party[i]
		var card := _build_card(member, card_w, card_h, i)
		card.position = Vector2(24 + i * (card_w + 8), card_y)
		add_child(card)
		_cards.append(card)

	# Detail panel below
	_detail_panel = Control.new()
	_detail_panel.position = Vector2(24, card_y + card_h + 16)
	_detail_panel.size = Vector2(vp.x - 48, vp.y - (card_y + card_h + 32 + 40))
	add_child(_detail_panel)
	_rebuild_detail()

	# Footer
	var footer := Label.new()
	footer.text = "←→: Switch member  B/Esc: Back"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.position = Vector2(0, vp.y - 28)
	footer.size = Vector2(vp.x, 18)
	footer.add_theme_font_size_override("font_size", 11)
	footer.add_theme_color_override("font_color", MUTED)
	add_child(footer)

	_update_focus()


func _build_card(member, w: float, h: float, index: int) -> Control:
	var card := Control.new()
	card.size = Vector2(w, h)
	card.mouse_filter = MOUSE_FILTER_STOP
	card.gui_input.connect(_on_card_click.bind(index))
	card.mouse_entered.connect(_on_card_hover.bind(index))

	var bg := ColorRect.new()
	bg.color = CARD_COLOR
	bg.name = "CardBG"
	bg.set_anchors_preset(PRESET_FULL_RECT)
	card.add_child(bg)
	RetroPanel.add_border(card, card.size, BORDER_LIGHT, BORDER_SHADOW)

	# Name
	var name_label := Label.new()
	name_label.text = str(member.combatant_name if "combatant_name" in member else "???")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(0, 6)
	name_label.size = Vector2(w, 18)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", TEXT)
	card.add_child(name_label)

	# Job + Level
	var job_name := _job_label(member)
	var lvl := _get_level(member)
	var sub := Label.new()
	sub.text = "%s  Lv %d" % [job_name, lvl]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(0, 26)
	sub.size = Vector2(w, 16)
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", LABEL)
	card.add_child(sub)

	# HP bar
	var hp_cur: int = int(member.current_hp) if "current_hp" in member else 0
	var hp_max: int = int(member.max_hp) if "max_hp" in member else 1
	var mp_cur: int = int(member.current_mp) if "current_mp" in member else 0
	var mp_max: int = int(member.max_mp) if "max_mp" in member else 0
	_add_bar(card, 12, 54, w - 24, 10, hp_cur, hp_max, HP_COLOR, "HP")
	_add_bar(card, 12, 78, w - 24, 10, mp_cur, mp_max, MP_COLOR, "MP")

	# Stats (compact)
	var stats := Label.new()
	stats.text = "ATK %d  DEF %d\nMAG %d  SPD %d" % [
		int(member.attack) if "attack" in member else 0,
		int(member.defense) if "defense" in member else 0,
		int(member.magic) if "magic" in member else 0,
		int(member.speed) if "speed" in member else 0,
	]
	stats.position = Vector2(12, 100)
	stats.size = Vector2(w - 24, 40)
	stats.add_theme_font_size_override("font_size", 11)
	stats.add_theme_color_override("font_color", TEXT)
	card.add_child(stats)

	return card


func _add_bar(parent: Control, x: float, y: float, w: float, h: float, cur: int, max_v: int, color: Color, label: String) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.1)
	bg.position = Vector2(x, y)
	bg.size = Vector2(w, h)
	parent.add_child(bg)
	var fill := ColorRect.new()
	fill.color = color
	fill.position = Vector2(x, y)
	var pct: float = 0.0
	if max_v > 0:
		pct = clampf(float(cur) / float(max_v), 0.0, 1.0)
	fill.size = Vector2(w * pct, h)
	parent.add_child(fill)
	var txt := Label.new()
	txt.text = "%s %d/%d" % [label, cur, max_v]
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	txt.position = Vector2(x, y - 2)
	txt.size = Vector2(w, h + 4)
	txt.add_theme_font_size_override("font_size", 10)
	txt.add_theme_color_override("font_color", TEXT)
	parent.add_child(txt)


func _rebuild_detail() -> void:
	if _detail_panel == null:
		return
	for child in _detail_panel.get_children():
		child.queue_free()
	if focused_index >= party.size():
		return
	var member = party[focused_index]

	var bg := ColorRect.new()
	bg.color = CARD_COLOR
	bg.set_anchors_preset(PRESET_FULL_RECT)
	_detail_panel.add_child(bg)
	RetroPanel.add_border(_detail_panel, _detail_panel.size, BORDER_LIGHT, BORDER_SHADOW)

	# Two columns: Equipment (left) | Abilities + Passives (right)
	var col_w := (_detail_panel.size.x - 48.0) / 2.0

	_build_equipment_column(member, 16, 12, col_w, _detail_panel.size.y - 24)
	_build_abilities_column(member, 32 + col_w, 12, col_w, _detail_panel.size.y - 24)


func _build_equipment_column(member, x: float, y: float, w: float, h: float) -> void:
	var section_title := Label.new()
	section_title.text = "EQUIPMENT"
	section_title.position = Vector2(x, y)
	section_title.add_theme_font_size_override("font_size", 14)
	section_title.add_theme_color_override("font_color", LABEL)
	_detail_panel.add_child(section_title)

	var cy := y + 28.0
	_add_equipment_row("Weapon", member.equipped_weapon if "equipped_weapon" in member else "", WEAPON_COLOR, x, cy, w)
	cy += 44
	_add_equipment_row("Armor", member.equipped_armor if "equipped_armor" in member else "", ARMOR_COLOR, x, cy, w)
	cy += 44
	_add_equipment_row("Accessory", member.equipped_accessory if "equipped_accessory" in member else "", ACCESSORY_COLOR, x, cy, w)


func _add_equipment_row(slot_label: String, item_id: String, color: Color, x: float, y: float, w: float) -> void:
	var slot := Label.new()
	slot.text = slot_label
	slot.position = Vector2(x, y)
	slot.add_theme_font_size_override("font_size", 11)
	slot.add_theme_color_override("font_color", MUTED)
	_detail_panel.add_child(slot)

	var item_name := "— None —"
	var item_desc := ""
	if item_id != "":
		var info := _resolve_equipment(item_id)
		item_name = info.get("name", item_id)
		item_desc = info.get("description", "")

	var name_label := Label.new()
	name_label.text = item_name
	name_label.position = Vector2(x, y + 14)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", color)
	_detail_panel.add_child(name_label)

	if item_desc != "":
		var desc := Label.new()
		desc.text = item_desc
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.position = Vector2(x, y + 32)
		desc.size = Vector2(w, 30)
		desc.add_theme_font_size_override("font_size", 10)
		desc.add_theme_color_override("font_color", MUTED)
		_detail_panel.add_child(desc)


func _build_abilities_column(member, x: float, y: float, w: float, h: float) -> void:
	var abilities: Array = []
	if "learned_abilities" in member:
		abilities = member.learned_abilities
	var passives: Array = []
	if "equipped_passives" in member:
		passives = member.equipped_passives

	var header := Label.new()
	header.text = "ABILITIES"
	header.position = Vector2(x, y)
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", LABEL)
	_detail_panel.add_child(header)

	var cy: float = y + 24.0
	if abilities.is_empty():
		var none := Label.new()
		none.text = "— None learned —"
		none.position = Vector2(x, cy)
		none.add_theme_font_size_override("font_size", 11)
		none.add_theme_color_override("font_color", MUTED)
		_detail_panel.add_child(none)
		cy += 20
	else:
		for ability_id in abilities:
			var row := Label.new()
			row.text = "• " + _format_id(str(ability_id))
			row.position = Vector2(x, cy)
			row.size = Vector2(w, 16)
			row.add_theme_font_size_override("font_size", 12)
			row.add_theme_color_override("font_color", TEXT)
			_detail_panel.add_child(row)
			cy += 18
			if cy > y + h * 0.5:
				break

	# Passives
	var passives_header := Label.new()
	passives_header.text = "PASSIVES"
	passives_header.position = Vector2(x, y + h * 0.5)
	passives_header.add_theme_font_size_override("font_size", 14)
	passives_header.add_theme_color_override("font_color", LABEL)
	_detail_panel.add_child(passives_header)

	cy = y + h * 0.5 + 24.0
	if passives.is_empty():
		var none_p := Label.new()
		none_p.text = "— None equipped —"
		none_p.position = Vector2(x, cy)
		none_p.add_theme_font_size_override("font_size", 11)
		none_p.add_theme_color_override("font_color", MUTED)
		_detail_panel.add_child(none_p)
	else:
		for passive_id in passives:
			var row := Label.new()
			row.text = "◦ " + _format_id(str(passive_id))
			row.position = Vector2(x, cy)
			row.size = Vector2(w, 16)
			row.add_theme_font_size_override("font_size", 12)
			row.add_theme_color_override("font_color", TEXT)
			_detail_panel.add_child(row)
			cy += 18
			if cy > y + h:
				break


func _job_label(member) -> String:
	if "job" in member and member.job != null:
		if member.job is Dictionary and member.job.has("name"):
			return str(member.job["name"])
		if member.job is Object and "name" in member.job:
			return str(member.job.name)
	return "Job"


func _get_level(member) -> int:
	if "job_level" in member:
		return int(member.job_level)
	if "level" in member:
		return int(member.level)
	return 1


func _format_id(id: String) -> String:
	return id.replace("_", " ").capitalize()


func _resolve_equipment(item_id: String) -> Dictionary:
	## Best-effort lookup: try EquipmentSystem, then item data files.
	if Engine.has_singleton("EquipmentSystem"):
		var eq = Engine.get_singleton("EquipmentSystem")
		for method in ["get_item", "get_weapon", "get_armor", "get_accessory"]:
			if eq.has_method(method):
				var data = eq.call(method, item_id)
				if data is Dictionary and not data.is_empty():
					return data
	return {"name": _format_id(item_id), "description": ""}


func _update_focus() -> void:
	for i in _cards.size():
		var card: Control = _cards[i]
		var bg := card.get_node_or_null("CardBG") as ColorRect
		if bg:
			bg.color = CARD_FOCUS if i == focused_index else CARD_COLOR


func _on_card_click(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		focused_index = index
		_update_focus()
		_rebuild_detail()


func _on_card_hover(index: int) -> void:
	if index != focused_index:
		focused_index = index
		_update_focus()
		_rebuild_detail()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_left") and not event.is_echo():
		focused_index = max(0, focused_index - 1)
		_update_focus()
		_rebuild_detail()
		if SoundManager:
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") and not event.is_echo():
		focused_index = min(party.size() - 1, focused_index + 1)
		_update_focus()
		_rebuild_detail()
		if SoundManager:
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	if SoundManager:
		SoundManager.play_ui("menu_close")
	closed.emit()
	queue_free()
