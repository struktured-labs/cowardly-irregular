extends BaseInterior
class_name ScripturaGuildInterior

## ScripturaGuildInterior - The Scriptweaver's Guild, arcane archive of the
## Scriptura capital district. Where the Harmonia library preserves stories,
## the Guild edits them — towering rune-etched shelves, a self-turning tome
## on a central lectern, a wall of pinned "correction slips" (reality
## patches awaiting approval), glowing ink wells, a locked cabinet of
## deprecated truths, and a brass clockwork orrery charting drift no
## honest sky should have. Cold blue-violet stone, warm candlelight
## accents. Scholar-Adept Quill keeps the desk nearest the lectern.

const GUILD_LAYOUT = [
	"WWWWWWWWWWWWWWWWWW",
	"W.SSSSSSSSSSSSSS.W",
	"W................W",
	"W..K..........K..W",
	"W.....I......I...W",
	"W.....I......I...W",
	"W.....I......I...W",
	"W.....I......I...W",
	"W........L.......W",
	"W..C...........X.W",
	"W................W",
	"W................W",
	"WWWWWWWWDDWWWWWWWW",
]

## Self-turning lectern book (3-frame page flip)
var _book_sprite: Sprite2D
var _book_frames: Array[ImageTexture] = []
var _book_frame: int = 0
var _book_timer: float = 0.0
const BOOK_PAGE_SPEED: float = 1.4

## Hovering candles (2-frame flicker + independent bob)
var _candle_sprites: Array[Sprite2D] = []
var _candle_frames: Array[ImageTexture] = []
var _candle_frame: int = 0
var _candle_timer: float = 0.0
const CANDLE_SPEED: float = 0.18
var _candle_lights: Array[PointLight2D] = []
var _candle_base_positions: Array[Vector2] = []
var _candle_bob_time: float = 0.0

## Clockwork orrery slow rotation (2-frame, very slow swap)
var _orrery_sprite: Sprite2D
var _orrery_frames: Array[ImageTexture] = []
var _orrery_time: float = 0.0

## Ambient sconces + ceiling ward-lights + ink-well glow, breathing
var _lamp_lights: Array[PointLight2D] = []
var _light_time: float = 0.0

## Floating correction glyphs drifting near the slip wall
var _glyph_sprites: Array[Sprite2D] = []
var _glyph_base_positions: Array[Vector2] = []
var _glyph_time: float = 0.0

## Glyph moth crawl (2-frame) on the east rune-shelf island
var _moth_frames: Array[ImageTexture] = []
var _moth_sprite: Sprite2D
var _moth_base: Vector2 = Vector2.ZERO
var _moth_frame: int = 0
var _moth_timer: float = 0.0

## Sigil floor circle pulse (under the lectern)
var _sigil_sprite: Sprite2D
var _sigil_time: float = 0.0


func _get_area_id() -> String:
	return "scriptura_guild"


func _get_display_name() -> String:
	return "Scriptweaver's Guild"


func _get_ambient_key() -> String:
	return "ambient_scriptorium"


func _get_map_width() -> int:
	return 18


func _get_map_height() -> int:
	return 13


func _get_layout() -> Array:
	return GUILD_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(8, 11)
	spawn_points["desk"] = Vector2(9, 9)


func _get_music_track() -> String:
	return "village"


func _draw_floor_tile(image: Image) -> void:
	# Cold sigil-inlaid flagstone — dark blue-violet stone with a faint
	# glowing rune dot at the center of each tile, distinct from the
	# library's warm oak and the chapel's pale marble.
	var stone = Color(0.16, 0.14, 0.24)
	var stone_dark = Color(0.10, 0.09, 0.17)
	var stone_light = Color(0.21, 0.19, 0.32)
	var seam = Color(0.07, 0.06, 0.12)
	var sigil = Color(0.42, 0.70, 0.92, 0.65)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var seam_line = (x % 16 == 0) or (y % 16 == 0)
			var block = ((x / 16) + (y / 16)) % 2
			if seam_line:
				image.set_pixel(x, y, seam)
			elif x % 16 == 8 and y % 16 == 8:
				image.set_pixel(x, y, sigil)
			elif (x % 16 == 7 or x % 16 == 9) and y % 16 == 8:
				image.set_pixel(x, y, sigil.darkened(0.3))
			else:
				var base = stone_light if block == 0 else stone
				image.set_pixel(x, y, base if (x + y) % 11 != 0 else stone_dark)


func _draw_wall_tile(image: Image) -> void:
	# Dark arcane ashlar with a thin etched rune channel down each
	# block face — reads as 'built to hold something in' rather than
	# the chapel's dressed stone or the library's wood panelling.
	var stone = Color(0.20, 0.18, 0.29)
	var stone_light = Color(0.27, 0.24, 0.37)
	var mortar = Color(0.09, 0.08, 0.15)
	var rune = Color(0.48, 0.76, 0.94, 0.55)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var row = y / 10
			var offset = 10 if row % 2 == 0 else 0
			var in_mortar_h = y % 10 == 0
			var in_mortar_v = (x + offset) % 20 == 0
			if in_mortar_h or in_mortar_v:
				image.set_pixel(x, y, mortar)
			elif x % 8 == 4 and y % 10 == 5:
				image.set_pixel(x, y, rune)
			else:
				image.set_pixel(x, y, stone_light if (x + y) % 11 == 0 else stone)


func _process(delta: float) -> void:
	_animate_lectern_book(delta)
	_animate_hovering_candles(delta)
	_spin_orrery(delta)
	_breathe_lamps(delta)
	_drift_glyphs(delta)
	_crawl_moth(delta)
	_pulse_sigil_circle(delta)


func _setup_decorations() -> void:
	super._setup_decorations()
	_create_ambient_tint()
	_create_rune_back_shelves()
	_create_rune_shelf_island(6)
	_create_rune_shelf_island(13)
	_create_sigil_floor_circle()
	_create_lectern()
	_create_correction_slip_wall(3)
	_create_correction_slip_wall(14)
	_create_ink_wells()
	_create_clockwork_orrery()
	_create_astrolabe_stand()
	_create_deprecated_truths_cabinet()
	_create_hovering_candles()
	_create_wall_sconces()
	_create_ceiling_wardlamps()
	_create_sealed_edict_racks()
	_create_catalog_of_verified_facts()
	_create_step_stool()
	_create_entry_rune_mat()
	_create_no_unsanctioned_revisions_sign()
	_create_floating_glyphs()
	_create_spectacles_and_loose_slip()
	_create_section_placards()
	_create_cobweb()
	_create_glyph_moth()
	_create_potted_nightbloom()
	_create_correction_drop_slot()


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


