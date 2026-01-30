extends Area2D
class_name VillageBar

## VillageBar - Classic JRPG bar with dancing girl (FF5 style)
## Now triggers transition to TavernInterior scene when entered

signal drink_purchased()
signal transition_triggered(target_map: String, target_spawn: String)

@export var bar_name: String = "The Dancing Tonberry"

## Visual
var sprite: Sprite2D
var dancer_sprite: Sprite2D
var name_label: Label
var enter_label: Label

## Animation state
var _anim_frame: int = 0
var _anim_timer: float = 0.0
const ANIM_SPEED: float = 0.2

## Dancer sprite cache
var _dancer_frames: Array[ImageTexture] = []

## State
var _player_nearby: bool = false

const TILE_SIZE: int = 32


func _ready() -> void:
	_generate_bar_sprite()
	_generate_dancer_sprites()
	_setup_collision()
	_setup_name_label()
	_setup_enter_label()

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	# Animate dancer
	_anim_timer += delta
	if _anim_timer >= ANIM_SPEED:
		_anim_timer -= ANIM_SPEED
		_anim_frame = (_anim_frame + 1) % _dancer_frames.size()
		if dancer_sprite and _dancer_frames.size() > 0:
			dancer_sprite.texture = _dancer_frames[_anim_frame]


func _generate_bar_sprite() -> void:
	sprite = Sprite2D.new()
	sprite.name = "BarSprite"

	var image = Image.create(TILE_SIZE * 3, TILE_SIZE * 2, false, Image.FORMAT_RGBA8)
	_draw_bar(image)

	var texture = ImageTexture.create_from_image(image)
	sprite.texture = texture
	sprite.centered = true
	add_child(sprite)

	# Add dancer sprite separately for animation
	dancer_sprite = Sprite2D.new()
	dancer_sprite.name = "DancerSprite"
	dancer_sprite.position = Vector2(20, -8)  # Position on stage
	add_child(dancer_sprite)


