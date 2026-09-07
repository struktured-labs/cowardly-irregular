extends Node2D
class_name Landmark

## Landmark — visual decoration on the overworld map.
## Ruins, campfires, stone circles, etc. Pure visual, no interaction.
## Makes the world feel lived-in and helps with navigation.

enum Type {
	RUINS, CAMPFIRE, STONE_CIRCLE, WELL, STATUE,
	# World-specific types
	FIRE_HYDRANT,   # W2 Suburban
	BUS_STOP,       # W2 Suburban
	GEAR_PILE,      # W3 Steampunk
	STEAM_PIPE,     # W3 Steampunk
	SMOKESTACK,     # W4 Industrial
	BARREL_STACK,   # W4 Industrial
	DATA_TERMINAL,  # W5 Futuristic
	SERVER_RACK,    # W5 Futuristic
	VOID_CRYSTAL,   # W6 Abstract
}

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
		Type.FIRE_HYDRANT:
			_draw_fire_hydrant(img)
		Type.BUS_STOP:
			_draw_bus_stop(img)
		Type.GEAR_PILE:
			_draw_gear_pile(img)
		Type.STEAM_PIPE:
			_draw_steam_pipe(img)
		Type.SMOKESTACK:
			_draw_smokestack(img)
		Type.BARREL_STACK:
			_draw_barrel_stack(img)
		Type.DATA_TERMINAL:
			_draw_data_terminal(img)
		Type.SERVER_RACK:
			_draw_server_rack(img)
		Type.VOID_CRYSTAL:
			_draw_void_crystal(img)

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


# --- World-specific landmark draws ---

func _draw_fire_hydrant(img: Image) -> void:
	var red = Color(0.85, 0.15, 0.1)
	var dark = Color(0.6, 0.1, 0.08)
	var cap = Color(0.7, 0.7, 0.7)
	# Body
	for y in range(16, 28):
		for x in range(13, 19):
			img.set_pixel(x, y, red if (x + y) % 3 != 0 else dark)
	# Cap
	for x in range(12, 20):
		img.set_pixel(x, 15, cap)
		img.set_pixel(x, 14, cap)
	# Nozzles
	img.set_pixel(11, 20, dark)
	img.set_pixel(12, 20, red)
	img.set_pixel(19, 20, red)
	img.set_pixel(20, 20, dark)


func _draw_bus_stop(img: Image) -> void:
	var pole = Color(0.6, 0.6, 0.6)
	var sign_c = Color(0.2, 0.4, 0.7)
	# Pole
	for y in range(10, 30):
		img.set_pixel(16, y, pole)
	# Sign
	for y in range(8, 14):
		for x in range(11, 22):
			img.set_pixel(x, y, sign_c)
	# Bench
	for x in range(10, 22):
		img.set_pixel(x, 26, Color(0.45, 0.3, 0.15))
		img.set_pixel(x, 27, Color(0.35, 0.22, 0.1))


func _draw_gear_pile(img: Image) -> void:
	var brass = Color(0.72, 0.58, 0.3)
	var dark = Color(0.5, 0.4, 0.2)
	# Large gear
	for angle_i in range(12):
		var a = angle_i * TAU / 12.0
		var gx = 14 + int(cos(a) * 8)
		var gy = 18 + int(sin(a) * 8)
		if gx >= 0 and gx < TILE_SIZE and gy >= 0 and gy < TILE_SIZE:
			img.set_pixel(gx, gy, brass)
	# Small gear
	for angle_i in range(8):
		var a = angle_i * TAU / 8.0
		var gx = 20 + int(cos(a) * 4)
		var gy = 12 + int(sin(a) * 4)
		if gx >= 0 and gx < TILE_SIZE and gy >= 0 and gy < TILE_SIZE:
			img.set_pixel(gx, gy, dark)
	# Center dots
	img.set_pixel(14, 18, dark)
	img.set_pixel(20, 12, brass)


func _draw_steam_pipe(img: Image) -> void:
	var pipe = Color(0.5, 0.45, 0.4)
	var dark = Color(0.35, 0.3, 0.28)
	var steam = Color(0.85, 0.85, 0.82, 0.5)
	# Horizontal pipe
	for x in range(4, 28):
		img.set_pixel(x, 20, pipe)
		img.set_pixel(x, 21, dark)
	# Valve
	for y in range(16, 20):
		img.set_pixel(15, y, pipe)
		img.set_pixel(16, y, dark)
	# Steam wisps
	img.set_pixel(15, 14, steam)
	img.set_pixel(16, 13, steam)
	img.set_pixel(14, 12, steam)


func _draw_smokestack(img: Image) -> void:
	var brick = Color(0.5, 0.3, 0.25)
	var dark = Color(0.35, 0.2, 0.15)
	var smoke = Color(0.4, 0.4, 0.4, 0.6)
	# Stack
	for y in range(10, 30):
		var w = 3 if y < 20 else 4
		for dx in range(-w, w + 1):
			img.set_pixel(16 + dx, y, brick if (dx + y) % 3 != 0 else dark)
	# Smoke
	for dy in range(0, 8):
		var sx = 16 + (dy % 3) - 1
		if sx >= 0 and sx < TILE_SIZE:
			img.set_pixel(sx, 9 - dy, smoke)


func _draw_barrel_stack(img: Image) -> void:
	var barrel = Color(0.55, 0.4, 0.2)
	var band = Color(0.4, 0.4, 0.4)
	# Bottom row (2 barrels)
	for i in range(2):
		var bx = 10 + i * 10
		for y in range(20, 28):
			for x in range(bx, bx + 8):
				if x < TILE_SIZE:
					img.set_pixel(x, y, barrel if y != 23 else band)
	# Top barrel
	for y in range(13, 21):
		for x in range(13, 21):
			img.set_pixel(x, y, barrel if y != 16 else band)


func _draw_data_terminal(img: Image) -> void:
	var frame = Color(0.2, 0.25, 0.3)
	var screen = Color(0.0, 0.6, 0.4)
	var dark = Color(0.0, 0.3, 0.2)
	# Terminal body
	for y in range(10, 26):
		for x in range(10, 22):
			if x == 10 or x == 21 or y == 10 or y == 25:
				img.set_pixel(x, y, frame)
			else:
				img.set_pixel(x, y, screen if (x + y) % 2 == 0 else dark)
	# Stand
	for y in range(26, 30):
		img.set_pixel(15, y, frame)
		img.set_pixel(16, y, frame)


func _draw_server_rack(img: Image) -> void:
	var frame = Color(0.25, 0.25, 0.28)
	var led_on = Color(0.0, 0.9, 0.3)
	var led_off = Color(0.15, 0.15, 0.18)
	# Rack body
	for y in range(6, 28):
		for x in range(10, 22):
			if x == 10 or x == 21 or y == 6 or y == 27:
				img.set_pixel(x, y, frame)
			else:
				img.set_pixel(x, y, led_off)
	# LED rows
	for row in range(4):
		var y = 9 + row * 5
		for x in range(12, 20):
			img.set_pixel(x, y, led_on if (x + row) % 3 == 0 else led_off)


func _draw_void_crystal(img: Image) -> void:
	var crystal = Color(0.9, 0.9, 1.0, 0.6)
	var core = Color(1.0, 1.0, 1.0, 0.8)
	# Diamond shape floating
	var cx = 16
	var cy = 14
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var dx = abs(x - cx)
			var dy = abs(y - cy)
			if dx + dy < 8:
				var t = float(dx + dy) / 8.0
				img.set_pixel(x, y, core if dx + dy < 3 else crystal)
