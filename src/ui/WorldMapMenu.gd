extends Control
class_name WorldMapMenu

## WorldMapMenu — shows discovered worlds, current location, completion %.
## Accessible from the overworld menu (Start → World Map).
## Display-only: no teleporting from here (that's the debug teleport menu).

signal closed()

const WORLD_DATA := [
	{"id": 1, "name": "The Old Kingdom",  "theme": "Medieval",   "color": Color(0.6, 0.85, 0.5)},
	{"id": 2, "name": "The Mundane Sprawl","theme": "Suburban",  "color": Color(0.9, 0.8, 0.5)},
	{"id": 3, "name": "The Clockwork",     "theme": "Steampunk", "color": Color(0.7, 0.55, 0.35)},
	{"id": 4, "name": "The Assembly",       "theme": "Industrial","color": Color(0.55, 0.55, 0.65)},
	{"id": 5, "name": "The Network",        "theme": "Digital",  "color": Color(0.4, 0.75, 1.0)},
	{"id": 6, "name": "The Vertex",         "theme": "Abstract", "color": Color(0.85, 0.6, 0.95)},
]

## Flags that represent key progression within a world.
## Each flag present = +1 towards completion.
const PROGRESS_FLAGS := {
	1: ["cutscene_flag_prologue_complete", "cutscene_flag_chapter1_complete",
		"cutscene_flag_chapter3_complete", "cutscene_flag_rat_king_defeated",
		"cutscene_flag_chapter4_complete", "cutscene_flag_chapter9_complete",
		"cutscene_flag_world1_mordaine_defeated"],
	2: ["cutscene_flag_world2_prologue_complete", "cutscene_flag_world2_chapter1_complete",
		"cutscene_flag_world2_chapter2_complete", "cutscene_flag_world2_chapter3_complete",
		"cutscene_flag_arbiter_suburban_defeated", "cutscene_flag_curator_suburban_defeated",
		"cutscene_flag_chapter11_complete"],
	3: ["cutscene_flag_world3_prologue_complete", "cutscene_flag_world3_chapter1_complete",
		"cutscene_flag_world3_chapter2_complete", "cutscene_flag_world3_chapter3_complete",
		"cutscene_flag_warden_industrial_defeated", "cutscene_flag_world3_chapter5_complete"],
	4: ["cutscene_flag_world4_prologue_complete", "cutscene_flag_world4_chapter1_complete",
		"cutscene_flag_world4_chapter2_complete", "cutscene_flag_world4_chapter3_complete",
		"cutscene_flag_world4_chapter4_complete", "cutscene_flag_world4_chapter5_complete"],
	5: ["cutscene_flag_world5_prologue_complete", "cutscene_flag_world5_chapter1_complete",
		"cutscene_flag_world5_chapter2_complete", "cutscene_flag_world5_chapter3_complete",
		"cutscene_flag_world5_chapter4_complete", "cutscene_flag_world5_chapter5_complete"],
	6: ["cutscene_flag_world6_prologue_complete", "cutscene_flag_world6_chapter1_complete",
		"cutscene_flag_world6_chapter2_complete", "cutscene_flag_world6_chapter3_complete"],
}

const BG_COLOR := Color(0.04, 0.04, 0.08, 0.95)
const PANEL_COLOR := Color(0.08, 0.08, 0.14)
const BORDER_LIGHT := Color(0.65, 0.75, 0.9)
const BORDER_SHADOW := Color(0.2, 0.25, 0.4)
const TEXT_COLOR := Color(0.9, 0.95, 1.0)
const DIM_COLOR := Color(0.5, 0.55, 0.7)
const LOCKED_COLOR := Color(0.3, 0.3, 0.4)

var _selected: int = 0
var _world_cards: Array[Control] = []
var _current_world: int = 1


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	_current_world = _detect_current_world()
	_build_ui()
	_highlight()


