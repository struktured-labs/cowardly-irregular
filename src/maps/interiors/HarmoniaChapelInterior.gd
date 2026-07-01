extends BaseInterior
class_name HarmoniaChapelInterior

## HarmoniaChapelInterior - Cathedral-depth chapel in Harmonia Village.
## Sister Concord foreshadows the Mordaine fight: she remembers when
## the Chancellor used to come here, and she's worried what's changed.
## Stone/marble nave, stained glass, altar, pews, bell tower, censer,
## prayer candles, choir loft, and a small cast of worshipers.

const CHAPEL_LAYOUT = [
	"WWWWWWWWWWWWWWWWWW",
	"W......AAA.......W",
	"W......AAA.......W",
	"W.......CC.......W",
	"W.PPP...CC...PPP.W",
	"W.......CC.......W",
	"W.PPP...CC...PPP.W",
	"W.......CC.......W",
	"W.PPP...CC...PPP.W",
	"W.......CC.......W",
	"W..O....CC.....T.W",
	"W.......CC.......W",
	"WWWWWWWWDDWWWWWWWW",
]

## Censer sway
var _censer_sprite: Sprite2D
var _censer_time: float = 0.0

## Prayer candle flicker (3-frame, shared across all racks)
var _candle_sprites: Array[Sprite2D] = []
var _candle_frames: Array[ImageTexture] = []
var _candle_frame: int = 0
var _candle_timer: float = 0.0
const CANDLE_SPEED: float = 0.18

## Wall sconce flicker (3-frame, shared across all sconces)
var _sconce_sprites: Array[Sprite2D] = []
var _sconce_frames: Array[ImageTexture] = []
var _sconce_frame: int = 0
var _sconce_timer: float = 0.0
const SCONCE_SPEED: float = 0.15

## Stained glass light-pool breathing
var _window_lights: Array[PointLight2D] = []
var _light_time: float = 0.0

## Chorister's floating musical notes
var _note_sprites: Array[Sprite2D] = []
var _note_base_positions: Array[Vector2] = []
var _note_time: float = 0.0

## Dust motes drifting in the sunbeam
var _mote_sprites: Array[Sprite2D] = []
var _mote_base_positions: Array[Vector2] = []
var _mote_phases: Array[float] = []
var _mote_time: float = 0.0

## Incense wisps rising from the censer
var _smoke_sprites: Array[Sprite2D] = []
var _smoke_base_positions: Array[Vector2] = []
var _smoke_time: float = 0.0


func _get_area_id() -> String:
	return "harmonia_chapel"


func _get_display_name() -> String:
	return "Chapel"


func _get_map_width() -> int:
	return 18


func _get_map_height() -> int:
	return 13


func _get_layout() -> Array:
	return CHAPEL_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(8, 11)
	spawn_points["altar"] = Vector2(8, 2)


func _draw_floor_tile(image: Image) -> void:
	# Pale cathedral marble — flagstone seams plus fine diagonal veining,
	# distinct from BaseInterior's flat dungeon-gray default.
	var marble = Color(0.72, 0.68, 0.62)
	var marble_light = Color(0.80, 0.77, 0.70)
	var marble_dark = Color(0.58, 0.54, 0.48)
	var seam = Color(0.44, 0.40, 0.36)
	var vein = Color(0.67, 0.61, 0.56)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var seam_line = (x % 16 == 0) or (y % 16 == 0)
			var vein_line = ((x * 3 + y * 5) % 23 == 0) or ((x * 5 + y * 7) % 29 == 0)
			var block = ((x / 16) + (y / 16)) % 2
			if seam_line:
				image.set_pixel(x, y, seam)
			elif vein_line:
				image.set_pixel(x, y, vein)
			else:
				var base = marble_light if block == 0 else marble
				image.set_pixel(x, y, base if (x + y) % 9 != 0 else marble_dark)


func _draw_wall_tile(image: Image) -> void:
	# Dressed ashlar stone with formal coursing — reads more 'built to
	# last centuries' than the default rubble wall.
	var stone = Color(0.50, 0.47, 0.46)
	var stone_light = Color(0.60, 0.57, 0.55)
	var stone_dark = Color(0.38, 0.36, 0.35)
	var mortar = Color(0.30, 0.28, 0.27)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var row = y / 8
			var offset = 8 if row % 2 == 0 else 0
			var in_mortar_h = y % 8 == 0
			var in_mortar_v = (x + offset) % 16 == 0
			if in_mortar_h or in_mortar_v:
				image.set_pixel(x, y, mortar)
			else:
				var shade = (x + y * 2) % 13
				var c = stone
				if shade == 0:
					c = stone_light
				elif shade == 12:
					c = stone_dark
				image.set_pixel(x, y, c)


func _process(delta: float) -> void:
	_sway_censer(delta)
	_animate_candles(delta)
	_animate_sconces(delta)
	_flicker_window_light(delta)
	_bob_notes(delta)
	_drift_motes(delta)
	_rise_smoke(delta)


func _setup_decorations() -> void:
	super._setup_decorations()
	_create_ambient_dimming()
	_create_altar_platform()
	_create_altar_furnishings()
	_create_kneeler_cushions()
	_create_sunbeam()
	_create_rose_window()
	_create_stained_glass_windows()
	_create_choir_loft()
	_create_organ_pipes()
	_create_aisle_carpet()
	_create_floor_medallion()
	_create_altar_rail()
	_create_processional_torches()
	_create_pews()
	_create_wall_sconces()
	_create_hanging_banners()
	_create_bell_tower_stairs()
	_create_censer()
	_create_prayer_candles()
	_create_offering_box()
	_create_prayer_request_board()
	_create_confessional()
	_create_memorial_plaque()
	_create_musical_notes()
	_create_dust_motes()
	_create_incense_smoke()
	_create_guest_ledger()
	_create_vestry_door()
	_create_processional_poles()
	_create_reliquary_niche()


func _create_light_texture(radius: int = 96) -> ImageTexture:
	var size = radius * 2
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = size / 2
	for y in range(size):
		for x in range(size):
			var dist = Vector2(x - center, y - center).length()
			var alpha = clampf(1.0 - dist / float(center), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, alpha * alpha))
	return ImageTexture.create_from_image(img)


func _create_ambient_dimming() -> void:
	# Dim, cool-hushed nave so the colored glass pools and candle glow
	# read as relief instead of fighting a fully-lit room.
	var dim = CanvasModulate.new()
	dim.name = "CathedralDim"
	dim.color = Color(0.66, 0.64, 0.74)
	add_child(dim)


# ---------------------------------------------------------------------------
# Altar
# ---------------------------------------------------------------------------

