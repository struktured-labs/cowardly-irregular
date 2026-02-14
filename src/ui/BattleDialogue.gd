extends CanvasLayer
class_name BattleDialogue

## Battle Dialogue System - Shows character portraits with themed dialogue boxes
## Used for boss intros, story moments, and character reactions
## Supports custom character portraits via CharacterPortrait widget

const CharacterPortraitClass = preload("res://src/ui/CharacterPortrait.gd")

signal dialogue_finished()
signal dialogue_advanced()

## Dialogue queue
var _dialogue_queue: Array = []  # Array of {speaker: String, text: String, portrait: String}
var _current_index: int = 0
var _is_typing: bool = false
var _typing_speed: float = 0.03  # Seconds per character
var _current_text: String = ""
var _displayed_chars: int = 0
var _typing_timer: Timer

## Party reference for custom portrait lookups
var _party: Array = []

## Speaker name to party member mapping
const SPEAKER_TO_CHAR_ID = {
	"hero": "hero",
	"mira": "mira",
	"zack": "zack",
	"vex": "vex"
}

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

## Character color themes (matching Win98Menu)
const CHARACTER_THEMES = {
	"hero": {
		"bg": Color(0.1, 0.1, 0.25),
		"border": Color(0.7, 0.7, 1.0),
		"text": Color(1.0, 1.0, 1.0),
		"name": Color(0.5, 0.7, 1.0),
		"portrait_bg": Color(0.15, 0.15, 0.35)
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
	"narrator": {
		"bg": Color(0.02, 0.02, 0.05),
		"border": Color(0.4, 0.4, 0.5),
		"text": Color(0.8, 0.8, 0.85),
		"name": Color(0.6, 0.6, 0.7),
		"portrait_bg": Color(0.05, 0.05, 0.08)
	},
	"enemy": {
		"bg": Color(0.15, 0.05, 0.05),
		"border": Color(0.8, 0.3, 0.3),
		"text": Color(1.0, 0.9, 0.9),
		"name": Color(1.0, 0.5, 0.4),
		"portrait_bg": Color(0.2, 0.08, 0.08)
	},
	"rat_king": {
		"bg": Color(0.12, 0.08, 0.05),
		"border": Color(0.8, 0.7, 0.3),  # Golden crown color
		"text": Color(1.0, 0.95, 0.85),
		"name": Color(1.0, 0.85, 0.3),  # Gold
		"portrait_bg": Color(0.15, 0.1, 0.06)
	}
}


func _ready() -> void:
	layer = 100  # Above everything else
	process_mode = Node.PROCESS_MODE_ALWAYS  # Independent of battle speed
	_setup_typing_timer()
	_build_ui()
	visible = false


func _exit_tree() -> void:
	"""Cleanup timer when node is freed"""
	if _typing_timer and is_instance_valid(_typing_timer):
		_typing_timer.stop()


func _setup_typing_timer() -> void:
	_typing_timer = Timer.new()
	_typing_timer.one_shot = false
	_typing_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_typing_timer.timeout.connect(_on_typing_tick)
	add_child(_typing_timer)


func _build_ui() -> void:
	# Semi-transparent overlay
	_background = ColorRect.new()
	_background.color = Color(0, 0, 0, 0.4)
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.size = get_viewport().get_visible_rect().size
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

	# Create initial empty state (will be themed when dialogue starts)
	_create_dialogue_visuals(CHARACTER_THEMES["narrator"])


func _create_dialogue_visuals(theme: Dictionary) -> void:
	# Clear existing children of dialogue box
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

	# Portrait border
	_draw_retro_border(_portrait_frame, PORTRAIT_SIZE, PORTRAIT_SIZE, theme["border"].darkened(0.2))

	# Portrait image
	_portrait_image = TextureRect.new()
	_portrait_image.position = Vector2(4, 4)
	_portrait_image.size = Vector2(PORTRAIT_SIZE - 8, PORTRAIT_SIZE - 8)
	_portrait_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
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
	_advance_hint.position = Vector2(box_width - 150, box_height - 20)
	_advance_hint.add_theme_font_size_override("font_size", 10)
	_advance_hint.add_theme_color_override("font_color", theme["text"].darkened(0.4))
	_advance_hint.visible = false
	_dialogue_box.add_child(_advance_hint)


func _draw_retro_border(parent: Control, width: float, height: float, color: Color) -> void:
	"""Draw pixel-tile retro border"""
	var shadow_color = color.darkened(0.5)

	# Top border
	var top = ColorRect.new()
	top.color = color
	top.position = Vector2(0, 0)
	top.size = Vector2(width, TILE_SIZE)
	parent.add_child(top)

	# Bottom border (shadow)
	var bottom = ColorRect.new()
	bottom.color = shadow_color
	bottom.position = Vector2(0, height - TILE_SIZE)
	bottom.size = Vector2(width, TILE_SIZE)
	parent.add_child(bottom)

	# Left border
	var left = ColorRect.new()
	left.color = color
	left.position = Vector2(0, 0)
	left.size = Vector2(TILE_SIZE, height)
	parent.add_child(left)

	# Right border (shadow)
	var right = ColorRect.new()
	right.color = shadow_color
	right.position = Vector2(width - TILE_SIZE, 0)
	right.size = Vector2(TILE_SIZE, height)
	parent.add_child(right)

	# Inner highlight line
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


## Public API

func set_party(party: Array) -> void:
	"""Set the party reference for custom portrait lookups"""
	_party = party


func show_dialogue(dialogue_lines: Array) -> void:
	"""Start showing dialogue. Each line is {speaker: String, text: String, portrait: String (optional)}"""
	_dialogue_queue = dialogue_lines
	_current_index = 0
	visible = true
	_show_current_line()


func show_boss_intro(boss_name: String, intro_lines: Array) -> void:
	"""Show boss intro dialogue with automatic speaker assignment"""
	var dialogue = []

	for line in intro_lines:
		var entry = {}
		if line.begins_with("*") and line.ends_with("*"):
			# Narrator text (italics indicator)
			entry["speaker"] = ""
			entry["text"] = line.trim_prefix("*").trim_suffix("*")
			entry["portrait"] = "narrator"
			entry["theme"] = "narrator"
		elif ":" in line:
			# Character dialogue
			var parts = line.split(":", true, 1)
			entry["speaker"] = parts[0].strip_edges()
			entry["text"] = parts[1].strip_edges() if parts.size() > 1 else ""
			# Determine theme from speaker
			if entry["speaker"].to_lower().contains("hero"):
				entry["portrait"] = "hero"
				entry["theme"] = "hero"
			elif entry["speaker"].to_lower().contains("rat") or entry["speaker"].to_lower().contains("king"):
				entry["portrait"] = "rat_king"
				entry["theme"] = "rat_king"
			else:
				entry["portrait"] = "hero"
				entry["theme"] = "hero"
		else:
			# Plain narration
			entry["speaker"] = ""
			entry["text"] = line
			entry["portrait"] = "narrator"
			entry["theme"] = "narrator"

		dialogue.append(entry)

	show_dialogue(dialogue)


func _show_current_line() -> void:
	"""Display the current dialogue line"""
	if _current_index >= _dialogue_queue.size():
		_finish_dialogue()
		return

	var entry = _dialogue_queue[_current_index]
	var theme_name = entry.get("theme", "narrator")
	var theme = CHARACTER_THEMES.get(theme_name, CHARACTER_THEMES["narrator"])

	# Rebuild visuals with new theme
	_create_dialogue_visuals(theme)

	# Set speaker name
	_speaker_label.text = entry.get("speaker", "")

	# Set portrait - check for party member custom portraits first
	var portrait_type = entry.get("portrait", "narrator")
	var custom_portrait = _get_party_member_portrait(portrait_type)
	if custom_portrait:
		# Remove the default portrait_image and add custom portrait widget
		_portrait_image.visible = false
		# Remove any existing custom portrait
		for child in _portrait_frame.get_children():
			if child.has_meta("custom_portrait"):
				child.queue_free()
		custom_portrait.position = Vector2(4, 4)
		custom_portrait.set_meta("custom_portrait", true)
		_portrait_frame.add_child(custom_portrait)
	else:
		# Use procedural portrait
		_portrait_image.visible = true
		_portrait_image.texture = _create_portrait(portrait_type)
		# Remove any existing custom portrait
		for child in _portrait_frame.get_children():
			if child.has_meta("custom_portrait"):
				child.queue_free()

	# Start typing effect
	_current_text = entry.get("text", "")
	_displayed_chars = 0
	_text_label.text = ""
	_advance_hint.visible = false
	_is_typing = true
	_typing_timer.start(_typing_speed)


func _on_typing_tick() -> void:
	"""Add next character to displayed text"""
	# Safety check in case timer fires after node is freed
	if not is_instance_valid(self) or not is_instance_valid(_text_label):
		return

	if _displayed_chars < _current_text.length():
		_displayed_chars += 1
		_text_label.text = _current_text.substr(0, _displayed_chars)

		# Play typing sound occasionally
		if _displayed_chars % 3 == 0 and SoundManager:
			SoundManager.play_ui("menu_move")
	else:
		_finish_typing()


func _finish_typing() -> void:
	"""Complete the typing effect"""
	if _typing_timer and is_instance_valid(_typing_timer):
		_typing_timer.stop()
	_is_typing = false
	if _text_label and is_instance_valid(_text_label):
		_text_label.text = _current_text
	if _advance_hint and is_instance_valid(_advance_hint):
		_advance_hint.visible = true


func _advance_dialogue() -> void:
	"""Move to next dialogue line"""
	if _is_typing:
		# Skip to end of current line
		_finish_typing()
	else:
		# Move to next line
		_current_index += 1
		dialogue_advanced.emit()
		_show_current_line()

	if SoundManager:
		SoundManager.play_ui("menu_select")


func _finish_dialogue() -> void:
	"""Complete dialogue sequence"""
	visible = false
	_dialogue_queue.clear()
	_current_index = 0
	dialogue_finished.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_advance_dialogue()
		get_viewport().set_input_as_handled()


## Portrait Generation

func _get_party_member_portrait(portrait_type: String) -> Control:
	"""Try to get a CharacterPortrait for a party member"""
	# Check if this is a party member portrait type
	var char_id = SPEAKER_TO_CHAR_ID.get(portrait_type.to_lower(), "")
	if char_id == "":
		return null

	# Find the party member
	for member in _party:
		if not member is Combatant:
			continue
		var member_id = member.combatant_name.to_lower().replace(" ", "_")
		if member_id == char_id:
			# Found the party member - create portrait with their customization
			var custom = member.customization if "customization" in member else null
			var job_id = member.job.get("id", "fighter") if member.job else "fighter"
			if custom:
				# Use CharacterPortrait with customization
				var portrait = CharacterPortraitClass.new(custom, job_id, CharacterPortraitClass.PortraitSize.LARGE)
				portrait.size = Vector2(PORTRAIT_SIZE - 8, PORTRAIT_SIZE - 8)
				return portrait

	return null


func _create_portrait(portrait_type: String) -> ImageTexture:
	"""Create a portrait image based on type"""
	var size = int(PORTRAIT_SIZE - 8)
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	match portrait_type:
		"hero":
			_draw_hero_portrait(img, size)
		"healer":
			_draw_healer_portrait(img, size)
		"rogue":
			_draw_rogue_portrait(img, size)
		"mage":
			_draw_mage_portrait(img, size)
		"rat_king":
			_draw_rat_king_portrait(img, size)
		"narrator", _:
			_draw_narrator_portrait(img, size)

	return ImageTexture.create_from_image(img)


func _draw_hero_portrait(img: Image, size: int) -> void:
	"""Draw hero face (brave warrior)"""
	var cx = size / 2
	var cy = size / 2

	# Face
	var skin = Color(0.95, 0.8, 0.7)
	var hair = Color(0.4, 0.3, 0.2)
	var eyes = Color(0.2, 0.4, 0.7)

	# Hair (top)
	for y in range(size / 5, size / 2):
		for x in range(size / 4, size * 3 / 4):
			var dy = y - size / 3
			var dx = x - cx
			if dx * dx / 200.0 + dy * dy / 100.0 < 1.0:
				img.set_pixel(x, y, hair)

	# Face oval
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

	# Mouth (determined smile)
	for x in range(-5, 6):
		img.set_pixel(cx + x, cy + 12, Color(0.7, 0.4, 0.4))


func _draw_healer_portrait(img: Image, size: int) -> void:
	"""Draw healer face (kind white mage)"""
	var cx = size / 2
	var cy = size / 2

	var skin = Color(0.95, 0.85, 0.8)
	var hair = Color(0.9, 0.85, 0.7)  # Blonde
	var eyes = Color(0.4, 0.7, 0.5)  # Green
	var hood = Color(1.0, 0.95, 0.95)

	# Hood
	for y in range(size / 6, size * 2 / 3):
		for x in range(size / 5, size * 4 / 5):
			var dy = y - size / 3
			var dx = x - cx
			if dx * dx / 250.0 + dy * dy / 180.0 < 1.0:
				img.set_pixel(x, y, hood)

	# Face
	for y in range(size / 3, size * 3 / 4):
		for x in range(size / 3, size * 2 / 3):
			var dy = y - size / 2
			var dx = x - cx
			if dx * dx / 120.0 + dy * dy / 150.0 < 1.0:
				img.set_pixel(x, y, skin)

	# Gentle eyes
	img.set_pixel(cx - 6, cy - 2, eyes)
	img.set_pixel(cx + 6, cy - 2, eyes)

	# Soft smile
	for x in range(-4, 5):
		img.set_pixel(cx + x, cy + 8, Color(0.8, 0.5, 0.5))


func _draw_rogue_portrait(img: Image, size: int) -> void:
	"""Draw rogue face (sly thief)"""
	var cx = size / 2
	var cy = size / 2

	var skin = Color(0.85, 0.75, 0.65)
	var hair = Color(0.15, 0.1, 0.1)  # Black
	var eyes = Color(0.3, 0.25, 0.2)
	var bandana = Color(0.4, 0.3, 0.5)

	# Bandana
	for y in range(size / 5, size / 3):
		for x in range(size / 5, size * 4 / 5):
			img.set_pixel(x, y, bandana)

	# Hair peeking out
	for y in range(size / 4, size / 2):
		for x in range(size / 5, size / 3):
			img.set_pixel(x, y, hair)

	# Face
	for y in range(size / 3, size * 3 / 4):
		for x in range(size / 4, size * 3 / 4):
			var dy = y - size / 2
			var dx = x - cx
			if dx * dx / 180.0 + dy * dy / 180.0 < 1.0:
				img.set_pixel(x, y, skin)

	# Narrow eyes (cunning)
	for x in range(-3, 0):
		img.set_pixel(cx - 7 + x, cy, eyes)
		img.set_pixel(cx + 7 + x, cy, eyes)

	# Smirk
	for x in range(0, 6):
		img.set_pixel(cx + x, cy + 10 - x / 3, Color(0.6, 0.4, 0.4))


func _draw_mage_portrait(img: Image, size: int) -> void:
	"""Draw mage face (mysterious black mage)"""
	var cx = size / 2
	var cy = size / 2

	var hat = Color(0.1, 0.05, 0.2)
	var eyes = Color(1.0, 0.9, 0.3)  # Glowing yellow

	# Pointed hat
	for y in range(0, size * 2 / 3):
		var hat_width = (size * 2 / 3 - y) / 3 + 5
		for x in range(cx - hat_width, cx + hat_width):
			if x >= 0 and x < size:
				img.set_pixel(x, y, hat)

	# Hat brim
	for x in range(size / 5, size * 4 / 5):
		for y in range(size / 2 - 5, size / 2):
			img.set_pixel(x, y, hat)

	# Dark face (shadowed)
	for y in range(size / 2, size * 4 / 5):
		for x in range(size / 3, size * 2 / 3):
			img.set_pixel(x, y, Color(0.05, 0.02, 0.08))

	# Glowing eyes
	for dx in range(-2, 3):
		img.set_pixel(cx - 8 + dx, cy + 5, eyes)
		img.set_pixel(cx + 8 + dx, cy + 5, eyes)


func _draw_rat_king_portrait(img: Image, size: int) -> void:
	"""Draw rat king face (pompous rat with tiny crown)"""
	var cx = size / 2
	var cy = size / 2

	var fur = Color(0.45, 0.35, 0.3)
	var fur_dark = Color(0.3, 0.22, 0.18)
	var fur_light = Color(0.55, 0.45, 0.38)
	var eyes = Color(0.8, 0.2, 0.2)  # Beady red
	var nose = Color(0.9, 0.6, 0.6)
	var crown = Color(1.0, 0.85, 0.2)  # Gold
	var crown_gem = Color(0.8, 0.2, 0.3)

	# Ears (large, round)
	for y in range(size / 6, size / 2):
		for x in range(size / 6, size / 3):
			var dy = y - size / 3
			var dx = x - size / 4
			if dx * dx / 80.0 + dy * dy / 100.0 < 1.0:
				img.set_pixel(x, y, fur_light if dx * dx + dy * dy < 40 else fur)

	for y in range(size / 6, size / 2):
		for x in range(size * 2 / 3, size * 5 / 6):
			var dy = y - size / 3
			var dx = x - size * 3 / 4
			if dx * dx / 80.0 + dy * dy / 100.0 < 1.0:
				img.set_pixel(x, y, fur_light if dx * dx + dy * dy < 40 else fur)

	# Face (rat snout shape)
	for y in range(size / 3, size - 5):
		for x in range(size / 4, size * 3 / 4):
			var dy = y - size / 2 - 5
			var dx = x - cx
			# Elongated snout
			var face_check = dx * dx / 180.0 + dy * dy / 280.0
			if face_check < 1.0:
				var shade = fur if face_check > 0.6 else fur_light
				img.set_pixel(x, y, shade)

	# Snout highlight
	for y in range(cy + 5, cy + 20):
		for x in range(cx - 8, cx + 9):
			var dy = y - cy - 12
			var dx = x - cx
			if dx * dx / 50.0 + dy * dy / 40.0 < 1.0:
				img.set_pixel(x, y, fur_light)

	# Beady eyes
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if dx * dx + dy * dy <= 4:
				img.set_pixel(cx - 12 + dx, cy - 5 + dy, eyes)
				img.set_pixel(cx + 12 + dx, cy - 5 + dy, eyes)
	# Eye shine
	img.set_pixel(cx - 13, cy - 6, Color.WHITE)
	img.set_pixel(cx + 11, cy - 6, Color.WHITE)

	# Pink nose
	for dy in range(-3, 4):
		for dx in range(-4, 5):
			if dx * dx / 12.0 + dy * dy / 8.0 < 1.0:
				img.set_pixel(cx + dx, cy + 18 + dy, nose)

	# Whiskers
	for i in range(8):
		img.set_pixel(cx - 15 - i, cy + 10 - i / 3, fur_dark)
		img.set_pixel(cx - 15 - i, cy + 14, fur_dark)
		img.set_pixel(cx - 15 - i, cy + 18 + i / 3, fur_dark)
		img.set_pixel(cx + 15 + i, cy + 10 - i / 3, fur_dark)
		img.set_pixel(cx + 15 + i, cy + 14, fur_dark)
		img.set_pixel(cx + 15 + i, cy + 18 + i / 3, fur_dark)

	# TINY CROWN (the important bit!)
	var crown_y = size / 5
	var crown_width = 16
	var crown_height = 12

	# Crown base
	for y in range(crown_y, crown_y + 4):
		for x in range(cx - crown_width / 2, cx + crown_width / 2 + 1):
			img.set_pixel(x, y, crown)

	# Crown points
	for point in range(3):
		var px = cx - 5 + point * 5
		for y in range(crown_y - 8 + abs(point - 1) * 3, crown_y):
			img.set_pixel(px, y, crown)
			img.set_pixel(px + 1, y, crown)

	# Crown gem
	for dy in range(-2, 2):
		for dx in range(-2, 2):
			if abs(dx) + abs(dy) < 3:
				img.set_pixel(cx + dx, crown_y - 3 + dy, crown_gem)


func _draw_narrator_portrait(img: Image, size: int) -> void:
	"""Draw narrator symbol (abstract, mystical)"""
	var cx = size / 2
	var cy = size / 2

	var color = Color(0.5, 0.5, 0.6)
	var glow = Color(0.7, 0.7, 0.8)

	# Draw an eye symbol (all-seeing narrator)
	# Outer eye shape
	for angle in range(360):
		var rad = deg_to_rad(angle)
		var r = 20 + sin(rad * 2) * 8
		var x = int(cx + cos(rad) * r)
		var y = int(cy + sin(rad) * r * 0.6)
		if x >= 0 and x < size and y >= 0 and y < size:
			img.set_pixel(x, y, color)

	# Pupil
	for dy in range(-8, 9):
		for dx in range(-8, 9):
			if dx * dx + dy * dy < 64:
				var c = glow if dx * dx + dy * dy < 16 else color
				img.set_pixel(cx + dx, cy + dy, c)

	# Highlight
	img.set_pixel(cx - 3, cy - 3, Color.WHITE)
	img.set_pixel(cx - 2, cy - 3, Color.WHITE)
