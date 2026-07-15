extends Node2D
class_name InnInterior

## InnInterior — "The Traveler's Rest" inn lobby
## Procedural top-down SNES-style inn interior.
## Cozy coaching inn: registration desk, central fireplace, communal table,
## stairs-up visual, coat rack, travel gear, wall art, hanging lanterns.

signal transition_triggered(target_map: String, target_spawn: String)
signal area_transition(target_map: String, target_spawn: String)
signal rest_requested()

const TILE_SIZE: int = 32
const MAP_WIDTH: int = 20
const MAP_HEIGHT: int = 14

## Scene nodes
var tilemap: TileMapLayer
var player: Node2D
var camera: Camera2D
var npcs: Node2D
var transitions: Node2D
var decorations: Node2D
var controller: Node

## Fireplace animation
var _fire_sprite: Sprite2D
var _fire_frames: Array[ImageTexture] = []
var _fire_frame: int = 0
var _fire_timer: float = 0.0
const FIRE_SPEED: float = 0.12

## Fireplace light flicker
var _fire_light: PointLight2D
var _fire_time: float = 0.0

## Spawn points (grid coords)
var spawn_points: Dictionary = {
	"entrance": Vector2(10, 12),
	"desk":     Vector2(3,  4),
	"fireplace": Vector2(10, 5),
}

## Layout — 20 cols × 14 rows
## W = half-timbered wall, . = wood plank floor
## h = stone hearth tile, c = carpet runner tile
## D = entrance door (south), U = stairs-up blocker
const INN_LAYOUT = [
	"WWWWWWWWWWWWWWWWWWWW",
	"W..................W",
	"W.DDD..........UUW",
	"W.DDD..........UUW",
	"W..................W",
	"W....hhh...........W",
	"W....hhh...........W",
	"W..ccccccccc.......W",
	"W..ccccccccc.......W",
	"W..................W",
	"W..................W",
	"W..................W",
	"W..................W",
	"WWWWWWWWWDDWWWWWWWWW",
]


## Rest service state
var _rest_pending: bool = false
var _rest_dialog: Control = null


func _ready() -> void:
	_setup_tilemap()
	_setup_decorations()
	_setup_fireplace_anim()
	_setup_npcs()
	_create_rest_interactable()
	_setup_transitions()
	_setup_player()
	_setup_camera()
	_setup_controller()

	if SoundManager:
		SoundManager.play_area_music("interior_inn")


func _process(delta: float) -> void:
	_animate_fireplace(delta)
	_flicker_fire_light(delta)


# ---------------------------------------------------------------------------
# Tilemap
# ---------------------------------------------------------------------------

func _setup_tilemap() -> void:
	tilemap = TileMapLayer.new()
	tilemap.name = "TileMapLayer"
	add_child(tilemap)

	var tileset = TileSet.new()
	tileset.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Source 0 — wood plank floor
	var floor_src = TileSetAtlasSource.new()
	var floor_img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	_draw_plank_floor(floor_img)
	floor_src.texture = ImageTexture.create_from_image(floor_img)
	floor_src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	floor_src.create_tile(Vector2i(0, 0))
	tileset.add_source(floor_src, 0)

	# Source 1 — half-timbered wall
	var wall_src = TileSetAtlasSource.new()
	var wall_img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	_draw_halftimber_wall(wall_img)
	wall_src.texture = ImageTexture.create_from_image(wall_img)
	wall_src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	wall_src.create_tile(Vector2i(0, 0))
	tileset.add_source(wall_src, 1)

	# Source 2 — stone hearth
	var hearth_src = TileSetAtlasSource.new()
	var hearth_img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	_draw_hearth_tile(hearth_img)
	hearth_src.texture = ImageTexture.create_from_image(hearth_img)
	hearth_src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	hearth_src.create_tile(Vector2i(0, 0))
	tileset.add_source(hearth_src, 2)

	# Source 3 — red/gold carpet
	var carpet_src = TileSetAtlasSource.new()
	var carpet_img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	_draw_carpet_tile(carpet_img)
	carpet_src.texture = ImageTexture.create_from_image(carpet_img)
	carpet_src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	carpet_src.create_tile(Vector2i(0, 0))
	tileset.add_source(carpet_src, 3)

	tilemap.tile_set = tileset
	_generate_floor()


func _draw_plank_floor(img: Image) -> void:
	var wood  := Color(0.48, 0.33, 0.20)
	var dark  := Color(0.38, 0.25, 0.13)
	var grain := Color(0.43, 0.29, 0.16)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Horizontal plank lines every 8px
			var plank_row = y / 8
			var base = dark if plank_row % 2 == 0 else wood
			# Subtle vertical grain within each plank
			var in_grain = (x + plank_row * 3) % 6 == 0
			var c = grain if in_grain else base
			# Plank gap line
			if y % 8 == 0:
				c = dark.darkened(0.15)
			img.set_pixel(x, y, c)


func _draw_halftimber_wall(img: Image) -> void:
	# Plaster base with dark wood beam overlay
	var plaster      := Color(0.82, 0.76, 0.65)
	var plaster_dark := Color(0.72, 0.66, 0.55)
	var beam         := Color(0.28, 0.18, 0.10)
	var beam_mid     := Color(0.35, 0.22, 0.13)

	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Plaster texture
			var noise = ((x * 3 + y * 7) % 5 == 0)
			var c = plaster_dark if noise else plaster

			# Horizontal beam every 16px
			if y % 16 < 3:
				c = beam if (x + y) % 4 != 0 else beam_mid
			# Vertical beam every 16px
			elif x % 16 < 3:
				c = beam if (x + y) % 4 != 0 else beam_mid

			img.set_pixel(x, y, c)


func _draw_hearth_tile(img: Image) -> void:
	var stone      := Color(0.58, 0.52, 0.48)
	var stone_dark := Color(0.44, 0.40, 0.36)
	var soot       := Color(0.25, 0.22, 0.20)

	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Irregular stone blocks
			var block_row = y / 10
			var block_col = (x + block_row * 5) / 14
			var in_mortar_h = y % 10 < 2
			var in_mortar_v = (x + block_row * 5) % 14 < 2
			if in_mortar_h or in_mortar_v:
				img.set_pixel(x, y, stone_dark.darkened(0.1))
			else:
				# Soot darkening near center
				var cx = abs(x - TILE_SIZE / 2)
				var cy = abs(y - TILE_SIZE / 2)
				if cx + cy < 6:
					img.set_pixel(x, y, soot)
				else:
					var variation = (block_row + block_col) % 3
					var c = stone if variation != 1 else stone_dark
					img.set_pixel(x, y, c)


