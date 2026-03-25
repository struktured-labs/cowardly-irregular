extends CanvasLayer
class_name CutsceneDialogue

## CutsceneDialogue - General-purpose dialogue box for cutscenes.
## Adapted from BattleDialogue but works in any context.
## Supports NPC themes, narrator mode, party member portraits, and await-based sequencing.

signal dialogue_finished()
signal dialogue_advanced()

## Dialogue queue
var _dialogue_queue: Array = []
var _current_index: int = 0
var _is_typing: bool = false
var _typing_speed: float = 0.03
var _current_text: String = ""
var _displayed_chars: int = 0
var _typing_timer: Timer

## UI Elements
var _background: ColorRect
var _dialogue_box: Control
var _portrait_frame: Control
var _portrait_image: TextureRect
var _speaker_label: Label
var _text_label: RichTextLabel
var _advance_hint: Label

## Styling
const TILE_SIZE = 4
const BOX_HEIGHT = 120
const PORTRAIT_SIZE = 80
const MARGIN = 16

## Character color themes - extended for cutscene NPCs
const CHARACTER_THEMES = {
	"hero": {
		"bg": Color(0.1, 0.1, 0.25),
		"border": Color(0.7, 0.7, 1.0),
		"text": Color(1.0, 1.0, 1.0),
		"name": Color(0.5, 0.7, 1.0),
		"portrait_bg": Color(0.15, 0.15, 0.35)
	},
	"fighter": {
		"bg": Color(0.1, 0.1, 0.25),
		"border": Color(0.7, 0.7, 1.0),
		"text": Color(1.0, 1.0, 1.0),
		"name": Color(0.5, 0.7, 1.0),
		"portrait_bg": Color(0.15, 0.15, 0.35)
	},
	"cleric": {
		"bg": Color(0.15, 0.1, 0.2),
		"border": Color(1.0, 0.8, 0.9),
		"text": Color(1.0, 0.95, 1.0),
		"name": Color(1.0, 0.7, 0.85),
		"portrait_bg": Color(0.2, 0.1, 0.25)
	},
	"healer": {
		"bg": Color(0.15, 0.1, 0.2),
		"border": Color(1.0, 0.8, 0.9),
		"text": Color(1.0, 0.95, 1.0),
		"name": Color(1.0, 0.7, 0.85),
		"portrait_bg": Color(0.2, 0.1, 0.25)
	},
	"rogue": {
		"bg": Color(0.08, 0.08, 0.12),
		"border": Color(0.6, 0.5, 0.7),
		"text": Color(0.9, 0.85, 1.0),
		"name": Color(0.7, 0.9, 0.5),
		"portrait_bg": Color(0.1, 0.1, 0.15)
	},
	"mage": {
		"bg": Color(0.05, 0.0, 0.12),
		"border": Color(0.6, 0.3, 0.8),
		"text": Color(0.85, 0.75, 1.0),
		"name": Color(0.9, 0.5, 0.9),
		"portrait_bg": Color(0.08, 0.02, 0.15)
	},
	"bard": {
		"bg": Color(0.12, 0.08, 0.02),
		"border": Color(0.9, 0.75, 0.4),
		"text": Color(1.0, 0.95, 0.85),
		"name": Color(1.0, 0.85, 0.4),
		"portrait_bg": Color(0.15, 0.1, 0.05)
	},
	"narrator": {
		"bg": Color(0.02, 0.02, 0.05),
		"border": Color(0.4, 0.4, 0.5),
		"text": Color(0.8, 0.8, 0.85),
		"name": Color(0.6, 0.6, 0.7),
		"portrait_bg": Color(0.05, 0.05, 0.08)
	},
	"elder": {
		"bg": Color(0.1, 0.08, 0.05),
		"border": Color(0.7, 0.6, 0.4),
		"text": Color(1.0, 0.95, 0.85),
		"name": Color(0.85, 0.75, 0.5),
		"portrait_bg": Color(0.12, 0.1, 0.06)
	},
	"scholar": {
		"bg": Color(0.05, 0.08, 0.1),
		"border": Color(0.4, 0.7, 0.8),
		"text": Color(0.9, 0.95, 1.0),
		"name": Color(0.5, 0.85, 0.95),
		"portrait_bg": Color(0.06, 0.1, 0.12)
	},
	"merchant": {
		"bg": Color(0.08, 0.1, 0.05),
		"border": Color(0.6, 0.8, 0.4),
		"text": Color(0.95, 1.0, 0.9),
		"name": Color(0.7, 0.9, 0.4),
		"portrait_bg": Color(0.1, 0.12, 0.06)
	},
	"shopkeeper": {
		"bg": Color(0.1, 0.08, 0.04),
		"border": Color(0.8, 0.65, 0.3),
		"text": Color(1.0, 0.95, 0.85),
		"name": Color(0.9, 0.75, 0.35),
		"portrait_bg": Color(0.12, 0.1, 0.05)
	},
	"mysterious": {
		"bg": Color(0.03, 0.02, 0.06),
		"border": Color(0.5, 0.3, 0.6),
		"text": Color(0.85, 0.8, 0.95),
		"name": Color(0.7, 0.5, 0.9),
		"portrait_bg": Color(0.05, 0.03, 0.08)
	},
	"enemy": {
		"bg": Color(0.15, 0.05, 0.05),
		"border": Color(0.8, 0.3, 0.3),
		"text": Color(1.0, 0.9, 0.9),
		"name": Color(1.0, 0.5, 0.4),
		"portrait_bg": Color(0.2, 0.08, 0.08)
	},
	"goblin": {
		"bg": Color(0.08, 0.1, 0.04),
		"border": Color(0.5, 0.7, 0.3),
		"text": Color(0.9, 1.0, 0.85),
		"name": Color(0.6, 0.85, 0.3),
		"portrait_bg": Color(0.1, 0.12, 0.05)
	},
	"system": {
		"bg": Color(0.0, 0.02, 0.05),
		"border": Color(0.0, 0.6, 0.4),
		"text": Color(0.0, 1.0, 0.7),
		"name": Color(0.0, 0.8, 0.5),
		"portrait_bg": Color(0.0, 0.03, 0.06)
	}
}