func _create_altar_platform() -> void:
	var w = TILE_SIZE * 3
	var h = TILE_SIZE * 2 + 10
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var step_top = Color(0.78, 0.74, 0.66)
	var step_light = Color(0.88, 0.85, 0.78)
	var step_dark = Color(0.60, 0.56, 0.48)
	var riser = Color(0.48, 0.44, 0.38)
	for y in range(h):
		for x in range(w):
			var step = 0
			if y < 10:
				step = 2
			elif y < 20:
				step = 1
			var on_riser = (y == 9 or y == 19)
			if on_riser:
				img.set_pixel(x, y, riser)
			else:
				var grain = (x + y) % 11 == 0
				var c = step_top
				if step == 2:
					c = step_light
				elif grain:
					c = step_dark
				img.set_pixel(x, y, c)
	var sprite = Sprite2D.new()
	sprite.name = "AltarPlatform"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(7 * TILE_SIZE, 1 * TILE_SIZE - 10)
	decorations.add_child(sprite)


func _create_altar_furnishings() -> void:
	_create_altar_cloth()
	_create_candlestick(Vector2(7.3, 1.35))
	_create_candlestick(Vector2(9.6, 1.35))
	_create_chalice(Vector2(8.4, 1.45))
	_create_holy_book(Vector2(8.0, 2.05))


func _create_altar_cloth() -> void:
	var w = TILE_SIZE * 3 - 8
	var h = 16
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var white = Color(0.92, 0.90, 0.85)
	var white_shadow = Color(0.80, 0.77, 0.70)
	var gold = Color(0.80, 0.68, 0.28)
	for y in range(h):
		for x in range(w):
			var c = white if y < h - 3 else white_shadow
			if y == 0 or y == h - 1:
				c = gold
			img.set_pixel(x, y, c)
	# Gold fringe dashes along the bottom hem
	for x in range(0, w, 4):
		img.set_pixel(x, h - 1, gold)
	# Embroidered sunburst emblem, centered
	var cx = w / 2
	for i in range(6):
		var ang = i * PI / 3.0
		var ex = cx + int(cos(ang) * 5)
		var ey = int(h / 2.0) + int(sin(ang) * 3)
		if ex >= 0 and ex < w and ey >= 0 and ey < h:
			img.set_pixel(ex, ey, gold)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(7 * TILE_SIZE + 4, 1 * TILE_SIZE + 2)
	decorations.add_child(sprite)