func _draw_bar(image: Image) -> void:
	image.fill(Color.TRANSPARENT)

	var wood = Color(0.38, 0.24, 0.13)
	var wood_light = Color(0.48, 0.34, 0.20)
	var wood_dark = Color(0.28, 0.16, 0.08)
	var brick = Color(0.58, 0.38, 0.26)
	var brick_light = Color(0.68, 0.48, 0.34)
	var brick_dark = Color(0.45, 0.28, 0.18)
	var mortar = Color(0.38, 0.32, 0.26)
	var window = Color(0.92, 0.82, 0.52, 0.85)
	var window_bright = Color(1.0, 0.92, 0.65, 0.92)
	var window_frame = Color(0.22, 0.15, 0.08)
	var stage = Color(0.52, 0.42, 0.28)
	var stage_light = Color(0.62, 0.52, 0.35)
	var outline = Color(0.12, 0.08, 0.04)

	# Roof with shingle detail and proper 3D shading
	for y in range(0, 12):
		for x in range(2, 94):
			var row = (y / 3) % 2
			var c = wood if row == 0 else wood_dark
			# Left side lighter (lit), right side darker
			if x < 30:
				c = wood_light if row == 0 else wood
			elif x > 70:
				c = c.darkened(0.08)
			# Shingle edge details
			if y % 3 == 2:
				c = c.darkened(0.1)
			image.set_pixel(x, y, c)
	# Eaves line
	for x in range(2, 94):
		image.set_pixel(x, 11, wood_dark)

	# Brick walls with per-brick variation and mortar
	for y in range(12, 58):
		for x in range(4, 92):
			var brick_row_idx = (y - 12) / 6
			var offset_amt = 4 if brick_row_idx % 2 == 0 else 0
			var in_mortar_h = ((y - 12) % 6 == 0)
			var in_mortar_v = ((x + offset_amt) % 8 == 0)
			if in_mortar_h or in_mortar_v:
				image.set_pixel(x, y, mortar)
			else:
				# Per-brick color variation
				var brick_hash = ((x + offset_amt) / 8 + brick_row_idx * 7) % 5
				var c = brick
				if brick_hash == 0:
					c = brick_light
				elif brick_hash == 1:
					c = brick_dark
				# Brick face shading (top lighter, bottom darker)
				var brick_y = (y - 12) % 6
				if brick_y == 1:
					c = c.lightened(0.05)
				elif brick_y == 4:
					c = c.darkened(0.05)
				# Wall left-right shading
				if x < 12:
					c = c.darkened(0.1)
				elif x > 84:
					c = c.darkened(0.1)
				image.set_pixel(x, y, c)
	# Building outline
	for y in range(12, 58):
		image.set_pixel(4, y, outline)
		image.set_pixel(91, y, outline)
	for x in range(4, 92):
		image.set_pixel(x, 57, outline)

	# Large window with frame and warm glow (showing interior)
	# Window frame
	for y in range(14, 42):
		for x in range(10, 86):
			if y == 14 or y == 41 or x == 10 or x == 85:
				image.set_pixel(x, y, window_frame)
			elif y == 15 or x == 11:
				image.set_pixel(x, y, wood_light)  # Inner highlight
	# Window glass with gradient warm glow
	for y in range(16, 40):
		for x in range(12, 84):
			var grad = float(y - 16) / 24.0
			var c = window_bright.lerp(window, grad)
			# Vertical dividers (window panes)
			if x == 32 or x == 56:
				c = window_frame
			# Horizontal divider
			elif y == 28:
				c = window_frame
			image.set_pixel(x, y, c)

	# Stage inside (visible through window) with spotlight
	for y in range(30, 40):
		for x in range(50, 78):
			var dist_center = abs(x - 64.0) / 14.0
			var c = stage if dist_center > 0.5 else stage_light
			image.set_pixel(x, y, c)
	# Stage spotlight (bright circle on stage)
	for dy in range(-3, 4):
		for dx in range(-4, 5):
			var sx = 64 + dx
			var sy = 34 + dy
			if sx >= 12 and sx < 84 and sy >= 16 and sy < 40:
				var dist = sqrt(dx * dx + dy * dy) / 4.0
				if dist < 1.0:
					var glow = Color(1.0, 0.95, 0.7, 0.3 * (1.0 - dist))
					var current = image.get_pixel(sx, sy)
					image.set_pixel(sx, sy, current.lerp(glow, glow.a))

	# Bar counter with beveled wood
	for y in range(28, 38):
		for x in range(16, 45):
			var c = wood_dark
			if y == 28:
				c = wood_light  # Top edge
			elif y == 37:
				c = Color(0.20, 0.12, 0.06)  # Bottom shadow
			elif x == 16 or x == 44:
				c = outline
			image.set_pixel(x, y, c)
	# Mugs on counter
	for mug_x in [20, 28, 36]:
		for y in range(25, 28):
			image.set_pixel(mug_x, y, Color(0.55, 0.45, 0.25))
			image.set_pixel(mug_x + 1, y, Color(0.50, 0.40, 0.22))
		# Foam top
		image.set_pixel(mug_x, 25, Color(0.90, 0.85, 0.70))

	# Door with panel detail
	for y in range(42, 57):
		for x in range(40, 56):
			var c = wood_dark
			if x == 40 or x == 55:
				c = outline
			elif y == 42:
				c = outline
			elif x > 42 and x < 53 and y > 44 and y < 55:
				# Door panel
				if x == 43 or y == 45:
					c = wood  # Panel highlight
				elif x == 52 or y == 54:
					c = Color(0.20, 0.12, 0.06)  # Panel shadow
				else:
					c = Color(0.32, 0.20, 0.10)
			image.set_pixel(x, y, c)
	# Door handle
	image.set_pixel(52, 48, Color(0.72, 0.62, 0.30))
	image.set_pixel(52, 49, Color(0.55, 0.45, 0.22))
	# Step
	for x in range(38, 58):
		image.set_pixel(x, 57, Color(0.50, 0.46, 0.40))

	# Sign board with mug icon (SNES-quality)
	var sign_bg = Color(0.78, 0.68, 0.48)
	var sign_dark = Color(0.55, 0.45, 0.30)
	for y in range(2, 10):
		for x in range(36, 60):
			var c = sign_bg
			if x == 36 or x == 59 or y == 2 or y == 9:
				c = sign_dark  # Border
			elif y == 3 or x == 37:
				c = Color(0.85, 0.78, 0.58)  # Highlight
			image.set_pixel(x, y, c)
	# Mug icon with foam and handle
	var mug_color = Color(0.58, 0.48, 0.28)
	var mug_light = Color(0.68, 0.58, 0.35)
	var foam_color = Color(0.92, 0.88, 0.72)
	# Mug body
	for y in range(4, 8):
		for x in range(44, 51):
			var c = mug_color
			if x == 44:
				c = mug_light  # Left highlight
			elif x == 50:
				c = mug_color.darkened(0.15)
			image.set_pixel(x, y, c)
	# Foam top
	for x in range(43, 52):
		image.set_pixel(x, 4, foam_color)
	# Handle
	image.set_pixel(51, 5, mug_color)
	image.set_pixel(52, 5, mug_color)
	image.set_pixel(52, 6, mug_color)
	image.set_pixel(51, 7, mug_color)
	# Hanging chains
	image.set_pixel(38, 1, outline)
	image.set_pixel(57, 1, outline)


