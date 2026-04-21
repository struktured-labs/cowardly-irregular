extends Control
class_name BestiaryMenu

## BestiaryMenu — discovered-monster viewer accessible from OverworldMenu.
## Left pane: scrollable list of seen monsters sorted by level.
## Right pane: idle sprite + stats + flavor text.
## D-pad to navigate, B to close.

signal closed()

const BG_COLOR := Color(0.05, 0.05, 0.1, 0.95)
const PANEL_COLOR := Color(0.1, 0.1, 0.15)
const BORDER_LIGHT := RetroPanel.BORDER_LIGHT
const BORDER_SHADOW := RetroPanel.BORDER_SHADOW
const HIGHLIGHT_COLOR := Color(0.2, 0.3, 0.5)
const TEXT_COLOR := Color(1.0, 1.0, 1.0)
const DIM_COLOR := Color(0.6, 0.65, 0.75)
const ACCENT := Color(0.6, 0.85, 1.0)

var _entries: Array = []  # from BestiarySystem.get_seen_entries_sorted()
var _selected: int = 0
var _row_nodes: Array = []

var _list_container: VBoxContainer = null
var _detail_name: Label = null
var _detail_epithet: Label = null
var _detail_level: Label = null
var _detail_stats: Label = null
var _detail_weak: Label = null
var _detail_resist: Label = null
var _detail_flavor: Label = null
var _detail_sprite: AnimatedSprite2D = null
var _detail_sprite_bg: ColorRect = null
var _detail_placeholder: Label = null
var _count_label: Label = null


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	_entries = BestiarySystem.get_seen_entries_sorted()
	_build_ui()
	_refresh_detail()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)

	var viewport := get_viewport_rect().size
	if viewport.x == 0:
		viewport = Vector2(1280, 720)

	# Title + count in top bar
	var header := Label.new()
	header.text = "Bestiary"
	header.position = Vector2(24, 16)
	header.size = Vector2(300, 32)
	header.add_theme_font_size_override("font_size", 26)
	header.add_theme_color_override("font_color", ACCENT)
	header.clip_text = false
	header.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	add_child(header)

	var counts: Vector2i = BestiarySystem.discovery_counts()
	_count_label = Label.new()
	_count_label.text = "%d / %d discovered" % [counts.x, counts.y]
	_count_label.position = Vector2(viewport.x - 260, 22)
	_count_label.size = Vector2(240, 24)
	_count_label.add_theme_font_size_override("font_size", 16)
	_count_label.add_theme_color_override("font_color", DIM_COLOR)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.clip_text = false
	_count_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	add_child(_count_label)

	# Left panel: monster list
	var list_panel := _make_panel(Vector2(24, 64), Vector2(viewport.x * 0.35, viewport.y - 112))
	add_child(list_panel)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(12, 12)
	scroll.size = list_panel.size - Vector2(24, 24)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_panel.add_child(scroll)

	_list_container = VBoxContainer.new()
	_list_container.size_flags_horizontal = SIZE_EXPAND_FILL
	_list_container.add_theme_constant_override("separation", 2)
	scroll.add_child(_list_container)

	_populate_list()

	# Right panel: detail view
	var detail_x: float = viewport.x * 0.38 + 24
	var detail_panel := _make_panel(
		Vector2(detail_x, 64),
		Vector2(viewport.x - detail_x - 24, viewport.y - 112),
	)
	add_child(detail_panel)

	_build_detail(detail_panel)

	# Footer
	var footer := Label.new()
	footer.text = "↑↓: Select   B / Esc: Close"
	footer.position = Vector2(24, viewport.y - 32)
	footer.size = Vector2(viewport.x - 48, 24)
	footer.add_theme_font_size_override("font_size", 14)
	footer.add_theme_color_override("font_color", DIM_COLOR)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(footer)


func _make_panel(pos: Vector2, sz: Vector2) -> Control:
	var panel := Control.new()
	panel.position = pos
	panel.custom_minimum_size = sz
	panel.size = sz

	var bg := ColorRect.new()
	bg.color = PANEL_COLOR
	bg.set_anchors_preset(PRESET_FULL_RECT)
	panel.add_child(bg)

	# Bevel borders
	for edge in [
		{"pos": Vector2(0, 0), "size": Vector2(sz.x, 2), "color": BORDER_LIGHT},
		{"pos": Vector2(0, 0), "size": Vector2(2, sz.y), "color": BORDER_LIGHT},
		{"pos": Vector2(0, sz.y - 2), "size": Vector2(sz.x, 2), "color": BORDER_SHADOW},
		{"pos": Vector2(sz.x - 2, 0), "size": Vector2(2, sz.y), "color": BORDER_SHADOW},
	]:
		var rect := ColorRect.new()
		rect.color = edge.color
		rect.position = edge.pos
		rect.size = edge.size
		panel.add_child(rect)

	return panel