func _draw_carpet_tile(img: Image) -> void:
	var red       := Color(0.72, 0.18, 0.14)
	var red_dark  := Color(0.55, 0.12, 0.10)
	var gold      := Color(0.80, 0.68, 0.28)
	var gold_dark := Color(0.65, 0.52, 0.20)

	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Border stripe
			var near_edge = (x < 3 or x >= TILE_SIZE - 3 or y < 3 or y >= TILE_SIZE - 3)
			if near_edge:
				var c = gold if (x + y) % 3 != 0 else gold_dark
				img.set_pixel(x, y, c)
				continue

			# Diamond weave pattern
			var dx = (x - TILE_SIZE / 2)
			var dy = (y - TILE_SIZE / 2)
			var diagonal = (abs(dx) + abs(dy)) % 8
			if diagonal < 2:
				img.set_pixel(x, y, gold_dark)
			elif diagonal < 4:
				img.set_pixel(x, y, gold)
			elif (x + y) % 4 == 0:
				img.set_pixel(x, y, red_dark)
			else:
				img.set_pixel(x, y, red)


func _generate_floor() -> void:
	for y in range(MAP_HEIGHT):
		for x in range(MAP_WIDTH):
			var ch = INN_LAYOUT[y][x]
			match ch:
				"W":
					tilemap.set_cell(Vector2i(x, y), 1, Vector2i(0, 0))
				"h":
					tilemap.set_cell(Vector2i(x, y), 2, Vector2i(0, 0))
				"c":
					tilemap.set_cell(Vector2i(x, y), 3, Vector2i(0, 0))
				_:
					tilemap.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))


# ---------------------------------------------------------------------------
# Decorations
# ---------------------------------------------------------------------------

func _setup_decorations() -> void:
	decorations = Node2D.new()
	decorations.name = "Decorations"
	add_child(decorations)

	_create_registration_desk()
	_create_fireplace_surround()
	_create_armchairs()
	_create_communal_table()
	_create_stairs_up()
	_create_coat_rack()
	_create_travel_gear_pile()
	_create_wall_paintings()
	_create_tapestry()
	_create_lanterns()
	_create_ambient_light()


func _create_light_texture(radius: int = 128) -> ImageTexture:
	var size = radius * 2
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = size / 2
	for y in range(size):
		for x in range(size):
			var dist = Vector2(x - center, y - center).length()
			var alpha = clampf(1.0 - dist / float(center), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, alpha * alpha))
	return ImageTexture.create_from_image(img)


func _create_registration_desk() -> void:
	# 3-tile-wide wooden counter at x=2,y=2-3 (grid)
	var node = Node2D.new()
	node.name = "RegistrationDesk"

	# Counter body
	var desk = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 3, TILE_SIZE * 2, false, Image.FORMAT_RGBA8)
	var wood_top  := Color(0.55, 0.38, 0.22)
	var wood_body := Color(0.38, 0.24, 0.13)
	var wood_dark := Color(0.30, 0.18, 0.10)

	for y in range(TILE_SIZE * 2):
		for x in range(TILE_SIZE * 3):
			if y < 6:
				# Counter top surface
				var grain = (x + y) % 7 < 2
				img.set_pixel(x, y, wood_top.darkened(0.1) if grain else wood_top)
			else:
				var panel = (x / 18) % 2
				img.set_pixel(x, y, wood_dark if panel == 0 else wood_body)

	desk.texture = ImageTexture.create_from_image(img)
	desk.position = Vector2(2.5 * TILE_SIZE, 2.5 * TILE_SIZE)
	node.add_child(desk)

	# Brass bell
	var bell = Sprite2D.new()
	var bell_img = Image.create(16, 18, false, Image.FORMAT_RGBA8)
	bell_img.fill(Color.TRANSPARENT)
	var brass := Color(0.80, 0.68, 0.28)
	var brass_hi := Color(0.95, 0.85, 0.50)
	for y in range(16):
		var half_w = int(7.5 * sin(float(y) / 16.0 * PI)) + 1
		for x in range(8 - half_w, 8 + half_w):
			var hi = (x == 9 and y < 6)
			bell_img.set_pixel(x, y, brass_hi if hi else brass)
	# Handle
	for y in range(16, 18):
		for x in range(6, 10):
			bell_img.set_pixel(x, y, brass.darkened(0.2))
	bell.texture = ImageTexture.create_from_image(bell_img)
	bell.position = Vector2(3.0 * TILE_SIZE, 1.5 * TILE_SIZE)
	node.add_child(bell)

	# Ledger book
	var ledger = Sprite2D.new()
	var led_img = Image.create(24, 18, false, Image.FORMAT_RGBA8)
	led_img.fill(Color.TRANSPARENT)
	var cover := Color(0.35, 0.25, 0.55)
	var page  := Color(0.92, 0.90, 0.82)
	# Book cover
	for y in range(18):
		for x in range(24):
			led_img.set_pixel(x, y, cover)
	# Open pages
	for y in range(2, 16):
		for x in range(4, 20):
			led_img.set_pixel(x, y, page)
	# Text lines
	for line in range(4):
		var ly = 4 + line * 3
		for x in range(5, 18):
			if (x + line) % 5 != 0:
				led_img.set_pixel(x, ly, Color(0.3, 0.3, 0.4))
	ledger.texture = ImageTexture.create_from_image(led_img)
	ledger.position = Vector2(2.0 * TILE_SIZE, 1.6 * TILE_SIZE)
	node.add_child(ledger)

	# Quill pen
	var quill = Sprite2D.new()
	var q_img = Image.create(6, 22, false, Image.FORMAT_RGBA8)
	q_img.fill(Color.TRANSPARENT)
	for y in range(22):
		# Feather shaft
		q_img.set_pixel(2, y, Color(0.85, 0.82, 0.75))
		if y < 14:
			# Feather barbs on each side
			if y % 2 == 0 and y > 2:
				var bx = 2 - (y / 4)
				if bx >= 0:
					q_img.set_pixel(bx, y, Color(0.90, 0.88, 0.80))
				bx = 2 + (y / 4)
				if bx < 6:
					q_img.set_pixel(bx, y, Color(0.90, 0.88, 0.80))
	quill.texture = ImageTexture.create_from_image(q_img)
	quill.position = Vector2(2.4 * TILE_SIZE, 1.4 * TILE_SIZE)
	node.add_child(quill)

	# Key rack behind desk (visual strip with 3 dangling keys)
	var keyrack = Sprite2D.new()
	var kr_img = Image.create(TILE_SIZE * 3, 20, false, Image.FORMAT_RGBA8)
	kr_img.fill(Color.TRANSPARENT)
	var rack_wood := Color(0.40, 0.26, 0.14)
	# Rack bar
	for x in range(TILE_SIZE * 3):
		for y in range(0, 4):
			kr_img.set_pixel(x, y, rack_wood)
	# Three keys hanging
	var key_brass := Color(0.78, 0.65, 0.25)
	var key_ring  := Color(0.65, 0.52, 0.18)
	for k in range(3):
		var kx = 16 + k * 28
		# Ring
		for y in range(4, 9):
			kr_img.set_pixel(kx, y, key_ring)
			kr_img.set_pixel(kx + 4, y, key_ring)
		for x in range(kx, kx + 5):
			kr_img.set_pixel(x, 4, key_ring)
			kr_img.set_pixel(x, 8, key_ring)
		# Shaft
		for y in range(9, 18):
			kr_img.set_pixel(kx + 2, y, key_brass)
		# Teeth
		kr_img.set_pixel(kx + 4, 13, key_brass)
		kr_img.set_pixel(kx + 4, 15, key_brass)
	keyrack.texture = ImageTexture.create_from_image(kr_img)
	keyrack.position = Vector2(1.5 * TILE_SIZE, 0.5 * TILE_SIZE)
	node.add_child(keyrack)

	decorations.add_child(node)