func _generate_dancer_sprites() -> void:
	_dancer_frames.clear()

	# Generate 4 dance animation frames
	for frame in range(4):
		var image = Image.create(24, 32, false, Image.FORMAT_RGBA8)
		_draw_dancer(image, frame)
		var texture = ImageTexture.create_from_image(image)
		_dancer_frames.append(texture)

	if _dancer_frames.size() > 0:
		dancer_sprite.texture = _dancer_frames[0]


func _draw_dancer(image: Image, frame: int) -> void:
	image.fill(Color.TRANSPARENT)

	var skin = Color(0.95, 0.80, 0.70)
	var skin_light = Color(1.0, 0.88, 0.78)
	var skin_shadow = Color(0.82, 0.68, 0.58)
	var hair = Color(0.85, 0.65, 0.25)
	var hair_light = Color(0.95, 0.78, 0.38)
	var hair_dark = Color(0.72, 0.52, 0.18)
	var dress = Color(0.85, 0.25, 0.35)
	var dress_light = Color(0.95, 0.42, 0.52)
	var dress_dark = Color(0.68, 0.15, 0.22)
	var dress_shine = Color(1.0, 0.55, 0.62)
	var outline = Color(0.15, 0.08, 0.10)

	# Animation offsets
	var arm_angle = sin(frame * PI / 2) * 4
	var leg_angle = cos(frame * PI / 2) * 3
	var body_sway = sin(frame * PI / 2) * 2

	var cx = 12 + int(body_sway)

	# Shadow under dancer
	for x in range(cx - 5, cx + 6):
		var dist = abs(x - cx) / 5.0
		if x >= 0 and x < 24 and dist <= 1.0:
			image.set_pixel(x, 30, Color(0, 0, 0, 0.2 * (1.0 - dist)))

	# Head with multi-zone skin shading
	for y in range(2, 10):
		for x in range(cx - 4, cx + 4):
			if x >= 0 and x < 24:
				var c = skin
				# Multi-zone shading
				if y < 4:
					c = skin_light  # Forehead
				elif y > 7:
					c = skin_shadow  # Chin
				elif x < cx - 2:
					c = skin_shadow  # Left shadow
				elif x > cx + 1:
					c = skin_shadow  # Right shadow
				image.set_pixel(x, y, c)
	# Head outline
	for x in range(cx - 4, cx + 4):
		if x >= 0 and x < 24:
			image.set_pixel(x, 1, outline)
	for y in range(2, 10):
		if cx - 5 >= 0:
			image.set_pixel(cx - 5, y, outline)
		if cx + 4 < 24:
			image.set_pixel(cx + 4, y, outline)

	# Eyes (simple but expressive)
	if cx - 2 >= 0 and cx + 2 < 24:
		image.set_pixel(cx - 2, 5, Color(0.15, 0.25, 0.45))  # Left iris
		image.set_pixel(cx - 1, 5, Color(1.0, 1.0, 1.0))      # Catchlight
		image.set_pixel(cx + 1, 5, Color(0.15, 0.25, 0.45))   # Right iris
		image.set_pixel(cx + 2, 5, Color(1.0, 1.0, 1.0))      # Catchlight
	# Mouth (small smile)
	if cx >= 0 and cx < 24:
		image.set_pixel(cx, 7, Color(0.78, 0.45, 0.42))

	# Hair with flowing animation and shading
	for y in range(0, 8):
		for x in range(cx - 5, cx + 5):
			if x >= 0 and x < 24 and y < 6:
				var c = hair
				if x < cx - 2:
					c = hair_light  # Shine on left
				elif x > cx + 2:
					c = hair_dark
				if y < 2:
					c = hair_light  # Top shine
				image.set_pixel(x, y, c)
	# Flowing side hair with wave animation
	var hair_wave = int(sin(frame * PI / 2) * 2)
	for y in range(4, 15):
		var hx = cx + 5 + hair_wave
		if hx >= 0 and hx < 24:
			var c = hair if y < 10 else hair_dark
			image.set_pixel(hx, y, c)
		# Hair on other side too
		var hx2 = cx - 5 - hair_wave
		if hx2 >= 0 and hx2 < 24 and y < 12:
			image.set_pixel(hx2, y, hair_dark)

	# Dress body with 3-zone shading and fabric flow
	for y in range(10, 26):
		var dress_width = 5 if y < 18 else (7 + int(sin(y * 0.5 + frame * 1.5) * 1.5))
		for x in range(cx - dress_width, cx + dress_width):
			if x >= 0 and x < 24:
				var rel_x = float(x - (cx - dress_width)) / float(dress_width * 2)
				var c = dress
				# Fabric shading: left highlight, center, right shadow
				if rel_x < 0.2:
					c = dress_dark
				elif rel_x < 0.35:
					c = dress
				elif rel_x > 0.8:
					c = dress_dark
				elif rel_x > 0.55:
					c = dress_light
				# Satin shine highlights
				if y < 14 and rel_x > 0.35 and rel_x < 0.55:
					c = dress_shine
				# Skirt folds (wavy lines)
				if y > 18 and sin(x * 0.8 + y * 0.5 + frame) > 0.5:
					c = c.lightened(0.06)
				image.set_pixel(x, y, c)
		# Dress outline on sides
		var left_edge = cx - dress_width - 1
		var right_edge = cx + dress_width
		if left_edge >= 0 and left_edge < 24:
			image.set_pixel(left_edge, y, outline)
		if right_edge >= 0 and right_edge < 24:
			image.set_pixel(right_edge, y, outline)
	# Dress hemline
	for x in range(cx - 8, cx + 9):
		if x >= 0 and x < 24:
			image.set_pixel(x, 26, outline)

	# Belt/sash detail at waist
	for x in range(cx - 5, cx + 5):
		if x >= 0 and x < 24:
			image.set_pixel(x, 14, Color(0.82, 0.68, 0.28))

	# Arms (raised in dance pose) with skin tones and outline
	var left_arm_x = cx - 6 + int(arm_angle)
	var right_arm_x = cx + 5 - int(arm_angle)
	for y in range(11, 18):
		if left_arm_x >= 0 and left_arm_x < 24:
			image.set_pixel(left_arm_x, y, skin_shadow)
			if left_arm_x + 1 < 24:
				image.set_pixel(left_arm_x + 1, y, skin)
		if right_arm_x >= 0 and right_arm_x < 24:
			image.set_pixel(right_arm_x, y, skin)
			if right_arm_x - 1 >= 0:
				image.set_pixel(right_arm_x - 1, y, skin_shadow)
	# Hands (skin dot at arm end)
	if left_arm_x >= 0 and left_arm_x < 24:
		image.set_pixel(left_arm_x, 11, skin_light)
	if right_arm_x >= 0 and right_arm_x < 24:
		image.set_pixel(right_arm_x, 11, skin_light)

	# Legs/feet peeking from dress
	var left_foot_x = cx - 3 + int(leg_angle)
	var right_foot_x = cx + 2 - int(leg_angle)
	for foot_x in [left_foot_x, right_foot_x]:
		if foot_x >= 0 and foot_x < 24:
			image.set_pixel(foot_x, 27, skin)
			image.set_pixel(foot_x, 28, Color(0.72, 0.25, 0.30))  # Red shoe
			if foot_x + 1 < 24:
				image.set_pixel(foot_x + 1, 28, Color(0.65, 0.20, 0.25))

	# Legs (dancing)
	var left_leg_x = cx - 3 + int(leg_angle)
	var right_leg_x = cx + 2 - int(leg_angle)
	for y in range(26, 32):
		if left_leg_x >= 0 and left_leg_x < 24:
			image.set_pixel(left_leg_x, y, skin)
		if right_leg_x >= 0 and right_leg_x < 24:
			image.set_pixel(right_leg_x, y, skin)


