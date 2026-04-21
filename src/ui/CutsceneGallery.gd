extends Control
class_name CutsceneGallery

## Theater — replay any previously-seen cutscene from the overworld menu.
## (File keeps its legacy class name for save/compat, but the displayed UI
## and menu entry are both "Theater".)
##
## Discovery tracking: a cutscene's `set_flag` step names the flag it sets
## on completion. We look up `cutscene_flag_<flag>` in GameState and show
## the entry only when that flag is true. Story-internal guidance hints
## and NPC chatter are excluded.
##
## Replay: selecting an entry plays the cutscene inline via CutsceneDirector
## and returns focus to the Theater when it finishes.

signal closed()

const BG_COLOR := Color(0.05, 0.04, 0.08, 0.95)
const PANEL_COLOR := Color(0.1, 0.1, 0.15)
const BORDER_LIGHT := RetroPanel.BORDER_LIGHT
const BORDER_SHADOW := RetroPanel.BORDER_SHADOW
const TEXT_COLOR := Color(1.0, 1.0, 1.0)
const DIM_COLOR := Color(0.55, 0.55, 0.65)
const ACCENT := Color(1.0, 0.92, 0.55)
const LOCKED_COLOR := Color(0.3, 0.3, 0.35)

const WORLD_NAMES := {
	1: "Medieval", 2: "Suburban", 3: "Steampunk",
	4: "Industrial", 5: "Digital", 6: "Abstract",
}

var _items_by_world: Dictionary = {}     # int world -> Array[{id,title,unlocked}]
var _world_order: Array = []             # ascending list of worlds that have entries
var _selected_world_idx: int = 0
var _selected_item_idx: int = 0

var _world_tabs: Array[Label] = []
var _item_rows: Array[Label] = []
var _title_label: Label
var _count_label: Label
var _footer: Label
var _item_scroll: ScrollContainer
var _item_container: VBoxContainer
var _playing: bool = false
var _cutscene_director: Node = null


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	_scan_cutscenes()
	_build_ui()
	_update_display()


func _scan_cutscenes() -> void:
	_items_by_world.clear()
	_world_order.clear()

	var dir := DirAccess.open("res://data/cutscenes")
	if dir == null:
		return

	var files: Array[String] = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".json") and not fname.begins_with("."):
			files.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	files.sort()

	for filename in files:
		var path := "res://data/cutscenes/" + filename
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var json := JSON.new()
		if json.parse(f.get_as_text()) != OK:
			continue
		if not (json.data is Dictionary):
			continue
		var data: Dictionary = json.data
		var id: String = data.get("id", "")
		var title: String = data.get("title", filename.replace(".json", ""))
		var world: int = data.get("world", 0)

		if id == "" or world <= 0:
			continue
		# Guidance hints + encounter barks aren't story beats
		if "guidance" in id or "encounter" in id or "npcs" in id:
			continue

		var unlocked := false
		for step in data.get("steps", []):
			if step.get("type") == "set_flag":
				var flag: String = step.get("flag", "")
				if flag != "" and GameState.game_constants.get("cutscene_flag_" + flag, false):
					unlocked = true
					break

		if not _items_by_world.has(world):
			_items_by_world[world] = []
		_items_by_world[world].append({
			"id": id,
			"title": title,
			"unlocked": unlocked,
		})

	_world_order = _items_by_world.keys()
	_world_order.sort()


func _build_ui() -> void:
	for child in get_children():
		child.queue_free()
	_world_tabs.clear()
	_item_rows.clear()

	var viewport := get_viewport_rect().size
	if viewport.x == 0:
		viewport = Vector2(1280, 720)

	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)

	_title_label = Label.new()
	_title_label.text = "Theater"
	_title_label.position = Vector2(24, 16)
	_title_label.size = Vector2(300, 32)
	_title_label.add_theme_font_size_override("font_size", 26)
	_title_label.add_theme_color_override("font_color", ACCENT)
	_title_label.clip_text = false
	_title_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	add_child(_title_label)

	_count_label = Label.new()
	_count_label.position = Vector2(viewport.x - 260, 22)
	_count_label.size = Vector2(240, 24)
	_count_label.add_theme_font_size_override("font_size", 15)
	_count_label.add_theme_color_override("font_color", DIM_COLOR)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.clip_text = false
	_count_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	add_child(_count_label)

	# World tab row
	var tab_x := 24.0
	for w in _world_order:
		var tab := Label.new()
		tab.text = "W%d · %s" % [w, WORLD_NAMES.get(w, "?")]
		tab.position = Vector2(tab_x, 56)
		tab.add_theme_font_size_override("font_size", 14)
		tab.clip_text = false
		tab.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		add_child(tab)
		_world_tabs.append(tab)
		tab_x += 150.0

	# Scrollable list
	_item_scroll = ScrollContainer.new()
	_item_scroll.position = Vector2(24, 92)
	_item_scroll.size = Vector2(viewport.x - 48, viewport.y - 92 - 40)
	_item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_item_scroll)

	_item_container = VBoxContainer.new()
	_item_container.size_flags_horizontal = SIZE_EXPAND_FILL
	_item_container.add_theme_constant_override("separation", 4)
	_item_scroll.add_child(_item_container)

	_footer = Label.new()
	_footer.text = "←/→: World   ↑/↓: Select   A: Replay   B: Close"
	_footer.position = Vector2(24, viewport.y - 32)
	_footer.size = Vector2(viewport.x - 48, 20)
	_footer.add_theme_font_size_override("font_size", 13)
	_footer.add_theme_color_override("font_color", DIM_COLOR)
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_footer)