func _create_fireplace_surround() -> void:
	# Stone mantle surround at grid x=4..6, y=5 (above hearth tiles)
	var node = Node2D.new()
	node.name = "FireplaceSurround"

	var surround = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 3, TILE_SIZE * 2, false, Image.FORMAT_RGBA8)
	var stone       := Color(0.55, 0.50, 0.46)
	var stone_hi    := Color(0.70, 0.65, 0.60)
	var stone_dark  := Color(0.40, 0.36, 0.32)
	var arch_inside := Color(0.12, 0.09, 0.08)

	for y in range(TILE_SIZE * 2):
		for x in range(TILE_SIZE * 3):
			# Outer stone mantle
			var in_arch = (x > 20 and x < TILE_SIZE * 3 - 20 and y > 20)
			if in_arch:
				img.set_pixel(x, y, arch_inside)
			else:
				var block_r = y / 12
				var block_c = (x + block_r * 6) / 20
				var mortar_h = y % 12 < 2
				var mortar_v = (x + block_r * 6) % 20 < 2
				if mortar_h or mortar_v:
					img.set_pixel(x, y, stone_dark)
				else:
					var hi = (block_r + block_c) % 3 == 0
					img.set_pixel(x, y, stone_hi if hi else stone)

	surround.texture = ImageTexture.create_from_image(img)
	surround.position = Vector2(4.5 * TILE_SIZE, 4.5 * TILE_SIZE)
	node.add_child(surround)

	# Mantle shelf — small decorative items
	var shelf = Sprite2D.new()
	var sh_img = Image.create(TILE_SIZE * 3, 10, false, Image.FORMAT_RGBA8)
	var wood_shelf := Color(0.50, 0.34, 0.18)
	for x in range(TILE_SIZE * 3):
		for y in range(10):
			sh_img.set_pixel(x, y, wood_shelf if y > 1 else wood_shelf.lightened(0.2))
	# Small candles on shelf
	for c_idx in range(2):
		var cx2 = 14 + c_idx * 52
		# Candle body (white)
		for y in range(3, 9):
			sh_img.set_pixel(cx2, y, Color(0.95, 0.94, 0.88))
			sh_img.set_pixel(cx2 + 1, y, Color(0.95, 0.94, 0.88))
	shelf.texture = ImageTexture.create_from_image(sh_img)
	shelf.position = Vector2(3.0 * TILE_SIZE, 3.5 * TILE_SIZE)
	node.add_child(shelf)

	decorations.add_child(node)


func _setup_fireplace_anim() -> void:
	_fire_sprite = Sprite2D.new()
	_fire_sprite.name = "FireFlame"
	_fire_sprite.z_index = 5
	_fire_sprite.position = Vector2(5.5 * TILE_SIZE, 5.0 * TILE_SIZE)
	add_child(_fire_sprite)

	_fire_frames.clear()
	for f in range(3):
		var img = Image.create(TILE_SIZE * 2, TILE_SIZE, false, Image.FORMAT_RGBA8)
		_draw_flame_frame(img, f)
		_fire_frames.append(ImageTexture.create_from_image(img))

	if _fire_frames.size() > 0:
		_fire_sprite.texture = _fire_frames[0]

	# Fireplace light
	_fire_light = PointLight2D.new()
	_fire_light.name = "FireLight"
	_fire_light.position = Vector2(5.5 * TILE_SIZE, 5.5 * TILE_SIZE)
	_fire_light.color = Color(1.0, 0.55, 0.15, 0.8)
	_fire_light.energy = 0.9
	_fire_light.texture = _create_light_texture(160)
	add_child(_fire_light)


func _draw_flame_frame(img: Image, frame: int) -> void:
	img.fill(Color.TRANSPARENT)
	var offsets = [0, 2, -2]
	var ofs = offsets[frame % 3]

	var outer := Color(0.95, 0.55, 0.10)
	var mid   := Color(0.98, 0.80, 0.20)
	var inner := Color(1.00, 0.96, 0.60)
	var base  := Color(0.80, 0.30, 0.05)

	var cx = TILE_SIZE + ofs
	var height = TILE_SIZE - 4

	for y in range(TILE_SIZE):
		var row_pct = float(TILE_SIZE - y) / float(TILE_SIZE)
		var half_w = int(12.0 * row_pct * row_pct) + 1
		# Flame body — per-column randomization via frame offset
		for x in range(cx - half_w, cx + half_w):
			if x < 0 or x >= TILE_SIZE * 2:
				continue
			var dx = abs(x - cx)
			if y > height:
				img.set_pixel(x, y, base)
			elif dx < 2 and row_pct > 0.4:
				img.set_pixel(x, y, inner)
			elif dx < 5:
				img.set_pixel(x, y, mid)
			else:
				img.set_pixel(x, y, outer)

		# Flame tip wisps — alternate per frame
		if y < 8 and (y + frame) % 2 == 0:
			var tip_x = cx + (-1 if frame == 1 else 1) * (y / 3)
			if tip_x >= 0 and tip_x < TILE_SIZE * 2:
				img.set_pixel(tip_x, y, outer.lightened(0.1))