func _setup_collision() -> void:
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(TILE_SIZE * 2, TILE_SIZE)
	collision.shape = shape
	collision.position = Vector2(0, TILE_SIZE / 2)
	add_child(collision)

	collision_layer = 4
	collision_mask = 2
	monitoring = true
	monitorable = true


func _setup_name_label() -> void:
	name_label = Label.new()
	name_label.text = bar_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(-70, -50)
	name_label.size = Vector2(140, 20)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.5))
	name_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	name_label.visible = false
	add_child(name_label)


func _setup_enter_label() -> void:
	enter_label = Label.new()
	enter_label.text = "[A] Enter"
	enter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enter_label.position = Vector2(-30, 35)
	enter_label.size = Vector2(60, 20)
	enter_label.add_theme_font_size_override("font_size", 10)
	enter_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	enter_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	enter_label.add_theme_constant_override("shadow_offset_x", 1)
	enter_label.add_theme_constant_override("shadow_offset_y", 1)
	enter_label.visible = false
	add_child(enter_label)


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("set_can_move"):
		_player_nearby = true
		name_label.visible = true
		enter_label.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.has_method("set_can_move"):
		_player_nearby = false
		name_label.visible = false
		enter_label.visible = false


func interact(_player: Node2D) -> void:
	# Trigger transition to tavern interior
	print("[BAR] Interact triggered - transitioning to tavern_interior")
	if SoundManager:
		SoundManager.play_ui("menu_open")
	transition_triggered.emit("tavern_interior", "entrance")
	print("[BAR] transition_triggered signal emitted")