func _create_ambient_tint() -> void:
	# Cold blue-violet wash — the Guild reads as colder and more
	# clinical than the library's warm wood, in contrast with the
	# hovering candlelight's warm accent pools.
	var tint = CanvasModulate.new()
	tint.name = "GuildTint"
	tint.color = Color(0.80, 0.82, 0.92)
	add_child(tint)


# ---------------------------------------------------------------------------
# Shelving
# ---------------------------------------------------------------------------

func _create_rune_back_shelves() -> void:
	# One continuous run along the north wall, broken into sections by
	# stone pilasters, each etched with a single glowing rune.
	var w = TILE_SIZE * 14
	var h = TILE_SIZE * 3
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var shelf_back = Color(0.08, 0.07, 0.14)
	var pilaster = Color(0.30, 0.28, 0.38)
	var pilaster_dark = Color(0.20, 0.18, 0.27)
	var rune_glow = Color(0.50, 0.80, 0.95)
	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, shelf_back)
	var pilaster_x = [0, w / 3, (w * 2) / 3, w - 6]
	for px in pilaster_x:
		for y in range(h):
			for dx in range(6):
				var xx = px + dx
				if xx >= 0 and xx < w:
					img.set_pixel(xx, y, pilaster if dx != 5 else pilaster_dark)
		if px + 3 < w:
			img.set_pixel(px + 2, int(h / 2.0), rune_glow)
			img.set_pixel(px + 3, int(h / 2.0) - 2, rune_glow.darkened(0.2))
			img.set_pixel(px + 3, int(h / 2.0) + 2, rune_glow.darkened(0.2))
	for sy in range(0, h, 16):
		for x in range(w):
			img.set_pixel(x, sy, pilaster_dark)
			img.set_pixel(x, sy + 1, pilaster_dark.darkened(0.2))
	var spine_sets = [
		[Color(0.30, 0.20, 0.50), Color(0.38, 0.26, 0.60)],
		[Color(0.14, 0.30, 0.46), Color(0.20, 0.40, 0.58)],
		[Color(0.42, 0.16, 0.30), Color(0.52, 0.22, 0.38)],
		[Color(0.55, 0.48, 0.20), Color(0.68, 0.60, 0.28)],
	]
	var rng = RandomNumberGenerator.new()
	rng.seed = 4471
	for sy in range(0, h - 16, 16):
		var x = 8
		while x < w - 8:
			var set_idx = rng.randi_range(0, spine_sets.size() - 1)
			var pair: Array = spine_sets[set_idx]
			var book_w = rng.randi_range(3, 6)
			var book_h = rng.randi_range(10, 14)
			var rune_trim = set_idx == 1
			for by in range(16 - book_h, 15):
				for bx in range(book_w):
					var xx = x + bx
					if xx < w:
						var c = pair[0] if bx % 3 != 0 else pair[1]
						if rune_trim and (by == 16 - book_h or by == 14):
							c = Color(0.55, 0.85, 0.95)
						img.set_pixel(xx, sy + by, c)
			x += book_w + 1
			for px in pilaster_x:
				if x >= px - 2 and x <= px + 8:
					x = px + 8
	var sprite = Sprite2D.new()
	sprite.name = "RuneBackShelves"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(2 * TILE_SIZE, 2 * TILE_SIZE - h)
	decorations.add_child(sprite)


func _create_rune_shelf_island(gx: int) -> void:
	# Freestanding double-sided stack of bound correction-orders and
	# reference tomes — same silhouette as the library's islands but
	# colder, with rune-glow spine trim instead of gold.
	var w = TILE_SIZE
	var h = TILE_SIZE * 4
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var frame_stone = Color(0.24, 0.22, 0.33)
	var shelf_back = Color(0.08, 0.07, 0.14)
	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, shelf_back)
	for x in [0, 1, w - 2, w - 1]:
		for y in range(h):
			img.set_pixel(x, y, frame_stone)
	var spine_sets = [
		[Color(0.30, 0.20, 0.50), Color(0.38, 0.26, 0.60)],
		[Color(0.14, 0.30, 0.46), Color(0.20, 0.40, 0.58)],
		[Color(0.42, 0.16, 0.30), Color(0.52, 0.22, 0.38)],
	]
	var rng = RandomNumberGenerator.new()
	rng.seed = gx * 61 + 7
	var y2 = 0
	while y2 < h - 16:
		for x in range(4, w - 4, 5):
			var pair: Array = spine_sets[rng.randi_range(0, spine_sets.size() - 1)]
			var book_h = rng.randi_range(10, 14)
			for by in range(16 - book_h, 15):
				var c = pair[0] if (x + by) % 3 != 0 else pair[1]
				img.set_pixel(x, y2 + by, c)
				img.set_pixel(x + 1, y2 + by, c)
		for x in range(w):
			img.set_pixel(x, y2, frame_stone.darkened(0.3))
		y2 += 16
	var sprite = Sprite2D.new()
	sprite.name = "RuneShelfIsland_%d" % gx
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(gx * TILE_SIZE, 8 * TILE_SIZE - h)
	decorations.add_child(sprite)


# ---------------------------------------------------------------------------
# Lectern + sigil circle
# ---------------------------------------------------------------------------

func _create_sigil_floor_circle() -> void:
	# A wide inlaid rune-circle beneath the lectern — the one piece of
	# floor in the room that's visibly doing something.
	var size = 64
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var glow = Color(0.45, 0.72, 0.95, 0.55)
	var glow_dim = Color(0.45, 0.72, 0.95, 0.25)
	var center = size / 2.0
	for r in [30, 24, 12]:
		for i in range(72):
			var ang = i * TAU / 72.0
			var px = int(center + cos(ang) * r)
			var py = int(center + sin(ang) * r * 0.5)
			if px >= 0 and px < size and py >= 0 and py < size:
				img.set_pixel(px, py, glow if r != 24 else glow_dim)
	for i in range(8):
		var ang = i * TAU / 8.0
		var ex = int(center + cos(ang) * 30)
		var ey = int(center + sin(ang) * 15)
		if ex >= 0 and ex < size and ey >= 0 and ey < size:
			img.set_pixel(ex, ey, glow)
	_sigil_sprite = Sprite2D.new()
	_sigil_sprite.name = "SigilCircle"
	_sigil_sprite.z_index = -1
	_sigil_sprite.texture = ImageTexture.create_from_image(img)
	_sigil_sprite.position = Vector2(9.5 * TILE_SIZE, 9 * TILE_SIZE)
	decorations.add_child(_sigil_sprite)