func _ready() -> void:
	layer = 96  # Above CutsceneDirector (95), below transitions (100)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_typing_timer()
	_build_ui()
	visible = false


func _exit_tree() -> void:
	if _typing_timer and is_instance_valid(_typing_timer):
		_typing_timer.stop()


func _setup_typing_timer() -> void:
	_typing_timer = Timer.new()
	_typing_timer.one_shot = false
	_typing_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_typing_timer.timeout.connect(_on_typing_tick)
	add_child(_typing_timer)


func _build_ui() -> void:
	# Semi-transparent overlay (dimmer than battle - cutscenes are more immersive)
	_background = ColorRect.new()
	_background.color = Color(0, 0, 0, 0.3)
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.size = get_viewport().get_visible_rect().size
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	# Calculate positions
	var screen_size = get_viewport().get_visible_rect().size
	var box_width = screen_size.x - MARGIN * 2
	var box_y = screen_size.y - BOX_HEIGHT - MARGIN

	# Main dialogue container
	_dialogue_box = Control.new()
	_dialogue_box.position = Vector2(MARGIN, box_y)
	_dialogue_box.size = Vector2(box_width, BOX_HEIGHT)
	add_child(_dialogue_box)

	# Create initial empty state
	_create_dialogue_visuals(CHARACTER_THEMES["narrator"])


