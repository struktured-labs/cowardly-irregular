extends BaseInterior
class_name HarmoniaLibraryInterior

## HarmoniaLibraryInterior - Cathedral-depth 'Quiet Library' at Harmonia's
## top-left H cluster. Cantor Vell keeps records of the four elemental
## dragons — his lines foreshadow the W1 advanced content (Pyrroth,
## Glacius, Voltharion, Umbraxis). Floor-to-ceiling stacks, reading
## desks, a fireplace corner, a mezzanine ladder, and a small cast of
## scholars.

const LIBRARY_LAYOUT = [
	"WWWWWWWWWWWWWWWWWWWW",
	"W.SSSSSSSSSSSSSSSS.W",
	"W..................W",
	"W..................W",
	"W.....I......I.....W",
	"W.....I......I.....W",
	"W.....I......I.....W",
	"W.....I......I.....W",
	"W.........G......R.W",
	"W..TT....TT....TT..W",
	"W.......KK.........W",
	"W.F...C.KK...C...L.W",
	"W..................W",
	"WWWWWWWWWDDWWWWWWWWW",
]

## Fireplace flicker (2-frame)
var _fire_sprite: Sprite2D
var _fire_frames: Array[ImageTexture] = []
var _fire_frame: int = 0
var _fire_timer: float = 0.0
const FIRE_SPEED: float = 0.22
var _fire_light: PointLight2D
var _fire_time: float = 0.0

## Sleeping cat breathing (2-frame)
var _cat_sprite: Sprite2D
var _cat_frames: Array[ImageTexture] = []
var _cat_frame: int = 0
var _cat_timer: float = 0.0
const CAT_SPEED: float = 0.9

## Globe slow 'turn' (2-frame, very slow swap)
var _globe_sprite: Sprite2D
var _globe_frames: Array[ImageTexture] = []
var _globe_time: float = 0.0

## Reading lamps + ambient ceiling lamps breathing
var _lamp_lights: Array[PointLight2D] = []
var _light_time: float = 0.0

## Loose page drifting near the nervous researcher
var _page_sprite: Sprite2D
var _page_base: Vector2 = Vector2.ZERO
var _page_time: float = 0.0

## Bookworm crawl (2-frame)
var _worm_frames: Array[ImageTexture] = []
var _worm_sprite: Sprite2D
var _worm_base: Vector2 = Vector2.ZERO
var _worm_frame: int = 0
var _worm_timer: float = 0.0


func _get_area_id() -> String:
	return "harmonia_library"


func _get_display_name() -> String:
	return "Library"


func _get_ambient_key() -> String:
	return "ambient_library"


func _get_map_width() -> int:
	return 20


func _get_map_height() -> int:
	return 14


func _get_layout() -> Array:
	return LIBRARY_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(9, 12)
	spawn_points["table"] = Vector2(9, 9)
	spawn_points["desk"] = Vector2(9, 10)


func _draw_floor_tile(image: Image) -> void:
	# Dark aged oak — deeper and glossier than the tavern's warm planks,
	# reads as 'old and scholarly' rather than 'tavern floor'.
	var wood = Color(0.36, 0.24, 0.14)
	var wood_dark = Color(0.27, 0.18, 0.10)
	var grain = Color(0.31, 0.21, 0.12)
	var polish = Color(0.42, 0.29, 0.17)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var plank = (x / 8) % 2
			var seam = y % 8 == 0
			var grain_line = (y + x / 4) % 5 == 0
			if seam:
				image.set_pixel(x, y, wood_dark.darkened(0.15))
			elif grain_line:
				image.set_pixel(x, y, grain)
			else:
				var base = polish if plank == 0 else wood
				image.set_pixel(x, y, base if (x + y) % 10 != 0 else wood_dark)


func _draw_wall_tile(image: Image) -> void:
	# Dark wood panelling with a raised-panel frame — the walls read as
	# 'built-in shelving country' even where there's no shelf.
	var panel = Color(0.28, 0.19, 0.11)
	var panel_light = Color(0.40, 0.27, 0.15)
	var seam = Color(0.17, 0.11, 0.07)
	var frame_hi = Color(0.46, 0.32, 0.18)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var vert_seam = x % 8 == 0
			var horiz_grain = y % 4 == 0
			var frame_edge = (x % 8 == 2 or x % 8 == 6) and (y % 16 == 2 or y % 16 == 13)
			if vert_seam:
				image.set_pixel(x, y, seam)
			elif frame_edge:
				image.set_pixel(x, y, frame_hi)
			elif horiz_grain:
				image.set_pixel(x, y, panel_light)
			else:
				image.set_pixel(x, y, panel)


func _process(delta: float) -> void:
	_animate_fireplace(delta)
	_flicker_fire_light(delta)
	_animate_cat(delta)
	_spin_globe(delta)
	_breathe_lamps(delta)
	_drift_page(delta)
	_crawl_worm(delta)


func _setup_decorations() -> void:
	super._setup_decorations()
	_create_ambient_warmth()
	_create_back_shelves()
	_create_shelf_island(6)
	_create_shelf_island(13)
	_create_reading_rug()
	_create_reading_tables()
	_create_checkout_desk()
	_create_fireplace()
	_create_ladder_mezzanine()
	_create_star_chart()
	_create_chained_tome()
	_create_library_cat()
	_create_globe()
	_create_scroll_racks()
	_create_card_catalog()
	_create_ceiling_lamps()
	_create_wall_sconces()
	_create_returns_cart()
	_create_step_stool()
	_create_loose_page()
	_create_silence_sign()
	_create_welcome_mat()
	_create_spectacles()
	_create_section_placards()
	_create_cobweb()
	_create_telescope()
	_create_returns_slot()
	_create_bookworm()
	_create_windowsill_plant()


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


func _create_ambient_warmth() -> void:
	# Barely-there warm multiply — keeps the room bright/readable while
	# unifying the wood tones, in contrast to the chapel's deeper dim.
	var warm = CanvasModulate.new()
	warm.name = "LibraryWarmth"
	warm.color = Color(0.92, 0.88, 0.80)
	add_child(warm)


# ---------------------------------------------------------------------------
# Shelving
# ---------------------------------------------------------------------------