func _pulse_sigil_circle(delta: float) -> void:
	_sigil_time += delta
	if _sigil_sprite:
		_sigil_sprite.modulate.a = 0.65 + 0.30 * sin(_sigil_time * 1.4)


func _create_lectern() -> void:
	var gx = 9
	var gy = 8
	var img = Image.create(20, 26, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var wood = Color(0.22, 0.18, 0.28)
	var wood_dark = Color(0.14, 0.11, 0.19)
	for y in range(18, 26):
		img.set_pixel(9, y, wood_dark)
		img.set_pixel(10, y, wood_dark)
	for x in range(5, 15):
		img.set_pixel(x, 24, wood_dark)
		img.set_pixel(x, 25, wood_dark)
	for y in range(0, 10):
		for x in range(2, 18):
			var slope = int(y * 0.3)
			if x >= 2 + slope and x <= 18 - slope:
				img.set_pixel(x, y + 8, wood)
	var stand = Sprite2D.new()
	stand.name = "LecternStand"
	stand.centered = false
	stand.texture = ImageTexture.create_from_image(img)
	stand.position = Vector2(gx * TILE_SIZE, gy * TILE_SIZE)
	decorations.add_child(stand)

	_book_frames.clear()
	for f in range(3):
		var bimg = Image.create(16, 10, false, Image.FORMAT_RGBA8)
		_draw_lectern_book_frame(bimg, f)
		_book_frames.append(ImageTexture.create_from_image(bimg))
	_book_sprite = Sprite2D.new()
	_book_sprite.name = "SelfTurningBook"
	_book_sprite.centered = false
	_book_sprite.texture = _book_frames[0]
	_book_sprite.position = Vector2(gx * TILE_SIZE + 2, gy * TILE_SIZE + 6)
	decorations.add_child(_book_sprite)

	var glow = PointLight2D.new()
	glow.position = Vector2(gx * TILE_SIZE + 8, gy * TILE_SIZE + 4)
	glow.color = Color(0.55, 0.80, 1.0)
	glow.energy = 0.4
	glow.texture = _create_light_texture(60)
	decorations.add_child(glow)
	_lamp_lights.append(glow)


func _draw_lectern_book_frame(img: Image, frame: int) -> void:
	# Three-frame page-flip loop — a page visibly mid-turn in frame 1.
	var cover = Color(0.10, 0.08, 0.16)
	var page = Color(0.86, 0.84, 0.92)
	var ink = Color(0.30, 0.28, 0.40)
	var turning_page = Color(0.70, 0.76, 0.90, 0.85)
	for y in range(10):
		for x in range(16):
			var c = page
			if y < 1 or y > 8:
				c = cover
			elif x == 7 or x == 8:
				c = Color(0.62, 0.58, 0.70)
			img.set_pixel(x, y, c)
	var lines: Array = [3, 4, 5, 6] if frame == 0 else ([2, 3, 5, 6] if frame == 1 else [3, 4, 6, 7])
	for line in lines:
		for x in range(2, 7):
			img.set_pixel(x, line, ink)
	if frame == 1:
		for i in range(4):
			var px = 9 + i
			var py = 3 - i / 2
			if px < 16 and py >= 0:
				img.set_pixel(px, py, turning_page)


func _animate_lectern_book(delta: float) -> void:
	_book_timer += delta
	if _book_timer >= BOOK_PAGE_SPEED:
		_book_timer -= BOOK_PAGE_SPEED
		_book_frame = (_book_frame + 1) % _book_frames.size()
		if _book_sprite and _book_frames.size() > 0:
			_book_sprite.texture = _book_frames[_book_frame]


# ---------------------------------------------------------------------------
# Correction slips + ink wells
# ---------------------------------------------------------------------------

func _create_correction_slip_wall(gx: int) -> void:
	# A board of pinned reality-patches — small papers, some red-inked
	# and struck through (rejected), some gold-sealed (approved). The
	# Guild's actual work, made visible.
	var w = TILE_SIZE
	var h = 28
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var board = Color(0.16, 0.14, 0.22)
	var board_dark = Color(0.11, 0.10, 0.16)
	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, board_dark if (x == 0 or y == 0 or x == w - 1 or y == h - 1) else board)
	var rng = RandomNumberGenerator.new()
	rng.seed = gx * 37 + 11
	var slip_colors = [Color(0.82, 0.78, 0.62), Color(0.78, 0.74, 0.60), Color(0.85, 0.82, 0.68)]
	for row in range(3):
		for col in range(3):
			var sx = 3 + col * 9
			var sy = 3 + row * 8
			if sx + 6 >= w or sy + 6 >= h:
				continue
			var slip: Color = slip_colors[rng.randi_range(0, slip_colors.size() - 1)]
			for yy in range(sy, sy + 6):
				for xx in range(sx, sx + 6):
					img.set_pixel(xx, yy, slip)
			var rejected = rng.randf() < 0.4
			if rejected:
				for i in range(6):
					img.set_pixel(sx + i, sy + 3, Color(0.55, 0.12, 0.12))
			else:
				img.set_pixel(sx + 1, sy + 1, Color(0.75, 0.60, 0.20))
				img.set_pixel(sx + 4, sy + 4, Color(0.75, 0.60, 0.20))
	var sprite = Sprite2D.new()
	sprite.name = "CorrectionSlipWall_%d" % gx
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(gx * TILE_SIZE, 2 * TILE_SIZE + 4)
	decorations.add_child(sprite)


