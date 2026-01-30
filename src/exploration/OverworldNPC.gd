extends Area2D
class_name OverworldNPC

## OverworldNPC - Simple NPC for villages and overworld
## Can be interacted with to show dialogue

signal dialogue_started(npc_name: String)
signal dialogue_ended(npc_name: String)

## NPC properties
@export var npc_name: String = "Villager"
@export var npc_type: String = "villager"  # villager, elder, shopkeeper, guard
@export var dialogue_lines: Array = ["Hello, traveler!"]
@export var facing_direction: int = 0  # 0=down, 1=up, 2=left, 3=right

## Visual
var sprite: Sprite2D
var name_label: Label
var dialogue_box: Control
var dialogue_label: Label

## State
var _current_line: int = 0
var _is_talking: bool = false
var _player_nearby: bool = false

## Animation
var _is_dancing: bool = false
var _dance_frame: int = 0
var _dance_timer: float = 0.0
const DANCE_SPEED: float = 0.2  # Seconds per frame
const DANCE_FRAMES: int = 4
var _sprite_cache: Dictionary = {}  # frame -> texture

const TILE_SIZE: int = 32


func _ready() -> void:
	_generate_sprite()
	_setup_collision()
	_setup_name_label()
	_setup_dialogue_box()

	# Pre-generate animation frames for dancer
	if npc_type == "dancer":
		_generate_dance_frames()

	# Add to interactables group for reliable interaction detection
	add_to_group("interactables")

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	if _is_dancing and npc_type == "dancer":
		_dance_timer += delta
		if _dance_timer >= DANCE_SPEED:
			_dance_timer -= DANCE_SPEED
			_dance_frame = (_dance_frame + 1) % DANCE_FRAMES
			_update_dance_sprite()


func _generate_sprite() -> void:
	sprite = Sprite2D.new()
	sprite.name = "Sprite"

	var image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	_draw_npc(image)

	var texture = ImageTexture.create_from_image(image)
	sprite.texture = texture
	sprite.centered = true
	add_child(sprite)


func _draw_npc(image: Image) -> void:
	# NPC color palette based on type
	var skin_color = Color(0.95, 0.80, 0.65)
	var hair_color = Color(0.35, 0.25, 0.15)
	var clothes_color = _get_clothes_color()
	var outline_color = Color(0.1, 0.1, 0.1)

	# Clear
	image.fill(Color.TRANSPARENT)

	# Body (simple humanoid shape)
	# Head (8x8 centered at top)
	for y in range(2, 10):
		for x in range(12, 20):
			if y == 2 or y == 9 or x == 12 or x == 19:
				image.set_pixel(x, y, outline_color)
			else:
				image.set_pixel(x, y, skin_color)

	# Hair (top of head)
	for y in range(2, 5):
		for x in range(13, 19):
			if y < 4:
				image.set_pixel(x, y, hair_color)

	# Eyes
	image.set_pixel(14, 6, outline_color)
	image.set_pixel(17, 6, outline_color)

	# Body/clothes (12x14)
	for y in range(10, 24):
		for x in range(10, 22):
			if y == 10 or y == 23 or x == 10 or x == 21:
				image.set_pixel(x, y, outline_color)
			else:
				image.set_pixel(x, y, clothes_color)

	# Arms
	for y in range(12, 20):
		image.set_pixel(8, y, clothes_color)
		image.set_pixel(9, y, clothes_color)
		image.set_pixel(22, y, clothes_color)
		image.set_pixel(23, y, clothes_color)

	# Hands
	for y in range(18, 21):
		image.set_pixel(8, y, skin_color)
		image.set_pixel(9, y, skin_color)
		image.set_pixel(22, y, skin_color)
		image.set_pixel(23, y, skin_color)

	# Legs
	for y in range(24, 30):
		for x in range(12, 16):
			image.set_pixel(x, y, clothes_color if y < 28 else outline_color)
		for x in range(16, 20):
			image.set_pixel(x, y, clothes_color if y < 28 else outline_color)

	# Feet
	for x in range(11, 16):
		image.set_pixel(x, 30, outline_color)
		image.set_pixel(x, 31, outline_color)
	for x in range(16, 21):
		image.set_pixel(x, 30, outline_color)
		image.set_pixel(x, 31, outline_color)