func _create_candlestick(grid_pos: Vector2) -> void:
	var img = Image.create(8, 22, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var gold = Color(0.80, 0.68, 0.28)
	var gold_dark = Color(0.58, 0.48, 0.18)
	var gold_light = Color(0.95, 0.86, 0.55)
	var wax = Color(0.92, 0.88, 0.78)
	for x in range(1, 7):
		img.set_pixel(x, 20, gold_dark)
		img.set_pixel(x, 21, gold_dark)
	for y in range(8, 20):
		img.set_pixel(3, y, gold_light if y == 8 else gold)
		img.set_pixel(4, y, gold)
	for x in range(2, 6):
		img.set_pixel(x, 7, gold)
	for y in range(2, 7):
		img.set_pixel(3, y, wax)
		img.set_pixel(4, y, wax)
	img.set_pixel(3, 1, Color(0.98, 0.85, 0.45))
	img.set_pixel(4, 0, Color(1.0, 0.95, 0.60))

	var sprite = Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = grid_pos * TILE_SIZE
	decorations.add_child(sprite)

	var glow = PointLight2D.new()
	glow.position = grid_pos * TILE_SIZE + Vector2(0, -8)
	glow.color = Color(1.0, 0.78, 0.42)
	glow.energy = 0.30
	glow.texture = _create_light_texture(44)
	decorations.add_child(glow)


func _create_chalice(grid_pos: Vector2) -> void:
	var img = Image.create(12, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var gold = Color(0.82, 0.70, 0.30)
	var gold_dark = Color(0.60, 0.50, 0.20)
	var gold_light = Color(0.95, 0.88, 0.58)
	for y in range(0, 5):
		var half = 5 - y
		for x in range(6 - half, 6 + half):
			if x >= 0 and x < 12:
				img.set_pixel(x, y, gold_light if x == 6 else gold)
	for y in range(5, 11):
		img.set_pixel(5, y, gold_dark)
		img.set_pixel(6, y, gold)
	for x in range(3, 9):
		img.set_pixel(x, 11, gold_dark)
		img.set_pixel(x, 12, gold_dark)
	var sprite = Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = grid_pos * TILE_SIZE
	decorations.add_child(sprite)


func _create_holy_book(grid_pos: Vector2) -> void:
	var img = Image.create(20, 12, false, Image.FORMAT_RGBA8)
	var cover = Color(0.35, 0.10, 0.12)
	var page = Color(0.90, 0.86, 0.74)
	var gold = Color(0.80, 0.68, 0.28)
	for y in range(12):
		for x in range(20):
			var c = page
			if y < 1 or y > 10 or x < 1 or x > 18:
				c = cover
			img.set_pixel(x, y, c)
	img.set_pixel(4, 4, gold)
	img.set_pixel(5, 4, gold)
	img.set_pixel(4, 5, gold)
	for line in range(2):
		var ly = 6 + line * 2
		for x in range(8, 17):
			if (x + line) % 3 != 0:
				img.set_pixel(x, ly, Color(0.35, 0.32, 0.30))
	var sprite = Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = grid_pos * TILE_SIZE
	decorations.add_child(sprite)


func _create_kneeler_cushions() -> void:
	_create_kneeler(Vector2(7.5, 3.3))
	_create_kneeler(Vector2(9.5, 3.3))


func _create_kneeler(grid_pos: Vector2) -> void:
	var img = Image.create(14, 8, false, Image.FORMAT_RGBA8)
	var cushion = Color(0.55, 0.12, 0.14)
	var cushion_dark = Color(0.40, 0.08, 0.10)
	var trim = Color(0.78, 0.66, 0.26)
	for y in range(8):
		for x in range(14):
			var c = cushion if y < 6 else cushion_dark
			if x == 0 or x == 13:
				c = trim
			img.set_pixel(x, y, c)
	var sprite = Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = grid_pos * TILE_SIZE
	decorations.add_child(sprite)


func _create_sunbeam() -> void:
	# Soft light shaft from the center window down onto the altar cloth.
	var w = TILE_SIZE * 2
	var h = TILE_SIZE * 4
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var beam = Color(0.95, 0.86, 0.55, 0.10)
	var beam_core = Color(1.0, 0.92, 0.65, 0.16)
	for y in range(h):
		var spread = int(float(y) / h * (w * 0.5))
		var cx = w / 2
		for x in range(cx - spread, cx + spread + 1):
			if x >= 0 and x < w:
				var dist = abs(x - cx)
				img.set_pixel(x, y, beam_core if dist < 3 else beam)
	var sprite = Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(8.5 * TILE_SIZE, 3.2 * TILE_SIZE)
	sprite.z_index = 3
	decorations.add_child(sprite)


func _create_altar_rail() -> void:
	# Low communion rail separating the sanctuary from the nave — reads
	# as 'you may look, but the altar steps are the priest's ground'.
	var gy = 3
	var w = TILE_SIZE * 4
	var h = 14
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var wood = Color(0.42, 0.28, 0.16)
	var wood_dark = Color(0.28, 0.18, 0.10)
	var gold = Color(0.78, 0.64, 0.26)
	for x in range(w):
		img.set_pixel(x, 2, gold)
		img.set_pixel(x, 3, wood)
	for post_x in range(4, w - 4, 12):
		for y in range(2, h):
			img.set_pixel(post_x, y, wood_dark)
			img.set_pixel(post_x + 1, y, wood_dark)
	var sprite_l = Sprite2D.new()
	sprite_l.centered = false
	sprite_l.texture = ImageTexture.create_from_image(img)
	sprite_l.position = Vector2(3 * TILE_SIZE, gy * TILE_SIZE - 6)
	decorations.add_child(sprite_l)
	var sprite_r = Sprite2D.new()
	sprite_r.centered = false
	sprite_r.texture = ImageTexture.create_from_image(img)
	sprite_r.position = Vector2(11 * TILE_SIZE, gy * TILE_SIZE - 6)
	decorations.add_child(sprite_r)


func _create_processional_torches() -> void:
	_create_torch_stand(Vector2(6.5, 1.5))
	_create_torch_stand(Vector2(10.5, 1.5))


func _create_torch_stand(grid_pos: Vector2) -> void:
	var img = Image.create(10, 30, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var iron = Color(0.28, 0.27, 0.29)
	var iron_light = Color(0.42, 0.40, 0.42)
	var outer = Color(0.94, 0.55, 0.16)
	var inner = Color(1.0, 0.90, 0.55)
	for x in range(2, 5):
		img.set_pixel(x, 29, iron)
		img.set_pixel(x + 3, 29, iron)
	for y in range(10, 29):
		img.set_pixel(4, y, iron)
		img.set_pixel(5, y, iron_light)
	for x in range(2, 8):
		img.set_pixel(x, 10, iron)
	for y in range(0, 10):
		var w = 3 if y > 4 else 1
		var cx = 4
		for x in range(cx - w, cx + w + 1):
			if x >= 0 and x < 10:
				img.set_pixel(x, y, inner if y > 6 else outer)
	var sprite = Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = grid_pos * TILE_SIZE
	decorations.add_child(sprite)
	var glow = PointLight2D.new()
	glow.position = grid_pos * TILE_SIZE + Vector2(0, -10)
	glow.color = Color(1.0, 0.70, 0.35)
	glow.energy = 0.38
	glow.texture = _create_light_texture(56)
	decorations.add_child(glow)


# ---------------------------------------------------------------------------
# Stained glass + choir loft
# ---------------------------------------------------------------------------

func _create_stained_glass_windows() -> void:
	var specs = [
		{"x": 4.0, "tint": Color(0.25, 0.45, 0.85), "pool_y": 3.4},
		{"x": 8.5, "tint": Color(0.85, 0.70, 0.30), "pool_y": 1.6},
		{"x": 13.0, "tint": Color(0.75, 0.22, 0.25), "pool_y": 3.4},
	]
	var light_tex = _create_light_texture(90)
	for spec in specs:
		_create_window(spec["x"], spec["tint"])
		var pool = PointLight2D.new()
		pool.position = Vector2(spec["x"] * TILE_SIZE, spec["pool_y"] * TILE_SIZE)
		pool.color = spec["tint"]
		pool.energy = 0.45
		pool.texture = light_tex
		decorations.add_child(pool)
		_window_lights.append(pool)


func _create_window(gx: float, tint: Color) -> void:
	var w = 22
	var h = 44
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var lead = Color(0.12, 0.11, 0.10)
	var glass_a = tint.lightened(0.25)
	var glass_b = tint
	var glass_c = tint.darkened(0.25)
	var glow = tint.lightened(0.55)
	for y in range(h):
		for x in range(w):
			var arch_cy = 12
			if y < arch_cy:
				var dist = Vector2(x - w / 2.0, y - arch_cy).length()
				if dist > w / 2.0 - 2:
					continue
			var on_lead = (x % 7 == 0) or (y % 8 == 0) or x == 0 or x == w - 1
			if on_lead:
				img.set_pixel(x, y, lead)
				continue
			var panel = ((x / 7) + (y / 8)) % 3
			var c = glass_b
			if panel == 0:
				c = glass_a
			elif panel == 2:
				c = glass_c
			if (x % 7 == 3 or x % 7 == 4) and (y % 8 == 3 or y % 8 == 4):
				c = glow
			img.set_pixel(x, y, c)
	var sprite = Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(gx * TILE_SIZE, 0.4 * TILE_SIZE)
	decorations.add_child(sprite)


func _flicker_window_light(delta: float) -> void:
	_light_time += delta
	for i in range(_window_lights.size()):
		var light = _window_lights[i]
		if is_instance_valid(light):
			light.energy = 0.40 + 0.10 * sin(_light_time * 0.6 + i * 2.1)


func _create_rose_window() -> void:
	# Large circular tracery window above the lancets — the cathedral's
	# centerpiece, echoing FF6/CT's grander sanctuary set-pieces.
	var size = 48
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var lead = Color(0.14, 0.13, 0.12)
	var wedge_colors = [
		Color(0.75, 0.22, 0.25), Color(0.25, 0.45, 0.85),
		Color(0.85, 0.70, 0.30), Color(0.30, 0.55, 0.35),
	]
	var center = size / 2.0
	for y in range(size):
		for x in range(size):
			var dist = Vector2(x - center, y - center).length()
			if dist > center - 1:
				continue
			var ang = atan2(y - center, x - center)
			var wedge = int(fposmod(ang + PI, TAU) / (TAU / 8.0)) % wedge_colors.size()
			var c = wedge_colors[wedge]
			var on_spoke = int(dist) % 6 == 0
			var on_ring = dist < 6 or (dist > center - 5 and dist < center - 3)
			if on_spoke or on_ring:
				img.set_pixel(x, y, lead)
			else:
				img.set_pixel(x, y, c if dist > 6 else c.lightened(0.4))
	var sprite = Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(8.5 * TILE_SIZE, -18)
	sprite.z_index = 2
	decorations.add_child(sprite)

	var glow = PointLight2D.new()
	glow.position = Vector2(8.5 * TILE_SIZE, 0.9 * TILE_SIZE)
	glow.color = Color(0.85, 0.65, 0.55)
	glow.energy = 0.30
	glow.texture = _create_light_texture(70)
	decorations.add_child(glow)
	_window_lights.append(glow)


func _create_choir_loft() -> void:
	# Shadowed gallery lip + robed silhouettes, hung above the back wall
	# to suggest an upper mezzanine without needing real floor geometry.
	var w = TILE_SIZE * 8
	var h = 30
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var rail_wood = Color(0.30, 0.20, 0.12)
	var rail_light = Color(0.42, 0.28, 0.16)
	var stone_shadow = Color(0.30, 0.28, 0.30, 0.85)
	var robe = Color(0.35, 0.30, 0.55)
	for y in range(0, 10):
		for x in range(w):
			img.set_pixel(x, y, stone_shadow)
	for x in range(w):
		img.set_pixel(x, 10, rail_light)
		img.set_pixel(x, 11, rail_wood)
	var bx = 4
	while bx < w - 4:
		for y in range(11, 20):
			img.set_pixel(bx, y, rail_wood)
		bx += 10
	for x in range(w):
		img.set_pixel(x, 20, rail_light)
	for i in range(4):
		var cx = 20 + i * 40
		for y in range(0, 10):
			var half = 4 - int(y / 3.0)
			for x in range(cx - half, cx + half + 1):
				if x >= 0 and x < w:
					img.set_pixel(x, y, robe)
	var sprite = Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(9 * TILE_SIZE, -5)
	sprite.z_index = -1
	decorations.add_child(sprite)

	var label = Label.new()
	label.text = "Choir Loft"
	label.position = Vector2(7.2 * TILE_SIZE, -34)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color(0.75, 0.70, 0.85))
	decorations.add_child(label)


func _create_organ_pipes() -> void:
	# Flanks the choir loft — implies a modest pipe organ up there,
	# which is where Wren's 'the loft carries sound' line points.
	var heights = [26, 34, 20, 30, 24, 36, 22]
	var w = 8
	var total_w = heights.size() * (w + 2)
	var start_x = 9 * TILE_SIZE - total_w / 2.0
	for i in range(heights.size()):
		var h = heights[i]
		var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
		var metal = Color(0.68, 0.62, 0.42) if i % 2 == 0 else Color(0.72, 0.72, 0.76)
		var metal_dark = metal.darkened(0.3)
		var metal_light = metal.lightened(0.3)
		for y in range(h):
			for x in range(w):
				var c = metal
				if x == 0 or x == w - 1:
					c = metal_dark
				elif x == 1:
					c = metal_light
				img.set_pixel(x, y, c)
		for x in range(2, w - 2):
			img.set_pixel(x, h - 6, metal_dark)
		var sprite = Sprite2D.new()
		sprite.centered = false
		sprite.texture = ImageTexture.create_from_image(img)
		sprite.position = Vector2(start_x + i * (w + 2), -h + 12)
		sprite.z_index = -1
		decorations.add_child(sprite)


# ---------------------------------------------------------------------------
# Aisle + pews
# ---------------------------------------------------------------------------

func _create_aisle_carpet() -> void:
	var gx = 8
	var gy = 3
	var gw = 2
	var gh = 9
	var w = TILE_SIZE * gw
	var h = TILE_SIZE * gh
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var red = Color(0.68, 0.16, 0.14)
	var red_dark = Color(0.52, 0.11, 0.10)
	var gold = Color(0.78, 0.66, 0.26)
	var gold_dark = Color(0.62, 0.50, 0.18)
	for y in range(h):
		for x in range(w):
			var near_edge = x < 3 or x >= w - 3
			if near_edge:
				img.set_pixel(x, y, gold if (x + y) % 3 != 0 else gold_dark)
				continue
			var diagonal = (x + y) % 10
			if diagonal < 2:
				img.set_pixel(x, y, gold_dark)
			elif (x + y / 4) % 5 == 0:
				img.set_pixel(x, y, red_dark)
			else:
				img.set_pixel(x, y, red)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(gx * TILE_SIZE, gy * TILE_SIZE)
	decorations.add_child(sprite)


func _create_floor_medallion() -> void:
	# Inlaid brass compass rose at the aisle crossing, half-transparent
	# so it reads as set into the marble rather than sitting on it.
	var size = 40
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var gold = Color(0.75, 0.63, 0.26, 0.55)
	var gold_dark = Color(0.55, 0.45, 0.16, 0.55)
	var center = size / 2.0
	for y in range(size):
		for x in range(size):
			var dist = Vector2(x - center, y - center).length()
			if dist > center - 2 and dist < center:
				img.set_pixel(x, y, gold)
			elif dist > center * 0.5 and dist < center * 0.5 + 2:
				img.set_pixel(x, y, gold_dark)
	for i in range(8):
		var ang = i * PI / 4.0
		for r in range(int(center * 0.5), int(center)):
			var px = int(center + cos(ang) * r)
			var py = int(center + sin(ang) * r)
			if px >= 0 and px < size and py >= 0 and py < size:
				img.set_pixel(px, py, gold_dark)
	var sprite = Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(8.5 * TILE_SIZE, 9 * TILE_SIZE)
	decorations.add_child(sprite)


func _create_pews() -> void:
	var left_rows = [4, 6, 8]
	var right_rows = [4, 6, 8]
	for i in range(left_rows.size()):
		_create_pew_bench(Vector2(2, left_rows[i]), i == 1)
	for i in range(right_rows.size()):
		_create_pew_bench(Vector2(13, right_rows[i]), i == 2)


func _create_pew_bench(anchor: Vector2, has_book: bool) -> void:
	var w = TILE_SIZE * 3
	var h = TILE_SIZE
	var img = Image.create(w, h + 6, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var wood = Color(0.36, 0.23, 0.14)
	var wood_light = Color(0.48, 0.32, 0.19)
	var wood_dark = Color(0.24, 0.15, 0.09)
	for y in range(0, 10):
		for x in range(w):
			img.set_pixel(x, y, wood_dark if y < 2 else wood)
		for fx2 in [1, w - 3]:
			for fy2 in range(0, 4):
				var half2 = 2 - int(fy2 / 2.0)
				for dx2 in range(-half2, half2 + 1):
					var px2 = fx2 + dx2
					if px2 >= 0 and px2 < w:
						img.set_pixel(px2, fy2, wood_light)
	for y in range(10, 22):
		for x in range(w):
			var c = wood
			if y == 10:
				c = wood_light
			elif x % 18 < 2:
				c = wood_dark
			img.set_pixel(x, y, c)
	for lx in [4, w / 2, w - 6]:
		for y in range(22, h + 6):
			img.set_pixel(lx, y, wood_dark)
			img.set_pixel(lx + 1, y, wood_dark)

	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = anchor * TILE_SIZE
	decorations.add_child(sprite)

	if has_book:
		_create_prayer_book(anchor * TILE_SIZE + Vector2(w / 2.0 - 8, 4))


func _create_prayer_book(pos: Vector2) -> void:
	var img = Image.create(16, 10, false, Image.FORMAT_RGBA8)
	var cover = Color(0.45, 0.10, 0.10)
	var page = Color(0.88, 0.84, 0.72)
	for y in range(10):
		for x in range(16):
			img.set_pixel(x, y, cover if (y < 2 or y > 7) else page)
	for line in range(3):
		var ly = 3 + line * 2
		for x in range(2, 14):
			if (x + line) % 4 != 0:
				img.set_pixel(x, ly, Color(0.35, 0.32, 0.30))
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = pos
	decorations.add_child(sprite)


# ---------------------------------------------------------------------------
# Wall sconces + banners
# ---------------------------------------------------------------------------

func _create_wall_sconces() -> void:
	_sconce_frames.clear()
	for f in range(3):
		var img = Image.create(10, 16, false, Image.FORMAT_RGBA8)
		_draw_sconce_flame(img, f)
		_sconce_frames.append(ImageTexture.create_from_image(img))
	var light_tex = _create_light_texture(64)
	for anchor in [Vector2(1, 4), Vector2(16, 4), Vector2(1, 8), Vector2(16, 8)]:
		_create_sconce(anchor, light_tex)


func _draw_sconce_flame(img: Image, frame: int) -> void:
	img.fill(Color.TRANSPARENT)
	var iron = Color(0.25, 0.24, 0.26)
	var outer = Color(0.92, 0.52, 0.14)
	var inner = Color(1.0, 0.90, 0.55)
	for y in range(10, 16):
		img.set_pixel(4, y, iron)
		img.set_pixel(5, y, iron)
	for x in range(2, 8):
		img.set_pixel(x, 10, iron)
	var offsets = [0, 1, -1]
	var ofs = offsets[frame % 3]
	var cx = 4 + ofs
	for y in range(0, 10):
		var w = 2 if y > 4 else 1
		for x in range(cx - w, cx + w + 1):
			if x >= 0 and x < 10:
				img.set_pixel(x, y, inner if y > 6 else outer)


func _create_sconce(anchor: Vector2, light_tex: ImageTexture) -> void:
	var sconce = Sprite2D.new()
	sconce.centered = false
	sconce.texture = _sconce_frames[0]
	sconce.position = anchor * TILE_SIZE + Vector2(TILE_SIZE / 2.0 - 5, 4)
	decorations.add_child(sconce)
	_sconce_sprites.append(sconce)

	var glow = PointLight2D.new()
	glow.position = anchor * TILE_SIZE + Vector2(TILE_SIZE / 2.0, 8)
	glow.color = Color(0.95, 0.62, 0.30)
	glow.energy = 0.32
	glow.texture = light_tex
	decorations.add_child(glow)


func _animate_sconces(delta: float) -> void:
	_sconce_timer += delta
	if _sconce_timer >= SCONCE_SPEED:
		_sconce_timer -= SCONCE_SPEED
		_sconce_frame = (_sconce_frame + 1) % _sconce_frames.size()
		for sconce in _sconce_sprites:
			if is_instance_valid(sconce):
				sconce.texture = _sconce_frames[_sconce_frame]


func _create_hanging_banners() -> void:
	_create_banner(Vector2(1, 6), Color(0.55, 0.10, 0.12))
	_create_banner(Vector2(16, 6), Color(0.15, 0.25, 0.55))


func _create_banner(anchor: Vector2, base_color: Color) -> void:
	var w = 18
	var h = TILE_SIZE * 2
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var gold = Color(0.78, 0.66, 0.26)
	var shade = base_color.darkened(0.25)
	for y in range(h):
		for x in range(w):
			var c = base_color if (x + y) % 9 != 0 else shade
			if x < 2 or x >= w - 2:
				c = gold
			img.set_pixel(x, y, c)
	for x in range(w):
		img.set_pixel(x, 0, gold)
		img.set_pixel(x, 1, gold.darkened(0.2))
	var tip_h = 14
	for y in range(h - tip_h, h):
		var progress = float(y - (h - tip_h)) / float(tip_h)
		var inset = int(progress * (w / 2.0))
		for x in range(inset, w - inset):
			img.set_pixel(x, y, base_color if (x + y) % 5 != 0 else shade)
	var cx = w / 2
	var cy = h / 2 - 10
	for y in range(cy - 4, cy + 4):
		for x in range(cx - 4, cx + 4):
			if Vector2(x - cx, y - cy).length() < 4:
				img.set_pixel(x, y, gold)
	var sprite = Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = anchor * TILE_SIZE
	decorations.add_child(sprite)


# ---------------------------------------------------------------------------
# Bell tower, censer, offering box, notes
# ---------------------------------------------------------------------------

func _create_bell_tower_stairs() -> void:
	var gx = 15
	var gy = 10
	var w = TILE_SIZE
	var h = TILE_SIZE
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var stone = Color(0.46, 0.44, 0.46)
	var stone_dark = Color(0.32, 0.30, 0.32)
	var stone_light = Color(0.58, 0.56, 0.58)
	var dark_well = Color(0.10, 0.09, 0.10)
	for y in range(h):
		for x in range(w):
			var dist = Vector2(x - w * 0.5, y - h * 0.5).length()
			if dist < 5:
				img.set_pixel(x, y, dark_well)
			else:
				var ring = int(dist) % 6
				var c = stone
				if ring < 2:
					c = stone_dark
				elif ring > 4:
					c = stone_light
				img.set_pixel(x, y, c)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(gx * TILE_SIZE, gy * TILE_SIZE)
	decorations.add_child(sprite)

	var label = Label.new()
	label.text = "→ Bell Tower"
	label.position = Vector2((gx - 0.3) * TILE_SIZE, (gy - 0.6) * TILE_SIZE)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color(0.85, 0.80, 0.65))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	decorations.add_child(label)


func _create_censer() -> void:
	var img = Image.create(20, 40, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var chain = Color(0.55, 0.50, 0.30)
	var brass = Color(0.75, 0.62, 0.28)
	var brass_dark = Color(0.52, 0.42, 0.18)
	var brass_light = Color(0.92, 0.82, 0.48)
	var smoke = Color(0.85, 0.85, 0.90, 0.35)
	for y in range(0, 14):
		img.set_pixel(9, y, chain)
		img.set_pixel(10, y, chain)
	for y in range(14, 30):
		for x in range(4, 16):
			var dist = Vector2(x - 10.0, y - 22.0).length()
			if dist < 7.0:
				var c = brass
				if x < 8:
					c = brass_dark
				elif y < 18:
					c = brass_light
				if int(dist) % 3 == 0 and (x + y) % 4 == 0:
					c = Color(0.15, 0.12, 0.08)
				img.set_pixel(x, y, c)
	for x in range(6, 15):
		img.set_pixel(x, 14, brass_dark)
	for x in range(8, 13):
		img.set_pixel(x, 29, brass_dark)
	for y in range(0, 6):
		var sx = 10 + int(sin(float(y)) * 2)
		img.set_pixel(sx, y, smoke)

	_censer_sprite = Sprite2D.new()
	_censer_sprite.name = "Censer"
	_censer_sprite.texture = ImageTexture.create_from_image(img)
	_censer_sprite.offset = Vector2(0, 20)
	_censer_sprite.position = Vector2(8.5 * TILE_SIZE, 5 * TILE_SIZE - 16)
	_censer_sprite.z_index = 6
	decorations.add_child(_censer_sprite)


func _sway_censer(delta: float) -> void:
	_censer_time += delta
	if _censer_sprite:
		_censer_sprite.rotation = sin(_censer_time * 1.3) * 0.12


func _create_prayer_candles() -> void:
	_candle_frames.clear()
	for f in range(3):
		var img = Image.create(6, 10, false, Image.FORMAT_RGBA8)
		_draw_candle_flame(img, f)
		_candle_frames.append(ImageTexture.create_from_image(img))
	for anchor in [Vector2(6, 2), Vector2(10, 2)]:
		_create_candle_rack(anchor)


func _draw_candle_flame(img: Image, frame: int) -> void:
	img.fill(Color.TRANSPARENT)
	var offsets = [0, 1, -1]
	var ofs = offsets[frame % 3]
	var outer = Color(0.95, 0.55, 0.15)
	var inner = Color(1.0, 0.92, 0.55)
	var cx = 3 + ofs
	for y in range(10):
		var w = 2 if y > 3 else 1
		for x in range(cx - w, cx + w + 1):
			if x >= 0 and x < 6:
				img.set_pixel(x, y, inner if y > 5 else outer)


func _create_candle_rack(anchor: Vector2) -> void:
	var node = Node2D.new()
	node.name = "CandleRack_%d_%d" % [int(anchor.x), int(anchor.y)]
	var wood = Color(0.34, 0.22, 0.13)
	var wood_dark = Color(0.22, 0.14, 0.08)
	var wax = Color(0.90, 0.86, 0.76)
	var wax_shadow = Color(0.74, 0.70, 0.60)

	var shelf_img = Image.create(TILE_SIZE, 8, false, Image.FORMAT_RGBA8)
	for x in range(TILE_SIZE):
		for y in range(8):
			shelf_img.set_pixel(x, y, wood_dark if y < 2 else wood)
	var shelf = Sprite2D.new()
	shelf.centered = false
	shelf.texture = ImageTexture.create_from_image(shelf_img)
	shelf.position = anchor * TILE_SIZE + Vector2(0, TILE_SIZE - 8)
	node.add_child(shelf)

	for i in range(3):
		var cx = 6 + i * 8
		var candle_img = Image.create(6, 16, false, Image.FORMAT_RGBA8)
		candle_img.fill(Color.TRANSPARENT)
		for y in range(16):
			for x in range(6):
				candle_img.set_pixel(x, y, wax_shadow if x == 0 else wax)
		var candle = Sprite2D.new()
		candle.centered = false
		candle.texture = ImageTexture.create_from_image(candle_img)
		candle.position = anchor * TILE_SIZE + Vector2(cx, TILE_SIZE - 24)
		node.add_child(candle)

		var flame = Sprite2D.new()
		flame.centered = false
		flame.texture = _candle_frames[0]
		flame.position = anchor * TILE_SIZE + Vector2(cx, TILE_SIZE - 34)
		flame.z_index = 4
		node.add_child(flame)
		_candle_sprites.append(flame)

		var glow = PointLight2D.new()
		glow.position = anchor * TILE_SIZE + Vector2(cx + 3, TILE_SIZE - 30)
		glow.color = Color(1.0, 0.75, 0.40)
		glow.energy = 0.35
		glow.texture = _create_light_texture(48)
		node.add_child(glow)

	decorations.add_child(node)


func _animate_candles(delta: float) -> void:
	_candle_timer += delta
	if _candle_timer >= CANDLE_SPEED:
		_candle_timer -= CANDLE_SPEED
		_candle_frame = (_candle_frame + 1) % _candle_frames.size()
		for flame in _candle_sprites:
			if is_instance_valid(flame):
				flame.texture = _candle_frames[_candle_frame]


func _create_offering_box() -> void:
	var gx = 3
	var gy = 10
	var img = Image.create(22, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var wood = Color(0.38, 0.25, 0.15)
	var wood_dark = Color(0.26, 0.16, 0.09)
	var wood_light = Color(0.50, 0.34, 0.20)
	var brass = Color(0.75, 0.62, 0.28)
	var coin = Color(0.85, 0.72, 0.30)
	for y in range(6, 20):
		for x in range(22):
			var c = wood
			if x < 2 or x > 19:
				c = wood_dark
			elif (x + y) % 9 == 0:
				c = wood_light
			img.set_pixel(x, y, c)
	for x in range(22):
		img.set_pixel(x, 5, brass)
		img.set_pixel(x, 6, wood_light)
	for x in range(9, 13):
		img.set_pixel(x, 5, Color(0.10, 0.08, 0.06))
	img.set_pixel(6, 3, coin)
	img.set_pixel(15, 4, coin)
	img.set_pixel(16, 3, coin.lightened(0.2))

	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(gx * TILE_SIZE + 5, gy * TILE_SIZE + 8)
	decorations.add_child(sprite)


func _create_prayer_request_board() -> void:
	# Corkboard of pinned prayer-request notes, nailed above the
	# offering box ledge — small human clutter next to the coin slot.
	var img = Image.create(24, 20, false, Image.FORMAT_RGBA8)
	var cork = Color(0.62, 0.48, 0.30)
	var frame = Color(0.36, 0.24, 0.14)
	for y in range(20):
		for x in range(24):
			var c = cork if (x + y) % 7 != 0 else cork.darkened(0.15)
			if x < 2 or x > 21 or y < 2 or y > 17:
				c = frame
			img.set_pixel(x, y, c)
	var notes = [Color(0.90, 0.85, 0.55), Color(0.85, 0.70, 0.75), Color(0.70, 0.85, 0.80)]
	var note_positions = [Vector2(4, 4), Vector2(12, 5), Vector2(6, 11), Vector2(15, 12)]
	for i in range(note_positions.size()):
		var p = note_positions[i]
		var col = notes[i % notes.size()]
		for y in range(int(p.y), int(p.y) + 5):
			for x in range(int(p.x), int(p.x) + 6):
				if x < 24 and y < 20:
					img.set_pixel(x, y, col)
	var sprite = Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(4 * TILE_SIZE, 9.5 * TILE_SIZE)
	decorations.add_child(sprite)


func _create_confessional() -> void:
	var gx = 1
	var gy = 9
	var w = TILE_SIZE
	var h = TILE_SIZE * 2 - 4
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var wood = Color(0.32, 0.20, 0.12)
	var wood_dark = Color(0.22, 0.13, 0.07)
	var wood_light = Color(0.44, 0.29, 0.17)
	var curtain = Color(0.35, 0.10, 0.14)
	var curtain_dark = Color(0.24, 0.06, 0.09)
	for y in range(h):
		for x in range(w):
			var c = wood
			if x < 3 or x >= w - 3:
				c = wood_dark
			elif (x + y) % 10 == 0:
				c = wood_light
			img.set_pixel(x, y, c)
	for y in range(8, h - 4):
		for x in range(8, w - 8):
			var fold = (x + y) % 5 < 2
			img.set_pixel(x, y, curtain_dark if fold else curtain)
	for y in range(2, 8):
		for x in range(6, w - 6):
			if (x + y) % 3 == 0:
				img.set_pixel(x, y, wood_dark)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(gx * TILE_SIZE, gy * TILE_SIZE - TILE_SIZE)
	decorations.add_child(sprite)

	var label = Label.new()
	label.text = "Confessional"
	label.position = Vector2((gx - 0.4) * TILE_SIZE, (gy - 1.5) * TILE_SIZE)
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(0.70, 0.62, 0.55))
	decorations.add_child(label)


func _create_memorial_plaque() -> void:
	# Brass dedication plaque by the door — abstracted engraving lines
	# (no real font rendering into pixel art), plus a wry caption label.
	var img = Image.create(26, 16, false, Image.FORMAT_RGBA8)
	var brass = Color(0.68, 0.56, 0.28)
	var brass_dark = Color(0.48, 0.38, 0.16)
	var engrave = Color(0.30, 0.24, 0.12)
	for y in range(16):
		for x in range(26):
			img.set_pixel(x, y, brass_dark if (x == 0 or y == 0 or x == 25 or y == 15) else brass)
	for line in range(3):
		var ly = 3 + line * 4
		for x in range(3, 23):
			if (x + line * 2) % 5 != 0:
				img.set_pixel(x, ly, engrave)
	var sprite = Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(6.5 * TILE_SIZE, 11.2 * TILE_SIZE)
	decorations.add_child(sprite)

	var label = Label.new()
	label.text = "In memory of the Founding Cantor — acoustics over sermons"
	label.position = Vector2(4.6 * TILE_SIZE, 11.7 * TILE_SIZE)
	label.add_theme_font_size_override("font_size", 7)
	label.add_theme_color_override("font_color", Color(0.60, 0.56, 0.50))
	decorations.add_child(label)


func _create_musical_notes() -> void:
	# Faint floating notes near Wren — a visual nod to the 'subtle
	# harmonic ambience' the choir loft implies.
	var note_img = Image.create(6, 8, false, Image.FORMAT_RGBA8)
	note_img.fill(Color.TRANSPARENT)
	var ink = Color(0.85, 0.80, 0.90)
	for y in range(2, 8):
		note_img.set_pixel(1, y, ink)
	for x in range(1, 4):
		for y in range(5, 8):
			if Vector2(x - 1, y - 6.5).length() < 1.6:
				note_img.set_pixel(x, y, ink)
	note_img.set_pixel(1, 2, ink)
	note_img.set_pixel(2, 1, ink)
	note_img.set_pixel(3, 1, ink)
	var tex = ImageTexture.create_from_image(note_img)
	var offsets = [Vector2(-4, -6), Vector2(3, -10), Vector2(-2, -14)]
	for ofs in offsets:
		var note = Sprite2D.new()
		note.texture = tex
		note.modulate = Color(0.85, 0.80, 0.95, 0.85)
		var base_pos = Vector2(6, 3) * TILE_SIZE + ofs
		note.position = base_pos
		decorations.add_child(note)
		_note_sprites.append(note)
		_note_base_positions.append(base_pos)


func _bob_notes(delta: float) -> void:
	_note_time += delta
	for i in range(_note_sprites.size()):
		var note = _note_sprites[i]
		if is_instance_valid(note):
			var base: Vector2 = _note_base_positions[i]
			note.position = base + Vector2(0, sin(_note_time * 2.0 + i * 1.7) * 3.0)


func _create_incense_smoke() -> void:
	# Continuously rising wisps above the censer, independent of its
	# pendulum sway — the two motions read as separate physical things.
	var img = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.88, 0.86, 0.90, 0.4))
	var tex = ImageTexture.create_from_image(img)
	for i in range(4):
		var wisp = Sprite2D.new()
		wisp.texture = tex
		wisp.z_index = 6
		var base_pos = Vector2(8.5 * TILE_SIZE, 4.5 * TILE_SIZE) + Vector2(0, -i * 6)
		wisp.position = base_pos
		decorations.add_child(wisp)
		_smoke_sprites.append(wisp)
		_smoke_base_positions.append(base_pos)


func _rise_smoke(delta: float) -> void:
	_smoke_time += delta
	for i in range(_smoke_sprites.size()):
		var wisp = _smoke_sprites[i]
		if not is_instance_valid(wisp):
			continue
		var base: Vector2 = _smoke_base_positions[i]
		var cycle = fmod(_smoke_time * 6.0 + i * 5.0, 24.0)
		wisp.position = base + Vector2(sin(_smoke_time * 1.5 + i) * 3.0, -cycle)
		wisp.modulate.a = clampf(1.0 - cycle / 24.0, 0.0, 1.0)


func _create_guest_ledger() -> void:
	# Visitor ledger on a small stand near the offering box — same
	# 'ledger' pixel-language as the inn's registration desk.
	var img = Image.create(20, 16, false, Image.FORMAT_RGBA8)
	var cover = Color(0.30, 0.22, 0.45)
	var page = Color(0.90, 0.88, 0.80)
	for y in range(16):
		for x in range(20):
			img.set_pixel(x, y, cover if (y < 2 or y > 13) else page)
	for line in range(4):
		var ly = 4 + line * 2
		for x in range(3, 17):
			if (x + line) % 5 != 0:
				img.set_pixel(x, ly, Color(0.30, 0.30, 0.40))
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(2 * TILE_SIZE + 4, 10 * TILE_SIZE + 6)
	decorations.add_child(sprite)


func _create_vestry_door() -> void:
	# Implies a working sacristy off the west wall, mirroring the bell
	# tower / choir loft trick of hinting at unseen rooms.
	var img = Image.create(TILE_SIZE - 10, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var wood = Color(0.26, 0.17, 0.10)
	var wood_dark = Color(0.18, 0.12, 0.07)
	var hinge = Color(0.55, 0.50, 0.40)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE - 10):
			img.set_pixel(x, y, wood_dark if x < 2 or x > TILE_SIZE - 13 else wood)
	for hy in [4, TILE_SIZE - 6]:
		img.set_pixel(2, hy, hinge)
		img.set_pixel(3, hy, hinge)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(1 * TILE_SIZE, 2 * TILE_SIZE)
	decorations.add_child(sprite)

	var label = Label.new()
	label.text = "Vestry"
	label.position = Vector2(0.9 * TILE_SIZE, 1.5 * TILE_SIZE)
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(0.70, 0.62, 0.55))
	decorations.add_child(label)


