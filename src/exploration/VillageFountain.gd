extends Area2D
class_name VillageFountain

## VillageFountain - Decorative fountain with tree in village center
## Provides ambient animation and lore dialogue

@export var fountain_name: String = "Village Fountain"
@export var tree_type: String = "cherry"  # cherry, oak, willow

## Visual
var sprite: Sprite2D
var name_label: Label
var dialogue_box: Control
var dialogue_label: Label

## Animation
var _anim_frame: int = 0
var _anim_timer: float = 0.0
const ANIM_SPEED: float = 0.25
var _sprite_frames: Array[ImageTexture] = []

## State
var _player_nearby: bool = false
var _dialogue_state: int = 0

const TILE_SIZE: int = 32

## Fountain lore dialogue
const FOUNTAIN_DIALOGUE = [
	"The fountain's water sparkles in the light.",
	"Legend says this tree was planted when Harmonia was founded.",
	"Toss a coin for luck? ...Nah, you'll need it for potions.",
	"The gentle sound of flowing water is soothing.",
	"You feel at peace."
]


func _ready() -> void:
	_generate_sprite_frames()
	_setup_collision()
	_setup_name_label()
	_setup_dialogue_box()

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	# Animate water
	_anim_timer += delta
	if _anim_timer >= ANIM_SPEED:
		_anim_timer -= ANIM_SPEED
		_anim_frame = (_anim_frame + 1) % _sprite_frames.size()
		if sprite and _sprite_frames.size() > 0:
			sprite.texture = _sprite_frames[_anim_frame]


func _generate_sprite_frames() -> void:
	sprite = Sprite2D.new()
	sprite.name = "Sprite"
	add_child(sprite)

	_sprite_frames.clear()

	# Generate 4 animation frames
	for frame in range(4):
		var image = Image.create(TILE_SIZE * 3, TILE_SIZE * 3, false, Image.FORMAT_RGBA8)
		_draw_fountain(image, frame)
		var texture = ImageTexture.create_from_image(image)
		_sprite_frames.append(texture)

	if _sprite_frames.size() > 0:
		sprite.texture = _sprite_frames[0]