func _populate_list() -> void:
	for child in _list_container.get_children():
		child.queue_free()
	_row_nodes.clear()

	if _entries.is_empty():
		var empty := Label.new()
		empty.text = "No monsters discovered yet.\nEncounter them in battle to fill the Bestiary."
		empty.add_theme_font_size_override("font_size", 15)
		empty.add_theme_color_override("font_color", DIM_COLOR)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(0, 80)
		_list_container.add_child(empty)
		return

	for entry in _entries:
		var row := Label.new()
		row.text = "  Lv %d  %s" % [entry.level, entry.name]
		row.add_theme_font_size_override("font_size", 17)
		row.add_theme_color_override("font_color", TEXT_COLOR)
		row.custom_minimum_size = Vector2(0, 28)
		row.clip_text = false
		row.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		_list_container.add_child(row)
		_row_nodes.append(row)

	_selected = clamp(_selected, 0, _row_nodes.size() - 1)
	_highlight_row()


func _highlight_row() -> void:
	for i in _row_nodes.size():
		var row: Label = _row_nodes[i]
		if not is_instance_valid(row):
			continue
		var entry: Dictionary = _entries[i]
		if i == _selected:
			row.add_theme_color_override("font_color", ACCENT)
			row.text = "▸ Lv %d  %s" % [entry.level, entry.name]
		else:
			row.add_theme_color_override("font_color", TEXT_COLOR)
			row.text = "  Lv %d  %s" % [entry.level, entry.name]


func _build_detail(parent: Control) -> void:
	var margin := 20
	var sprite_size := 180

	# Sprite preview background square (upper-left of detail panel)
	_detail_sprite_bg = ColorRect.new()
	_detail_sprite_bg.color = Color(0.02, 0.03, 0.08, 0.8)
	_detail_sprite_bg.position = Vector2(margin, margin)
	_detail_sprite_bg.size = Vector2(sprite_size, sprite_size)
	parent.add_child(_detail_sprite_bg)

	_detail_sprite = AnimatedSprite2D.new()
	_detail_sprite.position = _detail_sprite_bg.position + _detail_sprite_bg.size * 0.5
	parent.add_child(_detail_sprite)

	_detail_placeholder = Label.new()
	_detail_placeholder.text = "?"
	_detail_placeholder.position = _detail_sprite_bg.position
	_detail_placeholder.size = _detail_sprite_bg.size
	_detail_placeholder.add_theme_font_size_override("font_size", 96)
	_detail_placeholder.add_theme_color_override("font_color", Color(0.35, 0.4, 0.5))
	_detail_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_detail_placeholder.visible = false
	parent.add_child(_detail_placeholder)

	var text_x: float = margin + sprite_size + 20
	var text_w: float = parent.size.x - text_x - margin

	_detail_name = Label.new()
	_detail_name.position = Vector2(text_x, margin)
	_detail_name.size = Vector2(text_w, 32)
	_detail_name.add_theme_font_size_override("font_size", 24)
	_detail_name.add_theme_color_override("font_color", ACCENT)
	_detail_name.clip_text = false
	_detail_name.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	parent.add_child(_detail_name)

	_detail_epithet = Label.new()
	_detail_epithet.position = Vector2(text_x, margin + 32)
	_detail_epithet.size = Vector2(text_w, 22)
	_detail_epithet.add_theme_font_size_override("font_size", 15)
	_detail_epithet.add_theme_color_override("font_color", DIM_COLOR)
	_detail_epithet.clip_text = false
	_detail_epithet.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	parent.add_child(_detail_epithet)

	_detail_level = Label.new()
	_detail_level.position = Vector2(text_x, margin + 58)
	_detail_level.size = Vector2(text_w, 22)
	_detail_level.add_theme_font_size_override("font_size", 14)
	_detail_level.add_theme_color_override("font_color", TEXT_COLOR)
	_detail_level.clip_text = false
	_detail_level.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	parent.add_child(_detail_level)

	_detail_stats = Label.new()
	_detail_stats.position = Vector2(text_x, margin + 86)
	_detail_stats.size = Vector2(text_w, 48)
	_detail_stats.add_theme_font_size_override("font_size", 14)
	_detail_stats.add_theme_color_override("font_color", TEXT_COLOR)
	_detail_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(_detail_stats)

	_detail_weak = Label.new()
	_detail_weak.position = Vector2(text_x, margin + 140)
	_detail_weak.size = Vector2(text_w, 24)
	_detail_weak.add_theme_font_size_override("font_size", 14)
	_detail_weak.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
	_detail_weak.clip_text = false
	_detail_weak.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	parent.add_child(_detail_weak)

	_detail_resist = Label.new()
	_detail_resist.position = Vector2(text_x, margin + 164)
	_detail_resist.size = Vector2(text_w, 24)
	_detail_resist.add_theme_font_size_override("font_size", 14)
	_detail_resist.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	_detail_resist.clip_text = false
	_detail_resist.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	parent.add_child(_detail_resist)

	# Flavor text sits below the sprite & stats, full width
	_detail_flavor = Label.new()
	_detail_flavor.position = Vector2(margin, margin + sprite_size + 20)
	_detail_flavor.size = Vector2(parent.size.x - margin * 2, parent.size.y - sprite_size - margin * 3 - 12)
	_detail_flavor.add_theme_font_size_override("font_size", 15)
	_detail_flavor.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	_detail_flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_flavor.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	parent.add_child(_detail_flavor)