func _create_processional_poles() -> void:
	_create_banner_pole(Vector2(6, 10), Color(0.72, 0.18, 0.14))
	_create_banner_pole(Vector2(11, 10), Color(0.18, 0.30, 0.68))


func _create_banner_pole(grid_pos: Vector2, cloth_color: Color) -> void:
	var img = Image.create(14, 30, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var pole = Color(0.70, 0.58, 0.24)
	for y in range(0, 30):
		img.set_pixel(6, y, pole)
		img.set_pixel(7, y, pole.darkened(0.2))
	for y in range(0, 3):
		for x in range(4, 10):
			img.set_pixel(x, y, pole.lightened(0.2))
	for y in range(4, 20):
		var taper = int((y - 4) / 4.0)
		for x in range(8, 12 - taper):
			img.set_pixel(x, y, cloth_color if (x + y) % 5 != 0 else cloth_color.darkened(0.2))
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = grid_pos * TILE_SIZE
	decorations.add_child(sprite)


func _create_reliquary_niche() -> void:
	# Small stone alcove holding a sealed relic box — the kind of detail
	# that rewards a player who actually reads every wall.
	var img = Image.create(20, 22, false, Image.FORMAT_RGBA8)
	var stone = Color(0.40, 0.38, 0.38)
	var stone_dark = Color(0.26, 0.25, 0.25)
	var shadow = Color(0.14, 0.13, 0.14)
	for y in range(22):
		for x in range(20):
			var in_niche = x > 3 and x < 16 and y > 3 and y < 18
			img.set_pixel(x, y, shadow if in_niche else (stone if (x + y) % 5 != 0 else stone_dark))
	var relic_gold = Color(0.75, 0.63, 0.26)
	var relic_dark = Color(0.55, 0.45, 0.16)
	for y in range(10, 16):
		for x in range(6, 14):
			img.set_pixel(x, y, relic_gold if y == 10 else relic_dark)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(16 * TILE_SIZE + 2, 2 * TILE_SIZE)
	decorations.add_child(sprite)

	var glow = PointLight2D.new()
	glow.position = Vector2(16 * TILE_SIZE + 12, 2 * TILE_SIZE + 13)
	glow.color = Color(0.85, 0.72, 0.35)
	glow.energy = 0.22
	glow.texture = _create_light_texture(36)
	decorations.add_child(glow)


func _create_dust_motes() -> void:
	# Tiny drifting specks inside the sunbeam — the cheapest possible
	# 'light is a physical thing in this room' cue.
	var img = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 0.96, 0.85, 0.55))
	var tex = ImageTexture.create_from_image(img)
	var rng = RandomNumberGenerator.new()
	rng.seed = 4177
	for i in range(10):
		var mote = Sprite2D.new()
		mote.texture = tex
		mote.z_index = 3
		var base_pos = Vector2(8.5 * TILE_SIZE, 3.2 * TILE_SIZE) + Vector2(
			rng.randf_range(-24, 24), rng.randf_range(-40, 90))
		mote.position = base_pos
		decorations.add_child(mote)
		_mote_sprites.append(mote)
		_mote_base_positions.append(base_pos)
		_mote_phases.append(rng.randf_range(0.0, TAU))