func _create_ink_wells() -> void:
	# A small desk of glowing ink wells near the lectern — the Guild's
	# ink doesn't just write, it insists.
	var gx = 6
	var gy = 9
	var img = Image.create(24, 12, false, Image.FORMAT_RGBA8)
	var wood = Color(0.30, 0.24, 0.36)
	var wood_dark = Color(0.20, 0.16, 0.26)
	for y in range(8, 12):
		for x in range(24):
			img.set_pixel(x, y, wood if (x + y) % 9 != 0 else wood_dark)
	var glass = Color(0.30, 0.32, 0.40, 0.85)
	var ink_colors = [Color(0.35, 0.75, 0.95), Color(0.75, 0.35, 0.85), Color(0.95, 0.75, 0.30)]
	for i in range(3):
		var wx = 3 + i * 7
		for y in range(3, 8):
			for x in range(wx, wx + 4):
				img.set_pixel(x, y, glass)
		for x in range(wx + 1, wx + 3):
			img.set_pixel(x, 4, ink_colors[i])
	var sprite = Sprite2D.new()
	sprite.name = "InkWells"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(gx * TILE_SIZE, gy * TILE_SIZE + 10)
	decorations.add_child(sprite)

	for i in range(3):
		var wx = gx * TILE_SIZE + 5 + i * 7
		var glow = PointLight2D.new()
		glow.position = Vector2(wx, gy * TILE_SIZE + 15)
		glow.color = [Color(0.45, 0.85, 1.0), Color(0.85, 0.45, 0.95), Color(1.0, 0.85, 0.40)][i]
		glow.energy = 0.30
		glow.texture = _create_light_texture(30)
		decorations.add_child(glow)
		_lamp_lights.append(glow)


# ---------------------------------------------------------------------------
# Clockwork orrery + astrolabe
# ---------------------------------------------------------------------------

func _create_clockwork_orrery() -> void:
	_orrery_frames.clear()
	for f in range(2):
		var img = Image.create(30, 30, false, Image.FORMAT_RGBA8)
		_draw_orrery_frame(img, f)
		_orrery_frames.append(ImageTexture.create_from_image(img))

	var ped_img = Image.create(16, 18, false, Image.FORMAT_RGBA8)
	var wood = Color(0.28, 0.22, 0.34)
	var wood_dark = Color(0.18, 0.14, 0.23)
	for y in range(18):
		for x in range(16):
			ped_img.set_pixel(x, y, wood_dark if (x < 2 or x > 13) else wood)
	var ped = Sprite2D.new()
	ped.name = "OrreryPedestal"
	ped.centered = false
	ped.texture = ImageTexture.create_from_image(ped_img)
	ped.position = Vector2(3 * TILE_SIZE - 8, 9 * TILE_SIZE + 4)
	decorations.add_child(ped)

	_orrery_sprite = Sprite2D.new()
	_orrery_sprite.name = "Orrery"
	_orrery_sprite.texture = _orrery_frames[0]
	_orrery_sprite.position = Vector2(3 * TILE_SIZE, 9 * TILE_SIZE)
	decorations.add_child(_orrery_sprite)


func _draw_orrery_frame(img: Image, frame: int) -> void:
	img.fill(Color.TRANSPARENT)
	var brass = Color(0.72, 0.60, 0.30)
	var brass_dark = Color(0.50, 0.40, 0.18)
	var orb = Color(0.85, 0.55, 0.25)
	var moon = Color(0.75, 0.78, 0.85)
	var center = 15.0
	for r in [13, 9]:
		for i in range(48):
			var ang = i * TAU / 48.0 + (frame * PI / 48.0)
			var px = int(center + cos(ang) * r)
			var py = int(center + sin(ang) * r * 0.4)
			if px >= 0 and px < 30 and py >= 0 and py < 30:
				img.set_pixel(px, py, brass if i % 3 != 0 else brass_dark)
	img.set_pixel(int(center), int(center), orb)
	img.set_pixel(int(center) + 1, int(center), orb)
	img.set_pixel(int(center), int(center) + 1, orb)
	var moon_ang = frame * PI
	var mx = int(center + cos(moon_ang) * 13)
	var my = int(center + sin(moon_ang) * 5)
	if mx >= 0 and mx < 30 and my >= 0 and my < 30:
		img.set_pixel(mx, my, moon)


func _spin_orrery(delta: float) -> void:
	_orrery_time += delta
	if _orrery_time >= 2.2:
		_orrery_time -= 2.2
		if _orrery_sprite and _orrery_frames.size() > 1:
			_orrery_sprite.texture = _orrery_frames[1] if _orrery_sprite.texture == _orrery_frames[0] else _orrery_frames[0]


func _create_astrolabe_stand() -> void:
	# Static brass astrolabe beside the orrery — the Guild measures
	# more than it moves.
	var img = Image.create(14, 26, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var brass = Color(0.70, 0.58, 0.28)
	var brass_dark = Color(0.48, 0.38, 0.16)
	var center = Vector2(7, 8)
	for r in [6, 4]:
		for i in range(32):
			var ang = i * TAU / 32.0
			var px = int(center.x + cos(ang) * r)
			var py = int(center.y + sin(ang) * r)
			if px >= 0 and px < 14 and py >= 0 and py < 16:
				img.set_pixel(px, py, brass)
	for y in range(16, 24):
		img.set_pixel(6, y, brass_dark)
		img.set_pixel(7, y, brass_dark)
	for x in range(3, 11):
		img.set_pixel(x, 24, brass_dark)
		img.set_pixel(x, 25, brass_dark)
	var sprite = Sprite2D.new()
	sprite.name = "Astrolabe"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(4.3 * TILE_SIZE, 8.5 * TILE_SIZE)
	decorations.add_child(sprite)


# ---------------------------------------------------------------------------
# Deprecated truths cabinet
# ---------------------------------------------------------------------------

func _create_deprecated_truths_cabinet() -> void:
	# Locked, iron-bound, and pointedly unlabeled. Whatever's filed
	# under 'deprecated' here used to be true.
	var gx = 15
	var gy = 9
	var w = TILE_SIZE
	var h = TILE_SIZE + 10
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var wood = Color(0.10, 0.08, 0.10)
	var wood_dark = Color(0.05, 0.04, 0.06)
	var iron = Color(0.24, 0.23, 0.26)
	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, wood if (x + y) % 9 != 0 else wood_dark)
	for x in [2, w - 3]:
		for y in range(h):
			img.set_pixel(x, y, iron)
	for y in [4, h - 6]:
		for x in range(w):
			img.set_pixel(x, y, iron)
	var chain = Color(0.35, 0.33, 0.30)
	for i in range(int(h * 0.7)):
		var cx = int(4 + i * (w - 8.0) / (h * 0.7))
		var cy = 6 + i
		if cy < h and cx < w:
			img.set_pixel(cx, cy, chain)
	for y in range(h / 2 - 4, h / 2 + 4):
		for x in range(w / 2 - 3, w / 2 + 3):
			img.set_pixel(x, y, Color(0.55, 0.46, 0.20))
	var sprite = Sprite2D.new()
	sprite.name = "DeprecatedTruthsCabinet"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(gx * TILE_SIZE, gy * TILE_SIZE - 10)
	decorations.add_child(sprite)

	var label = Label.new()
	label.text = "DEPRECATED — DO NOT CITE"
	label.position = Vector2((gx - 1.3) * TILE_SIZE, (gy - 1.0) * TILE_SIZE)
	label.add_theme_font_size_override("font_size", 7)
	label.add_theme_color_override("font_color", Color(0.55, 0.20, 0.20))
	decorations.add_child(label)