func _create_dialogue_visuals(theme: Dictionary) -> void:
	for child in _dialogue_box.get_children():
		child.queue_free()

	var box_width = _dialogue_box.size.x
	var box_height = _dialogue_box.size.y

	# Box background
	var box_bg = ColorRect.new()
	box_bg.color = theme["bg"]
	box_bg.size = Vector2(box_width, box_height)
	_dialogue_box.add_child(box_bg)

	# Border (pixel-tile style)
	_draw_retro_border(_dialogue_box, box_width, box_height, theme["border"])

	# Portrait frame (left side)
	_portrait_frame = Control.new()
	_portrait_frame.position = Vector2(TILE_SIZE * 2, TILE_SIZE * 2)
	_portrait_frame.size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_dialogue_box.add_child(_portrait_frame)

	var portrait_bg = ColorRect.new()
	portrait_bg.color = theme["portrait_bg"]
	portrait_bg.size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_portrait_frame.add_child(portrait_bg)

	_draw_retro_border(_portrait_frame, PORTRAIT_SIZE, PORTRAIT_SIZE, theme["border"].darkened(0.2))

	# Enable clipping so large artist portraits don't overflow the frame
	_portrait_frame.clip_contents = true

	# Portrait image
	_portrait_image = TextureRect.new()
	_portrait_image.position = Vector2(4, 4)
	_portrait_image.size = Vector2(PORTRAIT_SIZE - 8, PORTRAIT_SIZE - 8)
	_portrait_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_frame.add_child(_portrait_image)

	# Text area (right of portrait)
	var text_x = PORTRAIT_SIZE + TILE_SIZE * 4
	var text_width = box_width - text_x - TILE_SIZE * 3

	# Speaker name
	_speaker_label = Label.new()
	_speaker_label.position = Vector2(text_x, TILE_SIZE * 2)
	_speaker_label.add_theme_font_size_override("font_size", 14)
	_speaker_label.add_theme_color_override("font_color", theme["name"])
	_dialogue_box.add_child(_speaker_label)

	# Dialogue text
	_text_label = RichTextLabel.new()
	_text_label.position = Vector2(text_x, TILE_SIZE * 2 + 20)
	_text_label.size = Vector2(text_width, box_height - TILE_SIZE * 4 - 30)
	_text_label.bbcode_enabled = true
	_text_label.scroll_active = false
	_text_label.add_theme_font_size_override("normal_font_size", 13)
	_text_label.add_theme_color_override("default_color", theme["text"])
	_dialogue_box.add_child(_text_label)

	# Advance hint
	_advance_hint = Label.new()
	_advance_hint.text = "Z / A to continue..."
	_advance_hint.position = Vector2(box_width - 140, box_height - 20)
	_advance_hint.add_theme_font_size_override("font_size", 10)
	_advance_hint.add_theme_color_override("font_color", theme["text"].darkened(0.4))
	_advance_hint.visible = false
	_dialogue_box.add_child(_advance_hint)


func _draw_retro_border(parent: Control, width: float, height: float, color: Color) -> void:
	var shadow_color = color.darkened(0.5)

	var top = ColorRect.new()
	top.color = color
	top.position = Vector2(0, 0)
	top.size = Vector2(width, TILE_SIZE)
	parent.add_child(top)

	var bottom = ColorRect.new()
	bottom.color = shadow_color
	bottom.position = Vector2(0, height - TILE_SIZE)
	bottom.size = Vector2(width, TILE_SIZE)
	parent.add_child(bottom)

	var left = ColorRect.new()
	left.color = color
	left.position = Vector2(0, 0)
	left.size = Vector2(TILE_SIZE, height)
	parent.add_child(left)

	var right = ColorRect.new()
	right.color = shadow_color
	right.position = Vector2(width - TILE_SIZE, 0)
	right.size = Vector2(TILE_SIZE, height)
	parent.add_child(right)

	var inner_top = ColorRect.new()
	inner_top.color = color.lightened(0.3)
	inner_top.position = Vector2(TILE_SIZE, TILE_SIZE)
	inner_top.size = Vector2(width - TILE_SIZE * 2, 1)
	parent.add_child(inner_top)

	var inner_left = ColorRect.new()
	inner_left.color = color.lightened(0.3)
	inner_left.position = Vector2(TILE_SIZE, TILE_SIZE)
	inner_left.size = Vector2(1, height - TILE_SIZE * 2)
	parent.add_child(inner_left)


## =====================
## PUBLIC API
## =====================

func show_dialogue(dialogue_lines: Array) -> void:
	_dialogue_queue = dialogue_lines
	_current_index = 0
	visible = true
	_show_current_line()


func skip_all() -> void:
	"""Immediately finish all dialogue (for cutscene skip)."""
	_finish_dialogue()


## =====================
## DIALOGUE FLOW
## =====================