func _drift_motes(delta: float) -> void:
	_mote_time += delta
	for i in range(_mote_sprites.size()):
		var mote = _mote_sprites[i]
		if not is_instance_valid(mote):
			continue
		var base: Vector2 = _mote_base_positions[i]
		var phase: float = _mote_phases[i]
		var drift = Vector2(sin(_mote_time * 0.4 + phase) * 6.0, cos(_mote_time * 0.25 + phase) * 4.0)
		mote.position = base + drift
		mote.modulate.a = 0.35 + 0.25 * sin(_mote_time * 0.9 + phase)


# ---------------------------------------------------------------------------
# NPCs
# ---------------------------------------------------------------------------

func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	_create_sister_concord(OverworldNPCScript)
	_create_worshiper_elowen(OverworldNPCScript)
	_create_worshiper_bram(OverworldNPCScript)
	_create_chorister_wren(OverworldNPCScript)
	_create_repentant_fenn(OverworldNPCScript)


func _create_sister_concord(NPCScript) -> void:
	var sister = NPCScript.new()
	sister.npc_name = "Sister Concord"
	sister.npc_type = "scholar"
	sister.position = Vector2(8 * TILE_SIZE, 2 * TILE_SIZE)
	sister.dialogue_lines = [
		"Welcome, traveler. Rest your soul a moment.",
		"This chapel used to be full on the holy days.",
		"The Chancellor would sit there, third pew from the back. Always alone.",
		"He hasn't been here in months. Not since the cave started... whispering.",
		"If you go to the castle, look him in the eye. Tell me what you see there.",
	]
	npcs.add_child(sister)