# ---------------------------------------------------------------------------
# Hovering candles
# ---------------------------------------------------------------------------

func _create_hovering_candles() -> void:
	_candle_frames.clear()
	for f in range(2):
		var img = Image.create(8, 12, false, Image.FORMAT_RGBA8)
		_draw_candle_frame(img, f)
		_candle_frames.append(ImageTexture.create_from_image(img))

	var spots = [
		Vector2(5.5, 3.5), Vector2(12.5, 3.5),
		Vector2(9.5, 6.0), Vector2(4.0, 10.0), Vector2(14.0, 10.0),
	]
	_candle_base_positions.clear()
	for gp in spots:
		var pos = gp * TILE_SIZE
		_candle_base_positions.append(pos)
		var sprite = Sprite2D.new()
		sprite.texture = _candle_frames[0]
		sprite.position = pos
		decorations.add_child(sprite)
		_candle_sprites.append(sprite)

		var glow = PointLight2D.new()
		glow.position = pos + Vector2(4, 4)
		glow.color = Color(1.0, 0.80, 0.45)
		glow.energy = 0.42
		glow.texture = _create_light_texture(50)
		decorations.add_child(glow)
		_candle_lights.append(glow)


func _draw_candle_frame(img: Image, frame: int) -> void:
	img.fill(Color.TRANSPARENT)
	var wax = Color(0.85, 0.80, 0.65)
	var wick = Color(0.25, 0.20, 0.15)
	var outer = Color(0.95, 0.55, 0.15)
	var inner = Color(1.0, 0.92, 0.55)
	for y in range(6, 12):
		for x in range(2, 6):
			img.set_pixel(x, y, wax)
	img.set_pixel(4, 5, wick)
	var ofs = 1 if frame == 1 else 0
	for y in range(0, 5):
		var half = 1 if y > 2 else 0
		for x in range(4 - half - ofs, 5 + half - ofs):
			if x >= 0 and x < 8:
				img.set_pixel(x, y, inner if y > 2 else outer)


func _animate_hovering_candles(delta: float) -> void:
	_candle_timer += delta
	if _candle_timer >= CANDLE_SPEED:
		_candle_timer -= CANDLE_SPEED
		_candle_frame = (_candle_frame + 1) % _candle_frames.size()
		for sprite in _candle_sprites:
			if is_instance_valid(sprite):
				sprite.texture = _candle_frames[_candle_frame]
	_candle_bob_time += delta
	for i in range(_candle_sprites.size()):
		var sprite = _candle_sprites[i]
		if is_instance_valid(sprite) and i < _candle_base_positions.size():
			var base: Vector2 = _candle_base_positions[i]
			sprite.position = base + Vector2(0, sin(_candle_bob_time * 1.3 + i * 1.7) * 2.5)
			if i < _candle_lights.size() and is_instance_valid(_candle_lights[i]):
				_candle_lights[i].position = sprite.position + Vector2(4, 4)


# ---------------------------------------------------------------------------
# Ambient lighting
# ---------------------------------------------------------------------------

func _create_wall_sconces() -> void:
	var light_tex = _create_light_texture(55)
	for anchor in [Vector2(1, 5), Vector2(16, 5), Vector2(1, 9)]:
		_create_sconce(anchor, light_tex)