func _show_current_line() -> void:
	if _current_index >= _dialogue_queue.size():
		_finish_dialogue()
		return

	var entry = _dialogue_queue[_current_index]
	var theme_name = entry.get("theme", "narrator")
	var theme = CHARACTER_THEMES.get(theme_name, CHARACTER_THEMES["narrator"])

	_create_dialogue_visuals(theme)

	_speaker_label.text = entry.get("speaker", "")

	# Set portrait
	var portrait_type = entry.get("portrait", theme_name)
	_portrait_image.texture = _create_portrait(portrait_type)

	# Hide portrait frame for narrator (no-portrait mode)
	var hide_portrait = entry.get("hide_portrait", false)
	if portrait_type == "narrator" and entry.get("speaker", "") == "":
		hide_portrait = true

	if hide_portrait:
		_portrait_frame.visible = false
		# Expand text area to use full width
		var text_x = TILE_SIZE * 4
		var box_width = _dialogue_box.size.x
		_speaker_label.position.x = text_x
		_text_label.position.x = text_x
		_text_label.size.x = box_width - text_x - TILE_SIZE * 3
	else:
		_portrait_frame.visible = true

	# Start typing effect
	_current_text = entry.get("text", "")
	_displayed_chars = 0
	_text_label.text = ""
	_advance_hint.visible = false
	_is_typing = true
	_typing_timer.start(_typing_speed)


func _on_typing_tick() -> void:
	if not is_instance_valid(self) or not is_instance_valid(_text_label):
		return

	if _displayed_chars < _current_text.length():
		_displayed_chars += 1
		_text_label.text = _current_text.substr(0, _displayed_chars)

		if _displayed_chars % 3 == 0 and SoundManager:
			SoundManager.play_ui("menu_move")
	else:
		_finish_typing()


func _finish_typing() -> void:
	if _typing_timer and is_instance_valid(_typing_timer):
		_typing_timer.stop()
	_is_typing = false
	if _text_label and is_instance_valid(_text_label):
		_text_label.text = _current_text
	if _advance_hint and is_instance_valid(_advance_hint):
		_advance_hint.visible = true


func _advance_dialogue() -> void:
	if _is_typing:
		_finish_typing()
	else:
		_current_index += 1
		dialogue_advanced.emit()
		_show_current_line()

	if SoundManager:
		SoundManager.play_ui("menu_select")


func _finish_dialogue() -> void:
	visible = false
	_dialogue_queue.clear()
	_current_index = 0
	dialogue_finished.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_accept"):
		_advance_dialogue()
		get_viewport().set_input_as_handled()

	# Left-click to advance dialogue
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance_dialogue()
		get_viewport().set_input_as_handled()


## =====================
## PORTRAIT LOADING / GENERATION
## =====================

## Mapping from portrait type to sprite asset paths
const PORTRAIT_SPRITES = {
	"fighter": "res://assets/sprites/portraits/fighter.png",
	"hero": "res://assets/sprites/portraits/fighter.png",
	"cleric": "res://assets/sprites/portraits/cleric.png",
	"healer": "res://assets/sprites/portraits/cleric.png",
	"mage": "res://assets/sprites/portraits/mage.png",
	"rogue": "res://assets/sprites/portraits/rogue.png",
	"bard": "res://assets/sprites/portraits/bard.png",
	"shopkeeper": "res://assets/sprites/npcs/bram.png",
	"merchant": "res://assets/sprites/npcs/bram.png",
	"scholar": "res://assets/sprites/npcs/scholar_milo.png",
}

## Cache loaded portrait textures to avoid repeated disk reads
var _portrait_cache: Dictionary = {}


func _create_portrait(portrait_type: String) -> Texture2D:
	# Try loading artist sprite portrait first
	var sprite_path = PORTRAIT_SPRITES.get(portrait_type, "")
	if sprite_path != "":
		if _portrait_cache.has(sprite_path):
			return _portrait_cache[sprite_path]
		if ResourceLoader.exists(sprite_path):
			var tex = load(sprite_path)
			if tex:
				_portrait_cache[sprite_path] = tex
				return tex

	# Fallback to procedural portrait generation
	var size = int(PORTRAIT_SIZE - 8)
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	match portrait_type:
		"hero", "fighter":
			_draw_fighter_portrait(img, size)
		"cleric", "healer":
			_draw_cleric_portrait(img, size)
		"rogue":
			_draw_rogue_portrait(img, size)
		"mage":
			_draw_mage_portrait(img, size)
		"bard":
			_draw_bard_portrait(img, size)
		"elder":
			_draw_elder_portrait(img, size)
		"scholar":
			_draw_scholar_portrait(img, size)
		"shopkeeper", "merchant":
			_draw_shopkeeper_portrait(img, size)
		"goblin":
			_draw_goblin_portrait(img, size)
		"mysterious":
			_draw_mysterious_portrait(img, size)
		"system":
			_draw_system_portrait(img, size)
		"narrator", _:
			_draw_narrator_portrait(img, size)

	return ImageTexture.create_from_image(img)