func _refresh_detail() -> void:
	if _entries.is_empty() or _selected < 0 or _selected >= _entries.size():
		_detail_name.text = ""
		_detail_epithet.text = ""
		_detail_level.text = ""
		_detail_stats.text = ""
		_detail_weak.text = ""
		_detail_resist.text = ""
		_detail_flavor.text = ""
		_detail_sprite.visible = false
		_detail_placeholder.visible = true
		return

	var entry: Dictionary = _entries[_selected]
	_detail_name.text = entry.name
	_detail_epithet.text = entry.epithet if entry.epithet != "" else ""
	_detail_level.text = "Level %d" % entry.level

	var stats: Dictionary = entry.stats
	_detail_stats.text = "HP %d   MP %d   ATK %d   DEF %d   MAG %d   SPD %d" % [
		stats.get("max_hp", 0),
		stats.get("max_mp", 0),
		stats.get("attack", 0),
		stats.get("defense", 0),
		stats.get("magic", 0),
		stats.get("speed", 0),
	]

	_detail_weak.text = "Weak: %s" % (", ".join(entry.weaknesses) if not entry.weaknesses.is_empty() else "—")
	_detail_resist.text = "Resist: %s" % (", ".join(entry.resistances) if not entry.resistances.is_empty() else "—")
	_detail_flavor.text = entry.flavor if entry.flavor != "" else "(No lore entry written yet.)"

	_load_sprite(entry.id)


func _load_sprite(monster_id: String) -> void:
	var frames: SpriteFrames = HybridSpriteLoader.load_monster_sprite_frames(monster_id)
	if frames == null or frames.get_animation_names().size() == 0:
		_detail_sprite.visible = false
		_detail_placeholder.visible = true
		return

	_detail_sprite.sprite_frames = frames
	var anim := "idle" if frames.has_animation("idle") else frames.get_animation_names()[0]
	_detail_sprite.animation = anim
	_detail_sprite.play(anim)

	# Scale to fit the 180px preview box while preserving aspect
	var tex: Texture2D = frames.get_frame_texture(anim, 0)
	if tex:
		var sz := tex.get_size()
		var max_dim: float = max(sz.x, sz.y)
		if max_dim > 0:
			var target: float = 160.0
			var scale: float = target / max_dim
			_detail_sprite.scale = Vector2(scale, scale)
	_detail_sprite.visible = true
	_detail_placeholder.visible = false


func _input(event: InputEvent) -> void:
	if _entries.is_empty():
		if event.is_action_pressed("ui_cancel"):
			_close()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_up"):
		_selected = (_selected - 1 + _row_nodes.size()) % _row_nodes.size()
		_highlight_row()
		_refresh_detail()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_selected = (_selected + 1) % _row_nodes.size()
		_highlight_row()
		_refresh_detail()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	closed.emit()
	queue_free()