func _detect_current_world() -> int:
	"""Determine current world from story flags — last world with prologue complete."""
	if not GameState:
		return 1
	var flags: Dictionary = GameState.game_constants
	var w := 1
	for world_id in range(6, 0, -1):
		var prologue_flag := "cutscene_flag_world%d_prologue_complete" % world_id
		if world_id == 1:
			prologue_flag = "cutscene_flag_prologue_complete"
		if flags.get(prologue_flag, false):
			w = world_id
			break
	return w


func _is_world_unlocked(world_id: int) -> bool:
	if not GameState:
		return world_id == 1
	if world_id == 1:
		return true
	var prev_complete := "cutscene_flag_world%d_complete" % (world_id - 1)
	if world_id == 2:
		prev_complete = "cutscene_flag_world1_mordaine_defeated"
	return GameState.game_constants.get(prev_complete, false)


func _get_completion(world_id: int) -> Vector2i:
	"""Returns (done, total) for a world's progress flags."""
	var flags: Array = PROGRESS_FLAGS.get(world_id, [])
	if flags.is_empty():
		return Vector2i(0, 0)
	var done := 0
	for flag in flags:
		if GameState and GameState.game_constants.get(flag, false):
			done += 1
	return Vector2i(done, flags.size())


func _build_ui() -> void:
	for child in get_children():
		child.queue_free()
	_world_cards.clear()

	var vp := get_viewport_rect().size
	if vp.x <= 0:
		vp = Vector2(1280, 720)

	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)

	# Header
	var header := Label.new()
	header.text = "World Map"
	header.position = Vector2(24, 16)
	header.size = Vector2(300, 32)
	header.add_theme_font_size_override("font_size", 26)
	header.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	header.clip_text = false
	header.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	add_child(header)

	# Build world cards — 2 columns, 3 rows
	var card_w := int((vp.x - 72) / 2)
	var card_h := 82
	var gap := 12
	var start_x := 24
	var start_y := 64

	for i in WORLD_DATA.size():
		var world: Dictionary = WORLD_DATA[i]
		var col: int = i % 2
		var row: int = i / 2
		var card := _build_card(world, Vector2(card_w, card_h))
		card.position = Vector2(
			start_x + col * (card_w + gap),
			start_y + row * (card_h + gap),
		)
		add_child(card)
		_world_cards.append(card)

	# Current location
	var loc := Label.new()
	var loc_name := "Unknown"
	if MapSystem and MapSystem.has_method("get_current_location_name"):
		loc_name = MapSystem.get_current_location_name()
	loc.text = "Current: World %d — %s" % [_current_world, loc_name]
	loc.position = Vector2(24, vp.y - 56)
	loc.size = Vector2(vp.x - 48, 20)
	loc.add_theme_font_size_override("font_size", 14)
	loc.add_theme_color_override("font_color", DIM_COLOR)
	add_child(loc)

	# Footer
	var footer := Label.new()
	footer.text = "↑↓←→: Select   B / Esc: Close"
	footer.position = Vector2(24, vp.y - 32)
	footer.size = Vector2(vp.x - 48, 20)
	footer.add_theme_font_size_override("font_size", 13)
	footer.add_theme_color_override("font_color", DIM_COLOR)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(footer)

	_selected = clamp(_current_world - 1, 0, WORLD_DATA.size() - 1)