func _draw_fighter_portrait(img: Image, size: int) -> void:
	var cx = size / 2
	var cy = size / 2
	var skin = Color(0.95, 0.8, 0.7)
	var hair = Color(0.4, 0.3, 0.2)
	var eyes = Color(0.2, 0.4, 0.7)

	# Hair
	for y in range(size / 5, size / 2):
		for x in range(size / 4, size * 3 / 4):
			var dy = y - size / 3
			var dx = x - cx
			if dx * dx / 200.0 + dy * dy / 100.0 < 1.0:
				img.set_pixel(x, y, hair)

	# Face
	for y in range(size / 3, size * 4 / 5):
		for x in range(size / 4, size * 3 / 4):
			var dy = y - size / 2 - 5
			var dx = x - cx
			if dx * dx / 180.0 + dy * dy / 200.0 < 1.0:
				img.set_pixel(x, y, skin)

	# Eyes
	img.set_pixel(cx - 8, cy, eyes)
	img.set_pixel(cx - 7, cy, eyes)
	img.set_pixel(cx + 7, cy, eyes)
	img.set_pixel(cx + 8, cy, eyes)

	# Mouth
	for x in range(-5, 6):
		img.set_pixel(cx + x, cy + 12, Color(0.7, 0.4, 0.4))


func _draw_cleric_portrait(img: Image, size: int) -> void:
	var cx = size / 2
	var cy = size / 2
	var skin = Color(0.95, 0.85, 0.8)
	var hair = Color(0.9, 0.85, 0.7)
	var eyes = Color(0.4, 0.7, 0.5)
	var hood = Color(1.0, 0.95, 0.95)

	for y in range(size / 6, size * 2 / 3):
		for x in range(size / 5, size * 4 / 5):
			var dy = y - size / 3
			var dx = x - cx
			if dx * dx / 250.0 + dy * dy / 180.0 < 1.0:
				img.set_pixel(x, y, hood)

	for y in range(size / 3, size * 3 / 4):
		for x in range(size / 3, size * 2 / 3):
			var dy = y - size / 2
			var dx = x - cx
			if dx * dx / 120.0 + dy * dy / 150.0 < 1.0:
				img.set_pixel(x, y, skin)

	img.set_pixel(cx - 6, cy - 2, eyes)
	img.set_pixel(cx + 6, cy - 2, eyes)

	for x in range(-4, 5):
		img.set_pixel(cx + x, cy + 8, Color(0.8, 0.5, 0.5))


func _draw_rogue_portrait(img: Image, size: int) -> void:
	var cx = size / 2
	var cy = size / 2
	var skin = Color(0.85, 0.75, 0.65)
	var hair = Color(0.15, 0.1, 0.1)
	var eyes = Color(0.3, 0.25, 0.2)
	var bandana = Color(0.4, 0.3, 0.5)

	for y in range(size / 5, size / 3):
		for x in range(size / 5, size * 4 / 5):
			img.set_pixel(x, y, bandana)

	for y in range(size / 4, size / 2):
		for x in range(size / 5, size / 3):
			img.set_pixel(x, y, hair)

	for y in range(size / 3, size * 3 / 4):
		for x in range(size / 4, size * 3 / 4):
			var dy = y - size / 2
			var dx = x - cx
			if dx * dx / 180.0 + dy * dy / 180.0 < 1.0:
				img.set_pixel(x, y, skin)

	for x in range(-3, 0):
		img.set_pixel(cx - 7 + x, cy, eyes)
		img.set_pixel(cx + 7 + x, cy, eyes)

	for x in range(0, 6):
		img.set_pixel(cx + x, cy + 10 - x / 3, Color(0.6, 0.4, 0.4))


func _draw_mage_portrait(img: Image, size: int) -> void:
	var cx = size / 2
	var cy = size / 2
	var hat = Color(0.1, 0.05, 0.2)
	var eyes = Color(1.0, 0.9, 0.3)

	for y in range(0, size * 2 / 3):
		var hat_width = (size * 2 / 3 - y) / 3 + 5
		for x in range(cx - hat_width, cx + hat_width):
			if x >= 0 and x < size:
				img.set_pixel(x, y, hat)

	for x in range(size / 5, size * 4 / 5):
		for y in range(size / 2 - 5, size / 2):
			img.set_pixel(x, y, hat)

	for y in range(size / 2, size * 4 / 5):
		for x in range(size / 3, size * 2 / 3):
			img.set_pixel(x, y, Color(0.05, 0.02, 0.08))

	for dx in range(-2, 3):
		img.set_pixel(cx - 8 + dx, cy + 5, eyes)
		img.set_pixel(cx + 8 + dx, cy + 5, eyes)