func _generate_dance_frames() -> void:
	"""Generate all dance animation frames for dancer NPC"""
	for frame in range(DANCE_FRAMES):
		var image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
		_draw_dancer_frame(image, frame)
		var texture = ImageTexture.create_from_image(image)
		_sprite_cache[frame] = texture


func _draw_dancer_frame(image: Image, frame: int) -> void:
	"""Draw dancer with different poses for each frame"""
	var skin_color = Color(0.95, 0.80, 0.65)
	var hair_color = Color(0.2, 0.15, 0.1)
	var dress_color = Color(0.9, 0.3, 0.4)  # Red dress
	var dress_accent = Color(0.95, 0.5, 0.3)  # Orange/gold trim
	var outline_color = Color(0.1, 0.1, 0.1)

	image.fill(Color.TRANSPARENT)

	# Dance pose parameters based on frame
	# Frame 0: Arms down, feet together
	# Frame 1: Left arm up, right foot out
	# Frame 2: Both arms up, on tiptoes
	# Frame 3: Right arm up, left foot out
	var left_arm_up = frame == 1 or frame == 2
	var right_arm_up = frame == 2 or frame == 3
	var body_offset = -2 if frame == 2 else 0  # Jump up on frame 2
	var skirt_swirl = frame % 2  # Alternate skirt direction
	var head_tilt = 1 if frame == 1 else (-1 if frame == 3 else 0)

	# Head (slightly tilted based on pose)
	var head_x = 16 + head_tilt
	for y in range(2 + body_offset, 10 + body_offset):
		for x in range(head_x - 4, head_x + 4):
			if x >= 0 and x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
				if y == 2 + body_offset or y == 9 + body_offset or x == head_x - 4 or x == head_x + 3:
					image.set_pixel(x, y, outline_color)
				else:
					image.set_pixel(x, y, skin_color)

	# Hair (long, flowing)
	for y in range(2 + body_offset, 6 + body_offset):
		for x in range(head_x - 3, head_x + 3):
			if x >= 0 and x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
				image.set_pixel(x, y, hair_color)
	# Hair flowing down back
	for y in range(6 + body_offset, 14 + body_offset):
		var hair_x = head_x + 3 - (skirt_swirl * 2)
		if hair_x >= 0 and hair_x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
			image.set_pixel(hair_x, y, hair_color)
			if hair_x + 1 < TILE_SIZE:
				image.set_pixel(hair_x + 1, y, hair_color)

	# Eyes
	if head_x - 2 >= 0 and head_x + 1 < TILE_SIZE:
		image.set_pixel(head_x - 2, 6 + body_offset, outline_color)
		image.set_pixel(head_x + 1, 6 + body_offset, outline_color)

	# Smile
	if head_x - 1 >= 0 and head_x + 1 < TILE_SIZE and 8 + body_offset < TILE_SIZE:
		image.set_pixel(head_x - 1, 8 + body_offset, Color(0.8, 0.5, 0.5))
		image.set_pixel(head_x, 8 + body_offset, Color(0.8, 0.5, 0.5))

	# Body/dress top
	for y in range(10 + body_offset, 18 + body_offset):
		for x in range(12, 20):
			if x >= 0 and x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
				if y == 10 + body_offset or x == 12 or x == 19:
					image.set_pixel(x, y, outline_color)
				else:
					image.set_pixel(x, y, dress_color)

	# Dress skirt (flowing, swirling)
	var skirt_center = 16 + (skirt_swirl * 2 - 1) * 2
	for y in range(18 + body_offset, 28 + body_offset):
		var progress = float(y - (18 + body_offset)) / 10.0
		var skirt_width = int(6 + progress * 6)  # Gets wider at bottom
		var swirl_offset = int(sin(progress * 3.14) * 3 * (skirt_swirl * 2 - 1))
		for x in range(skirt_center - skirt_width + swirl_offset, skirt_center + skirt_width + swirl_offset):
			if x >= 0 and x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
				# Dress pattern - alternating stripes
				var stripe = (x + y) % 4 < 2
				var color = dress_color if stripe else dress_accent
				image.set_pixel(x, y, color)

	# Left arm
	var left_arm_y_start = 12 + body_offset + (-6 if left_arm_up else 0)
	var left_arm_y_end = 20 + body_offset + (-6 if left_arm_up else 0)
	var left_arm_x = 10 + (-2 if left_arm_up else 0)
	for y in range(max(0, left_arm_y_start), min(TILE_SIZE, left_arm_y_end)):
		if left_arm_x >= 0 and left_arm_x < TILE_SIZE:
			image.set_pixel(left_arm_x, y, skin_color)
			if left_arm_x + 1 < TILE_SIZE:
				image.set_pixel(left_arm_x + 1, y, skin_color)

	# Right arm
	var right_arm_y_start = 12 + body_offset + (-6 if right_arm_up else 0)
	var right_arm_y_end = 20 + body_offset + (-6 if right_arm_up else 0)
	var right_arm_x = 21 + (2 if right_arm_up else 0)
	for y in range(max(0, right_arm_y_start), min(TILE_SIZE, right_arm_y_end)):
		if right_arm_x >= 0 and right_arm_x < TILE_SIZE:
			image.set_pixel(right_arm_x, y, skin_color)
			if right_arm_x - 1 >= 0:
				image.set_pixel(right_arm_x - 1, y, skin_color)

	# Legs peeking from skirt
	var leg_y = 26 + body_offset
	if leg_y >= 0 and leg_y < TILE_SIZE - 3:
		# Left leg
		var left_leg_x = 14 + (-2 if frame == 3 else 0)
		for y in range(leg_y, min(TILE_SIZE, leg_y + 4)):
			if left_leg_x >= 0 and left_leg_x < TILE_SIZE:
				image.set_pixel(left_leg_x, y, skin_color)
		# Right leg
		var right_leg_x = 18 + (2 if frame == 1 else 0)
		for y in range(leg_y, min(TILE_SIZE, leg_y + 4)):
			if right_leg_x >= 0 and right_leg_x < TILE_SIZE:
				image.set_pixel(right_leg_x, y, skin_color)

	# Feet/shoes
	var shoe_color = Color(0.8, 0.2, 0.3)  # Red shoes
	var foot_y = 30 + body_offset
	if foot_y >= 0 and foot_y < TILE_SIZE:
		for dx in [-1, 0, 1]:
			var lx = 14 + (-2 if frame == 3 else 0) + dx
			var rx = 18 + (2 if frame == 1 else 0) + dx
			if lx >= 0 and lx < TILE_SIZE:
				image.set_pixel(lx, foot_y, shoe_color)
			if rx >= 0 and rx < TILE_SIZE:
				image.set_pixel(rx, foot_y, shoe_color)


