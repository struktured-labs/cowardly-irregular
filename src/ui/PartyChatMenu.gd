extends Control

## PartyChatMenu
##
## Full-screen modal listing all currently available party chats
## grouped by world. D-pad to navigate, A to play, B to close.
## Emits `closed(played_id)` so the caller can resume exploration and
## optionally re-focus state after the played cutscene finishes.

signal closed(played_id: String)

const PANEL_W := 520
const PANEL_H := 420
const ROW_H := 36
const WORLD_HEADER_H := 28
const ROW_INDENT := 20

const WORLD_NAMES := {
	1: "World 1 — Medieval",
	2: "World 2 — Suburban",
	3: "World 3 — Steampunk",
	4: "World 4 — Industrial",
	5: "World 5 — Digital",
	6: "World 6 — Abstract",
}

var _chats: Array = []        # [{id, title, world}]
var _selection: int = 0
var _scroll: ScrollContainer = null
var _rows_container: VBoxContainer = null
var _row_nodes: Array = []    # Label nodes, one per chat (not headers)
var _hint_label: Label = null
var _title_label: Label = null
var _playing: bool = false
var _cutscene_director: CutsceneDirector = null


func _ready() -> void:
	# Full-screen transparent backdrop that darkens the game beneath
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_build_panel()
	_populate()
	_highlight()


func _build_panel() -> void:
	var panel: Control = RetroPanel.create_panel(
		PANEL_W, PANEL_H,
		Color(0.06, 0.08, 0.14, 0.96),
		Color(0.7, 0.85, 1.0),
		Color(0.15, 0.2, 0.4),
	)
	# Center panel on screen
	panel.position = Vector2(
		(get_viewport_rect().size.x - PANEL_W) / 2,
		(get_viewport_rect().size.y - PANEL_H) / 2,
	)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	_title_label = Label.new()
	_title_label.text = "Party Chat"
	_title_label.position = Vector2(20, 12)
	_title_label.size = Vector2(PANEL_W - 40, 32)
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_title_label.clip_text = false
	_title_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	panel.add_child(_title_label)

	var divider := ColorRect.new()
	divider.color = Color(0.3, 0.4, 0.6, 0.8)
	divider.position = Vector2(20, 48)
	divider.size = Vector2(PANEL_W - 40, 2)
	panel.add_child(divider)

	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(12, 58)
	_scroll.size = Vector2(PANEL_W - 24, PANEL_H - 98)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_scroll)

	_rows_container = VBoxContainer.new()
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_container.add_theme_constant_override("separation", 2)
	_scroll.add_child(_rows_container)

	_hint_label = Label.new()
	_hint_label.text = "[A/Enter/Click] Play    [B/Esc/RClick] Close    (Wheel scrolls)"
	_hint_label.position = Vector2(20, PANEL_H - 32)
	_hint_label.size = Vector2(PANEL_W - 40, 24)
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.clip_text = false
	_hint_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	panel.add_child(_hint_label)


func _populate() -> void:
	_chats = PartyChatSystem.get_available_chats() if PartyChatSystem else []
	_row_nodes.clear()
	for child in _rows_container.get_children():
		child.queue_free()

	if _chats.is_empty():
		var empty := Label.new()
		empty.text = "No party chats available right now.\nProgress the story to unlock more."
		empty.add_theme_font_size_override("font_size", 16)
		empty.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(PANEL_W - 40, 80)
		_rows_container.add_child(empty)
		return

	var last_world: int = -1
	for chat in _chats:
		if chat.world != last_world:
			last_world = chat.world
			var header := Label.new()
			header.text = WORLD_NAMES.get(chat.world, "World %d" % chat.world)
			header.add_theme_font_size_override("font_size", 16)
			header.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
			header.custom_minimum_size = Vector2(0, WORLD_HEADER_H)
			_rows_container.add_child(header)
		var row := Label.new()
		row.text = "  " + chat.title
		row.add_theme_font_size_override("font_size", 18)
		row.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
		row.custom_minimum_size = Vector2(0, ROW_H)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.clip_text = false
		row.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		_rows_container.add_child(row)
		_row_nodes.append(row)
		# Mouse: hover to select, click to play
		var idx_now: int = _row_nodes.size() - 1
		var btn := Button.new()
		btn.flat = true
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.mouse_entered.connect(_on_row_hover.bind(idx_now))
		btn.pressed.connect(_on_row_click.bind(idx_now))
		row.add_child(btn)

	_selection = clamp(_selection, 0, max(0, _row_nodes.size() - 1))


func _highlight() -> void:
	for i in _row_nodes.size():
		var row: Label = _row_nodes[i]
		if not is_instance_valid(row):
			continue
		if i == _selection:
			row.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
			row.text = "▸ " + _chats[i].title
		else:
			row.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
			row.text = "  " + _chats[i].title
	# Controller-first: D-pad past the visible window must scroll the container. Without this the highlight moves off-screen and the mouse-only scrollbar becomes the only way to catch up (struktured playtest msg 2802).
	_ensure_selection_visible()


func _ensure_selection_visible() -> void:
	if _scroll == null or not is_instance_valid(_scroll):
		return
	if _selection < 0 or _selection >= _row_nodes.size():
		return
	var row: Label = _row_nodes[_selection]
	if not is_instance_valid(row):
		return
	_scroll.ensure_control_visible(row)


func _input(event: InputEvent) -> void:
	if _playing:
		return
	# Right-click cancel works whether the list is empty or not
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_close("")
		get_viewport().set_input_as_handled()
		return
	if _chats.is_empty():
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("party_chat"):
			_close("")
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_up"):
		_selection = (_selection - 1 + _row_nodes.size()) % _row_nodes.size()
		_highlight()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_selection = (_selection + 1) % _row_nodes.size()
		_highlight()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_play_selected()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("party_chat"):
		_close("")
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		# Mouse wheel = move selection
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_selection = (_selection - 1 + _row_nodes.size()) % _row_nodes.size()
			_highlight()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_selection = (_selection + 1) % _row_nodes.size()
			_highlight()
			get_viewport().set_input_as_handled()


func _on_row_hover(idx: int) -> void:
	if idx < 0 or idx >= _row_nodes.size():
		return
	if idx == _selection:
		return
	_selection = idx
	_highlight()
	if SoundManager:
		SoundManager.play_ui("menu_move")


func _on_row_click(idx: int) -> void:
	if idx < 0 or idx >= _row_nodes.size():
		return
	_selection = idx
	_highlight()
	# Click is "play" — same as gamepad A / keyboard Enter
	_play_selected()


func _play_selected() -> void:
	if _selection < 0 or _selection >= _chats.size():
		return
	var chat = _chats[_selection]
	_playing = true
	var cutscene_id: String = chat.id

	if not _cutscene_director:
		_cutscene_director = CutsceneDirector.new()
		add_child(_cutscene_director)
	# Hide panel while cutscene plays so it doesn't overlay the scene
	visible = false
	_cutscene_director.cutscene_finished.connect(
		func(_id: String):
			PartyChatSystem.mark_viewed(cutscene_id)
			_close(cutscene_id),
		CONNECT_ONE_SHOT,
	)
	_cutscene_director.play_cutscene(cutscene_id)


func _close(played_id: String) -> void:
	closed.emit(played_id)
	queue_free()