func _draw_bard_portrait(img: Image, size: int) -> void:
	var cx = size / 2
	var cy = size / 2
	var skin = Color(0.9, 0.78, 0.68)
	var hair = Color(0.6, 0.35, 0.15)
	var eyes = Color(0.35, 0.55, 0.3)
	var hat = Color(0.5, 0.2, 0.2)
	var feather = Color(0.9, 0.3, 0.2)

	# Feathered cap (tilted beret)
	for y in range(size / 6, size / 2 - 5):
		for x in range(size / 5, size * 3 / 4):
			var dy = y - size / 3
			var dx = x - cx + 5
			if dx * dx / 200.0 + dy * dy / 80.0 < 1.0:
				img.set_pixel(x, y, hat)

	# Feather
	for i in range(15):
		var fx = cx + 10 + i
		var fy = size / 5 - i / 2
		if fx >= 0 and fx < size and fy >= 0 and fy < size:
			img.set_pixel(fx, fy, feather)
			if fy + 1 < size:
				img.set_pixel(fx, fy + 1, feather)

	# Hair
	for y in range(size / 3, size * 2 / 3):
		for x in range(size / 4, size / 3):
			img.set_pixel(x, y, hair)
		for x in range(size * 2 / 3, size * 3 / 4):
			img.set_pixel(x, y, hair)

	# Face
	for y in range(size / 3, size * 3 / 4):
		for x in range(size / 4, size * 3 / 4):
			var dy = y - size / 2
			var dx = x - cx
			if dx * dx / 170.0 + dy * dy / 180.0 < 1.0:
				img.set_pixel(x, y, skin)

	# Bright eyes
	img.set_pixel(cx - 7, cy - 2, eyes)
	img.set_pixel(cx - 6, cy - 2, eyes)
	img.set_pixel(cx + 6, cy - 2, eyes)
	img.set_pixel(cx + 7, cy - 2, eyes)

	# Cheerful smile
	for x in range(-6, 7):
		var smile_y = cy + 8 + abs(x) / 3
		if smile_y < size:
			img.set_pixel(cx + x, smile_y, Color(0.75, 0.45, 0.45))


func _draw_elder_portrait(img: Image, size: int) -> void:
	var cx = size / 2
	var cy = size / 2
	var skin = Color(0.85, 0.72, 0.62)
	var hair = Color(0.75, 0.73, 0.7)
	var eyes = Color(0.4, 0.35, 0.3)
	var robe = Color(0.35, 0.25, 0.15)

	# White/gray hair
	for y in range(size / 5, size / 2):
		for x in range(size / 4, size * 3 / 4):
			var dy = y - size / 3
			var dx = x - cx
			if dx * dx / 200.0 + dy * dy / 120.0 < 1.0:
				img.set_pixel(x, y, hair)

	# Face (wrinkled)
	for y in range(size / 3, size * 4 / 5):
		for x in range(size / 4, size * 3 / 4):
			var dy = y - size / 2 - 5
			var dx = x - cx
			if dx * dx / 180.0 + dy * dy / 200.0 < 1.0:
				img.set_pixel(x, y, skin)

	# Wrinkle lines
	for x in range(-3, 4):
		img.set_pixel(cx + x - 8, cy - 5, skin.darkened(0.15))
		img.set_pixel(cx + x + 8, cy - 5, skin.darkened(0.15))

	# Tired but wise eyes
	img.set_pixel(cx - 8, cy, eyes)
	img.set_pixel(cx - 7, cy, eyes)
	img.set_pixel(cx + 7, cy, eyes)
	img.set_pixel(cx + 8, cy, eyes)

	# Slight frown
	for x in range(-4, 5):
		img.set_pixel(cx + x, cy + 12, Color(0.6, 0.4, 0.4))

	# Robe collar hint
	for y in range(size * 3 / 4, size * 4 / 5):
		for x in range(size / 3, size * 2 / 3):
			img.set_pixel(x, y, robe)