func _update_dance_sprite() -> void:
	"""Update sprite to current dance frame"""
	if _sprite_cache.has(_dance_frame):
		sprite.texture = _sprite_cache[_dance_frame]


func start_dancing() -> void:
	"""Start the dance animation"""
	if npc_type != "dancer":
		return
	_is_dancing = true
	_dance_frame = 0
	_dance_timer = 0.0
	_update_dance_sprite()


func stop_dancing() -> void:
	"""Stop the dance animation and return to normal pose"""
	_is_dancing = false
	_dance_frame = 0
	# Regenerate normal sprite
	var image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	_draw_npc(image)
	var texture = ImageTexture.create_from_image(image)
	sprite.texture = texture


func _get_clothes_color() -> Color:
	match npc_type:
		"elder":
			return Color(0.6, 0.5, 0.7)  # Purple robes
		"shopkeeper":
			return Color(0.2, 0.5, 0.3)  # Green apron
		"guard":
			return Color(0.4, 0.4, 0.5)  # Gray armor
		"innkeeper":
			return Color(0.7, 0.5, 0.3)  # Brown
		"bartender":
			return Color(0.5, 0.35, 0.2)  # Dark brown apron
		"dancer":
			return Color(0.9, 0.3, 0.4)  # Red dress
		"knight":
			return Color(0.55, 0.55, 0.65)  # Silver armor
		"mysterious":
			return Color(0.25, 0.2, 0.35)  # Dark purple cloak
		"bard":
			return Color(0.7, 0.55, 0.3)  # Gold/tan tunic
		_:
			# Random villager colors
			var colors = [
				Color(0.3, 0.4, 0.7),  # Blue
				Color(0.7, 0.3, 0.3),  # Red
				Color(0.3, 0.6, 0.4),  # Green
				Color(0.6, 0.6, 0.3),  # Yellow
			]
			return colors[hash(npc_name) % colors.size()]


