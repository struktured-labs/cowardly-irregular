extends CanvasLayer
class_name KeyItemPopup

## Zelda-style full-screen "You obtained X!" popup.
## Usage:
##   KeyItemPopup.show_item(get_tree().get_root(), {
##       "name": "Crimson Shard",
##       "description": "A shard of the Elder Flame. Opens the first seal.",
##       "sprite_path": "res://assets/sprites/items/shard.png"  # optional
##   })

signal dismissed()

const PANEL_W := 440.0
const PANEL_H := 260.0
## One extra text line on the card, measured: a font-11 Label clamps to ~34px with theme margins.
const EXTRA_LINE_H := 36.0
const BG_COLOR := Color(0.03, 0.03, 0.08, 0.75)
const PANEL_COLOR := Color(0.12, 0.10, 0.18)
const BORDER_LIGHT := Color(1.0, 0.85, 0.4)
const BORDER_SHADOW := Color(0.4, 0.3, 0.1)
const TITLE_COLOR := Color(1.0, 0.95, 0.5)
const NAME_COLOR := Color(1.0, 1.0, 1.0)
const DESC_COLOR := Color(0.85, 0.85, 0.95)
const HINT_COLOR := Color(0.6, 0.6, 0.7)

var _bg: ColorRect = null
var _panel: Control = null
var _hint: Label = null
var _dismissable: bool = false
var _dismissing: bool = false
var _icon: Control = null  # the TextureRect, or the emblem Label when the reveal has no sprite


## Programmatic dismiss (a cutscene skip): the same fade as a press, safe before the reveal is dismissable and safe to call twice.
func dismiss() -> void:
	if _dismissing or _panel == null or not is_instance_valid(_panel):
		return
	_dismiss()


## A frozen "Press A" is true on one pad family and names another button on the rest; resolve the physical cap through InputProfileManager like the dialogue boxes do.
## ⛔ NO PAD, NO CAP. `glyph_for_action` answers an EMPTY device name out of the xbox table, so a
## keyboard-only player was told "Press Ⓑ / Z" — a glyph for hardware they do not have, in a
## family they may not own. Same guard as `DialogueChoiceMenu.pad_token` one file over.
static func continue_hint_text(device_name: String = "") -> String:
	if device_name == "" and Input.get_connected_joypads().is_empty():
		return "Press Z to continue"
	var cap := "A"
	if InputProfileManager:
		cap = InputProfileManager.glyph_for_action("ui_accept", device_name)
	return "Press %s / Z to continue" % cap


## The name the INVENTORY will show for this id, or "" when the id is unknown or ItemSystem is absent
## (headless tests, a mid-cutscene reveal of an item that was never registered).
static func _canonical_name(item_id: String) -> String:
	if item_id == "" or not ItemSystem:
		return ""
	if not ItemSystem.has_method("get_item"):
		return ""
	var data = ItemSystem.get_item(item_id)
	if not (data is Dictionary):
		return ""
	return str((data as Dictionary).get("name", ""))


## Emblem for a reveal with no sprite (all 21 authored grant_item steps): a glyph the font chain already proves, keyed on the item's ItemSystem category so the slot is never a blank band.
const EMBLEM_BY_CATEGORY := {0: "♦", 1: "▲", 2: "♥", 3: "⚔", 4: "✦"}
const EMBLEM_DEFAULT := "★"
static func emblem_glyph(item_id: String) -> String:
	if ItemSystem and ItemSystem.has_method("get_item"):
		var item: Dictionary = ItemSystem.get_item(item_id)
		if not item.is_empty() and item.has("category"):
			return EMBLEM_BY_CATEGORY.get(int(item["category"]), EMBLEM_DEFAULT)
	return EMBLEM_DEFAULT


static func show_item(parent: Node, item: Dictionary) -> KeyItemPopup:
	var popup := KeyItemPopup.new()
	popup.layer = 95
	if parent and is_instance_valid(parent):
		parent.add_child(popup)
	popup._present(item)
	return popup