func _create_worshiper_elowen(NPCScript) -> void:
	var elowen = NPCScript.new()
	elowen.npc_name = "Elowen Dray"
	elowen.npc_type = "villager"
	elowen.position = Vector2(3 * TILE_SIZE, 4 * TILE_SIZE)
	elowen.dialogue_lines = [
		"*whispering* Shh. I'm in the middle of something.",
		"*whispering* I asked for good weather for the harvest. And for my knees to forgive me for all this kneeling.",
		"*whispering* You can pray for embarrassing things here too, you know. No one checks.",
		"*whispering* The cave's been quiet lately. That doesn't comfort me the way people think it should.",
	]
	npcs.add_child(elowen)


func _create_worshiper_bram(NPCScript) -> void:
	var bram = NPCScript.new()
	bram.npc_name = "Bram Coll"
	bram.npc_type = "villager"
	bram.position = Vector2(14 * TILE_SIZE, 8 * TILE_SIZE)
	bram.dialogue_lines = [
		"*whispering* Third pew from the back. Same as always.",
		"*whispering* I'm not praying for anything in particular. Just sitting with it. Whatever it is.",
		"*whispering* Sister Concord never rushes anyone out. I respect that about her.",
		"*whispering* If you're here to ask the gods for a favor, get in line. It's a long line lately.",
	]
	npcs.add_child(bram)


