extends Node2D
class_name Landmark

## Landmark — visual decoration on the overworld map.
## Ruins, campfires, stone circles, etc. Pure visual, no interaction.
## Makes the world feel lived-in and helps with navigation.

enum Type { RUINS, CAMPFIRE, STONE_CIRCLE, WELL, STATUE }

const TILE_SIZE: int = 32

@export var landmark_type: Type = Type.RUINS
var _sprite: Sprite2D
var _glow: Sprite2D  # For campfire flicker


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.centered = true

	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	match landmark_type:
		Type.RUINS:
			_draw_ruins(img)
		Type.CAMPFIRE:
			_draw_campfire(img)
		Type.STONE_CIRCLE:
			_draw_stone_circle(img)
		Type.WELL:
			_draw_well(img)
		Type.STATUE:
			_draw_statue(img)

	_sprite.texture = ImageTexture.create_from_image(img)
	add_child(_sprite)


func _process(delta: float) -> void:
	# Campfire flicker
	if landmark_type == Type.CAMPFIRE and _sprite:
		var t = fmod(Time.get_ticks_msec() / 200.0, 1.0)
		_sprite.modulate = Color(1.0, 0.85 + 0.15 * sin(t * TAU), 0.7 + 0.3 * sin(t * TAU * 1.5))


func _draw_ruins(img: Image) -> void:
	var stone = Color(0.45, 0.42, 0.38)
	var dark = Color(0.3, 0.28, 0.25)
	var moss = Color(0.35, 0.5, 0.3)
	# Broken walls
	for y in range(18, 30):
		for x in range(6, 10):
			img.set_pixel(x, y, stone if (x + y) % 3 != 0 else dark)
	for y in range(14, 28):
		for x in range(20, 24):
			img.set_pixel(x, y, stone if (x + y) % 3 != 0 else dark)
	# Fallen column
	for x in range(10, 22):
		img.set_pixel(x, 26, stone)
		img.set_pixel(x, 27, dark)
	# Moss spots
	img.set_pixel(8, 20, moss)
	img.set_pixel(21, 16, moss)
	img.set_pixel(12, 27, moss)


func _draw_campfire(img: Image) -> void:
	var ash = Color(0.25, 0.22, 0.2)
	var ember = Color(0.9, 0.3, 0.1)
	var flame = Color(1.0, 0.7, 0.2)
	var log_c = Color(0.4, 0.25, 0.1)
	# Ash circle
	for y in range(22, 30):
		for x in range(10, 22):
			var dx = x - 16
			var dy = y - 26
			if dx * dx + dy * dy < 20:
				img.set_pixel(x, y, ash)
	# Logs
	for i in range(5):
		img.set_pixel(12 + i, 25, log_c)
		img.set_pixel(15 + i, 26, log_c)
	# Flames
	for y in range(18, 24):
		img.set_pixel(15, y, flame)
		img.set_pixel(16, y, ember)
		if y < 22:
			img.set_pixel(14, y, ember)
			img.set_pixel(17, y, flame)


func _draw_stone_circle(img: Image) -> void:
	var stone = Color(0.5, 0.48, 0.45)
	var dark = Color(0.35, 0.33, 0.3)
	# Ring of stones
	var cx = 16
	var cy = 16
	var r = 10
	for angle_i in range(8):
		var a = angle_i * TAU / 8.0
		var sx = cx + int(cos(a) * r)
		var sy = cy + int(sin(a) * r)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var px = sx + dx
				var py = sy + dy
				if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
					img.set_pixel(px, py, stone if (dx + dy) % 2 == 0 else dark)


func _draw_well(img: Image) -> void:
	var stone = Color(0.5, 0.48, 0.42)
	var dark = Color(0.2, 0.18, 0.15)
	var water = Color(0.2, 0.35, 0.55)
	# Stone rim
	for y in range(18, 28):
		for x in range(10, 22):
			var dx = x - 16
			var dy = y - 23
			var dist = dx * dx + dy * dy
			if dist < 30 and dist > 15:
				img.set_pixel(x, y, stone)
			elif dist <= 15:
				img.set_pixel(x, y, water if y > 20 else dark)
	# Posts
	img.set_pixel(10, 14, stone)
	img.set_pixel(10, 15, stone)
	img.set_pixel(10, 16, stone)
	img.set_pixel(10, 17, stone)
	img.set_pixel(21, 14, stone)
	img.set_pixel(21, 15, stone)
	img.set_pixel(21, 16, stone)
	img.set_pixel(21, 17, stone)
	# Crossbar
	for x in range(10, 22):
		img.set_pixel(x, 14, stone)


func _draw_statue(img: Image) -> void:
	var stone = Color(0.55, 0.52, 0.48)
	var dark = Color(0.38, 0.35, 0.32)
	# Pedestal
	for y in range(24, 30):
		for x in range(10, 22):
			img.set_pixel(x, y, dark if y == 24 else stone)
	# Figure (simple silhouette)
	for y in range(8, 24):
		var w = 3 if y < 12 else 4 if y < 20 else 5
		for dx in range(-w, w + 1):
			var px = 16 + dx
			if px >= 0 and px < TILE_SIZE:
				img.set_pixel(px, y, stone if abs(dx) < w else dark)
	# Head
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if dx * dx + dy * dy <= 4:
				img.set_pixel(16 + dx, 6 + dy, stone)