func _draw_scholar_portrait(img: Image, size: int) -> void:
	var cx = size / 2
	var cy = size / 2
	var skin = Color(0.88, 0.78, 0.68)
	var hair = Color(0.3, 0.25, 0.2)
	var eyes = Color(0.3, 0.5, 0.6)
	var glasses = Color(0.6, 0.65, 0.7)

	# Messy hair
	for y in range(size / 5, size / 2):
		for x in range(size / 4 - 3, size * 3 / 4 + 3):
			var dy = y - size / 3
			var dx = x - cx
			if dx * dx / 220.0 + dy * dy / 110.0 < 1.0:
				img.set_pixel(x, y, hair)

	# Face
	for y in range(size / 3, size * 4 / 5):
		for x in range(size / 4, size * 3 / 4):
			var dy = y - size / 2 - 5
			var dx = x - cx
			if dx * dx / 170.0 + dy * dy / 200.0 < 1.0:
				img.set_pixel(x, y, skin)

	# Glasses frames
	for dx in range(-3, 4):
		img.set_pixel(cx - 8 + dx, cy - 4, glasses)
		img.set_pixel(cx - 8 + dx, cy + 2, glasses)
		img.set_pixel(cx + 8 + dx, cy - 4, glasses)
		img.set_pixel(cx + 8 + dx, cy + 2, glasses)
	# Bridge
	for x in range(cx - 4, cx + 5):
		img.set_pixel(x, cy - 2, glasses)

	# Eyes behind glasses
	img.set_pixel(cx - 8, cy - 1, eyes)
	img.set_pixel(cx + 8, cy - 1, eyes)

	# Excited open mouth
	for x in range(-3, 4):
		img.set_pixel(cx + x, cy + 10, Color(0.6, 0.35, 0.35))
		img.set_pixel(cx + x, cy + 12, Color(0.6, 0.35, 0.35))


func _draw_shopkeeper_portrait(img: Image, size: int) -> void:
	var cx = size / 2
	var cy = size / 2
	var skin = Color(0.9, 0.75, 0.65)
	var hair = Color(0.35, 0.25, 0.15)
	var eyes = Color(0.35, 0.3, 0.25)
	var apron = Color(0.6, 0.5, 0.35)

	# Hair
	for y in range(size / 5, size / 2):
		for x in range(size / 4, size * 3 / 4):
			var dy = y - size / 3
			var dx = x - cx
			if dx * dx / 200.0 + dy * dy / 100.0 < 1.0:
				img.set_pixel(x, y, hair)

	# Face
	for y in range(size / 3, size * 4 / 5):
		for x in range(size / 4, size * 3 / 4):
			var dy = y - size / 2 - 5
			var dx = x - cx
			if dx * dx / 190.0 + dy * dy / 200.0 < 1.0:
				img.set_pixel(x, y, skin)

	# Eyes (skeptical)
	img.set_pixel(cx - 8, cy, eyes)
	img.set_pixel(cx - 7, cy, eyes)
	img.set_pixel(cx + 7, cy, eyes)
	img.set_pixel(cx + 8, cy, eyes)
	# Raised eyebrow
	for x in range(-3, 4):
		img.set_pixel(cx + 6 + x, cy - 5, hair)

	# Smirk
	for x in range(-2, 5):
		img.set_pixel(cx + x, cy + 11 - x / 4, Color(0.6, 0.4, 0.4))

	# Apron hint
	for y in range(size * 3 / 4, size * 4 / 5):
		for x in range(size / 3, size * 2 / 3):
			img.set_pixel(x, y, apron)