func _animate_fireplace(delta: float) -> void:
	_fire_timer += delta
	if _fire_timer >= FIRE_SPEED:
		_fire_timer -= FIRE_SPEED
		_fire_frame = (_fire_frame + 1) % _fire_frames.size()
		if _fire_sprite and _fire_frames.size() > 0:
			_fire_sprite.texture = _fire_frames[_fire_frame]


func _flicker_fire_light(delta: float) -> void:
	_fire_time += delta
	if _fire_light:
		_fire_light.energy = 0.75 + 0.25 * sin(_fire_time * 7.3) + 0.10 * sin(_fire_time * 13.1)


func _create_armchairs() -> void:
	# Two wing-back armchairs flanking fireplace at ~(3,7) and (7,7)
	var positions = [Vector2(3, 7), Vector2(7, 7)]
	for i in range(2):
		var chair = Sprite2D.new()
		var img = Image.create(TILE_SIZE + 8, TILE_SIZE + 12, false, Image.FORMAT_RGBA8)
		img.fill(Color.TRANSPARENT)
		_draw_armchair(img, i == 1)
		chair.texture = ImageTexture.create_from_image(img)
		chair.position = positions[i] * TILE_SIZE
		decorations.add_child(chair)


func _draw_armchair(img: Image, flip: bool) -> void:
	var leather      := Color(0.60, 0.15, 0.12)
	var leather_hi   := Color(0.78, 0.25, 0.18)
	var leather_dark := Color(0.42, 0.10, 0.08)
	var wood_leg     := Color(0.38, 0.24, 0.12)
	var button_gold  := Color(0.75, 0.62, 0.22)

	var W = img.get_width()
	var H = img.get_height()

	# Seat cushion
	for y in range(18, 30):
		for x in range(4, W - 4):
			var hi = (x - 4) % 8 < 3
			img.set_pixel(x, y, leather_hi if hi else leather)
	# Seat buttons
	for bx in [W / 2 - 6, W / 2 + 4]:
		img.set_pixel(bx, 22, button_gold)
		img.set_pixel(bx + 1, 22, button_gold)

	# Back cushion
	for y in range(4, 18):
		for x in range(6, W - 6):
			var hi = (x - 6) % 10 < 4
			img.set_pixel(x, y, leather_hi if hi else leather)

	# Wing sides
	for y in range(2, 20):
		# Left wing
		for x in range(1, 6):
			img.set_pixel(x, y, leather_dark)
		# Right wing
		for x in range(W - 6, W - 1):
			img.set_pixel(x, y, leather_dark)

	# Armrests
	for y in range(28, 36):
		for x in range(1, 8):
			img.set_pixel(x, y, leather)
		for x in range(W - 8, W - 1):
			img.set_pixel(x, y, leather)

	# Legs
	for leg_x in [4, W - 6]:
		for y in range(36, H):
			img.set_pixel(leg_x, y, wood_leg)
			img.set_pixel(leg_x + 1, y, wood_leg)


func _create_communal_table() -> void:
	# Long table at grid x=2..9, y=9..10 — 8 tiles wide, 2 tall
	var node = Node2D.new()
	node.name = "CommunalTable"

	var table = Sprite2D.new()
	var tw = TILE_SIZE * 8
	var th = TILE_SIZE * 2
	var img = Image.create(tw, th, false, Image.FORMAT_RGBA8)

	var top   := Color(0.55, 0.38, 0.22)
	var body  := Color(0.42, 0.28, 0.15)
	var dark  := Color(0.32, 0.20, 0.10)
	var edge  := Color(0.38, 0.24, 0.13)

	for y in range(th):
		for x in range(tw):
			if y < 6:
				# Table top with planks
				var grain = (x / 16) % 2
				img.set_pixel(x, y, edge if grain == 0 else top)
			elif y >= th - 6:
				img.set_pixel(x, y, edge)
			else:
				img.set_pixel(x, y, dark if (x / 20) % 2 == 0 else body)

	table.texture = ImageTexture.create_from_image(img)
	table.position = Vector2(6 * TILE_SIZE, 9.5 * TILE_SIZE)
	node.add_child(table)

	# Benches (north and south of table)
	for bench_side in range(2):
		var bench = Sprite2D.new()
		var bw = TILE_SIZE * 7
		var bh = 14
		var bimg = Image.create(bw, bh, false, Image.FORMAT_RGBA8)
		var bench_wood := Color(0.45, 0.30, 0.16)
		var bench_dark := Color(0.35, 0.22, 0.10)
		for y in range(bh):
			for x in range(bw):
				bimg.set_pixel(x, y, bench_dark if y < 3 or y >= bh - 2 else bench_wood)
		bench.texture = ImageTexture.create_from_image(bimg)
		var by = 8.5 * TILE_SIZE if bench_side == 0 else 11.0 * TILE_SIZE
		bench.position = Vector2(6.0 * TILE_SIZE, by)
		node.add_child(bench)

	# Table items — bowls, mugs, a dropped spoon
	_add_table_items(node)

	decorations.add_child(node)


func _add_table_items(parent: Node2D) -> void:
	var items = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 7, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var ceramic  := Color(0.78, 0.70, 0.58)
	var mug_tan  := Color(0.72, 0.56, 0.30)
	var soup     := Color(0.65, 0.45, 0.22)

	# 3 bowls
	for b in range(3):
		var bx = 18 + b * 56
		# Bowl rim
		for x in range(bx, bx + 20):
			img.set_pixel(x, 2, ceramic)
			img.set_pixel(x, 9, ceramic)
		for y in range(2, 10):
			img.set_pixel(bx, y, ceramic)
			img.set_pixel(bx + 19, y, ceramic)
		# Soup inside
		for y in range(3, 9):
			for x in range(bx + 1, bx + 19):
				img.set_pixel(x, y, soup)

	# 2 mugs
	for m in range(2):
		var mx = 80 + m * 60
		for y in range(1, 14):
			for x in range(mx, mx + 12):
				img.set_pixel(x, y, mug_tan)
		# Handle
		for y in range(4, 10):
			img.set_pixel(mx + 12, y, mug_tan)
			img.set_pixel(mx + 14, y, mug_tan)
		img.set_pixel(mx + 13, 4, mug_tan)
		img.set_pixel(mx + 13, 9, mug_tan)

	# Dropped spoon
	for y in range(6, 10):
		img.set_pixel(155, y, Color(0.75, 0.72, 0.68))
	for x in range(152, 158):
		img.set_pixel(x, 7, Color(0.75, 0.72, 0.68))

	items.texture = ImageTexture.create_from_image(img)
	items.position = Vector2(2.5 * TILE_SIZE, 9.2 * TILE_SIZE)
	parent.add_child(items)