func _populate_items() -> void:
	for child in _item_container.get_children():
		child.queue_free()
	_item_rows.clear()

	if _world_order.is_empty():
		var empty := Label.new()
		empty.text = "No cutscenes available — play through the story to unlock entries."
		empty.add_theme_font_size_override("font_size", 15)
		empty.add_theme_color_override("font_color", DIM_COLOR)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(0, 80)
		_item_container.add_child(empty)
		return

	var world: int = _world_order[_selected_world_idx]
	var items: Array = _items_by_world.get(world, [])

	for i in items.size():
		var entry: Dictionary = items[i]
		var row := Label.new()
		row.custom_minimum_size = Vector2(0, 28)
		row.add_theme_font_size_override("font_size", 17)
		row.clip_text = false
		row.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		_item_container.add_child(row)
		_item_rows.append(row)


func _update_display() -> void:
	# Count unlocked across all worlds
	var total := 0
	var unlocked := 0
	for world_items in _items_by_world.values():
		for item in world_items:
			total += 1
			if item.unlocked:
				unlocked += 1
	_count_label.text = "%d / %d unlocked" % [unlocked, total]

	# Tab highlighting
	for i in _world_tabs.size():
		var tab: Label = _world_tabs[i]
		if i == _selected_world_idx:
			tab.add_theme_color_override("font_color", ACCENT)
		else:
			tab.add_theme_color_override("font_color", DIM_COLOR)

	# Populate rows fresh each world change
	_populate_items()

	if _world_order.is_empty():
		return

	var world: int = _world_order[_selected_world_idx]
	var items: Array = _items_by_world.get(world, [])
	_selected_item_idx = clamp(_selected_item_idx, 0, max(0, items.size() - 1))

	for i in items.size():
		var entry: Dictionary = items[i]
		var row: Label = _item_rows[i]
		if not entry.unlocked:
			row.text = "  ??? (locked)"
			row.add_theme_color_override("font_color", LOCKED_COLOR)
			continue
		if i == _selected_item_idx:
			row.text = "▸ %s" % entry.title
			row.add_theme_color_override("font_color", ACCENT)
		else:
			row.text = "  %s" % entry.title
			row.add_theme_color_override("font_color", TEXT_COLOR)


func _current_entry() -> Dictionary:
	if _world_order.is_empty():
		return {}
	var world: int = _world_order[_selected_world_idx]
	var items: Array = _items_by_world.get(world, [])
	if _selected_item_idx < 0 or _selected_item_idx >= items.size():
		return {}
	return items[_selected_item_idx]


func _input(event: InputEvent) -> void:
	if _playing:
		return

	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
		return

	if _world_order.is_empty():
		return

	if event.is_action_pressed("ui_left"):
		_selected_world_idx = (_selected_world_idx - 1 + _world_order.size()) % _world_order.size()
		_selected_item_idx = 0
		_update_display()
		_play_nav_sfx()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_selected_world_idx = (_selected_world_idx + 1) % _world_order.size()
		_selected_item_idx = 0
		_update_display()
		_play_nav_sfx()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		var world_items: Array = _items_by_world.get(_world_order[_selected_world_idx], [])
		if not world_items.is_empty():
			_selected_item_idx = (_selected_item_idx - 1 + world_items.size()) % world_items.size()
			_update_display()
			_play_nav_sfx()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		var world_items: Array = _items_by_world.get(_world_order[_selected_world_idx], [])
		if not world_items.is_empty():
			_selected_item_idx = (_selected_item_idx + 1) % world_items.size()
			_update_display()
			_play_nav_sfx()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_try_replay_selected()
		get_viewport().set_input_as_handled()


func _play_nav_sfx() -> void:
	if SoundManager:
		SoundManager.play_ui("menu_move")


func _try_replay_selected() -> void:
	var entry := _current_entry()
	if entry.is_empty() or not entry.get("unlocked", false):
		return
	if SoundManager:
		SoundManager.play_ui("menu_select")
	_playing = true
	visible = false

	if _cutscene_director == null:
		var CutsceneDirectorClass = load("res://src/cutscene/CutsceneDirector.gd")
		_cutscene_director = CutsceneDirectorClass.new()
		add_child(_cutscene_director)

	_cutscene_director.cutscene_finished.connect(
		func(_id: String):
			_playing = false
			visible = true,
		CONNECT_ONE_SHOT,
	)
	_cutscene_director.play_cutscene(entry.id)


func _close() -> void:
	if SoundManager:
		SoundManager.play_ui("menu_select")
	closed.emit()
	queue_free()