func _create_back_shelves() -> void:
	# One continuous run, visually broken into 3 sections by stone
	# pilasters — reads as several shelving units without separate sprites.
	var w = TILE_SIZE * 16
	var h = TILE_SIZE * 3
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var shelf_back = Color(0.16, 0.11, 0.07)
	var pilaster = Color(0.40, 0.38, 0.36)
	var pilaster_dark = Color(0.28, 0.26, 0.25)
	var shelf_wood = Color(0.34, 0.23, 0.13)
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
	for sy in range(0, h, 16):
		for x in range(w):
			img.set_pixel(x, sy, shelf_wood)
			img.set_pixel(x, sy + 1, shelf_wood.darkened(0.2))
	var spine_sets = [
		[Color(0.45, 0.16, 0.12), Color(0.55, 0.20, 0.14)],
		[Color(0.62, 0.14, 0.16), Color(0.72, 0.20, 0.20)],
		[Color(0.18, 0.28, 0.55), Color(0.24, 0.36, 0.65)],
		[Color(0.70, 0.58, 0.22), Color(0.85, 0.72, 0.30)],
	]
	var rng = RandomNumberGenerator.new()
	rng.seed = 9042
	for sy in range(0, h - 16, 16):
		var x = 8
		while x < w - 8:
			var set_idx = rng.randi_range(0, spine_sets.size() - 1)
			var pair: Array = spine_sets[set_idx]
			var book_w = rng.randi_range(3, 6)
			var book_h = rng.randi_range(10, 14)
			var gold_trim = set_idx == 3
			for by in range(16 - book_h, 15):
				for bx in range(book_w):
					var xx = x + bx
					if xx < w:
						var c = pair[0] if bx % 3 != 0 else pair[1]
						if gold_trim and (by == 16 - book_h or by == 14):
							c = Color(0.90, 0.80, 0.45)
						img.set_pixel(xx, sy + by, c)
			x += book_w + 1
			for px in pilaster_x:
				if x >= px - 2 and x <= px + 8:
					x = px + 8
	var sprite = Sprite2D.new()
	sprite.name = "BackShelves"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(2 * TILE_SIZE, 2 * TILE_SIZE - h)
	decorations.add_child(sprite)


func _create_shelf_island(gx: int) -> void:
	# Freestanding double-sided stack — books face both aisles.
	var w = TILE_SIZE
	var h = TILE_SIZE * 5
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var frame_wood = Color(0.30, 0.20, 0.12)
	var shelf_back = Color(0.14, 0.10, 0.06)
	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, shelf_back)
	for x in [0, 1, w - 2, w - 1]:
		for y in range(h):
			img.set_pixel(x, y, frame_wood)
	var spine_sets = [
		[Color(0.45, 0.16, 0.12), Color(0.55, 0.20, 0.14)],
		[Color(0.62, 0.14, 0.16), Color(0.72, 0.20, 0.20)],
		[Color(0.18, 0.28, 0.55), Color(0.24, 0.36, 0.65)],
		[Color(0.70, 0.58, 0.22), Color(0.85, 0.72, 0.30)],
	]
	var rng = RandomNumberGenerator.new()
	rng.seed = gx * 71 + 3
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
			img.set_pixel(x, y2, frame_wood.darkened(0.2))
		y2 += 16
	var sprite = Sprite2D.new()
	sprite.name = "ShelfIsland_%d" % gx
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(gx * TILE_SIZE, 8 * TILE_SIZE - h)
	decorations.add_child(sprite)


func _create_card_catalog() -> void:
	var gx = 15
	var gy = 2
	var img = Image.create(TILE_SIZE + 8, 26, false, Image.FORMAT_RGBA8)
	var wood = Color(0.38, 0.25, 0.14)
	var wood_dark = Color(0.26, 0.17, 0.09)
	var brass = Color(0.72, 0.60, 0.26)
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


