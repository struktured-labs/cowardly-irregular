extends CanvasLayer
class_name CutsceneGallery

## CutsceneGallery — replay unlocked cutscenes from the overworld menu.
## Shows a list of cutscenes the player has seen, grouped by world.
## Selecting one replays it. Meta-aware: the game knows you're rewatching.
##
## Unlocked cutscenes are tracked via cutscene_flag_* in GameState.

signal gallery_closed()
signal cutscene_selected(cutscene_id: String)

const TILE_SIZE: int = 4

var _panel: Control
var _title_label: Label
var _world_tabs: Array[Label] = []
var _item_labels: Array[Label] = []
var _items: Array[Dictionary] = []  # [{id, title, world, unlocked}]
var _selected_world: int = 1
var _selected_index: int = 0
var _active: bool = false
var _bg: ColorRect


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func open() -> void:
	"""Open the gallery, scan for unlocked cutscenes."""
	_items.clear()
	_scan_cutscenes()
	_build_ui()
	_active = true
	visible = true
	_update_display()


func close() -> void:
	_active = false
	visible = false
	# Clean up UI children
	for child in get_children():
		child.queue_free()
	_world_tabs.clear()
	_item_labels.clear()
	gallery_closed.emit()


func _scan_cutscenes() -> void:
	"""Scan cutscene files and check which are unlocked."""
	var dir = DirAccess.open("res://data/cutscenes")
	if not dir:
		return

	var files: Array[String] = []
	dir.list_dir_begin()
	var file = dir.get_next()
	while file != "":
		if file.ends_with(".json") and not file.begins_with("."):
			files.append(file)
		file = dir.get_next()
	dir.list_dir_end()
	files.sort()

	for filename in files:
		var path = "res://data/cutscenes/" + filename
		var f = FileAccess.open(path, FileAccess.READ)
		if not f:
			continue
		var json = JSON.new()
		if json.parse(f.get_as_text()) != OK:
			continue
		var data = json.data
		if not data is Dictionary:
			continue

		var id = data.get("id", "")
		var title = data.get("title", filename.replace(".json", ""))
		var world = data.get("world", 0)

		# Skip non-story cutscenes (guidance hints, NPC chatter)
		if "guidance" in id or "encounter" in id:
			continue

		# Check if unlocked — cutscene sets a flag when completed
		var unlocked = false
		for step in data.get("steps", []):
			if step.get("type") == "set_flag":
				var flag = step.get("flag", "")
				if flag != "" and GameState:
					if GameState.game_constants.get("cutscene_flag_" + flag, false):
						unlocked = true
						break

		_items.append({
			"id": id,
			"title": title,
			"world": world,
			"unlocked": unlocked,
		})


func _build_ui() -> void:
	# Clean old UI
	for child in get_children():
		child.queue_free()
	_world_tabs.clear()
	_item_labels.clear()

	var screen_size = get_viewport().get_visible_rect().size

	# Background
	_bg = ColorRect.new()
	_bg.color = Color(0.05, 0.04, 0.08, 0.95)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	# Title
	_title_label = Label.new()
	_title_label.text = "Cutscene Gallery"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.position = Vector2(0, 16)
	_title_label.size = Vector2(screen_size.x, 30)
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_label)

	# World tabs
	var world_names = {1: "Medieval", 2: "Suburban", 3: "Steampunk", 4: "Industrial", 5: "Digital", 6: "Abstract"}
	var tab_x = 80.0
	for w in range(1, 7):
		var tab = Label.new()
		tab.text = "W%d: %s" % [w, world_names.get(w, "?")]
		tab.position = Vector2(tab_x, 52)
		tab.add_theme_font_size_override("font_size", 13)
		tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tab)
		_world_tabs.append(tab)
		tab_x += 180.0

	# Item list area
	var list_y = 85.0
	for i in range(12):  # Max visible items
		var label = Label.new()
		label.position = Vector2(100, list_y + i * 24)
		label.size = Vector2(screen_size.x - 200, 22)
		label.add_theme_font_size_override("font_size", 14)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		_item_labels.append(label)

	# Instructions
	var hint = Label.new()
	hint.text = "L/R: Change World  |  Up/Down: Select  |  A: Replay  |  B: Close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(0, screen_size.y - 30)
	hint.size = Vector2(screen_size.x, 20)
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)


func _get_world_items() -> Array:
	var result: Array = []
	for item in _items:
		if item["world"] == _selected_world:
			result.append(item)
	return result


func _update_display() -> void:
	# Update world tabs
	for i in range(_world_tabs.size()):
		var tab = _world_tabs[i]
		if i + 1 == _selected_world:
			tab.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
		else:
			tab.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))

	# Update item list
	var world_items = _get_world_items()
	for i in range(_item_labels.size()):
		var label = _item_labels[i]
		if i < world_items.size():
			var item = world_items[i]
			if item["unlocked"]:
				var prefix = "> " if i == _selected_index else "  "
				label.text = prefix + item["title"]
				if i == _selected_index:
					label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
				else:
					label.add_theme_color_override("font_color", Color(0.7, 0.68, 0.6))
			else:
				label.text = "  ??? (locked)"
				label.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3))
			label.visible = true
		else:
			label.visible = false


func _input(event: InputEvent) -> void:
	if not _active:
		return

	var world_items = _get_world_items()

	if event.is_action_pressed("ui_cancel"):
		if SoundManager:
			SoundManager.play_ui("menu_select")
		close()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_up"):
		_selected_index = maxi(_selected_index - 1, 0)
		if SoundManager:
			SoundManager.play_ui("menu_move")
		_update_display()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down"):
		_selected_index = mini(_selected_index + 1, world_items.size() - 1)
		if SoundManager:
			SoundManager.play_ui("menu_move")
		_update_display()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_left") or event.is_action_pressed("shoulder_left"):
		_selected_world = maxi(_selected_world - 1, 1)
		_selected_index = 0
		if SoundManager:
			SoundManager.play_ui("menu_move")
		_update_display()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_right") or event.is_action_pressed("shoulder_right"):
		_selected_world = mini(_selected_world + 1, 6)
		_selected_index = 0
		if SoundManager:
			SoundManager.play_ui("menu_move")
		_update_display()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_accept"):
		if _selected_index < world_items.size():
			var item = world_items[_selected_index]
			if item["unlocked"]:
				if SoundManager:
					SoundManager.play_ui("menu_select")
				close()
				cutscene_selected.emit(item["id"])
		get_viewport().set_input_as_handled()