func _draw_fountain(image: Image, frame: int) -> void:
	image.fill(Color.TRANSPARENT)

	var stone = Color(0.62, 0.60, 0.56)
	var stone_light = Color(0.72, 0.70, 0.66)
	var stone_dark = Color(0.45, 0.43, 0.40)
	var stone_shadow = Color(0.35, 0.33, 0.30)
	var water = Color(0.28, 0.48, 0.78, 0.85)
	var water_mid = Color(0.35, 0.55, 0.82, 0.88)
	var water_light = Color(0.52, 0.72, 0.95, 0.92)
	var water_deep = Color(0.18, 0.35, 0.62, 0.82)
	var water_sparkle = Color(0.85, 0.92, 1.0, 0.95)
	var trunk = Color(0.42, 0.28, 0.15)
	var trunk_light = Color(0.52, 0.38, 0.22)
	var trunk_dark = Color(0.30, 0.18, 0.08)
	var leaves = Color(0.25, 0.50, 0.25)
	var leaves_light = Color(0.38, 0.62, 0.35)
	var leaves_dark = Color(0.15, 0.38, 0.16)
	var leaves_deep = Color(0.08, 0.25, 0.10)
	var outline = Color(0.12, 0.10, 0.08)

	# Cherry blossom colors
	if tree_type == "cherry":
		leaves = Color(0.95, 0.70, 0.75)
		leaves_light = Color(1.0, 0.85, 0.88)
		leaves_dark = Color(0.80, 0.55, 0.62)
		leaves_deep = Color(0.65, 0.42, 0.48)

	var cx = 48
	var cy = 48

	# Fountain base (circular stone basin with 3D carved look)
	for y in range(54, 82):
		for x in range(14, 82):
			var dx = float(x - cx)
			var dy = float(y - 68) * 1.5
			var dist = sqrt(dx * dx + dy * dy)
			# Outer basin rim
			if dist < 36 and dist > 30:
				var c = stone
				# Cylindrical shading on rim
				var norm_d = (dist - 30) / 6.0
				if norm_d < 0.3:
					c = stone_light  # Inner edge highlight
				elif norm_d > 0.7:
					c = stone_dark  # Outer edge shadow
				# Left-right shading
				if dx < -10:
					c = c.darkened(0.08)
				elif dx > 10:
					c = c.lightened(0.05)
				# Stone texture
				if (x + y * 2) % 7 == 0:
					c = c.darkened(0.05)
				image.set_pixel(x, y, c)
			elif dist <= 30 and dist > 28:
				# Inner rim shadow
				image.set_pixel(x, y, stone_shadow)
			elif dist <= 28:
				# Water in basin with multi-frequency waves
				var w1 = sin((x + frame * 6) * 0.35 + y * 0.2) * 0.4 + 0.5
				var w2 = sin((x - frame * 4) * 0.25 + y * 0.35) * 0.3 + 0.5
				var combined = (w1 + w2) / 2.0
				var c = water
				if combined > 0.7:
					c = water_light
				elif combined > 0.55:
					c = water_mid
				elif combined < 0.3:
					c = water_deep
				# Depth shading (deeper toward center)
				var depth_factor = 1.0 - (dist / 28.0)
				c = c.darkened(depth_factor * 0.15)
				image.set_pixel(x, y, c)
			# Outer outline
			elif dist < 37 and dist >= 36:
				image.set_pixel(x, y, outline)

	# Water sparkle highlights in basin
	var sparkle_positions = [
		[cx - 12, 62], [cx + 8, 65], [cx - 5, 70], [cx + 15, 68]
	]
	for sp in sparkle_positions:
		var sx = sp[0] + (frame % 2)
		var sy = sp[1]
		if sx >= 0 and sx < 96 and sy >= 0 and sy < 96:
			image.set_pixel(sx, sy, water_sparkle)

	# Central pillar with cylindrical shading and decorative bands
	for y in range(38, 70):
		var pillar_half_w = 4
		for dx in range(-pillar_half_w, pillar_half_w + 1):
			var x = cx + dx
			if x >= 0 and x < 96:
				var c = stone
				# Cylindrical shading
				var rel = float(dx + pillar_half_w) / float(pillar_half_w * 2)
				if rel < 0.2:
					c = stone_dark
				elif rel < 0.4:
					c = stone
				elif rel < 0.6:
					c = stone_light  # Center highlight
				elif rel < 0.8:
					c = stone
				else:
					c = stone_dark
				# Decorative bands
				if y == 42 or y == 50 or y == 60:
					c = stone_light
				elif y == 43 or y == 51 or y == 61:
					c = stone_shadow
				image.set_pixel(x, y, c)
		# Pillar outline
		if cx - pillar_half_w - 1 >= 0:
			image.set_pixel(cx - pillar_half_w - 1, y, outline)
		if cx + pillar_half_w + 1 < 96:
			image.set_pixel(cx + pillar_half_w + 1, y, outline)

	# Water spout/bowl at top of pillar
	for dx in range(-6, 7):
		var x = cx + dx
		if x >= 0 and x < 96:
			image.set_pixel(x, 38, stone_light)
			image.set_pixel(x, 39, stone)
			if abs(dx) > 4:
				image.set_pixel(x, 37, stone_dark)

	# Water jets (animated, multi-stream)
	var jet_heights = [12, 14, 12, 10]
	var jet_height = jet_heights[frame]
	# Center jet
	for y in range(38 - jet_height, 38):
		var jx = cx
		var jet_t = float(38 - y) / jet_height
		var c = water_light if jet_t < 0.5 else water_sparkle
		if jx >= 0 and jx < 96 and y >= 0:
			image.set_pixel(jx, y, c)
			if jx + 1 < 96:
				image.set_pixel(jx + 1, y, water_mid)

	# Water arcs falling outward (parabolic)
	for arc_dir in [-1, 1]:
		for t_step in range(12):
			var t = float(t_step) / 12.0
			var ax = cx + int(arc_dir * t * 14 + frame * arc_dir * 0.5)
			var ay = 38 + int(t * t * 18) - 4
			if ax >= 0 and ax < 96 and ay >= 0 and ay < 96:
				image.set_pixel(ax, ay, water_light)
				if ay + 1 < 96:
					image.set_pixel(ax, ay + 1, water_mid)

	# Animated water droplets falling
	var drop_offset = frame * 3
	for i in range(6):
		var dx_f = (i - 3) * 8 + (drop_offset % 6) - 3
		var dy_f = 40 + (drop_offset + i * 4) % 20
		if dy_f > 38 and dy_f < 60:
			var px = cx + dx_f
			if px >= 0 and px < 96:
				image.set_pixel(px, dy_f, water_light)
				if dy_f + 1 < 96:
					image.set_pixel(px, dy_f + 1, water_mid)

	# Tree trunk with bark texture and shading
	var trunk_top = 8
	var trunk_bottom = 42
	for y in range(trunk_top, trunk_bottom):
		var trunk_half = 3
		for dx in range(-trunk_half, trunk_half + 1):
			var x = cx + dx
			if x >= 0 and x < 96:
				var c = trunk
				if dx < -1:
					c = trunk_light  # Left highlight
				elif dx > 1:
					c = trunk_dark  # Right shadow
				# Bark texture
				if (y + dx) % 4 == 0:
					c = trunk_dark
				image.set_pixel(x, y, c)
		# Trunk outline
		if cx - trunk_half - 1 >= 0:
			image.set_pixel(cx - trunk_half - 1, y, outline)
		if cx + trunk_half + 1 < 96:
			image.set_pixel(cx + trunk_half + 1, y, outline)

	# Tree canopy with multi-zone shading (SNES-style 3D foliage)
	var foliage_cx = cx
	var foliage_cy = 10
	var foliage_r = 28
	for y in range(foliage_cy - foliage_r, foliage_cy + foliage_r):
		for x in range(foliage_cx - foliage_r, foliage_cx + foliage_r):
			if x < 0 or x >= 96 or y < 0 or y >= 96:
				continue
			var dist = sqrt(pow(x - foliage_cx, 2) + pow(y - foliage_cy, 2))
			if dist < foliage_r - 1.5:
				var norm_y = float(y - foliage_cy) / foliage_r
				var norm_x = float(x - foliage_cx) / foliage_r
				var c = leaves
				# Multi-zone canopy shading
				if norm_y < -0.4:
					c = leaves_light  # Top highlight
				elif norm_y < -0.1 and norm_x < 0:
					c = leaves_light  # Upper-left light
				elif norm_y > 0.4:
					c = leaves_deep  # Bottom deep shadow
				elif norm_y > 0.15:
					c = leaves_dark  # Lower shadow
				elif norm_x > 0.4:
					c = leaves_dark  # Right shadow
				# Leaf cluster texture noise
				var leaf_noise = sin(x * 1.5 + y * 1.2 + frame * 0.5) * 0.5
				if leaf_noise > 0.3 and c != leaves_deep:
					c = c.lightened(0.06)
				elif leaf_noise < -0.3 and c != leaves_light:
					c = c.darkened(0.06)
				# Wind animation (subtle shift)
				var wind = sin(x * 0.1 + frame * 1.5) * 0.5
				if wind > 0.3 and norm_y < 0:
					c = c.lightened(0.03)
				image.set_pixel(x, y, c)
			elif dist < foliage_r:
				# Foliage outline
				image.set_pixel(x, y, leaves_deep)

	# Dappled light highlights on canopy
	for i in range(5):
		var hx = foliage_cx + int(cos(i * 1.8 + frame * 0.3) * 12) - 6
		var hy = foliage_cy + int(sin(i * 2.1 + frame * 0.3) * 10) - 8
		if hx >= 0 and hx < 96 and hy >= 0 and hy < 96:
			image.set_pixel(hx, hy, leaves_light.lightened(0.12))

	# Falling petals/leaves (all tree types, more for cherry)
	var petal_count = 5 if tree_type == "cherry" else 2
	for i in range(petal_count):
		var px_f = 25 + i * 12 + int(sin(frame * 1.2 + i * 2.5) * 5)
		var py_f = 30 + (frame * 4 + i * 8) % 30
		if py_f > 25 and py_f < 60 and px_f >= 0 and px_f < 96:
			image.set_pixel(px_f, py_f, leaves_light)
			# Petal shape (2-pixel for visibility)
			if px_f + 1 < 96:
				image.set_pixel(px_f + 1, py_f, leaves.lightened(0.1))


