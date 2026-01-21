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

	var stone = Color(0.6, 0.58, 0.55)
	var stone_dark = Color(0.45, 0.43, 0.40)
	var water = Color(0.3, 0.5, 0.8, 0.8)
	var water_light = Color(0.5, 0.7, 0.95, 0.9)
	var trunk = Color(0.4, 0.28, 0.15)
	var leaves = Color(0.25, 0.5, 0.25)
	var leaves_light = Color(0.35, 0.6, 0.35)

	# Cherry blossom colors
	if tree_type == "cherry":
		leaves = Color(0.95, 0.7, 0.75)
		leaves_light = Color(1.0, 0.85, 0.88)

	var cx = 48  # Center x
	var cy = 48  # Center y

	# Fountain base (circular stone basin)
	for y in range(56, 80):
		for x in range(16, 80):
			var dx = x - cx
			var dy = (y - 68) * 1.5
			var dist = sqrt(dx * dx + dy * dy)
			if dist < 34 and dist > 28:
				image.set_pixel(x, y, stone if (x + y) % 3 != 0 else stone_dark)
			elif dist <= 28:
				# Water in basin
				var water_anim = sin((x + y + frame * 8) * 0.3) > 0
				image.set_pixel(x, y, water if water_anim else water_light)

	# Central pillar
	for y in range(40, 70):
		for x in range(44, 52):
			image.set_pixel(x, y, stone if y % 4 < 2 else stone_dark)

	# Water jets (animated)
	var jet_heights = [12, 14, 12, 10]  # Varying heights
	var jet_height = jet_heights[frame]
	for y in range(40 - jet_height, 40):
		# Center jet
		image.set_pixel(47, y, water_light)
		image.set_pixel(48, y, water_light)

	# Water falling (animated droplets)
	var drop_offset = frame * 3
	for i in range(4):
		var dx = (i - 2) * 10 + (drop_offset % 8) - 4
		var dy = 40 + (drop_offset + i * 5) % 18
		if dy > 40 and dy < 58:
			var px = cx + dx
			var py = dy
			if px >= 0 and px < 96:
				image.set_pixel(px, py, water_light)

	# Tree in center of fountain
	# Trunk
	for y in range(10, 45):
		for x in range(45, 51):
			image.set_pixel(x, y, trunk)

	# Tree canopy (large fluffy circle)
	for y in range(-5, 30):
		for x in range(20, 76):
			var dx = x - cx
			var dy = y - 10
			var dist = sqrt(dx * dx + dy * dy)
			if dist < 28:
				# Leafy texture
				var leaf_anim = sin((x * 0.5 + y * 0.7 + frame * 0.5)) > -0.3
				if leaf_anim:
					var c = leaves if (x + y + frame) % 3 != 0 else leaves_light
					if y >= 0:
						image.set_pixel(x, y, c)

	# Falling petals/leaves (for cherry tree)
	if tree_type == "cherry":
		var petal_positions = [
			Vector2(30, 35 + frame * 4),
			Vector2(55, 30 + (frame + 2) % 4 * 5),
			Vector2(70, 40 + (frame + 1) % 4 * 4),
		]
		for petal_pos in petal_positions:
			if petal_pos.y > 25 and petal_pos.y < 55:
				image.set_pixel(int(petal_pos.x), int(petal_pos.y), leaves_light)


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