func _draw_goblin_portrait(img: Image, size: int) -> void:
	var cx = size / 2
	var cy = size / 2
	var skin = Color(0.4, 0.55, 0.3)
	var eyes = Color(0.9, 0.8, 0.2)
	var ears = Color(0.35, 0.48, 0.25)

	# Pointy ears
	for i in range(12):
		var lx = size / 5 - i
		var rx = size * 4 / 5 + i
		var ey = size / 3 + i / 2
		if lx >= 0 and lx < size and ey >= 0 and ey < size:
			img.set_pixel(lx, ey, ears)
			img.set_pixel(lx, ey + 1, ears)
		if rx >= 0 and rx < size and ey >= 0 and ey < size:
			img.set_pixel(rx, ey, ears)
			img.set_pixel(rx, ey + 1, ears)

	# Round face
	for y in range(size / 4, size * 3 / 4):
		for x in range(size / 4, size * 3 / 4):
			var dy = y - cy
			var dx = x - cx
			if dx * dx / 180.0 + dy * dy / 180.0 < 1.0:
				img.set_pixel(x, y, skin)

	# Big yellow eyes
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if dx * dx + dy * dy <= 4:
				img.set_pixel(cx - 10 + dx, cy - 3 + dy, eyes)
				img.set_pixel(cx + 10 + dx, cy - 3 + dy, eyes)
	# Pupils
	img.set_pixel(cx - 10, cy - 3, Color(0.1, 0.1, 0.1))
	img.set_pixel(cx + 10, cy - 3, Color(0.1, 0.1, 0.1))

	# Big grin
	for x in range(-8, 9):
		var gy = cy + 8 + abs(x) / 2
		if gy < size:
			img.set_pixel(cx + x, gy, Color(0.3, 0.1, 0.1))


func _draw_mysterious_portrait(img: Image, size: int) -> void:
	var cx = size / 2
	var cy = size / 2
	var cloak = Color(0.15, 0.1, 0.2)
	var eyes = Color(0.7, 0.5, 0.9)

	# Hood/cloak
	for y in range(size / 6, size * 5 / 6):
		for x in range(size / 5, size * 4 / 5):
			var dy = y - size / 3
			var dx = x - cx
			if dx * dx / 250.0 + dy * dy / 300.0 < 1.0:
				img.set_pixel(x, y, cloak)

	# Shadowed face
	for y in range(size / 3, size * 2 / 3):
		for x in range(size / 3, size * 2 / 3):
			var dy = y - cy
			var dx = x - cx
			if dx * dx / 120.0 + dy * dy / 120.0 < 1.0:
				img.set_pixel(x, y, cloak.lightened(0.05))

	# Glowing eyes
	for dx in range(-2, 3):
		img.set_pixel(cx - 8 + dx, cy - 2, eyes)
		img.set_pixel(cx + 8 + dx, cy - 2, eyes)


func _draw_system_portrait(img: Image, size: int) -> void:
	var cx = size / 2
	var cy = size / 2
	var green = Color(0.0, 0.8, 0.4)
	var dark_green = Color(0.0, 0.4, 0.2)

	# Terminal cursor block
	for y in range(cy - 10, cy + 10):
		for x in range(cx - 6, cx + 7):
			img.set_pixel(x, y, green)

	# Blinking underscore
	for x in range(cx - 8, cx + 9):
		img.set_pixel(x, cy + 12, green)
		img.set_pixel(x, cy + 13, green)

	# Bracket frame
	for y in range(cy - 15, cy + 16):
		img.set_pixel(cx - 15, y, dark_green)
		img.set_pixel(cx - 14, y, dark_green)
		img.set_pixel(cx + 14, y, dark_green)
		img.set_pixel(cx + 15, y, dark_green)
	for x in range(cx - 15, cx - 10):
		img.set_pixel(x, cy - 15, dark_green)
		img.set_pixel(x, cy + 15, dark_green)
	for x in range(cx + 10, cx + 16):
		img.set_pixel(x, cy - 15, dark_green)
		img.set_pixel(x, cy + 15, dark_green)


func _draw_narrator_portrait(img: Image, size: int) -> void:
	var cx = size / 2
	var cy = size / 2
	var color = Color(0.5, 0.5, 0.6)
	var glow = Color(0.7, 0.7, 0.8)

	# Eye symbol
	for angle in range(360):
		var rad = deg_to_rad(angle)
		var r = 20 + sin(rad * 2) * 8
		var x = int(cx + cos(rad) * r)
		var y = int(cy + sin(rad) * r * 0.6)
		if x >= 0 and x < size and y >= 0 and y < size:
			img.set_pixel(x, y, color)

	for dy in range(-8, 9):
		for dx in range(-8, 9):
			if dx * dx + dy * dy < 64:
				var c = glow if dx * dx + dy * dy < 16 else color
				img.set_pixel(cx + dx, cy + dy, c)

	img.set_pixel(cx - 3, cy - 3, Color.WHITE)
	img.set_pixel(cx - 2, cy - 3, Color.WHITE)