func _create_sconce(anchor: Vector2, light_tex: ImageTexture) -> void:
	# Cold witchlight sconce — same iron bracket silhouette as the
	# library's, but burning blue-violet instead of warm orange, so
	# the room's only warm light comes from candles and ink.
	var img = Image.create(10, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var iron = Color(0.22, 0.21, 0.26)
	var outer = Color(0.45, 0.55, 0.92)
	var inner = Color(0.75, 0.82, 1.0)
	for y in range(10, 16):
		img.set_pixel(4, y, iron)
		img.set_pixel(5, y, iron)
	for x in range(2, 8):
		img.set_pixel(x, 10, iron)
	for y in range(0, 10):
		var w = 2 if y > 4 else 1
		for x in range(4 - w, 5 + w):
			if x >= 0 and x < 10:
				img.set_pixel(x, y, inner if y > 6 else outer)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = anchor * TILE_SIZE + Vector2(TILE_SIZE / 2.0 - 5, 4)
	decorations.add_child(sprite)

	var glow = PointLight2D.new()
	glow.position = anchor * TILE_SIZE + Vector2(TILE_SIZE / 2.0, 8)
	glow.color = Color(0.55, 0.65, 0.95)
	glow.energy = 0.26
	glow.texture = light_tex
	decorations.add_child(glow)
	_lamp_lights.append(glow)


func _create_ceiling_wardlamps() -> void:
	var light_tex = _create_light_texture(85)
	for gp in [Vector2(4, 2), Vector2(13, 2), Vector2(9, 6)]:
		var lamp = PointLight2D.new()
		lamp.position = gp * TILE_SIZE
		lamp.color = Color(0.60, 0.68, 0.95)
		lamp.energy = 0.20
		lamp.texture = light_tex
		decorations.add_child(lamp)
		_lamp_lights.append(lamp)


func _breathe_lamps(delta: float) -> void:
	_light_time += delta
	for i in range(_lamp_lights.size()):
		var light = _lamp_lights[i]
		if is_instance_valid(light):
			var base_energy = 0.28
			light.energy = base_energy + 0.06 * sin(_light_time * 1.0 + i * 1.3)


# ---------------------------------------------------------------------------
# Small furniture
# ---------------------------------------------------------------------------

func _create_sealed_edict_racks() -> void:
	_create_sealed_edict_rack(Vector2(6, 3))
	_create_sealed_edict_rack(Vector2(11, 10))


func _create_sealed_edict_rack(grid_pos: Vector2) -> void:
	var img = Image.create(TILE_SIZE, 22, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var wood = Color(0.22, 0.18, 0.28)
	for x in range(2, TILE_SIZE - 2):
		img.set_pixel(x, 2, wood)
		img.set_pixel(x, 20, wood)
	for lx in [3, TILE_SIZE - 4]:
		for y in range(2, 21):
			img.set_pixel(lx, y, wood)
	var scroll_colors = [Color(0.70, 0.65, 0.85), Color(0.60, 0.72, 0.85), Color(0.75, 0.68, 0.55)]
	for i in range(3):
		var sx = 6 + i * 6
		var col: Color = scroll_colors[i % scroll_colors.size()]
		for y in range(5, 17):
			img.set_pixel(sx, y, col)
			img.set_pixel(sx + 1, y, col.darkened(0.15))
		img.set_pixel(sx, 4, Color(0.72, 0.58, 0.24))
		img.set_pixel(sx + 1, 4, Color(0.72, 0.58, 0.24))
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = grid_pos * TILE_SIZE
	decorations.add_child(sprite)


func _create_catalog_of_verified_facts() -> void:
	var gx = 15
	var gy = 2
	var img = Image.create(TILE_SIZE + 8, 26, false, Image.FORMAT_RGBA8)
	var wood = Color(0.26, 0.22, 0.34)
	var wood_dark = Color(0.17, 0.14, 0.23)
	var brass = Color(0.65, 0.55, 0.30)
	for y in range(26):
		for x in range(TILE_SIZE + 8):
			img.set_pixel(x, y, wood if (x + y) % 11 != 0 else wood_dark)
	for row in range(3):
		for col in range(4):
			var dx = 3 + col * 9
			var dy = 2 + row * 8
			for x in range(dx, dx + 7):
				for y in range(dy, dy + 6):
					img.set_pixel(x, y, wood_dark)
			img.set_pixel(dx + 3, dy + 3, brass)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(gx * TILE_SIZE, gy * TILE_SIZE)
	decorations.add_child(sprite)

	var label = Label.new()
	label.text = "Verified Facts (Current Rev.)"
	label.position = Vector2((gx - 1.2) * TILE_SIZE, (gy - 0.5) * TILE_SIZE)
	label.add_theme_font_size_override("font_size", 7)
	label.add_theme_color_override("font_color", Color(0.60, 0.68, 0.90))
	decorations.add_child(label)


func _create_step_stool() -> void:
	var img = Image.create(16, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var wood = Color(0.28, 0.22, 0.34)
	var wood_dark = Color(0.18, 0.14, 0.23)
	for y in range(6, 9):
		for x in range(1, 15):
			img.set_pixel(x, y, wood)
	for y in range(9, 14):
		for x in range(2, 5):
			img.set_pixel(x, y, wood_dark)
		for x in range(11, 14):
			img.set_pixel(x, y, wood_dark)
	for x in range(3, 13):
		img.set_pixel(x, 6, wood.lightened(0.15))
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(6.3 * TILE_SIZE, 6.3 * TILE_SIZE)
	decorations.add_child(sprite)


func _create_entry_rune_mat() -> void:
	var w = TILE_SIZE * 2
	var h = 14
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var mat = Color(0.18, 0.16, 0.26)
	var mat_dark = Color(0.12, 0.10, 0.18)
	var thread = Color(0.45, 0.70, 0.90, 0.7)
	for y in range(h):
		for x in range(w):
			var edge = x < 2 or x >= w - 2 or y < 2 or y >= h - 2
			if edge:
				img.set_pixel(x, y, thread)
			else:
				img.set_pixel(x, y, mat_dark if (x + y) % 6 == 0 else mat)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.z_index = -1
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(8 * TILE_SIZE, 11 * TILE_SIZE + 6)
	decorations.add_child(sprite)


func _create_no_unsanctioned_revisions_sign() -> void:
	# Small hand-lettered warning by the lectern — the game's
	# meta-comedic register, guild-flavored.
	var img = Image.create(34, 14, false, Image.FORMAT_RGBA8)
	var board = Color(0.55, 0.50, 0.62)
	var board_dark = Color(0.40, 0.36, 0.48)
	for y in range(14):
		for x in range(34):
			var frame_edge = x == 0 or y == 0 or x == 33 or y == 13
			img.set_pixel(x, y, board_dark if frame_edge else board)
	for line in range(2):
		var ly = 4 + line * 5
		for x in range(3, 31):
			if (x + line * 2) % 4 != 0:
				img.set_pixel(x, ly, Color(0.15, 0.13, 0.20))
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(7.5 * TILE_SIZE, 8.2 * TILE_SIZE)
	decorations.add_child(sprite)

	var label = Label.new()
	label.text = "NO UNSANCTIONED REVISIONS"
	label.position = Vector2(6.7 * TILE_SIZE, 8.6 * TILE_SIZE)
	label.add_theme_font_size_override("font_size", 7)
	label.add_theme_color_override("font_color", Color(0.20, 0.18, 0.28))
	decorations.add_child(label)


# ---------------------------------------------------------------------------
# Small flourishes
# ---------------------------------------------------------------------------

func _create_floating_glyphs() -> void:
	# Three faint rune-glyphs drifting near the correction-slip wall —
	# stray edits that haven't found a home yet.
	var rng = RandomNumberGenerator.new()
	rng.seed = 909
	_glyph_base_positions.clear()
	for i in range(3):
		var img = Image.create(6, 6, false, Image.FORMAT_RGBA8)
		img.fill(Color.TRANSPARENT)
		var c = Color(0.55, 0.80, 0.95, 0.75)
		img.set_pixel(3, 0, c)
		img.set_pixel(3, 5, c)
		img.set_pixel(0, 3, c)
		img.set_pixel(5, 3, c)
		img.set_pixel(2, 2, c)
		img.set_pixel(3, 3, c)
		var sprite = Sprite2D.new()
		sprite.texture = ImageTexture.create_from_image(img)
		var base = Vector2(3.5 + rng.randf() * 1.5, 3.0 + i * 0.8) * TILE_SIZE
		sprite.position = base
		decorations.add_child(sprite)
		_glyph_sprites.append(sprite)
		_glyph_base_positions.append(base)


func _drift_glyphs(delta: float) -> void:
	_glyph_time += delta
	for i in range(_glyph_sprites.size()):
		var sprite = _glyph_sprites[i]
		if is_instance_valid(sprite) and i < _glyph_base_positions.size():
			var base: Vector2 = _glyph_base_positions[i]
			sprite.position = base + Vector2(sin(_glyph_time * 0.6 + i * 2.1) * 5.0, cos(_glyph_time * 0.5 + i * 1.4) * 3.0)
			sprite.modulate.a = 0.6 + 0.3 * sin(_glyph_time * 1.1 + i)


func _create_spectacles_and_loose_slip() -> void:
	# A pair of reading glasses left on the ink-well desk beside an
	# unfiled slip — someone stepped away mid-correction.
	var img = Image.create(14, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var frame = Color(0.30, 0.28, 0.36)
	for cx in [3, 10]:
		for y in range(1, 5):
			for x in range(cx - 2, cx + 3):
				var dist = Vector2(x - cx, y - 3).length()
				if dist > 1.6 and dist < 2.4:
					img.set_pixel(x, y, frame)
	for x in range(5, 9):
		img.set_pixel(x, 3, frame)
	var sprite = Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(6 * TILE_SIZE + 4, 9 * TILE_SIZE + 6)
	decorations.add_child(sprite)

	var slip_img = Image.create(10, 8, false, Image.FORMAT_RGBA8)
	var paper = Color(0.84, 0.80, 0.68)
	for y in range(8):
		for x in range(10):
			slip_img.set_pixel(x, y, paper)
	for x in range(1, 8):
		if x % 2 == 0:
			slip_img.set_pixel(x, 3, Color(0.35, 0.32, 0.28))
	var slip = Sprite2D.new()
	slip.centered = false
	slip.rotation = -0.2
	slip.texture = ImageTexture.create_from_image(slip_img)
	slip.position = Vector2(6 * TILE_SIZE + 16, 9 * TILE_SIZE + 18)
	decorations.add_child(slip)


func _create_section_placards() -> void:
	var sections = [
		{"text": "Cosmology", "x": 3.0},
		{"text": "Grammar of Reality", "x": 7.5},
		{"text": "Deprecated", "x": 13.0},
	]
	for entry in sections:
		var label = Label.new()
		label.text = str(entry["text"])
		label.position = Vector2(float(entry["x"]) * TILE_SIZE, 0.3 * TILE_SIZE)
		label.add_theme_font_size_override("font_size", 8)
		label.add_theme_color_override("font_color", Color(0.65, 0.80, 0.95))
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		decorations.add_child(label)


func _create_cobweb() -> void:
	var size = 22
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var strand = Color(0.75, 0.78, 0.85, 0.5)
	for i in range(6):
		var ang = i * PI / 6.0
		var ex = int(size / 2.0 + cos(ang) * size / 2.0)
		var ey = int(size / 2.0 + sin(ang) * size / 2.0)
		_draw_glyph_line(img, Vector2(0, 0), Vector2(ex, ey), strand)
	for r in [6, 12, 18]:
		for i in range(24):
			var ang = i * TAU / 24.0
			var px = int(cos(ang) * r)
			var py = int(sin(ang) * r)
			if px >= 0 and px < size and py >= 0 and py < size:
				img.set_pixel(px, py, strand)
	var sprite = Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(2 * TILE_SIZE - 4, 2 * TILE_SIZE - 4)
	decorations.add_child(sprite)


func _draw_glyph_line(img: Image, a: Vector2, b: Vector2, c: Color) -> void:
	var steps = int(a.distance_to(b))
	for i in range(steps):
		var t = float(i) / float(max(steps, 1))
		var p = a.lerp(b, t)
		var px = int(p.x)
		var py = int(p.y)
		if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
			img.set_pixel(px, py, c)


func _create_glyph_moth() -> void:
	# Tiny animated critter nibbling the east rune-shelf island — the
	# Guild's answer to the library's bookworm.
	_moth_frames.clear()
	for f in range(2):
		var img = Image.create(6, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.TRANSPARENT)
		var wing = Color(0.60, 0.75, 0.90)
		var hump = 1 if f == 1 else 0
		for x in range(6):
			var y = 2 - (hump if x == 2 or x == 3 else 0)
			img.set_pixel(x, y, wing)
		_moth_frames.append(ImageTexture.create_from_image(img))
	_moth_sprite = Sprite2D.new()
	_moth_sprite.texture = _moth_frames[0]
	_moth_base = Vector2(13 * TILE_SIZE + 4, 5 * TILE_SIZE + 10)
	_moth_sprite.position = _moth_base
	decorations.add_child(_moth_sprite)


func _crawl_moth(delta: float) -> void:
	_moth_timer += delta
	if _moth_timer >= 0.55:
		_moth_timer -= 0.55
		_moth_frame = (_moth_frame + 1) % _moth_frames.size()
		if _moth_sprite:
			_moth_sprite.texture = _moth_frames[_moth_frame]
			_moth_sprite.position = _moth_base + Vector2(_moth_frame * 2.0, 0)


func _create_potted_nightbloom() -> void:
	# A single pale-blue flowering plant on the west wall — one spot
	# of living colour in a room otherwise made of stone and rules.
	var img = Image.create(16, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var pot = Color(0.30, 0.26, 0.38)
	var pot_dark = Color(0.20, 0.17, 0.28)
	var leaf = Color(0.30, 0.42, 0.36)
	var bloom = Color(0.55, 0.68, 0.92)
	for y in range(16, 24):
		for x in range(3, 13):
			img.set_pixel(x, y, pot_dark if x < 5 or x > 10 else pot)
	var fronds = [
		[Vector2(8, 15), Vector2(3, 6)], [Vector2(8, 15), Vector2(8, 2)],
		[Vector2(8, 15), Vector2(13, 7)], [Vector2(8, 15), Vector2(5, 10)],
	]
	for i in range(fronds.size()):
		var frond: Array = fronds[i]
		var a: Vector2 = frond[0]
		var b: Vector2 = frond[1]
		var steps = int(a.distance_to(b))
		for s in range(steps):
			var t = float(s) / float(max(steps, 1))
			var p = a.lerp(b, t)
			var px = int(p.x)
			var py = int(p.y)
			if px >= 0 and px < 16 and py >= 0 and py < 24:
				img.set_pixel(px, py, leaf)
		var tip = b
		if tip.x >= 0 and tip.x < 16 and tip.y >= 0 and tip.y < 24:
			img.set_pixel(int(tip.x), int(tip.y), bloom)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(1 * TILE_SIZE + 6, 2 * TILE_SIZE)
	decorations.add_child(sprite)


func _create_correction_drop_slot() -> void:
	# Brass 'Submit a Correction' slot by the entrance — self-service
	# for citizens who don't want to argue their case to a scholar.
	var img = Image.create(20, 12, false, Image.FORMAT_RGBA8)
	var brass = Color(0.62, 0.55, 0.32)
	var slot = Color(0.08, 0.09, 0.13)
	for y in range(12):
		for x in range(20):
			img.set_pixel(x, y, brass if (x == 0 or y == 0 or x == 19 or y == 11) else brass.darkened(0.1))
	for y in range(4, 8):
		for x in range(3, 17):
			img.set_pixel(x, y, slot)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(13 * TILE_SIZE, 11 * TILE_SIZE + 6)
	decorations.add_child(sprite)

	var label = Label.new()
	label.text = "Submit a Correction"
	label.position = Vector2(12.2 * TILE_SIZE, 11.9 * TILE_SIZE)
	label.add_theme_font_size_override("font_size", 7)
	label.add_theme_color_override("font_color", Color(0.55, 0.50, 0.34))
	decorations.add_child(label)


# ---------------------------------------------------------------------------
# NPCs
# ---------------------------------------------------------------------------

func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	_create_scholar_quill(OverworldNPCScript)
	_create_scribe_narrow(OverworldNPCScript)
	_create_apprentice_fenwick(OverworldNPCScript)
	_create_archivist_vane(OverworldNPCScript)
	_place_guild_hen()


## The Guild hen (one_chicken_problem) — home at last. She was temp-placed
## in Harmonia pending this scene and spawned INSIDE the Inn wall block
## there (live playtest 2026-07-11); same id, so caught-state carries over.
func _place_guild_hen() -> void:
	var ChickenScript = load("res://src/exploration/QuestChicken.gd")
	if ChickenScript == null:
		return
	var hen = ChickenScript.new()
	hen.chicken_id = "chicken_guild"
	hen.catch_line = "The Guild hen surrenders with dignity. The archivists pretend not to see."
	hen.position = Vector2(4 * TILE_SIZE, 6 * TILE_SIZE)
	npcs.add_child(hen)


func _create_scholar_quill(NPCScript) -> void:
	# Quest-critical: npc_id MUST stay "guild_scholar_scriptura" — the
	# quest system (world1_thirty_seven) keys the overdue-book favor
	# and the record hand-off on this exact id. Idle lines only; her
	# offer/in-progress/turn-in dialogue is owned by QuestSystem.
	var quill = NPCScript.new()
	quill.npc_name = "Scholar-Adept Quill"
	quill.npc_type = "scholar"
	quill.npc_id = "guild_scholar_scriptura"
	quill.position = Vector2(9 * TILE_SIZE, 8 * TILE_SIZE)
	quill.dialogue_lines = [
		"Every book in this room used to say something else. We just haven't gotten around to all of them.",
		"Translation work, mostly. Dead notation into something the current century can use. It never stays translated for long.",
		"The lectern turns its own pages at night. We stopped asking why. Asking why is how you end up filed under 'Deprecated.'",
		"You want the short version of what the Guild does? We keep the story consistent. Someone has to.",
	]
	npcs.add_child(quill)


func _create_scribe_narrow(NPCScript) -> void:
	var narrow = NPCScript.new()
	narrow.npc_name = "Scribe Narrow"
	narrow.npc_type = "scholar"
	narrow.position = Vector2(5 * TILE_SIZE, 10 * TILE_SIZE)
	narrow.dialogue_lines = [
		"This manuscript corrects itself as I copy it. I write a line, look away, look back — it's already better than what I wrote.",
		"I used to think that was insulting. Now I just let it happen. Saves time.",
		"*doesn't look up* If you're going to watch, at least tell me if it starts writing anything about you.",
		"Some nights it corrects tomorrow's page before I've copied today's. I don't report that one. Not anymore.",
	]
	npcs.add_child(narrow)


func _create_apprentice_fenwick(NPCScript) -> void:
	var fenwick = NPCScript.new()
	fenwick.npc_name = "Apprentice Fenwick"
	fenwick.npc_type = "villager"
	fenwick.position = Vector2(3 * TILE_SIZE, 4 * TILE_SIZE)
	fenwick.dialogue_lines = [
		"*staring at the slip wall* I submitted a correction two weeks ago. I have not stopped thinking about it since.",
		"It wasn't WRONG, exactly. It was just — an aggressive way to phrase 'the sky is blue.' They rejected it. Correctly. Fairly. I'm fine.",
		"Scholar-Adept Quill said 'we'll discuss it' four days ago. Nobody has discussed anything. I check the wall every hour.",
		"*whispering* Don't tell her I'm still checking. I'm supposed to be over it.",
	]
	npcs.add_child(fenwick)


func _create_archivist_vane(NPCScript) -> void:
	var vane = NPCScript.new()
	vane.npc_name = "Archivist Vane"
	vane.npc_type = "mysterious"
	vane.position = Vector2(14 * TILE_SIZE, 9 * TILE_SIZE)
	vane.dialogue_lines = [
		"The cabinet stays locked. Not because you'd misuse what's inside — because you'd believe it.",
		"'Deprecated' doesn't mean false. It means we found something we liked better and this stopped being convenient.",
		"*hand resting on the chain* I've read everything in there. I don't recommend it. I also don't regret it, which worries me more.",
		"If the Guild ever tells you a truth is deprecated, ask what replaced it. Watch how long the answer takes.",
	]
	npcs.add_child(vane)


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
	exit.target_map = "scriptura_plaza"
	exit.target_spawn = "guild_exit"
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