func _setup_collision() -> void:
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(TILE_SIZE, TILE_SIZE)
	collision.shape = shape
	add_child(collision)

	# Set collision layer/mask for interaction
	# Layer 4 = interactables (NPCs, signs, etc.) - detected by controller queries
	# Mask 2 = player layer - for detecting when player enters NPC zone
	collision_layer = 4  # So controller can find us via physics query
	collision_mask = 2   # To detect player entering our zone
	monitoring = true
	monitorable = true


func _setup_name_label() -> void:
	name_label = Label.new()
	name_label.text = npc_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(-40, -24)
	name_label.size = Vector2(80, 20)
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	name_label.visible = false
	add_child(name_label)


func _setup_dialogue_box() -> void:
	dialogue_box = Control.new()
	dialogue_box.name = "DialogueBox"
	dialogue_box.visible = false
	dialogue_box.z_index = 100

	# Background panel
	var panel = Panel.new()
	panel.position = Vector2(-100, -80)
	panel.size = Vector2(200, 60)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.2, 0.95)
	style.border_color = Color(0.8, 0.8, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	dialogue_box.add_child(panel)

	# Dialogue text
	dialogue_label = Label.new()
	dialogue_label.position = Vector2(-92, -72)
	dialogue_label.size = Vector2(184, 44)
	dialogue_label.add_theme_font_size_override("font_size", 11)
	dialogue_label.add_theme_color_override("font_color", Color.WHITE)
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_box.add_child(dialogue_label)

	add_child(dialogue_box)


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("set_can_move"):  # It's the player
		_player_nearby = true
		name_label.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.has_method("set_can_move"):
		_player_nearby = false
		name_label.visible = false
		if _is_talking:
			_end_dialogue()


func _input(event: InputEvent) -> void:
	if not _player_nearby:
		return

	if event.is_action_pressed("ui_accept"):
		if _is_talking:
			_advance_dialogue()
		else:
			_start_dialogue()
		get_viewport().set_input_as_handled()


func _start_dialogue() -> void:
	if dialogue_lines.is_empty():
		return

	_is_talking = true
	_current_line = 0
	dialogue_box.visible = true
	dialogue_label.text = dialogue_lines[0]
	dialogue_started.emit(npc_name)
	if SoundManager:
		SoundManager.play_ui("menu_open")

	# Dancer starts dancing when talked to
	if npc_type == "dancer":
		start_dancing()


func _advance_dialogue() -> void:
	_current_line += 1
	if _current_line >= dialogue_lines.size():
		_end_dialogue()
	else:
		dialogue_label.text = dialogue_lines[_current_line]
		if SoundManager:
			SoundManager.play_ui("menu_select")


func _end_dialogue() -> void:
	_is_talking = false
	dialogue_box.visible = false
	_current_line = 0
	dialogue_ended.emit(npc_name)
	if SoundManager:
		SoundManager.play_ui("menu_close")

	# Dancer stops dancing when dialogue ends
	if npc_type == "dancer" and _is_dancing:
		stop_dancing()


## Called by interaction system
func interact(player: Node2D) -> void:
	if _is_talking:
		_advance_dialogue()
	else:
		_start_dialogue()
