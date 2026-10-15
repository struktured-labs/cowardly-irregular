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
## The description's band, and the font it is measured at. Named because panel_h, the band and
## the hint's offset all have to agree, and three bare numbers in three places is how they stop.
const DESC_BAND_H := 44.0
const DESC_FONT_SIZE := 12
## The card's six font sites at 100%. Named so a Text Size guard reads what each one SHOULD draw
## at a preset rather than keeping its own copy of these numbers; every site passes its base
## through TextScale.scaled, which is what makes the card follow the player's setting.
const TITLE_FONT_SIZE := 20
const NAME_FONT_SIZE := 18
const BAG_FONT_SIZE := 11
const HINT_FONT_SIZE := 10
const EMBLEM_FONT_SIZE := 64
## The gutter the card keeps from the screen edge when Text Size grows it. The card is centred, so
## one number bounds the layout scale on both axes.
const VP_MARGIN := 16.0
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
		return "Press %s to continue" % CutsceneDialogue.confirm_key()
	var cap := "A"
	if InputProfileManager:
		cap = InputProfileManager.glyph_for_action("ui_accept", device_name)
	return "Press %s / %s to continue" % [cap, CutsceneDialogue.confirm_key()]


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


## The Text Size multiplier itself. `TextScale.scaled` rounds to an int, so it is sampled at a
## large base to keep the ratio exact. Same shape as VictoryOverlay._raw_text_scale.
func _raw_text_scale() -> float:
	return float(TextScale.scaled(1000)) / 1000.0


## Height of `text` wrapped into `width` at `font_size`, measured with the label's OWN resolved
## theme font — a throwaway Label is parented to this popup first, so the chain is the one the real
## description will have inside the panel rather than a default. 0.0 for empty text or no font.
func _measure_desc(text: String, width: float, font_size: int) -> float:
	if text == "":
		return 0.0
	var probe := Label.new()
	probe.add_theme_font_size_override("font_size", font_size)
	add_child(probe)
	var out := 0.0
	var pf: Font = probe.get_theme_font("font")
	if pf != null:
		out = pf.get_multiline_string_size(
			text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size).y
	remove_child(probe)
	probe.queue_free()
	return out