func _create_stairs_up() -> void:
	# Stairs at grid x=17..18, y=2..3 (layout marks these U)
	var node = Node2D.new()
	node.name = "StairsUp"

	var stair = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 2, TILE_SIZE * 2, false, Image.FORMAT_RGBA8)
	var step_light := Color(0.70, 0.52, 0.32)
	var step_dark  := Color(0.45, 0.30, 0.16)
	var arch_dark  := Color(0.18, 0.14, 0.12)
	var railing    := Color(0.35, 0.22, 0.12)

	for y in range(TILE_SIZE * 2):
		for x in range(TILE_SIZE * 2):
			# Dark archway background
			var in_arch = (x > 4 and x < TILE_SIZE * 2 - 4 and y < 20)
			if in_arch:
				img.set_pixel(x, y, arch_dark)
				continue
			# Stepped treads — 5 steps, each 8px tall
			var step_idx = (TILE_SIZE * 2 - y) / 10
			var on_riser = (TILE_SIZE * 2 - y) % 10 < 3
			if on_riser:
				img.set_pixel(x, y, step_dark)
			else:
				var grain = (x + step_idx * 4) % 8 < 3
				img.set_pixel(x, y, step_light if not grain else step_dark.lightened(0.1))

	# Railing on left side
	for y in range(4, TILE_SIZE * 2):
		img.set_pixel(6, y, railing)
		img.set_pixel(7, y, railing)

	stair.texture = ImageTexture.create_from_image(img)
	stair.position = Vector2(17.5 * TILE_SIZE, 2.5 * TILE_SIZE)
	node.add_child(stair)

	# "Upstairs" hint label
	var label = Label.new()
	label.text = "Upstairs"
	label.position = Vector2(16.5 * TILE_SIZE, 1.0 * TILE_SIZE)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.90, 0.82, 0.60))
	node.add_child(label)

	decorations.add_child(node)