func _present(item: Dictionary) -> void:
	var vp_size := Vector2(1280, 720)
	var vp := get_viewport()
	if vp:
		vp_size = vp.get_visible_rect().size
		if vp_size.x <= 0:
			vp_size = Vector2(1280, 720)

	# Dim background
	_bg = ColorRect.new()
	_bg.color = BG_COLOR
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)

	# A divergent reveal carries one extra line, so the CARD grows by one line rather than the
	# description sliding under it. EXTRA_LINE_H is the measured height of that label (a font-11
	# Label clamps to ~34px with the theme's margins, not to its font size).
	var bag_name: String = _canonical_name(str(item.get("item_id", "")))
	var shown_name: String = str(item.get("name", ""))
	var show_bag: bool = bag_name != "" \
		and bag_name.strip_edges().to_lower() != shown_name.strip_edges().to_lower()
	var panel_h: float = PANEL_H + (EXTRA_LINE_H if show_bag else 0.0)

	# Panel
	_panel = Control.new()
	_panel.size = Vector2(PANEL_W, panel_h)
	_panel.position = Vector2((vp_size.x - PANEL_W) / 2.0, (vp_size.y - panel_h) / 2.0 - 20)
	add_child(_panel)

	var panel_bg := ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(panel_bg)
	RetroPanel.add_border(_panel, _panel.size, BORDER_LIGHT, BORDER_SHADOW)

	# Title
	var title := Label.new()
	title.text = "Key Item Obtained!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 16)
	title.size = Vector2(PANEL_W, 28)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	_panel.add_child(title)

	# Item sprite (optional)
	var sprite_y := 56.0
	var sprite_path := str(item.get("sprite_path", ""))
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		var tex := load(sprite_path) as Texture2D
		if tex:
			var sprite_rect := TextureRect.new()
			sprite_rect.texture = tex
			## expand_mode BEFORE size — otherwise a sprite larger than 96 clamps the
			## 96 back up to the texture's own size and overflows the panel.
			sprite_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			sprite_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			sprite_rect.size = Vector2(96, 96)
			sprite_rect.position = Vector2((PANEL_W - 96) / 2.0, sprite_y)
			_panel.add_child(sprite_rect)
			_icon = sprite_rect
	if _icon == null:
		# No sprite (every authored reveal today): an emblem in the slot instead of a blank band under the title.
		var emblem := Label.new()
		emblem.text = emblem_glyph(str(item.get("item_id", "")))
		emblem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		emblem.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		emblem.position = Vector2((PANEL_W - 96) / 2.0, sprite_y)
		emblem.size = Vector2(96, 96)
		emblem.add_theme_font_size_override("font_size", 64)
		emblem.add_theme_color_override("font_color", BORDER_LIGHT)
		_panel.add_child(emblem)
		_icon = emblem

	# Name
	var name_label := Label.new()
	name_label.text = str(item.get("name", "???"))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(0, 160)
	name_label.size = Vector2(PANEL_W, 24)
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", NAME_COLOR)
	_panel.add_child(name_label)

	# ⛔ 16 of the 21 authored reveals announce a name items.json does not use — "Arbiter's Final
	# Paper" for `arbiter_grade_fragment`, whose canonical name is "Grade Fragment". All 16 are
	# CATEGORY 4 key items and ItemsMenu lists every category but OFFENSIVE, so the player is told one
	# name at the reveal and shown another in the bag, on the only two surfaces that name the thing.
	# WHICH name is canonical is cowir-story's call; that the player can FIND it is not. So when the
	# two differ, the bag's name goes under the flavour name — and this line DISAPPEARS on its own if
	# the names are ever aligned, because equal names render nothing.
	var desc_y := 188.0
	if show_bag:
		var bag := Label.new()
		bag.text = "In your bag: %s" % bag_name
		bag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bag.position = Vector2(0, 184)
		bag.size = Vector2(PANEL_W, EXTRA_LINE_H)
		bag.add_theme_font_size_override("font_size", 11)
		bag.add_theme_color_override("font_color", HINT_COLOR)
		_panel.add_child(bag)
		desc_y = 184.0 + EXTRA_LINE_H

	# Description
	var desc := Label.new()
	desc.text = str(item.get("description", ""))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.position = Vector2(20, desc_y)
	desc.size = Vector2(PANEL_W - 40, 44.0)
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", DESC_COLOR)
	_panel.add_child(desc)

	# Hint
	var hint := Label.new()
	hint.text = continue_hint_text()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(0, panel_h - 22.0)
	hint.size = Vector2(PANEL_W, 18)
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", HINT_COLOR)
	_panel.add_child(hint)
	_hint = hint

	# Entrance tween
	_panel.scale = Vector2(0.85, 0.85)
	_panel.modulate.a = 0.0
	_bg.modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_bg, "modulate:a", 1.0, 0.2)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.25).set_ease(Tween.EASE_OUT)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func(): _dismissable = true).set_delay(0.3)

	# Stinger
	if SoundManager and SoundManager.has_method("play_ui"):
		SoundManager.play_pickup("item_obtain")


func _input(event: InputEvent) -> void:
	if not _dismissable:
		return
	# Dismiss on A / B / Esc / left-click / right-click — anywhere is fine,
	# this is a notification not a choice. (Audit 2026-05-04: pre-fix had
	# only ui_accept/ui_cancel — mouse-only players had no way to dismiss.)
	var dismiss_pressed := event.is_action_pressed("ui_accept") \
		or event.is_action_pressed("ui_cancel")
	if not dismiss_pressed and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			dismiss_pressed = true
	if dismiss_pressed:
		_dismiss()
		get_viewport().set_input_as_handled()


func _dismiss() -> void:
	_dismissable = false
	_dismissing = true
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_bg, "modulate:a", 0.0, 0.2)
	tween.tween_property(_panel, "modulate:a", 0.0, 0.2)
	tween.tween_property(_panel, "scale", Vector2(0.9, 0.9), 0.2)
	await tween.finished
	dismissed.emit()
	queue_free()