func _build_card(world: Dictionary, sz: Vector2) -> Control:
	var world_id: int = world.id
	var unlocked: bool = _is_world_unlocked(world_id)
	var completion: Vector2i = _get_completion(world_id) if unlocked else Vector2i(0, 0)
	var pct: int = int(float(completion.x) / float(max(completion.y, 1)) * 100.0)
	var is_current: bool = world_id == _current_world

	var card := Control.new()
	card.custom_minimum_size = sz
	card.size = sz

	# Background
	var bg := ColorRect.new()
	bg.name = "CardBG"
	bg.color = PANEL_COLOR
	bg.size = sz
	card.add_child(bg)

	# Bevel
	for edge in [
		{"pos": Vector2(0, 0), "size": Vector2(sz.x, 2), "color": BORDER_LIGHT},
		{"pos": Vector2(0, 0), "size": Vector2(2, sz.y), "color": BORDER_LIGHT},
		{"pos": Vector2(0, sz.y - 2), "size": Vector2(sz.x, 2), "color": BORDER_SHADOW},
		{"pos": Vector2(sz.x - 2, 0), "size": Vector2(2, sz.y), "color": BORDER_SHADOW},
	]:
		var r := ColorRect.new()
		r.color = edge.color
		r.position = edge.pos
		r.size = edge.size
		card.add_child(r)

	# Color accent bar (left edge)
	var accent := ColorRect.new()
	accent.color = world.color if unlocked else LOCKED_COLOR
	accent.position = Vector2(2, 2)
	accent.size = Vector2(6, sz.y - 4)
	card.add_child(accent)

	# World number + name
	var title := Label.new()
	if unlocked:
		title.text = "W%d  %s" % [world_id, world.name]
	else:
		title.text = "W%d  ???" % world_id
	title.position = Vector2(16, 8)
	title.size = Vector2(sz.x - 32, 24)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", TEXT_COLOR if unlocked else LOCKED_COLOR)
	title.clip_text = false
	title.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	card.add_child(title)

	# Theme subtitle
	var sub := Label.new()
	sub.text = world.theme if unlocked else "Locked"
	sub.position = Vector2(16, 34)
	sub.size = Vector2(sz.x - 32, 18)
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", DIM_COLOR if unlocked else LOCKED_COLOR)
	card.add_child(sub)

	# Progress bar + percentage
	if unlocked and completion.y > 0:
		var bar_w: float = sz.x - 100
		var bar_x: float = 16
		var bar_y: float = 58

		var bar_bg := ColorRect.new()
		bar_bg.color = Color(0.15, 0.15, 0.2)
		bar_bg.position = Vector2(bar_x, bar_y)
		bar_bg.size = Vector2(bar_w, 10)
		card.add_child(bar_bg)

		var bar_fill := ColorRect.new()
		bar_fill.color = world.color.darkened(0.2)
		bar_fill.position = Vector2(bar_x, bar_y)
		bar_fill.size = Vector2(bar_w * float(completion.x) / float(completion.y), 10)
		card.add_child(bar_fill)

		var pct_label := Label.new()
		pct_label.text = "%d%%" % pct
		pct_label.position = Vector2(bar_x + bar_w + 8, bar_y - 4)
		pct_label.size = Vector2(60, 18)
		pct_label.add_theme_font_size_override("font_size", 14)
		pct_label.add_theme_color_override("font_color", TEXT_COLOR)
		card.add_child(pct_label)

	# Current world indicator
	if is_current:
		var marker := Label.new()
		marker.text = "YOU ARE HERE"
		marker.position = Vector2(sz.x - 140, 10)
		marker.size = Vector2(120, 18)
		marker.add_theme_font_size_override("font_size", 11)
		marker.add_theme_color_override("font_color", world.color)
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		card.add_child(marker)

	return card


func _highlight() -> void:
	for i in _world_cards.size():
		var card: Control = _world_cards[i]
		var bg: ColorRect = card.get_node_or_null("CardBG")
		if bg:
			if i == _selected:
				bg.color = Color(0.14, 0.18, 0.28)
			else:
				bg.color = PANEL_COLOR


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
		return

	var cols := 2
	var rows := 3
	var old := _selected

	if event.is_action_pressed("ui_up"):
		if _selected >= cols:
			_selected -= cols
	elif event.is_action_pressed("ui_down"):
		if _selected + cols < WORLD_DATA.size():
			_selected += cols
	elif event.is_action_pressed("ui_left"):
		if _selected % cols > 0:
			_selected -= 1
	elif event.is_action_pressed("ui_right"):
		if _selected % cols < cols - 1 and _selected + 1 < WORLD_DATA.size():
			_selected += 1

	if _selected != old:
		_highlight()
		if SoundManager:
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()


func _close() -> void:
	if SoundManager:
		SoundManager.play_ui("menu_close")
	closed.emit()
	queue_free()