func _create_coat_rack() -> void:
	# Near entrance, grid x=1, y=10
	var rack = Sprite2D.new()
	var img = Image.create(20, TILE_SIZE + 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var wood_pole := Color(0.40, 0.26, 0.14)
	var cloak_colors = [Color(0.30, 0.20, 0.45), Color(0.60, 0.30, 0.12), Color(0.22, 0.40, 0.22)]

	# Vertical pole
	for y in range(TILE_SIZE + 8):
		img.set_pixel(9, y, wood_pole)
		img.set_pixel(10, y, wood_pole)

	# Base
	for x in range(2, 18):
		img.set_pixel(x, TILE_SIZE + 6, wood_pole)
		img.set_pixel(x, TILE_SIZE + 7, wood_pole)

	# Hooks
	for h in range(3):
		var hx = 4 + h * 5
		img.set_pixel(hx, 8, wood_pole.lightened(0.2))
		img.set_pixel(hx, 9, wood_pole.lightened(0.2))

	# Hanging cloaks
	for c_idx in range(3):
		var cx2 = 3 + c_idx * 5
		var cloak = cloak_colors[c_idx]
		for y in range(10, 30 + c_idx * 4):
			var spread = min(y - 9, 5)
			for x in range(cx2 - spread, cx2 + spread + 1):
				if x >= 0 and x < 20:
					var fold = (x + y) % 4 < 2
					img.set_pixel(x, y, cloak.darkened(0.2) if fold else cloak)

	rack.texture = ImageTexture.create_from_image(img)
	rack.position = Vector2(1.3 * TILE_SIZE, 10 * TILE_SIZE)
	decorations.add_child(rack)


func _create_travel_gear_pile() -> void:
	# Corner pile at grid x=17..18, y=10..11
	var pile = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 2, TILE_SIZE + 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var blanket_red  := Color(0.65, 0.22, 0.18)
	var blanket_tan  := Color(0.70, 0.55, 0.30)
	var stick_wood   := Color(0.50, 0.35, 0.18)
	var tin_cup      := Color(0.55, 0.55, 0.58)

	# Rolled blanket
	for y in range(12, 28):
		for x in range(6, 38):
			var stripe = (x + y) % 6
			var c = blanket_red if stripe < 3 else blanket_tan
			img.set_pixel(x, y, c)
	# Strap end caps
	for x in range(6, 38):
		img.set_pixel(x, 12, blanket_tan.darkened(0.2))
		img.set_pixel(x, 27, blanket_tan.darkened(0.2))

	# Tin cup
	for y in range(4, 20):
		for x in range(40, 52):
			img.set_pixel(x, y, tin_cup)
	# Cup rim
	for x in range(38, 54):
		img.set_pixel(x, 4, tin_cup.lightened(0.3))

	# Walking stick (diagonal)
	for i in range(30):
		var sx = 20 + i
		var sy = TILE_SIZE + 8 - i - 2
		if sx < TILE_SIZE * 2 and sy >= 0:
			img.set_pixel(sx, sy, stick_wood)
			if sy + 1 < TILE_SIZE + 8:
				img.set_pixel(sx, sy + 1, stick_wood.darkened(0.2))

	pile.texture = ImageTexture.create_from_image(img)
	pile.position = Vector2(17 * TILE_SIZE, 10 * TILE_SIZE)
	decorations.add_child(pile)


func _create_wall_paintings() -> void:
	# Two framed landscape paintings on east wall, grid y=5 and y=8
	var y_positions = [5, 8]
	for i in range(2):
		var painting = Sprite2D.new()
		var pw = TILE_SIZE + 12
		var ph = TILE_SIZE - 4
		var img = Image.create(pw, ph, false, Image.FORMAT_RGBA8)

		# Gold frame
		var frame_gold := Color(0.78, 0.64, 0.24)
		var frame_dark := Color(0.55, 0.42, 0.14)
		for y in range(ph):
			for x in range(pw):
				var near = x < 4 or x >= pw - 4 or y < 4 or y >= ph - 4
				if near:
					img.set_pixel(x, y, frame_gold if (x + y) % 2 == 0 else frame_dark)

		# Landscape inside frame
		if i == 0:
			# Mountain scene
			var sky    := Color(0.42, 0.60, 0.78)
			var mount  := Color(0.55, 0.52, 0.50)
			var snow   := Color(0.90, 0.92, 0.95)
			var meadow := Color(0.30, 0.55, 0.22)
			for y in range(4, ph - 4):
				for x in range(4, pw - 4):
					var fy = float(y - 4) / float(ph - 8)
					if fy < 0.45:
						img.set_pixel(x, y, sky)
					elif fy < 0.6:
						# Mountain silhouette
						var peak = abs(x - pw / 2)
						var mh = int(0.3 * (pw / 2 - peak))
						if y < 4 + int((ph - 8) * 0.45) + mh:
							img.set_pixel(x, y, snow if mh > 8 else mount)
						else:
							img.set_pixel(x, y, mount)
					else:
						img.set_pixel(x, y, meadow)
		else:
			# Coastal scene
			var sky2    := Color(0.55, 0.70, 0.85)
			var sea     := Color(0.22, 0.40, 0.65)
			var sand    := Color(0.78, 0.68, 0.45)
			var wave    := Color(0.70, 0.82, 0.90)
			for y in range(4, ph - 4):
				for x in range(4, pw - 4):
					var fy = float(y - 4) / float(ph - 8)
					if fy < 0.40:
						img.set_pixel(x, y, sky2)
					elif fy < 0.65:
						var ripple = (x + y) % 8 < 2
						img.set_pixel(x, y, wave if ripple else sea)
					else:
						img.set_pixel(x, y, sand)

		painting.texture = ImageTexture.create_from_image(img)
		painting.position = Vector2(18.5 * TILE_SIZE, y_positions[i] * TILE_SIZE)
		decorations.add_child(painting)


func _create_tapestry() -> void:
	# Hanging tapestry on north wall at x=10, y=1
	var tap = Sprite2D.new()
	var tw2 = TILE_SIZE * 3
	var th2 = TILE_SIZE * 2
	var img = Image.create(tw2, th2, false, Image.FORMAT_RGBA8)

	var bg      := Color(0.20, 0.14, 0.45)
	var gold2   := Color(0.80, 0.68, 0.28)
	var silver  := Color(0.72, 0.75, 0.80)
	var crimson := Color(0.72, 0.18, 0.14)

	# Background fill
	for y in range(th2):
		for x in range(tw2):
			img.set_pixel(x, y, bg)

	# Border
	for y in range(th2):
		for x in range(tw2):
			var near = x < 3 or x >= tw2 - 3 or y < 3 or y >= th2 - 3
			if near:
				img.set_pixel(x, y, gold2 if (x + y) % 2 == 0 else gold2.darkened(0.3))

	# Shield crest in center
	var cx2 = tw2 / 2
	var cy2 = th2 / 2
	# Shield outline
	for y in range(cy2 - 16, cy2 + 16):
		for x in range(cx2 - 12, cx2 + 12):
			var in_shield = (abs(x - cx2) < 12 - max(0, y - cy2 - 4))
			if in_shield:
				var quadrant = (x > cx2) and (y > cy2)
				img.set_pixel(x, y, crimson if quadrant else silver)
	# Crown atop shield
	for y in range(cy2 - 22, cy2 - 16):
		for x in range(cx2 - 8, cx2 + 8):
			img.set_pixel(x, y, gold2)
	for peak in range(3):
		var px = cx2 - 8 + peak * 8
		for y in range(cy2 - 26, cy2 - 22):
			img.set_pixel(px, y, gold2)
			img.set_pixel(px + 1, y, gold2)

	# Fringe at bottom
	for x in range(tw2):
		if x % 4 < 2:
			for y in range(th2 - 8, th2):
				img.set_pixel(x, y, gold2.darkened(0.2))

	tap.texture = ImageTexture.create_from_image(img)
	tap.position = Vector2(10.5 * TILE_SIZE, 0.5 * TILE_SIZE)
	decorations.add_child(tap)


func _create_lanterns() -> void:
	# 4 hanging lanterns spread across the room
	var lantern_positions = [
		Vector2(5, 2), Vector2(10, 2), Vector2(15, 2), Vector2(5, 8)
	]
	var light_tex = _create_light_texture(96)

	for lp in lantern_positions:
		var lantern = Sprite2D.new()
		var img = Image.create(14, 22, false, Image.FORMAT_RGBA8)
		img.fill(Color.TRANSPARENT)

		var iron   := Color(0.32, 0.30, 0.28)
		var glass  := Color(0.85, 0.80, 0.55)
		var glow   := Color(0.98, 0.88, 0.55)

		# Chain link
		for y in range(0, 5):
			img.set_pixel(6, y, iron)
			img.set_pixel(7, y, iron)

		# Lantern body frame
		for y in range(5, 20):
			img.set_pixel(2, y, iron)
			img.set_pixel(11, y, iron)
		for x in range(2, 12):
			img.set_pixel(x, 5, iron)
			img.set_pixel(x, 19, iron)

		# Glass panels — warm glow
		for y in range(6, 19):
			for x in range(3, 11):
				var cx2 = 7.0
				var cy2 = 12.5
				var dist = Vector2(x - cx2, y - cy2).length()
				var c = glow if dist < 2 else glass
				img.set_pixel(x, y, c)

		# Bottom cap
		for x in range(4, 10):
			img.set_pixel(x, 20, iron)
			img.set_pixel(x, 21, iron)

		lantern.texture = ImageTexture.create_from_image(img)
		lantern.position = lp * TILE_SIZE
		decorations.add_child(lantern)

		# PointLight2D below each lantern
		var light = PointLight2D.new()
		light.position = lp * TILE_SIZE + Vector2(0, 28)
		light.color = Color(1.0, 0.88, 0.60)
		light.energy = 0.40
		light.texture = light_tex
		decorations.add_child(light)


func _create_ambient_light() -> void:
	# Low-energy corner fill lights
	var corners = [Vector2(1, 1), Vector2(18, 1), Vector2(1, 12), Vector2(18, 12)]
	var light_tex = _create_light_texture(96)
	for cp in corners:
		var light = PointLight2D.new()
		light.position = cp * TILE_SIZE
		light.color = Color(0.90, 0.80, 0.65)
		light.energy = 0.15
		light.texture = light_tex
		decorations.add_child(light)


# ---------------------------------------------------------------------------
# NPCs
# ---------------------------------------------------------------------------

## Per-world innkeeper register — the TRAVELERS recur across every inn (Fen
## lampshades it as recursion; that's diegetic), but the innkeeper is local.
## Pre-fix every world got Mira and "The Traveler's Rest", medieval sheets
## jokes included, straight through the digital world.
const INNKEEPERS := {
	1: {"name": "Mira", "weave": "Harmonian", "lines": [
		"Mira: Welcome to The Traveler's Rest!",
		"Mira: A room is 50 gold a night. All party members, fully restored.",
		"Mira: We change the sheets every Tuesday. Or Wednesday. Probably.",
		"Mira: Talk to me again when you're ready to rest.",
	]},
	2: {"name": "Denise", "weave": "wall-to-wall", "lines": [
		"Denise: Welcome to the Wayside Motor Lodge! Ice machine's broken.",
		"Denise: Fifty gold a night. Continental breakfast is a bowl of mints.",
		"Denise: Checkout is whenever. Time isn't real here, hon.",
		"Denise: Talk to me again when you're ready to rest.",
	]},
	3: {"name": "Barnaby", "weave": "loom-calibrated", "lines": [
		"Barnaby: The Cogsworth Hostelry welcomes you — mind the pressure valves.",
		"Barnaby: Fifty gold. Rooms are steam-heated to exactly 19.4 degrees.",
		"Barnaby: Checkout is at 9:41 sharp. The clock insists.",
		"Barnaby: Talk to me again when you're ready to rest.",
	]},
	4: {"name": "Foreman Ada", "weave": "regulation-grade", "lines": [
		"Foreman Ada: Bunk Block 7. Hard hats off past the yellow line.",
		"Foreman Ada: Fifty gold a shift. Sleeping IS the shift.",
		"Foreman Ada: Report all dreams to the safety board.",
		"Foreman Ada: Talk to me again when you're ready to rest.",
	]},
	5: {"name": "HOST-3SS", "weave": "procedurally-woven", "lines": [
		"HOST-3SS: Welcome to the Uptime Inn. Current uptime: 99.97%.",
		"HOST-3SS: Fifty gold per sleep cycle. Rest is scheduled downtime.",
		"HOST-3SS: Do not be alarmed if the pillows update overnight.",
		"HOST-3SS: Talk to me again when you're ready to rest.",
	]},
	6: {"name": "The Concierge", "weave": "conceptual", "lines": [
		"The Concierge: Welcome to The Rest. It is less a place than a pause.",
		"The Concierge: Fifty gold, though the number is mostly a courtesy.",
		"The Concierge: Your room is the idea of a room. It sleeps beautifully.",
		"The Concierge: Talk to me again when you're ready to rest.",
	]},
}


func _innkeeper() -> Dictionary:
	var w: int = 1
	if GameState and "current_world" in GameState:
		w = clampi(int(GameState.current_world), 1, 6)
	return INNKEEPERS.get(w, INNKEEPERS[1])


func _setup_npcs() -> void:
	npcs = Node2D.new()
	npcs.name = "NPCs"
	add_child(npcs)

	# Local innkeeper at the registration desk — identity follows the world.
	# 2026-07-14 playtest: user talked to innkeeper repeatedly but couldn't find how to rest — the RegistrationDesk tile was the only rest gate; now the greeting-line close opens the rest dialog automatically.
	var keeper := _innkeeper()
	_create_npc(keeper["name"], "innkeeper", Vector2(2, 3), keeper["lines"])
	var keeper_npc: Node = null
	for child in npcs.get_children():
		if child.get("npc_name") == keeper["name"]:
			keeper_npc = child
			break
	if keeper_npc and keeper_npc.has_signal("dialogue_ended"):
		keeper_npc.dialogue_ended.connect(func(_n): _on_rest_request())

	# Sleeping merchant in armchair
	_create_npc("Dorian", "merchant", Vector2(3, 8), [
		"Dorian: *snore* ..profitable... *snore*... margins...",
		"Dorian: Zzzz... buy low... *wheeze*... sell high...",
		"Dorian: ...*snort*... THE EXCHANGE RATE—",
		"Dorian: *falls back asleep*",
	])

	# Traveling scholar at table
	_create_npc("Scholar Fen", "scholarly", Vector2(8, 9), [
		"Scholar Fen: Ah, a fellow traveler! I've been studying the local ruins.",
		"Scholar Fen: The ancient scripts pre-date the current world by eons.",
		"Scholar Fen: They spoke of a 'loop' — an endless repetition of events.",
		"Scholar Fen: Each iteration, the heroes grow stronger. But also... stranger.",
		"Scholar Fen: I suspect this inn has seen the same adventurers many times.",
		"Scholar Fen: Different faces. Same choices. Same mistakes.",
		"Scholar Fen: *peers at you* You feel like a recursion.",
	])

	# Adventurer duo comparing notes
	_create_npc("Kael", "adventurer", Vector2(10, 10), [
		"Kael: Dude, you're still doing it MANUALLY?",
		"Kael: My autobattle script cleared the whole dungeon while I slept.",
		"Kael: Woke up to a victory fanfare and 3 level-ups.",
		"Kael: *sips coffee* This is how it should be.",
	])

	_create_npc("Brix", "adventurer", Vector2(12, 9), [
		"Brix: That's... not how games are supposed to work.",
		"Brix: You're supposed to EXPERIENCE the combat.",
		"Brix: FEEL the tension. SWEAT through the boss fight.",
		"Brix: Kael: *shrugs* My script felt the tension. Did a great job.",
	])

	# Maid near stairs — the carpet's provenance follows the world
	_create_npc("Tilly", "maid", Vector2(16, 6), [
		"Tilly: *sweeping* Morning.",
		"Tilly: Don't track mud on the carpet.",
		"Tilly: That's genuine %s weave. Costs more than your weapons." % keeper["weave"],
	])

	# one_chicken_problem: a hen got into the Inn's back kitchen nook.
	var ChickenScript = load("res://src/exploration/QuestChicken.gd")
	if ChickenScript:
		var hen = ChickenScript.new()
		hen.chicken_id = "chicken_inn_kitchen"
		hen.position = Vector2(17, 10) * TILE_SIZE
		npcs.add_child(hen)


func _create_npc(npc_name: String, npc_type: String, grid_pos: Vector2, dialogue: Array) -> void:
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if OverworldNPCScript:
		var npc = OverworldNPCScript.new()
		npc.npc_name = npc_name
		npc.npc_type = npc_type
		npc.dialogue_lines = dialogue
		npc.position = grid_pos * TILE_SIZE
		npcs.add_child(npc)
	else:
		var marker = _create_simple_npc(npc_name, npc_type, grid_pos)
		npcs.add_child(marker)


func _create_simple_npc(npc_name: String, npc_type: String, grid_pos: Vector2) -> Node2D:
	var npc = Area2D.new()
	npc.position = grid_pos * TILE_SIZE

	var sprite = Sprite2D.new()
	var img = Image.create(24, 32, false, Image.FORMAT_RGBA8)
	var color = Color(0.5, 0.5, 0.5)
	match npc_type:
		"innkeeper":  color = Color(0.55, 0.35, 0.55)
		"merchant":   color = Color(0.35, 0.50, 0.60)
		"scholarly":  color = Color(0.30, 0.35, 0.65)
		"adventurer": color = Color(0.55, 0.30, 0.20)
		"maid":       color = Color(0.60, 0.58, 0.70)
	for y in range(32):
		for x in range(24):
			img.set_pixel(x, y, color)
	sprite.texture = ImageTexture.create_from_image(img)
	npc.add_child(sprite)

	var label = Label.new()
	label.text = npc_name
	label.position = Vector2(-20, -40)
	label.add_theme_font_size_override("font_size", 10)
	npc.add_child(label)
	return npc


# ---------------------------------------------------------------------------
# Transitions
# ---------------------------------------------------------------------------

func _setup_transitions() -> void:
	transitions = Node2D.new()
	transitions.name = "Transitions"
	add_child(transitions)

	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if AreaTransitionScript:
		var exit = AreaTransitionScript.new()
		exit.name = "ExitDoor"
		exit.target_map = "village_return"
		exit.target_spawn = "inn_exit"
		exit.require_interaction = false
		exit.position = Vector2(10 * TILE_SIZE, 13.5 * TILE_SIZE)

		var collision = CollisionShape2D.new()
		var shape = RectangleShape2D.new()
		shape.size = Vector2(TILE_SIZE * 2, TILE_SIZE)
		collision.shape = shape
		exit.add_child(collision)

		exit.collision_layer = 4
		exit.collision_mask = 2
		exit.monitoring = true

		exit.transition_triggered.connect(_on_exit_triggered)
		transitions.add_child(exit)


func _on_exit_triggered(target_map: String, target_spawn: String) -> void:
	transition_triggered.emit("village_return", "inn_exit")
	area_transition.emit("village_return", "inn_exit")


# ---------------------------------------------------------------------------
# Player / Camera / Controller
# ---------------------------------------------------------------------------

func _setup_player() -> void:
	var PlayerScript = load("res://src/exploration/OverworldPlayer.gd")
	if PlayerScript:
		player = PlayerScript.new()
		player.position = spawn_points["entrance"] * TILE_SIZE
		# Explicit interior flag — see bc3da44d for why the auto-detect is unreliable.
		player._is_interior = true
		add_child(player)


func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera2D"
	camera.zoom = Vector2(2.5, 2.5)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0

	camera.limit_left   = 0
	camera.limit_top    = 0
	camera.limit_right  = MAP_WIDTH  * TILE_SIZE
	camera.limit_bottom = MAP_HEIGHT * TILE_SIZE

	if player:
		player.add_child(camera)
	else:
		add_child(camera)
		camera.position = Vector2(MAP_WIDTH * TILE_SIZE / 2, MAP_HEIGHT * TILE_SIZE / 2)


func spawn_player_at(spawn_name: String) -> void:
	if spawn_points.has(spawn_name) and player:
		player.position = spawn_points[spawn_name] * TILE_SIZE


func _setup_controller() -> void:
	var ControllerScript = load("res://src/exploration/OverworldController.gd")
	if ControllerScript and player:
		controller = ControllerScript.new()
		controller.player = player
		controller.encounter_enabled = false
		add_child(controller)


# ---------------------------------------------------------------------------
# Rest service — invoked from a service-bell interactable next to the innkeeper
# ---------------------------------------------------------------------------

func _create_rest_interactable() -> void:
	var area = Area2D.new()
	area.name = "RestService"
	area.position = Vector2(3 * TILE_SIZE, 3 * TILE_SIZE)

	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(TILE_SIZE, TILE_SIZE)
	collision.shape = shape
	area.add_child(collision)

	area.collision_layer = 4
	area.collision_mask = 2
	area.monitoring = true
	area.monitorable = true
	area.add_to_group("interactables")
	area.set_meta("interaction_callback", _on_rest_request)
	area.set_meta("parent_scene", self)
	add_child(area)


func _on_rest_request() -> void:
	if _rest_pending:
		_do_rest()
	else:
		_rest_pending = true
		_show_rest_prompt()


func _show_rest_prompt() -> void:
	if _rest_dialog and is_instance_valid(_rest_dialog):
		_rest_dialog.queue_free()
	_rest_dialog = _make_inn_dialog("Rest at the inn?\n[Talk again to confirm — step away to cancel]")
	rest_requested.emit()
	if SoundManager:
		SoundManager.play_ui("menu_open")


func _do_rest() -> void:
	_rest_pending = false
	if _rest_dialog and is_instance_valid(_rest_dialog):
		_rest_dialog.queue_free()
		_rest_dialog = null

	var game_loop = get_tree().root.get_node_or_null("GameLoop")
	if game_loop and game_loop.party:
		for member in game_loop.party:
			# 2026-07-15 playtest: "slept at inn, bard still KO'd" — HP was maxed but is_alive stayed false. Revive KO'd members first so the inn actually raises them, then top off HP/MP.
			if not member.is_alive and member.has_method("revive"):
				member.revive(member.max_hp)
			member.current_hp = member.max_hp
			member.current_mp = member.max_mp
			member.current_ap = 0

	if SoundManager:
		SoundManager.play_ui("heal")

	_rest_dialog = _make_inn_dialog("Your party is fully rested!\nHP and MP restored.")
	await get_tree().create_timer(1.6).timeout
	if _rest_dialog and is_instance_valid(_rest_dialog):
		_rest_dialog.queue_free()
		_rest_dialog = null


func _make_inn_dialog(text: String) -> Control:
	var holder = Control.new()
	holder.name = "RestDialog"
	holder.z_index = 100
	# 2026-07-15 playtest: was `3*TILE_SIZE - 120` = -24px, i.e. off-screen LEFT half the width of the dialog was clipped ("st at the inn?"). Anchor screen-center via viewport size so the dialog always renders on-screen regardless of the innkeeper's tile.
	holder.size = Vector2(240, 70)
	var _vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1280, 720)
	holder.position = Vector2((_vp.x - holder.size.x) / 2, _vp.y * 0.35)

	var panel = Panel.new()
	panel.position = Vector2.ZERO
	panel.size = holder.size
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.10, 0.05, 0.95)
	style.border_color = Color(0.7, 0.5, 0.3)
	style.set_border_width_all(3)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	holder.add_child(panel)

	var label = Label.new()
	label.position = Vector2(8, 8)
	label.size = Vector2(holder.size.x - 16, holder.size.y - 16)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	holder.add_child(label)

	add_child(holder)
	return holder