func _create_step_stool() -> void:
	var img = Image.create(16, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var wood = Color(0.38, 0.25, 0.15)
	var wood_dark = Color(0.26, 0.17, 0.09)
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


# ---------------------------------------------------------------------------
# Reading tables
# ---------------------------------------------------------------------------

func _create_reading_rug() -> void:
	var gx = 2
	var gy = 9
	var w = TILE_SIZE * 16
	var h = TILE_SIZE
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rug = Color(0.42, 0.16, 0.14, 0.55)
	var rug_dark = Color(0.30, 0.10, 0.10, 0.55)
	var trim = Color(0.55, 0.45, 0.20, 0.55)
	for y in range(h):
		for x in range(w):
			var edge = x < 4 or x >= w - 4 or y < 4 or y >= h - 4
			if edge:
				img.set_pixel(x, y, trim)
			else:
				img.set_pixel(x, y, rug if (x + y) % 9 != 0 else rug_dark)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.z_index = -1
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(gx * TILE_SIZE, gy * TILE_SIZE)
	decorations.add_child(sprite)


func _create_reading_tables() -> void:
	_create_reading_table(3, 0)
	_create_reading_table(9, 1)
	_create_reading_table(15, 2)


func _create_reading_table(gx: int, variant: int) -> void:
	var node = Node2D.new()
	node.name = "ReadingTable_%d" % gx
	var w = TILE_SIZE * 2
	var h = TILE_SIZE
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var top = Color(0.42, 0.28, 0.16)
	var edge = Color(0.30, 0.20, 0.11)
	var leg = Color(0.24, 0.16, 0.09)
	for y in range(h):
		for x in range(w):
			var c = top
			if y < 4:
				c = top.lightened(0.15) if (x / 6) % 2 == 0 else top
			elif y >= h - 3:
				c = edge
			img.set_pixel(x, y, c)
	for lx in [3, w - 5]:
		for y in range(h - 3, h + 6):
			if y < h:
				img.set_pixel(lx, y, leg)
	var table = Sprite2D.new()
	table.centered = false
	table.texture = ImageTexture.create_from_image(img)
	table.position = Vector2(gx * TILE_SIZE, 9 * TILE_SIZE)
	node.add_child(table)

	var book_img = Image.create(20, 12, false, Image.FORMAT_RGBA8)
	var cover = Color(0.32, 0.14, 0.10)
	var page = Color(0.90, 0.87, 0.76)
	for y in range(12):
		for x in range(20):
			var c = page
			if y < 1 or y > 10:
				c = cover
			elif x == 9 or x == 10:
				c = Color(0.70, 0.68, 0.60)
			book_img.set_pixel(x, y, c)
	for line in range(3):
		var ly = 3 + line * 2
		for x in range(2, 18):
			if x != 9 and x != 10 and (x + line) % 4 != 0:
				book_img.set_pixel(x, ly, Color(0.35, 0.32, 0.28))
	var book = Sprite2D.new()
	book.centered = false
	book.texture = ImageTexture.create_from_image(book_img)
	book.position = Vector2(gx * TILE_SIZE + 6, 9 * TILE_SIZE + 2)
	node.add_child(book)

	var qi_img = Image.create(12, 16, false, Image.FORMAT_RGBA8)
	qi_img.fill(Color.TRANSPARENT)
	var glass = Color(0.20, 0.22, 0.24, 0.85)
	var ink = Color(0.08, 0.08, 0.12)
	for y in range(10, 15):
		for x in range(1, 6):
			qi_img.set_pixel(x, y, glass)
	for x in range(2, 5):
		qi_img.set_pixel(x, 10, ink)
	var feather = Color(0.85, 0.82, 0.75)
	for i in range(10):
		var fx = 5 + i / 2
		var fy = 9 - i
		if fy >= 0:
			qi_img.set_pixel(fx, fy, feather)
	var qi = Sprite2D.new()
	qi.centered = false
	qi.texture = ImageTexture.create_from_image(qi_img)
	qi.position = Vector2(gx * TILE_SIZE + 40, 9 * TILE_SIZE + 6)
	node.add_child(qi)

	var note_img = Image.create(10, 8, false, Image.FORMAT_RGBA8)
	var paper = Color(0.88, 0.85, 0.70)
	for y in range(8):
		for x in range(10):
			note_img.set_pixel(x, y, paper)
	for x in range(1, 8):
		if x % 2 == 0:
			note_img.set_pixel(x, 3, Color(0.4, 0.4, 0.35))
	var note = Sprite2D.new()
	note.centered = false
	note.rotation = -0.15
	note.texture = ImageTexture.create_from_image(note_img)
	note.position = Vector2(gx * TILE_SIZE + 52, 9 * TILE_SIZE + 18)
	node.add_child(note)

	var lamp_img = Image.create(10, 18, false, Image.FORMAT_RGBA8)
	lamp_img.fill(Color.TRANSPARENT)
	var brass = Color(0.75, 0.62, 0.28)
	var brass_dark = Color(0.55, 0.45, 0.18)
	var shade = Color(0.80, 0.70, 0.40)
	for y in range(10, 16):
		lamp_img.set_pixel(4, y, brass_dark)
		lamp_img.set_pixel(5, y, brass)
	for x in range(3, 7):
		lamp_img.set_pixel(x, 16, brass_dark)
		lamp_img.set_pixel(x, 17, brass_dark)
	for y in range(2, 8):
		var half = 1 + (y - 2) / 2
		for x in range(4 - half, 5 + half):
			if x >= 0 and x < 10:
				lamp_img.set_pixel(x, y, shade)
	var lamp = Sprite2D.new()
	lamp.centered = false
	lamp.texture = ImageTexture.create_from_image(lamp_img)
	lamp.position = Vector2(gx * TILE_SIZE + 4, 9 * TILE_SIZE - 12)
	node.add_child(lamp)

	var glow = PointLight2D.new()
	glow.position = Vector2(gx * TILE_SIZE + 8, 9 * TILE_SIZE - 4)
	glow.color = Color(1.0, 0.85, 0.55)
	glow.energy = 0.38
	glow.texture = _create_light_texture(56)
	node.add_child(glow)
	_lamp_lights.append(glow)

	if variant == 1:
		_add_magnifier_map(node, gx)

	decorations.add_child(node)


func _add_magnifier_map(parent: Node2D, gx: int) -> void:
	var map_img = Image.create(24, 16, false, Image.FORMAT_RGBA8)
	var parchment = Color(0.82, 0.74, 0.54)
	var ink = Color(0.35, 0.28, 0.16)
	for y in range(16):
		for x in range(24):
			map_img.set_pixel(x, y, parchment)
	for x in range(2, 22):
		var y = 8 + int(sin(x * 0.5) * 3)
		if y >= 0 and y < 16:
			map_img.set_pixel(x, y, ink)
	map_img.set_pixel(6, 5, Color(0.55, 0.15, 0.12))
	map_img.set_pixel(16, 11, Color(0.55, 0.15, 0.12))
	var map_sprite = Sprite2D.new()
	map_sprite.centered = false
	map_sprite.texture = ImageTexture.create_from_image(map_img)
	map_sprite.position = Vector2(gx * TILE_SIZE + 20, 9 * TILE_SIZE + 10)
	parent.add_child(map_sprite)

	var lens_img = Image.create(18, 18, false, Image.FORMAT_RGBA8)
	lens_img.fill(Color.TRANSPARENT)
	var glass = Color(0.85, 0.92, 0.95, 0.35)
	var rim = Color(0.55, 0.45, 0.20)
	for y in range(16):
		for x in range(16):
			var dist = Vector2(x - 7, y - 7).length()
			if dist < 7:
				lens_img.set_pixel(x, y, glass)
			elif dist < 8:
				lens_img.set_pixel(x, y, rim)
	for i in range(4):
		lens_img.set_pixel(14 + i, 14 + i, rim)
	var lens = Sprite2D.new()
	lens.centered = false
	lens.texture = ImageTexture.create_from_image(lens_img)
	lens.position = Vector2(gx * TILE_SIZE + 22, 9 * TILE_SIZE + 6)
	parent.add_child(lens)


func _create_checkout_desk() -> void:
	var node = Node2D.new()
	node.name = "CheckoutDesk"
	var w = TILE_SIZE * 2
	var h = TILE_SIZE * 2
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var wood_top = Color(0.40, 0.26, 0.15)
	var wood_body = Color(0.28, 0.18, 0.10)
	var wood_dark = Color(0.20, 0.13, 0.07)
	for y in range(h):
		for x in range(w):
			if y < 6:
				var grain = (x + y) % 7 < 2
				img.set_pixel(x, y, wood_top.darkened(0.1) if grain else wood_top)
			else:
				var panel = (x / 16) % 2
				img.set_pixel(x, y, wood_dark if panel == 0 else wood_body)
	var desk = Sprite2D.new()
	desk.centered = false
	desk.texture = ImageTexture.create_from_image(img)
	desk.position = Vector2(8 * TILE_SIZE, 10 * TILE_SIZE)
	node.add_child(desk)

	var stamp_img = Image.create(12, 10, false, Image.FORMAT_RGBA8)
	stamp_img.fill(Color.TRANSPARENT)
	for y in range(4, 8):
		for x in range(2, 10):
			stamp_img.set_pixel(x, y, Color(0.30, 0.10, 0.10))
	for y in range(0, 4):
		for x in range(3, 9):
			stamp_img.set_pixel(x, y, Color(0.35, 0.25, 0.15))
	var stamp = Sprite2D.new()
	stamp.centered = false
	stamp.texture = ImageTexture.create_from_image(stamp_img)
	stamp.position = Vector2(8 * TILE_SIZE + 8, 10 * TILE_SIZE + 4)
	node.add_child(stamp)

	for i in range(3):
		var pull_y = 14 + i * 6
		var pull = ColorRect.new()
		pull.color = Color(0.72, 0.60, 0.26)
		pull.size = Vector2(3, 2)
		pull.position = Vector2(40, pull_y)
		desk.add_child(pull)

	# Brass service bell — same silhouette as the inn's, quieter duty
	var bell_img = Image.create(16, 18, false, Image.FORMAT_RGBA8)
	bell_img.fill(Color.TRANSPARENT)
	var brass = Color(0.78, 0.66, 0.28)
	var brass_hi = Color(0.94, 0.84, 0.50)
	for y in range(16):
		var half_w = int(7.0 * sin(float(y) / 16.0 * PI)) + 1
		for x in range(8 - half_w, 8 + half_w):
			bell_img.set_pixel(x, y, brass_hi if (x == 9 and y < 6) else brass)
	for y in range(16, 18):
		for x in range(6, 10):
			bell_img.set_pixel(x, y, brass.darkened(0.2))
	var bell = Sprite2D.new()
	bell.texture = ImageTexture.create_from_image(bell_img)
	bell.position = Vector2(8 * TILE_SIZE + 30, 10 * TILE_SIZE - 4)
	node.add_child(bell)

	var stack_img = Image.create(22, 14, false, Image.FORMAT_RGBA8)
	stack_img.fill(Color.TRANSPARENT)
	var spines = [Color(0.55, 0.20, 0.14), Color(0.24, 0.36, 0.65), Color(0.70, 0.58, 0.22)]
	for i in range(3):
		var by = 10 - i * 4
		for x in range(22):
			stack_img.set_pixel(x, by, spines[i])
			stack_img.set_pixel(x, by + 1, spines[i].darkened(0.2))
			stack_img.set_pixel(x, by + 2, spines[i])
			stack_img.set_pixel(x, by + 3, spines[i])
	var stack = Sprite2D.new()
	stack.centered = false
	stack.texture = ImageTexture.create_from_image(stack_img)
	stack.position = Vector2(8 * TILE_SIZE + 58, 10 * TILE_SIZE + 20)
	node.add_child(stack)

	decorations.add_child(node)


func _create_returns_cart() -> void:
	var img = Image.create(24, 18, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var wood = Color(0.36, 0.24, 0.14)
	var wheel = Color(0.18, 0.16, 0.15)
	for y in range(4, 12):
		for x in range(2, 22):
			img.set_pixel(x, y, wood)
	for wx in [4, 19]:
		for y in range(12, 16):
			for x in range(wx - 2, wx + 3):
				var dist = Vector2(x - wx, y - 14).length()
				if dist < 2.2:
					img.set_pixel(x, y, wheel)
	var spines = [Color(0.55, 0.20, 0.14), Color(0.24, 0.36, 0.65), Color(0.70, 0.58, 0.22)]
	for i in range(3):
		var bx = 5 + i * 6
		for y in range(0, 4):
			img.set_pixel(bx, y, spines[i])
			img.set_pixel(bx + 1, y, spines[i])
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(10.3 * TILE_SIZE, 10.3 * TILE_SIZE)
	decorations.add_child(sprite)


# ---------------------------------------------------------------------------
# Fireplace
# ---------------------------------------------------------------------------

func _create_fireplace() -> void:
	var node = Node2D.new()
	node.name = "Fireplace"
	var w = TILE_SIZE
	var h = TILE_SIZE + 10
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var stone = Color(0.48, 0.44, 0.40)
	var stone_dark = Color(0.34, 0.31, 0.28)
	var soot = Color(0.16, 0.14, 0.13)
	for y in range(h):
		for x in range(w):
			var in_arch = x > 5 and x < w - 5 and y > 5 and y < h - 6
			if in_arch:
				img.set_pixel(x, y, soot)
			else:
				var mortar = y % 8 < 2
				img.set_pixel(x, y, stone_dark if mortar else stone)
	var surround = Sprite2D.new()
	surround.centered = false
	surround.texture = ImageTexture.create_from_image(img)
	surround.position = Vector2(2 * TILE_SIZE, 10 * TILE_SIZE - 10)
	node.add_child(surround)
	decorations.add_child(node)

	_fire_sprite = Sprite2D.new()
	_fire_sprite.name = "FireFlame"
	_fire_sprite.z_index = 5
	_fire_sprite.position = Vector2(2.5 * TILE_SIZE, 11 * TILE_SIZE - 4)
	decorations.add_child(_fire_sprite)

	_fire_frames.clear()
	for f in range(2):
		var fimg = Image.create(20, 20, false, Image.FORMAT_RGBA8)
		_draw_fire_frame(fimg, f)
		_fire_frames.append(ImageTexture.create_from_image(fimg))
	_fire_sprite.texture = _fire_frames[0]

	_fire_light = PointLight2D.new()
	_fire_light.position = Vector2(2.5 * TILE_SIZE, 11 * TILE_SIZE - 4)
	_fire_light.color = Color(1.0, 0.55, 0.18, 0.85)
	_fire_light.energy = 0.7
	_fire_light.texture = _create_light_texture(120)
	decorations.add_child(_fire_light)


func _draw_fire_frame(img: Image, frame: int) -> void:
	img.fill(Color.TRANSPARENT)
	var ofs = 1 if frame == 1 else -1
	var outer = Color(0.95, 0.55, 0.10)
	var mid = Color(0.98, 0.80, 0.20)
	var inner = Color(1.00, 0.96, 0.60)
	var cx = 10 + ofs
	for y in range(20):
		var row_pct = float(20 - y) / 20.0
		var half_w = int(8.0 * row_pct * row_pct) + 1
		for x in range(cx - half_w, cx + half_w):
			if x < 0 or x >= 20:
				continue
			var dx = abs(x - cx)
			if dx < 2 and row_pct > 0.4:
				img.set_pixel(x, y, inner)
			elif dx < 4:
				img.set_pixel(x, y, mid)
			else:
				img.set_pixel(x, y, outer)


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
		_fire_light.energy = 0.55 + 0.20 * sin(_fire_time * 6.7) + 0.08 * sin(_fire_time * 11.3)


func _create_library_cat() -> void:
	var stack_img = Image.create(18, 10, false, Image.FORMAT_RGBA8)
	stack_img.fill(Color.TRANSPARENT)
	var spines = [Color(0.55, 0.20, 0.14), Color(0.24, 0.36, 0.65)]
	for i in range(2):
		var by = i * 5
		for x in range(18):
			stack_img.set_pixel(x, by, spines[i])
			stack_img.set_pixel(x, by + 1, spines[i].darkened(0.2))
			stack_img.set_pixel(x, by + 2, spines[i])
	var stack = Sprite2D.new()
	stack.centered = false
	stack.texture = ImageTexture.create_from_image(stack_img)
	stack.position = Vector2(3 * TILE_SIZE + 2, 10 * TILE_SIZE + 10)
	decorations.add_child(stack)

	_cat_frames.clear()
	for f in range(2):
		var img = Image.create(18, 12, false, Image.FORMAT_RGBA8)
		_draw_cat_frame(img, f)
		_cat_frames.append(ImageTexture.create_from_image(img))
	_cat_sprite = Sprite2D.new()
	_cat_sprite.centered = false
	_cat_sprite.texture = _cat_frames[0]
	_cat_sprite.position = Vector2(3 * TILE_SIZE + 2, 10 * TILE_SIZE)
	decorations.add_child(_cat_sprite)


func _draw_cat_frame(img: Image, frame: int) -> void:
	img.fill(Color.TRANSPARENT)
	var fur = Color(0.35, 0.28, 0.24)
	var fur_dark = Color(0.24, 0.19, 0.16)
	var breathe = 1 if frame == 1 else 0
	for y in range(2 - breathe, 12):
		for x in range(0, 18):
			var cx = 9.0
			var cy = 7.0
			var ry = 5.0 + breathe * 0.6
			var dist = sqrt(pow((x - cx) / 8.0, 2) + pow((y - cy) / ry, 2))
			if dist < 1.0:
				img.set_pixel(x, y, fur_dark if dist > 0.75 else fur)
	for i in range(6):
		var tx = 2 + i
		var ty = 9 + int(sin(i * 0.8) * 2)
		if tx < 18 and ty < 12:
			img.set_pixel(tx, ty, fur_dark)
	img.set_pixel(6, 2 - breathe, fur_dark)
	img.set_pixel(12, 2 - breathe, fur_dark)


func _animate_cat(delta: float) -> void:
	_cat_timer += delta
	if _cat_timer >= CAT_SPEED:
		_cat_timer -= CAT_SPEED
		_cat_frame = (_cat_frame + 1) % _cat_frames.size()
		if _cat_sprite:
			_cat_sprite.texture = _cat_frames[_cat_frame]


# ---------------------------------------------------------------------------
# Mezzanine, star chart, chained tome
# ---------------------------------------------------------------------------

func _create_ladder_mezzanine() -> void:
	var gx = 17
	var gy = 11
	var img = Image.create(20, TILE_SIZE + 6, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var wood = Color(0.42, 0.28, 0.16)
	var wood_dark = Color(0.28, 0.18, 0.10)
	for rail_x in [2, 17]:
		for y in range(TILE_SIZE + 6):
			img.set_pixel(rail_x, y, wood)
			img.set_pixel(rail_x + 1, y, wood_dark)
	var ry = 4
	while ry < TILE_SIZE + 2:
		for x in range(2, 19):
			img.set_pixel(x, ry, wood_dark)
		ry += 8
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(gx * TILE_SIZE + 6, gy * TILE_SIZE - 6)
	decorations.add_child(sprite)

	var mw = TILE_SIZE * 4
	var mh = 40
	var mimg = Image.create(mw, mh, false, Image.FORMAT_RGBA8)
	var far_shelf = Color(0.20, 0.15, 0.10, 0.9)
	var far_book = Color(0.35, 0.25, 0.30, 0.9)
	for y in range(mh):
		for x in range(mw):
			mimg.set_pixel(x, y, far_shelf)
	for sy in range(4, mh - 4, 10):
		for x in range(2, mw - 2, 4):
			if (x / 4 + sy) % 3 != 0:
				mimg.set_pixel(x, sy, far_book)
				mimg.set_pixel(x + 1, sy, far_book)
	var rail = Color(0.30, 0.20, 0.12)
	for x in range(mw):
		mimg.set_pixel(x, mh - 2, rail)
		mimg.set_pixel(x, mh - 1, rail.darkened(0.2))
	var backdrop = Sprite2D.new()
	backdrop.centered = false
	backdrop.texture = ImageTexture.create_from_image(mimg)
	backdrop.position = Vector2(15 * TILE_SIZE, -mh + 10)
	backdrop.z_index = -1
	decorations.add_child(backdrop)

	var label = Label.new()
	label.text = "Mezzanine ↑"
	label.position = Vector2((gx - 1.0) * TILE_SIZE, (gy - 1.2) * TILE_SIZE)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color(0.80, 0.72, 0.55))
	decorations.add_child(label)


func _create_star_chart() -> void:
	var w = 40
	var h = 56
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var navy = Color(0.08, 0.08, 0.20)
	var navy_light = Color(0.12, 0.12, 0.28)
	var frame = Color(0.55, 0.45, 0.22)
	for y in range(h):
		for x in range(w):
			var border = x < 3 or x >= w - 3 or y < 3 or y >= h - 3
			img.set_pixel(x, y, frame if border else navy)
	var rng = RandomNumberGenerator.new()
	rng.seed = 555
	var stars: Array[Vector2] = []
	for i in range(22):
		var sx = rng.randi_range(5, w - 6)
		var sy = rng.randi_range(5, h - 6)
		stars.append(Vector2(sx, sy))
		img.set_pixel(sx, sy, Color.WHITE)
		if rng.randf() > 0.5:
			img.set_pixel(sx + 1, sy, navy_light.lightened(0.5))
	for i in range(0, 8, 2):
		if i + 1 < stars.size():
			_draw_star_line(img, stars[i], stars[i + 1], Color(0.55, 0.55, 0.75, 0.6))
	var sprite = Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(1.4 * TILE_SIZE, 5 * TILE_SIZE)
	decorations.add_child(sprite)


func _draw_star_line(img: Image, a: Vector2, b: Vector2, c: Color) -> void:
	var steps = int(a.distance_to(b))
	for i in range(steps):
		var t = float(i) / float(max(steps, 1))
		var p = a.lerp(b, t)
		var px = int(p.x)
		var py = int(p.y)
		if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
			img.set_pixel(px, py, c)


func _create_chained_tome() -> void:
	var gx = 17
	var gy = 8
	var img = Image.create(20, 26, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var wood = Color(0.30, 0.20, 0.12)
	var wood_dark = Color(0.20, 0.13, 0.07)
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
	var lectern = Sprite2D.new()
	lectern.centered = false
	lectern.texture = ImageTexture.create_from_image(img)
	lectern.position = Vector2(gx * TILE_SIZE, gy * TILE_SIZE)
	decorations.add_child(lectern)

	var tome_img = Image.create(16, 10, false, Image.FORMAT_RGBA8)
	var cover = Color(0.12, 0.10, 0.14)
	var clasp = Color(0.55, 0.48, 0.22)
	for y in range(10):
		for x in range(16):
			tome_img.set_pixel(x, y, cover)
	for x in range(6, 10):
		tome_img.set_pixel(x, 4, clasp)
		tome_img.set_pixel(x, 5, clasp)
	var tome = Sprite2D.new()
	tome.centered = false
	tome.texture = ImageTexture.create_from_image(tome_img)
	tome.position = Vector2(gx * TILE_SIZE + 2, gy * TILE_SIZE + 6)
	decorations.add_child(tome)

	var chain_color = Color(0.45, 0.42, 0.38)
	for i in range(8):
		var cy = gy * TILE_SIZE + 16 + i * 3
		var cx = gx * TILE_SIZE + 4 + int(sin(i * 0.8) * 2)
		var link = ColorRect.new()
		link.color = chain_color
		link.size = Vector2(2, 2)
		link.position = Vector2(cx, cy)
		decorations.add_child(link)

	var post_a = Vector2(gx - 1.2, gy + 0.6)
	var post_b = Vector2(gx + 0.6, gy + 0.6)
	_create_stanchion(post_a)
	_create_stanchion(post_b)
	_create_rope_swag(post_a * TILE_SIZE + Vector2(4, 4), post_b * TILE_SIZE + Vector2(4, 4))


func _create_stanchion(grid_pos: Vector2) -> void:
	var img = Image.create(8, 22, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var brass = Color(0.72, 0.60, 0.26)
	var brass_dark = Color(0.52, 0.42, 0.16)
	for x in range(2, 6):
		img.set_pixel(x, 20, brass_dark)
		img.set_pixel(x, 21, brass_dark)
	for y in range(2, 20):
		img.set_pixel(3, y, brass)
		img.set_pixel(4, y, brass)
	for y in range(0, 3):
		for x in range(2, 6):
			img.set_pixel(x, y, brass.lightened(0.2))
	var sprite = Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = grid_pos * TILE_SIZE
	decorations.add_child(sprite)


func _create_rope_swag(a: Vector2, b: Vector2) -> void:
	var rope = Color(0.55, 0.12, 0.12)
	var steps = 12
	for i in range(steps + 1):
		var t = float(i) / float(steps)
		var x = lerp(a.x, b.x, t)
		var sag = sin(t * PI) * 8.0
		var y = lerp(a.y, b.y, t) + sag
		var dot = ColorRect.new()
		dot.color = rope
		dot.size = Vector2(2, 2)
		dot.position = Vector2(x, y)
		decorations.add_child(dot)


# ---------------------------------------------------------------------------
# Globe, scroll racks, ceiling lamps, loose page
# ---------------------------------------------------------------------------

func _create_globe() -> void:
	_globe_frames.clear()
	for f in range(2):
		var img = Image.create(28, 28, false, Image.FORMAT_RGBA8)
		_draw_globe_frame(img, f)
		_globe_frames.append(ImageTexture.create_from_image(img))

	var ped_img = Image.create(16, 20, false, Image.FORMAT_RGBA8)
	var wood = Color(0.36, 0.24, 0.14)
	var wood_dark = Color(0.24, 0.16, 0.09)
	for y in range(20):
		for x in range(16):
			ped_img.set_pixel(x, y, wood_dark if (x < 2 or x > 13) else wood)
	var ped = Sprite2D.new()
	ped.centered = false
	ped.texture = ImageTexture.create_from_image(ped_img)
	ped.position = Vector2(10 * TILE_SIZE - 8, 7 * TILE_SIZE + 12)
	decorations.add_child(ped)

	_globe_sprite = Sprite2D.new()
	_globe_sprite.texture = _globe_frames[0]
	_globe_sprite.position = Vector2(10 * TILE_SIZE, 7 * TILE_SIZE + 8)
	decorations.add_child(_globe_sprite)


func _draw_globe_frame(img: Image, frame: int) -> void:
	img.fill(Color.TRANSPARENT)
	var ocean = Color(0.22, 0.40, 0.60)
	var land = Color(0.35, 0.55, 0.30)
	var brass = Color(0.72, 0.60, 0.26)
	var center = 14.0
	for y in range(28):
		for x in range(28):
			var dist = Vector2(x - center, y - center).length()
			if dist < 12:
				var land_swirl = sin((x + frame * 6) * 0.5) + cos(y * 0.4)
				var c = land if land_swirl > 0.3 else ocean
				if dist > 10:
					c = c.darkened(0.2)
				img.set_pixel(x, y, c)
			elif dist < 13:
				img.set_pixel(x, y, brass)
	for y in range(24, 28):
		img.set_pixel(13, y, brass)
		img.set_pixel(14, y, brass)


func _spin_globe(delta: float) -> void:
	_globe_time += delta
	if _globe_time >= 3.5:
		_globe_time -= 3.5
		if _globe_sprite and _globe_frames.size() > 1:
			_globe_sprite.texture = _globe_frames[1] if _globe_sprite.texture == _globe_frames[0] else _globe_frames[0]


func _create_scroll_racks() -> void:
	_create_scroll_rack(Vector2(6, 11))
	_create_scroll_rack(Vector2(13, 11))


func _create_scroll_rack(grid_pos: Vector2) -> void:
	var img = Image.create(TILE_SIZE, 26, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var wood = Color(0.34, 0.22, 0.13)
	for x in range(2, TILE_SIZE - 2):
		img.set_pixel(x, 2, wood)
		img.set_pixel(x, 24, wood)
	for lx in [3, TILE_SIZE - 4]:
		for y in range(2, 25):
			img.set_pixel(lx, y, wood)
	var scroll_colors = [Color(0.80, 0.70, 0.45), Color(0.75, 0.62, 0.35), Color(0.85, 0.78, 0.55)]
	for i in range(4):
		var sx = 6 + i * 6
		var col: Color = scroll_colors[i % scroll_colors.size()]
		for y in range(6, 20):
			img.set_pixel(sx, y, col)
			img.set_pixel(sx + 1, y, col.darkened(0.15))
		img.set_pixel(sx, 5, col.lightened(0.2))
		img.set_pixel(sx + 1, 5, col.lightened(0.2))
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = grid_pos * TILE_SIZE
	decorations.add_child(sprite)


func _create_ceiling_lamps() -> void:
	var light_tex = _create_light_texture(90)
	for gp in [Vector2(3, 5), Vector2(16, 5), Vector2(9.5, 3)]:
		var lamp = PointLight2D.new()
		lamp.position = gp * TILE_SIZE
		lamp.color = Color(0.95, 0.88, 0.65)
		lamp.energy = 0.22
		lamp.texture = light_tex
		decorations.add_child(lamp)
		_lamp_lights.append(lamp)


func _create_wall_sconces() -> void:
	# Iron wall sconces along the side walls — same warm task lighting
	# language as the reading lamps, extended to the general room.
	var light_tex = _create_light_texture(60)
	for anchor in [Vector2(1, 5), Vector2(18, 5), Vector2(1, 9)]:
		_create_sconce(anchor, light_tex)


func _create_sconce(anchor: Vector2, light_tex: ImageTexture) -> void:
	var img = Image.create(10, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var iron = Color(0.25, 0.24, 0.26)
	var outer = Color(0.92, 0.60, 0.20)
	var inner = Color(1.0, 0.90, 0.55)
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
	glow.color = Color(0.95, 0.68, 0.35)
	glow.energy = 0.28
	glow.texture = light_tex
	decorations.add_child(glow)
	_lamp_lights.append(glow)


func _create_silence_sign() -> void:
	# Small hand-lettered placard by the checkout desk — the game's
	# meta-comedic register showing up even in the quiet room.
	var img = Image.create(30, 14, false, Image.FORMAT_RGBA8)
	var board = Color(0.72, 0.62, 0.42)
	var board_dark = Color(0.55, 0.46, 0.30)
	for y in range(14):
		for x in range(30):
			var frame_edge = x == 0 or y == 0 or x == 29 or y == 13
			img.set_pixel(x, y, board_dark if frame_edge else board)
	for line in range(2):
		var ly = 4 + line * 5
		for x in range(3, 27):
			if (x + line * 2) % 4 != 0:
				img.set_pixel(x, ly, Color(0.25, 0.20, 0.14))
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(8 * TILE_SIZE, 9.2 * TILE_SIZE)
	decorations.add_child(sprite)

	var label = Label.new()
	label.text = "SILENCE (Cantor Vell is watching)"
	label.position = Vector2(6.9 * TILE_SIZE, 9.6 * TILE_SIZE)
	label.add_theme_font_size_override("font_size", 7)
	label.add_theme_color_override("font_color", Color(0.30, 0.24, 0.16))
	decorations.add_child(label)


func _create_welcome_mat() -> void:
	var w = TILE_SIZE * 2
	var h = 14
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var mat = Color(0.34, 0.24, 0.16)
	var mat_dark = Color(0.24, 0.17, 0.11)
	for y in range(h):
		for x in range(w):
			var edge = x < 2 or x >= w - 2 or y < 2 or y >= h - 2
			img.set_pixel(x, y, mat_dark if edge or (x + y) % 6 == 0 else mat)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.z_index = -1
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(8 * TILE_SIZE, 12 * TILE_SIZE + 8)
	decorations.add_child(sprite)


func _create_spectacles() -> void:
	# Reading glasses left behind on the left-hand table — tiny prop,
	# implies someone stepped away mid-thought.
	var img = Image.create(14, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var frame = Color(0.30, 0.26, 0.22)
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
	sprite.position = Vector2(3 * TILE_SIZE + 44, 9 * TILE_SIZE + 4)
	decorations.add_child(sprite)


func _create_section_placards() -> void:
	# Small hanging labels over the back shelf run — cheap wayfinding
	# that makes the stacks feel catalogued rather than decorative.
	var sections = [
		{"text": "History", "x": 4.5},
		{"text": "Bestiary", "x": 9.0},
		{"text": "Astronomy", "x": 13.5},
	]
	for entry in sections:
		var label = Label.new()
		label.text = str(entry["text"])
		label.position = Vector2(float(entry["x"]) * TILE_SIZE, 0.3 * TILE_SIZE)
		label.add_theme_font_size_override("font_size", 8)
		label.add_theme_color_override("font_color", Color(0.85, 0.78, 0.60))
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		decorations.add_child(label)


func _create_cobweb() -> void:
	# A neglected high corner above the east island — nobody's shelved
	# a 'Geography' section in years, apparently.
	var size = 22
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var strand = Color(0.80, 0.80, 0.82, 0.55)
	for i in range(6):
		var ang = i * PI / 6.0
		var ex = int(size / 2.0 + cos(ang) * size / 2.0)
		var ey = int(size / 2.0 + sin(ang) * size / 2.0)
		_draw_star_line(img, Vector2(0, 0), Vector2(ex, ey), strand)
	for r in [6, 12, 18]:
		for i in range(24):
			var ang = i * TAU / 24.0
			var px = int(cos(ang) * r)
			var py = int(sin(ang) * r)
			if px >= 0 and px < size and py >= 0 and py < size:
				img.set_pixel(px, py, strand)
	var sprite = Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(15 * TILE_SIZE - 4, 3 * TILE_SIZE - 4)
	decorations.add_child(sprite)


func _create_telescope() -> void:
	# Brass telescope beside the star chart — Dr. Reeve's tool of the
	# trade, propped rather than in active use.
	var img = Image.create(8, 34, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var brass = Color(0.72, 0.60, 0.26)
	var brass_dark = Color(0.52, 0.42, 0.16)
	var wood = Color(0.34, 0.22, 0.13)
	for i in range(20):
		var tx = 2 + i / 4
		var ty = 2 + i
		if ty < 24:
			img.set_pixel(tx, ty, brass if i % 4 != 0 else brass_dark)
			img.set_pixel(tx + 1, ty, brass)
	for y in range(24, 34):
		img.set_pixel(2, y, wood)
		img.set_pixel(6, y, wood)
	for x in range(0, 8):
		var tripod_shade = Color(0.24, 0.16, 0.09) if x % 2 == 0 else Color(0.30, 0.20, 0.11)
		img.set_pixel(x, 30, tripod_shade)
	var sprite = Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(2.7 * TILE_SIZE, 6.5 * TILE_SIZE)
	decorations.add_child(sprite)


func _create_returns_slot() -> void:
	# Brass mail-slot 'Book Return' set into the wall by the entrance —
	# a self-service option for players who don't want to wake Cantor Vell.
	var img = Image.create(20, 12, false, Image.FORMAT_RGBA8)
	var brass = Color(0.72, 0.60, 0.26)
	var slot = Color(0.10, 0.09, 0.10)
	for y in range(12):
		for x in range(20):
			img.set_pixel(x, y, brass if (x == 0 or y == 0 or x == 19 or y == 11) else brass.darkened(0.1))
	for y in range(4, 8):
		for x in range(3, 17):
			img.set_pixel(x, y, slot)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(13 * TILE_SIZE, 12 * TILE_SIZE + 6)
	decorations.add_child(sprite)

	var label = Label.new()
	label.text = "Book Return"
	label.position = Vector2(12.5 * TILE_SIZE, 12.9 * TILE_SIZE)
	label.add_theme_font_size_override("font_size", 7)
	label.add_theme_color_override("font_color", Color(0.55, 0.48, 0.30))
	decorations.add_child(label)


func _create_bookworm() -> void:
	# Tiny animated critter on the east shelf island — a two-frame
	# inchworm crawl, purely for players who stand still long enough
	# to notice.
	_worm_frames.clear()
	for f in range(2):
		var img = Image.create(6, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.TRANSPARENT)
		var body = Color(0.55, 0.65, 0.30)
		var hump = 1 if f == 1 else 0
		for x in range(6):
			var y = 2 - (hump if x == 2 or x == 3 else 0)
			img.set_pixel(x, y, body)
		_worm_frames.append(ImageTexture.create_from_image(img))
	_worm_sprite = Sprite2D.new()
	_worm_sprite.texture = _worm_frames[0]
	_worm_base = Vector2(13 * TILE_SIZE + 4, 5 * TILE_SIZE + 10)
	_worm_sprite.position = _worm_base
	decorations.add_child(_worm_sprite)


func _crawl_worm(delta: float) -> void:
	_worm_timer += delta
	if _worm_timer >= 0.6:
		_worm_timer -= 0.6
		_worm_frame = (_worm_frame + 1) % _worm_frames.size()
		if _worm_sprite:
			_worm_sprite.texture = _worm_frames[_worm_frame]
			_worm_sprite.position = _worm_base + Vector2(_worm_frame * 2.0, 0)


func _create_windowsill_plant() -> void:
	# Small potted fern on the west wall — the one spot of green in an
	# otherwise all-wood, all-paper room.
	var img = Image.create(16, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var pot = Color(0.55, 0.32, 0.20)
	var pot_dark = Color(0.40, 0.22, 0.13)
	var leaf = Color(0.30, 0.50, 0.25)
	var leaf_dark = Color(0.20, 0.38, 0.18)
	for y in range(16, 24):
		for x in range(3, 13):
			img.set_pixel(x, y, pot_dark if x < 5 or x > 10 else pot)
	var fronds = [
		[Vector2(8, 15), Vector2(3, 6)], [Vector2(8, 15), Vector2(8, 2)],
		[Vector2(8, 15), Vector2(13, 7)], [Vector2(8, 15), Vector2(5, 10)],
		[Vector2(8, 15), Vector2(11, 9)],
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
				img.set_pixel(px, py, leaf if i % 2 == 0 else leaf_dark)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(1 * TILE_SIZE + 6, 2 * TILE_SIZE)
	decorations.add_child(sprite)


func _breathe_lamps(delta: float) -> void:
	_light_time += delta
	for i in range(_lamp_lights.size()):
		var light = _lamp_lights[i]
		if is_instance_valid(light):
			# First 3 entries are the reading-table lamps (brighter task
			# lighting); the rest are ambient ceiling fill lights.
			var base_energy = 0.34 if i < 3 else 0.20
			light.energy = base_energy + 0.06 * sin(_light_time * 1.1 + i * 1.3)


func _create_loose_page() -> void:
	# A stray page near the chained-tome alcove — pairs with Tessin's
	# 'I wasn't doing anything' dialogue.
	var img = Image.create(8, 10, false, Image.FORMAT_RGBA8)
	var paper = Color(0.88, 0.85, 0.72)
	for y in range(10):
		for x in range(8):
			img.set_pixel(x, y, paper)
	for x in range(1, 7):
		if x % 2 == 0:
			img.set_pixel(x, 4, Color(0.4, 0.4, 0.35))
	_page_sprite = Sprite2D.new()
	_page_sprite.texture = ImageTexture.create_from_image(img)
	_page_base = Vector2(15.5, 7.5) * TILE_SIZE
	_page_sprite.position = _page_base
	_page_sprite.rotation = 0.3
	decorations.add_child(_page_sprite)


func _drift_page(delta: float) -> void:
	_page_time += delta
	if _page_sprite:
		_page_sprite.position = _page_base + Vector2(sin(_page_time * 0.7) * 4.0, cos(_page_time * 0.5) * 2.0)
		_page_sprite.rotation = 0.3 + sin(_page_time * 0.6) * 0.15


# ---------------------------------------------------------------------------
# NPCs
# ---------------------------------------------------------------------------

func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	_create_cantor_vell(OverworldNPCScript)
	_create_scholar_yorick(OverworldNPCScript)
	_create_student_pip(OverworldNPCScript)
	_create_historian_reeve(OverworldNPCScript)
	_create_researcher_tessin(OverworldNPCScript)


func _create_cantor_vell(NPCScript) -> void:
	var cantor = NPCScript.new()
	cantor.npc_name = "Cantor Vell"
	cantor.npc_type = "scholar"
	cantor.position = Vector2(9 * TILE_SIZE, 10 * TILE_SIZE)
	cantor.dialogue_lines = [
		"Quiet, please. The pages are old and they hear everything.",
		"I keep the names of the dragons here. Four of them. Maybe more.",
		"Pyrroth was first in the songs, but only because the sailors loved fire.",
		"Glacius listens, even now. The Frozen Sovereign always listens.",
		"Voltharion and Umbraxis... I would not speak their true names aloud.",
		"If you find their caves, traveler — do not introduce yourself.",
	]
	npcs.add_child(cantor)


func _create_scholar_yorick(NPCScript) -> void:
	var yorick = NPCScript.new()
	yorick.npc_name = "Yorick Pell"
	yorick.npc_type = "scholar"
	yorick.position = Vector2(9 * TILE_SIZE, 9 * TILE_SIZE)
	yorick.dialogue_lines = [
		"Fascinating. Absolutely fascinating. This passage describes a hero's journey that loops back on itself.",
		"Recursion is the pattern of everything, you know. Rivers, family trees, the way a kingdom repeats its own mistakes.",
		"I've cross-referenced eleven accounts of the 'first' war. They can't all be first. Someone's lying, or something stranger is true.",
		"Do you ever get the feeling you've had this exact conversation before? No? Just me, then.",
		"*doesn't look up* Mm. Fascinating. Absolutely fascinating.",
	]
	npcs.add_child(yorick)


func _create_student_pip(NPCScript) -> void:
	var pip = NPCScript.new()
	pip.npc_name = "Pip"
	pip.npc_type = "villager"
	pip.position = Vector2(4 * TILE_SIZE, 9 * TILE_SIZE)
	pip.dialogue_lines = [
		"*snoring softly*",
		"Zzz... five more minutes... the exam isn't until... zzz...",
		"*mumbles* No, Professor, I DID read chapter twelve...",
		"*wakes with a start* WHAT— oh. Oh, it's just you. I was resting my eyes.",
		"*wipes drool off the page* This book and I have reached an understanding.",
	]
	npcs.add_child(pip)


func _create_historian_reeve(NPCScript) -> void:
	var reeve = NPCScript.new()
	reeve.npc_name = "Dr. Absalom Reeve"
	reeve.npc_type = "scholar"
	reeve.position = Vector2(2 * TILE_SIZE, 5 * TILE_SIZE)
	reeve.dialogue_lines = [
		"The stars don't lie, but they do exaggerate. Every constellation was named by someone trying to seem important.",
		"I've charted the sky's drift for a decade now. It moves faster than the old records say it should.",
		"Some nights the pattern almost resolves into a shape. A face, maybe. I stop looking before I'm sure.",
		"If this world really has been through this before, the sky is the one witness that can't lie about it.",
		"Don't mind me. Just talking to the ceiling. It listens better than most scholars I know.",
	]
	npcs.add_child(reeve)


func _create_researcher_tessin(NPCScript) -> void:
	var tessin = NPCScript.new()
	tessin.npc_name = "Tessin"
	tessin.npc_type = "mysterious"
	tessin.position = Vector2(16 * TILE_SIZE, 8 * TILE_SIZE)
	tessin.dialogue_lines = [
		"*flinches* Oh! I— I wasn't doing anything. I was just LOOKING at the rope.",
		"That book's chained for a reason. I'm not touching it. I'm just reading the chain. Very carefully.",
		"*glances over shoulder* Is Cantor Vell watching? Don't tell me if he is. I don't want to know.",
		"Fine. FINE. I want to know what's in there. Everyone does. That's the whole point of chaining it.",
		"*steps back quickly* You didn't see me standing this close. We've never had this conversation.",
	]
	npcs.add_child(tessin)


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
	exit.target_spawn = "library_exit"
	exit.require_interaction = false
	exit.position = Vector2(9.5 * TILE_SIZE, 13.5 * TILE_SIZE)
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