func _setup_collision() -> void:
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(TILE_SIZE * 2, TILE_SIZE * 2)
	collision.shape = shape
	collision.position = Vector2(0, TILE_SIZE / 2)  # Centered on base
	add_child(collision)

	collision_layer = 4
	collision_mask = 2
	monitoring = true
	monitorable = true


func _setup_name_label() -> void:
	name_label = Label.new()
	name_label.text = fountain_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(-50, -50)
	name_label.size = Vector2(100, 20)
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
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

	var panel = Panel.new()
	panel.position = Vector2(-120, -100)
	panel.size = Vector2(240, 70)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.15, 0.2, 0.95)
	style.border_color = Color(0.5, 0.7, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	dialogue_box.add_child(panel)

	dialogue_label = Label.new()
	dialogue_label.position = Vector2(-112, -92)
	dialogue_label.size = Vector2(224, 54)
	dialogue_label.add_theme_font_size_override("font_size", 11)
	dialogue_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_box.add_child(dialogue_label)

	add_child(dialogue_box)


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("set_can_move"):
		_player_nearby = true
		name_label.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.has_method("set_can_move"):
		_player_nearby = false
		name_label.visible = false
		dialogue_box.visible = false
		_dialogue_state = 0


func interact(player: Node2D) -> void:
	dialogue_box.visible = true
	dialogue_label.text = FOUNTAIN_DIALOGUE[_dialogue_state]
	_dialogue_state = (_dialogue_state + 1) % FOUNTAIN_DIALOGUE.size()

	if SoundManager:
		SoundManager.play_ui("menu_select")