## How much the CARD may grow. Only ever GROWS, like VictoryOverlay's result cards: at 80% Text Size
## the card is pixel-identical to before this change and only its text gets smaller, so 100% and
## below are untouched.
##
## The cap is the point of the function. At 200% an uncapped card is 880px wide before the
## description is measured, and on a 640x360 web viewport that is wider than the screen — so fixing
## a text overflow would push the card's own border off the display.
##
## ⛔ `needed_h` IS THE CARD'S FULL HEIGHT AT 1.0, NOT `PANEL_H`, and the difference is a real hole
## rather than a refinement. The description's growth is added AFTER the scale is chosen, so a cap
## against the base 260 lets the longest authored description at 200% land past the bottom of the
## screen — the card would be clamped to the top margin and lose its own continue hint instead.
## Growth is very nearly LINEAR in the scale, because the font and the wrap width scale TOGETHER:
## the line count holds and each line's height scales, so the full height at g is about g times the
## height at 1.0. That is the quantity worth capping, and it is why this takes an argument.
func _layout_scale(vp_size: Vector2, needed_h: float) -> float:
	var want: float = maxf(1.0, _raw_text_scale())
	var cap: float = minf(
		(vp_size.x - 2.0 * VP_MARGIN) / PANEL_W,
		(vp_size.y - 2.0 * VP_MARGIN) / maxf(1.0, needed_h))
	return clampf(want, 1.0, maxf(1.0, cap))


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
	## ⛔ THE CARD GROWS FOR A LONG DESCRIPTION TOO, AND IT HAS TO BE MEASURED BEFORE THE PANEL
	## EXISTS — RetroPanel.add_border draws from _panel.size at construction, so growing the
	## panel afterwards leaves the border behind. The description band used to be a flat 44px with
	## the continue hint pinned at panel_h - 22; the longest authored key-item description is 245
	## characters, which wraps to four lines, overruns the band and is drawn THROUGH the hint and
	## past the card's bottom border. Rendered at 1280x720 the last line and "[Z] Continue" sit on
	## top of each other. Both numbers now scale with Text Size, and the band still has to be
	## measured up front for the same reason. `_measure_desc` does the measuring.
	var desc_text: String = str(item.get("description", ""))

	## TEXT SIZE, resolved here because it needs the CONTENT. `g` scales the GEOMETRY and every font
	## goes through TextScale — both halves, because TextScale.apply_tree's own docstring says it
	## cannot do the second one: "re-scaling text is not re-scaling a LAYOUT". Every band on this card
	## is a literal, so scaling only the fonts would grow the text inside bands that stayed put, which
	## is the collision this card was already fixed for once.
	##
	## Measured at 1.0 FIRST so the cap sees the card's real height, then again at the chosen scale
	## so the band the description is compared against has scaled too — comparing a grown font with
	## the flat 44px band would read every description as an overflow and grow the card twice.
	var base_desc_h: float = maxf(DESC_BAND_H,
		_measure_desc(desc_text, PANEL_W - 40.0, DESC_FONT_SIZE))
	var needed_h: float = PANEL_H + (EXTRA_LINE_H if show_bag else 0.0) \
		+ (base_desc_h - DESC_BAND_H)
	var g := _layout_scale(vp_size, needed_h)
	var panel_w: float = PANEL_W * g

	var desc_font: int = TextScale.scaled(DESC_FONT_SIZE)
	var band_h: float = DESC_BAND_H * g
	var desc_h: float = maxf(band_h,
		_measure_desc(desc_text, panel_w - 40.0 * g, desc_font))
	var panel_h: float = PANEL_H * g + (EXTRA_LINE_H * g if show_bag else 0.0) + (desc_h - band_h)

	# Panel
	_panel = Control.new()
	_panel.size = Vector2(panel_w, panel_h)
	## Clamped to the margin, TOP FIRST AND BOTTOM LAST, and the order is the whole point.
	##
	## The content-aware cap already keeps `panel_h` inside `vp.y - 2*VP_MARGIN`, so for every card
	## that fits, the top clamp is all that is needed — it only ever absorbs the `-20*g` nudge, which
	## at 200% is enough on its own to centre a tall card above the screen edge.
	##
	## ⛔ BUT A TOP-ONLY CLAMP MAKES THE ONE CASE IT CANNOT FIX STRICTLY WORSE, and I shipped that
	## before measuring it. When the card is taller than the screen (only reachable below the g >= 1
	## floor, with a description longer than any authored), pinning the top pushes the BOTTOM off —
	## and the bottom is where the continue hint lives, so the player loses the one line telling them
	## how to dismiss a card that now looks stuck. Measured on 640x360 with a 140px description:
	## centred was top=-18 bottom=338 (hint visible, top border clipped); top-pinned was top=16
	## bottom=372 (hint GONE). Cutting the title is cosmetic; cutting the hint is functional.
	##
	## So the bottom clamp is applied second and wins: an oversized card gives up its top border to
	## keep its hint, which is also what the unclamped original happened to do.
	var panel_y: float = maxf(VP_MARGIN, (vp_size.y - panel_h) / 2.0 - 20.0 * g)
	panel_y = minf(panel_y, vp_size.y - VP_MARGIN - panel_h)
	_panel.position = Vector2(maxf(VP_MARGIN, (vp_size.x - panel_w) / 2.0), panel_y)
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
	title.position = Vector2(0, 16.0 * g)
	title.size = Vector2(panel_w, 28.0 * g)
	title.add_theme_font_size_override("font_size", TextScale.scaled(TITLE_FONT_SIZE))
	title.add_theme_color_override("font_color", TITLE_COLOR)
	_panel.add_child(title)

	# Item sprite (optional)
	var sprite_y := 56.0 * g
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
			sprite_rect.size = Vector2(96, 96) * g
			sprite_rect.position = Vector2((panel_w - 96.0 * g) / 2.0, sprite_y)
			_panel.add_child(sprite_rect)
			_icon = sprite_rect
	if _icon == null:
		var icon_tex := ItemIcons.tinted(str(item.get("item_id", "")))
		if icon_tex:
			var icon_rect := TextureRect.new()
			icon_rect.name = "ItemIcon"
			icon_rect.texture = icon_tex
			icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.size = Vector2(64, 64) * g
			icon_rect.position = Vector2((panel_w - 64.0 * g) / 2.0, sprite_y + 16.0 * g)
			_panel.add_child(icon_rect)
			_icon = icon_rect
	if _icon == null:
		# No sprite and no icon texture: an emblem in the slot instead of a blank band under the title.
		var emblem := Label.new()
		emblem.text = emblem_glyph(str(item.get("item_id", "")))
		emblem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		emblem.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		emblem.position = Vector2((panel_w - 96.0 * g) / 2.0, sprite_y)
		emblem.size = Vector2(96, 96) * g
		emblem.add_theme_font_size_override("font_size", TextScale.scaled(EMBLEM_FONT_SIZE))
		emblem.add_theme_color_override("font_color", BORDER_LIGHT)
		_panel.add_child(emblem)
		_icon = emblem

	# Name
	var name_label := Label.new()
	name_label.text = str(item.get("name", "???"))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(0, 160.0 * g)
	name_label.size = Vector2(panel_w, 24.0 * g)
	name_label.add_theme_font_size_override("font_size", TextScale.scaled(NAME_FONT_SIZE))
	name_label.add_theme_color_override("font_color", NAME_COLOR)
	_panel.add_child(name_label)

	# ⛔ 16 of the 21 authored reveals announce a name items.json does not use — "Arbiter's Final
	# Paper" for `arbiter_grade_fragment`, whose canonical name is "Grade Fragment". All 16 are
	# CATEGORY 4 key items and ItemsMenu lists every category but OFFENSIVE, so the player is told one
	# name at the reveal and shown another in the bag, on the only two surfaces that name the thing.
	# WHICH name is canonical is cowir-story's call; that the player can FIND it is not. So when the
	# two differ, the bag's name goes under the flavour name — and this line DISAPPEARS on its own if
	# the names are ever aligned, because equal names render nothing.
	var desc_y := 188.0 * g
	if show_bag:
		var bag := Label.new()
		bag.text = "In your bag: %s" % bag_name
		bag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bag.position = Vector2(0, 184.0 * g)
		bag.size = Vector2(panel_w, EXTRA_LINE_H * g)
		bag.add_theme_font_size_override("font_size", TextScale.scaled(BAG_FONT_SIZE))
		bag.add_theme_color_override("font_color", HINT_COLOR)
		_panel.add_child(bag)
		desc_y = (184.0 + EXTRA_LINE_H) * g

	# Description
	var desc := Label.new()
	desc.text = str(item.get("description", ""))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.position = Vector2(20.0 * g, desc_y)
	desc.size = Vector2(panel_w - 40.0 * g, desc_h)
	desc.add_theme_font_size_override("font_size", desc_font)
	desc.add_theme_color_override("font_color", DESC_COLOR)
	_panel.add_child(desc)

	# Hint
	var hint := Label.new()
	hint.text = continue_hint_text()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(0, panel_h - 22.0 * g)
	hint.size = Vector2(panel_w, 18.0 * g)
	hint.add_theme_font_size_override("font_size", TextScale.scaled(HINT_FONT_SIZE))
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