func _create_chorister_wren(NPCScript) -> void:
	var wren = NPCScript.new()
	wren.npc_name = "Wren"
	wren.npc_type = "villager"
	wren.position = Vector2(6 * TILE_SIZE, 3 * TILE_SIZE)
	wren.dialogue_lines = [
		"Mi-mi-mi-mi-MI— sorry. Warming up. Cantor Vell says a flat note offends the acoustics personally.",
		"The loft up there carries sound better than anywhere in Harmonia. You can hear a whisper from the back pew.",
		"I've been practicing the Founding Hymn for three months. I still crack on the high part.",
		"Want to hear my scales? No? Everyone says no. I'm doing it anyway. La-la-la-LAAAA—",
	]
	npcs.add_child(wren)


func _create_repentant_fenn(NPCScript) -> void:
	var fenn = NPCScript.new()
	fenn.npc_name = "Fenn Marrow"
	fenn.npc_type = "mysterious"
	fenn.position = Vector2(10 * TILE_SIZE, 2 * TILE_SIZE)
	fenn.dialogue_lines = [
		"Don't look at me like that. I'm ALLOWED to be here.",
		"One candle. That's the going rate for lifting a merchant's coin purse, apparently.",
		"Sister Concord says the flame remembers what the thief forgets. I think she's just being kind.",
		"*lights the wick, watches it catch* There. The universe and I are square. Probably.",
		"You didn't see me. I wasn't even here. This conversation isn't happening.",
	]
	npcs.add_child(fenn)


# ---------------------------------------------------------------------------
# Transitions
# ---------------------------------------------------------------------------

func _setup_transitions() -> void:
	super._setup_transitions()
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return
	var exit = AreaTransitionScript.new()
	exit.name = "Exit"
	exit.target_map = "harmonia_village"
	exit.target_spawn = "chapel_exit"
	exit.require_interaction = false
	exit.position = Vector2(8.5 * TILE_SIZE, 12.5 * TILE_SIZE)
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
