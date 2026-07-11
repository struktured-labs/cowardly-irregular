extends BaseInterior
class_name ScripturaBookshopInterior

## ScripturaBookshopInterior - Aldrin's independent bookshop, tucked into
## the Scriptura capital district. Defiantly un-official next to the
## Guild's rune-etched order: cluttered floor stacks, mismatched lamps, a
## wood stove, a reading cat, hand-lettered signs, and a "banned in the
## capital" shelf tucked under the counter behind a curtain nobody looks
## twice at. Warmer and homier than anything else in the district. Aldrin
## keeps the counter; the shop keeps its own kind of record.

const BOOKSHOP_LAYOUT = [
	"WWWWWWWWWWWWWWWW",
	"W..SS......SS..W",
	"W..SS......SS..W",
	"W..............W",
	"W......AA......W",
	"W......NN......W",
	"W..............W",
	"W......TT......W",
	"W..............W",
	"W.V............W",
	"W..............W",
	"WWWWWWWDDWWWWWWW",
]

## Wood stove flicker (2-frame)
var _stove_sprite: Sprite2D
var _stove_frames: Array[ImageTexture] = []
var _stove_frame: int = 0
var _stove_timer: float = 0.0
const STOVE_SPEED: float = 0.24
var _stove_light: PointLight2D
var _stove_time: float = 0.0

## Reading cat breathing (2-frame)
var _cat_sprite: Sprite2D
var _cat_frames: Array[ImageTexture] = []
var _cat_frame: int = 0
var _cat_timer: float = 0.0
const CAT_SPEED: float = 0.95

## Door bell idle sway
var _bell_sprite: Sprite2D
var _bell_time: float = 0.0

## Mismatched lamps breathing
var _lamp_lights: Array[PointLight2D] = []
var _light_time: float = 0.0

## Dust motes drifting in the window light
var _mote_sprites: Array[Sprite2D] = []
var _mote_base_positions: Array[Vector2] = []
var _mote_time: float = 0.0

## Loose ribbon bookmark near the reading nook
var _page_sprite: Sprite2D
var _page_base: Vector2 = Vector2.ZERO
var _page_time: float = 0.0


func _get_area_id() -> String:
	return "scriptura_bookshop"


func _get_display_name() -> String:
	return "Aldrin's Books"


func _get_ambient_key() -> String:
	return "ambient_library"


func _get_map_width() -> int:
	return 16


func _get_map_height() -> int:
	return 12


func _get_layout() -> Array:
	return BOOKSHOP_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(7, 10)
	spawn_points["counter"] = Vector2(7, 6)


func _get_music_track() -> String:
	return "interior_library"


func _draw_floor_tile(image: Image) -> void:
	# Honey-warm worn floorboards — lighter and cozier than the
	# library's dark aged oak, scuffed from decades of browsing feet.
	var wood = Color(0.52, 0.36, 0.22)
	var wood_dark = Color(0.40, 0.27, 0.15)
	var grain = Color(0.46, 0.31, 0.18)
	var worn = Color(0.58, 0.42, 0.26)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var plank = (x / 8) % 2
			var seam = y % 8 == 0
			var grain_line = (y + x / 4) % 5 == 0
			if seam:
				image.set_pixel(x, y, wood_dark.darkened(0.1))
			elif grain_line:
				image.set_pixel(x, y, grain)
			else:
				var base = worn if plank == 0 else wood
				image.set_pixel(x, y, base if (x + y) % 10 != 0 else wood_dark)


func _draw_wall_tile(image: Image) -> void:
	# Warm plank walls with a patched exposed-brick lower course — the
	# look of a shop quietly repaired by its owner for years rather
	# than a guild contractor.
	var plank = Color(0.44, 0.30, 0.18)
	var plank_light = Color(0.54, 0.38, 0.24)
	var seam = Color(0.26, 0.17, 0.10)
	var brick = Color(0.48, 0.24, 0.18)
	var brick_dark = Color(0.36, 0.17, 0.13)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var vert_seam = x % 8 == 0
			var horiz_grain = y % 4 == 0
			var in_brick_course = y >= TILE_SIZE - 10
			if in_brick_course:
				var brick_seam = (x % 8 == 0) or ((y - (TILE_SIZE - 10)) % 5 == 0)
				image.set_pixel(x, y, brick_dark if brick_seam else brick)
			elif vert_seam:
				image.set_pixel(x, y, seam)
			elif horiz_grain:
				image.set_pixel(x, y, plank_light)
			else:
				image.set_pixel(x, y, plank)


func _process(delta: float) -> void:
	_animate_stove(delta)
	_flicker_stove_light(delta)
	_animate_cat(delta)
	_sway_bell(delta)
	_breathe_lamps(delta)
	_drift_motes(delta)
	_drift_page(delta)


func _setup_decorations() -> void:
	super._setup_decorations()
	_create_ambient_warmth()
	_create_corner_shelf(3)
	_create_corner_shelf(11)
	_create_counter()
	_create_banned_shelf()
	_create_till_and_ledger()
	_create_browsing_table()
	_create_book_stack(Vector2(5.5, 3.2), 0)
	_create_book_stack(Vector2(11.3, 8.3), 1)
	_create_book_stack(Vector2(4.3, 8.4), 2)
	_create_book_stack(Vector2(12.2, 3.3), 0)
	_create_wood_stove()
	_create_reading_cat()
	_create_reading_nook_chair()
	_create_mismatched_lamps()
	_create_door_bell()
	_create_hand_lettered_signs()
	_create_price_chalkboard()
	_create_step_ladder()
	_create_welcome_mat()
	_create_curtain()
	_create_coat_hooks()
	_create_section_placards()
	_create_cobweb()
	_create_dust_motes()
	_create_loose_bookmark()


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
	# Warm honeyed wash — cozier and browner than the library's, no
	# trace of the Guild's cold blue-violet a few doors down.
	var warm = CanvasModulate.new()
	warm.name = "BookshopWarmth"
	warm.color = Color(0.96, 0.88, 0.76)
	add_child(warm)


# ---------------------------------------------------------------------------
# Shelving
# ---------------------------------------------------------------------------

func _create_corner_shelf(gx: int) -> void:
	# Crowded, mismatched shelving crammed into the corners — no two
	# shelves the same height, unlike the Guild's uniform rune-shelves.
	var w = TILE_SIZE * 2
	var h = TILE_SIZE * 2 + 10
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var shelf_back = Color(0.24, 0.16, 0.10)
	var frame_wood = Color(0.36, 0.24, 0.14)
	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, shelf_back)
	for x in [0, 1, w - 2, w - 1]:
		for y in range(h):
			img.set_pixel(x, y, frame_wood)
	var spine_sets = [
		[Color(0.55, 0.20, 0.14), Color(0.65, 0.26, 0.18)],
		[Color(0.24, 0.36, 0.30), Color(0.30, 0.44, 0.36)],
		[Color(0.62, 0.50, 0.20), Color(0.72, 0.60, 0.26)],
		[Color(0.30, 0.28, 0.46), Color(0.38, 0.34, 0.56)],
	]
	var rng = RandomNumberGenerator.new()
	rng.seed = gx * 53 + 5
	var shelf_rows = [6, 22, 38]
	for sy in shelf_rows:
		for x in range(w):
			img.set_pixel(x, sy, frame_wood.darkened(0.15))
		var x = 4
		while x < w - 4:
			var pair: Array = spine_sets[rng.randi_range(0, spine_sets.size() - 1)]
			var book_w = rng.randi_range(3, 6)
			var lean = rng.randi_range(0, 1) == 1
			var book_h = rng.randi_range(11, 15)
			for by in range(book_h):
				for bx in range(book_w):
					var xx = x + bx + (by / 4 if lean else 0)
					var yy = sy - by
					if xx < w and yy >= 0:
						img.set_pixel(xx, yy, pair[0] if bx % 3 != 0 else pair[1])
			x += book_w + 1
	var sprite = Sprite2D.new()
	sprite.name = "CornerShelf_%d" % gx
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(gx * TILE_SIZE, 1 * TILE_SIZE - 10)
	decorations.add_child(sprite)


# ---------------------------------------------------------------------------
# Counter + the shelf under it
# ---------------------------------------------------------------------------

func _create_counter() -> void:
	var node = Node2D.new()
	node.name = "Counter"
	var w = TILE_SIZE * 2
	var h = TILE_SIZE + 6
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var wood_top = Color(0.48, 0.34, 0.20)
	var wood_body = Color(0.34, 0.23, 0.13)
	var wood_dark = Color(0.24, 0.16, 0.09)
	for y in range(h):
		for x in range(w):
			if y < 6:
				var grain = (x + y) % 7 < 2
				img.set_pixel(x, y, wood_top.darkened(0.1) if grain else wood_top)
			else:
				var panel = (x / 16) % 2
				img.set_pixel(x, y, wood_dark if panel == 0 else wood_body)
	var counter = Sprite2D.new()
	counter.centered = false
	counter.texture = ImageTexture.create_from_image(img)
	counter.position = Vector2(7 * TILE_SIZE, 5 * TILE_SIZE - 6)
	node.add_child(counter)

	var stack_img = Image.create(20, 12, false, Image.FORMAT_RGBA8)
	stack_img.fill(Color.TRANSPARENT)
	var spines = [Color(0.55, 0.20, 0.14), Color(0.24, 0.36, 0.30), Color(0.62, 0.50, 0.20)]
	for i in range(3):
		var by = 9 - i * 3
		for x in range(20):
			stack_img.set_pixel(x, by, spines[i])
			stack_img.set_pixel(x, by + 1, spines[i].darkened(0.2))
			stack_img.set_pixel(x, by + 2, spines[i])
	var string_color = Color(0.75, 0.68, 0.50)
	for x in [4, 15]:
		for y in range(0, 10):
			stack_img.set_pixel(x, y, string_color)
	var stack = Sprite2D.new()
	stack.centered = false
	stack.texture = ImageTexture.create_from_image(stack_img)
	stack.position = Vector2(7 * TILE_SIZE + 6, 5 * TILE_SIZE - 12)
	node.add_child(stack)

	# Small brass service bell, tarnished from years of use
	var bell_img = Image.create(12, 14, false, Image.FORMAT_RGBA8)
	bell_img.fill(Color.TRANSPARENT)
	var brass = Color(0.62, 0.52, 0.28)
	var brass_hi = Color(0.78, 0.68, 0.42)
	for y in range(12):
		var half_w = int(5.0 * sin(float(y) / 12.0 * PI)) + 1
		for x in range(6 - half_w, 6 + half_w):
			if x >= 0 and x < 12:
				bell_img.set_pixel(x, y, brass_hi if (x == 7 and y < 5) else brass)
	var bell = Sprite2D.new()
	bell.texture = ImageTexture.create_from_image(bell_img)
	bell.position = Vector2(7 * TILE_SIZE + 40, 5 * TILE_SIZE - 8)
	node.add_child(bell)

	decorations.add_child(node)


func _create_banned_shelf() -> void:
	# The real inventory — tucked under the counter, half-hidden by a
	# curtain. Nothing on it looks dangerous. That's rather the point.
	var img = Image.create(28, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var crate = Color(0.30, 0.20, 0.12)
	var crate_dark = Color(0.20, 0.13, 0.08)
	for y in range(16):
		for x in range(28):
			img.set_pixel(x, y, crate if (x + y) % 8 != 0 else crate_dark)
	var spines = [Color(0.35, 0.12, 0.12), Color(0.15, 0.15, 0.30), Color(0.30, 0.10, 0.25)]
	for i in range(3):
		var bx = 4 + i * 8
		for y in range(2, 12):
			img.set_pixel(bx, y, spines[i])
			img.set_pixel(bx + 1, y, spines[i].darkened(0.2))
	var sprite = Sprite2D.new()
	sprite.name = "BannedShelf"
	sprite.centered = false
	sprite.z_index = -1
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(6.5 * TILE_SIZE, 5 * TILE_SIZE + 6)
	decorations.add_child(sprite)


func _create_curtain() -> void:
	# A patched curtain half-drawn across the banned shelf's alcove —
	# not hidden, exactly. Just not advertised.
	var img = Image.create(18, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cloth = Color(0.36, 0.24, 0.30)
	var patch = Color(0.44, 0.32, 0.20)
	for y in range(20):
		for x in range(18):
			var fold = (x + y / 4) % 6 < 1
			img.set_pixel(x, y, cloth.darkened(0.15) if fold else cloth)
	for px in [3, 12]:
		for y in range(4, 8):
			for x in range(px, px + 4):
				if x < 18:
					img.set_pixel(x, y, patch)
	var sprite = Sprite2D.new()
	sprite.name = "BannedCurtain"
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.rotation = -0.08
	sprite.position = Vector2(7 * TILE_SIZE, 6 * TILE_SIZE - 2)
	decorations.add_child(sprite)


func _create_till_and_ledger() -> void:
	var img = Image.create(16, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var ledger = Color(0.42, 0.30, 0.18)
	var page = Color(0.85, 0.80, 0.65)
	for y in range(2, 9):
		for x in range(1, 15):
			img.set_pixel(x, y, page if y > 3 else ledger)
	for x in range(2, 13):
		if x % 2 == 0:
			img.set_pixel(x, 6, Color(0.35, 0.32, 0.25))
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(8 * TILE_SIZE + 2, 5 * TILE_SIZE - 10)
	decorations.add_child(sprite)


# ---------------------------------------------------------------------------
# Browsing table + floor stacks
# ---------------------------------------------------------------------------

func _create_browsing_table() -> void:
	var node = Node2D.new()
	node.name = "BrowsingTable"
	var w = TILE_SIZE * 2
	var h = TILE_SIZE
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var top = Color(0.46, 0.32, 0.19)
	var edge = Color(0.32, 0.22, 0.13)
	var leg = Color(0.26, 0.18, 0.10)
	for y in range(h):
		for x in range(w):
			var c = top
			if y < 4:
				c = top.lightened(0.12) if (x / 6) % 2 == 0 else top
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
	table.position = Vector2(7 * TILE_SIZE, 7 * TILE_SIZE)
	node.add_child(table)

	var piles = [Color(0.55, 0.20, 0.14), Color(0.24, 0.36, 0.30), Color(0.62, 0.50, 0.20), Color(0.30, 0.28, 0.46)]
	var rng = RandomNumberGenerator.new()
	rng.seed = 771
	for i in range(3):
		var pile_img = Image.create(14, 10, false, Image.FORMAT_RGBA8)
		pile_img.fill(Color.TRANSPARENT)
		for by in range(3):
			var col: Color = piles[rng.randi_range(0, piles.size() - 1)]
			for x in range(14):
				pile_img.set_pixel(x, 8 - by * 3, col)
				pile_img.set_pixel(x, 8 - by * 3 - 1, col.darkened(0.2))
		var pile = Sprite2D.new()
		pile.centered = false
		pile.texture = ImageTexture.create_from_image(pile_img)
		pile.position = Vector2(7 * TILE_SIZE + 4 + i * 16, 7 * TILE_SIZE - 8)
		node.add_child(pile)

	decorations.add_child(node)


func _create_book_stack(grid_pos: Vector2, variant: int) -> void:
	# Loose floor stacks — the shop's real character. No shelf could
	# keep up with what Aldrin brings in.
	var palettes = [
		[Color(0.55, 0.20, 0.14), Color(0.65, 0.26, 0.18)],
		[Color(0.24, 0.36, 0.30), Color(0.30, 0.44, 0.36)],
		[Color(0.62, 0.50, 0.20), Color(0.72, 0.60, 0.26)],
	]
	var pair: Array = palettes[variant % palettes.size()]
	var img = Image.create(18, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var book_count = 4 + variant % 2
	for i in range(book_count):
		var by = 14 - i * 3
		var lean = (i * 3) % 5
		for x in range(2 + lean, 16):
			img.set_pixel(x, by, pair[0] if i % 2 == 0 else pair[1])
			img.set_pixel(x, by - 1, (pair[0] if i % 2 == 0 else pair[1]).darkened(0.2))
	var sprite = Sprite2D.new()
	sprite.name = "BookStack_%d_%d" % [int(grid_pos.x * 10), int(grid_pos.y * 10)]
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = grid_pos * TILE_SIZE
	decorations.add_child(sprite)


# ---------------------------------------------------------------------------
# Wood stove
# ---------------------------------------------------------------------------

func _create_wood_stove() -> void:
	var node = Node2D.new()
	node.name = "WoodStove"
	var w = 26
	var h = 30
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var iron = Color(0.20, 0.19, 0.20)
	var iron_light = Color(0.30, 0.29, 0.30)
	var soot_door = Color(0.10, 0.09, 0.09)
	var pipe = Color(0.24, 0.23, 0.24)
	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, iron if (x + y) % 9 != 0 else iron_light)
	for y in range(10, 20):
		for x in range(6, 20):
			var dist = Vector2(x - 13, y - 15).length()
			if dist < 7:
				img.set_pixel(x, y, soot_door)
	for x in range(4, 6):
		for y in range(0, 10):
			img.set_pixel(x, y, pipe)
	var stove = Sprite2D.new()
	stove.centered = false
	stove.texture = ImageTexture.create_from_image(img)
	stove.position = Vector2(2 * TILE_SIZE, 8 * TILE_SIZE)
	node.add_child(stove)
	decorations.add_child(node)

	_stove_frames.clear()
	for f in range(2):
		var fimg = Image.create(14, 12, false, Image.FORMAT_RGBA8)
		_draw_stove_fire_frame(fimg, f)
		_stove_frames.append(ImageTexture.create_from_image(fimg))
	_stove_sprite = Sprite2D.new()
	_stove_sprite.name = "StoveFire"
	_stove_sprite.z_index = 5
	_stove_sprite.texture = _stove_frames[0]
	_stove_sprite.position = Vector2(2 * TILE_SIZE + 6, 8 * TILE_SIZE + 10)
	decorations.add_child(_stove_sprite)

	_stove_light = PointLight2D.new()
	_stove_light.position = Vector2(2 * TILE_SIZE + 13, 8 * TILE_SIZE + 15)
	_stove_light.color = Color(1.0, 0.58, 0.20, 0.85)
	_stove_light.energy = 0.6
	_stove_light.texture = _create_light_texture(100)
	decorations.add_child(_stove_light)


func _draw_stove_fire_frame(img: Image, frame: int) -> void:
	img.fill(Color.TRANSPARENT)
	var ofs = 1 if frame == 1 else -1
	var outer = Color(0.95, 0.55, 0.10)
	var mid = Color(0.98, 0.80, 0.20)
	var inner = Color(1.00, 0.96, 0.60)
	var cx = 7 + ofs
	for y in range(12):
		var row_pct = float(12 - y) / 12.0
		var half_w = int(5.0 * row_pct * row_pct) + 1
		for x in range(cx - half_w, cx + half_w):
			if x < 0 or x >= 14:
				continue
			var dx = abs(x - cx)
			if dx < 1 and row_pct > 0.4:
				img.set_pixel(x, y, inner)
			elif dx < 3:
				img.set_pixel(x, y, mid)
			else:
				img.set_pixel(x, y, outer)


func _animate_stove(delta: float) -> void:
	_stove_timer += delta
	if _stove_timer >= STOVE_SPEED:
		_stove_timer -= STOVE_SPEED
		_stove_frame = (_stove_frame + 1) % _stove_frames.size()
		if _stove_sprite and _stove_frames.size() > 0:
			_stove_sprite.texture = _stove_frames[_stove_frame]


func _flicker_stove_light(delta: float) -> void:
	_stove_time += delta
	if _stove_light:
		_stove_light.energy = 0.48 + 0.16 * sin(_stove_time * 6.2) + 0.06 * sin(_stove_time * 10.8)


# ---------------------------------------------------------------------------
# Reading cat + nook
# ---------------------------------------------------------------------------

func _create_reading_cat() -> void:
	_cat_frames.clear()
	for f in range(2):
		var img = Image.create(16, 10, false, Image.FORMAT_RGBA8)
		_draw_curled_cat_frame(img, f)
		_cat_frames.append(ImageTexture.create_from_image(img))
	_cat_sprite = Sprite2D.new()
	_cat_sprite.centered = false
	_cat_sprite.texture = _cat_frames[0]
	_cat_sprite.position = Vector2(3 * TILE_SIZE + 6, 9 * TILE_SIZE + 4)
	decorations.add_child(_cat_sprite)


func _draw_curled_cat_frame(img: Image, frame: int) -> void:
	img.fill(Color.TRANSPARENT)
	var fur = Color(0.42, 0.30, 0.20)
	var fur_dark = Color(0.30, 0.21, 0.14)
	var breathe = 1 if frame == 1 else 0
	for y in range(2 - breathe, 10):
		for x in range(0, 16):
			var cx = 8.0
			var cy = 6.0
			var rx = 7.0
			var ry = 3.5 + breathe * 0.5
			var dist = sqrt(pow((x - cx) / rx, 2) + pow((y - cy) / ry, 2))
			if dist < 1.0:
				img.set_pixel(x, y, fur_dark if dist > 0.75 else fur)
	img.set_pixel(3, 5 - breathe, fur_dark)
	img.set_pixel(13, 5 - breathe, fur_dark)


func _animate_cat(delta: float) -> void:
	_cat_timer += delta
	if _cat_timer >= CAT_SPEED:
		_cat_timer -= CAT_SPEED
		_cat_frame = (_cat_frame + 1) % _cat_frames.size()
		if _cat_sprite:
			_cat_sprite.texture = _cat_frames[_cat_frame]


func _create_reading_nook_chair() -> void:
	# The old regular's chair — worn smooth in one specific spot.
	var img = Image.create(20, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cloth = Color(0.45, 0.28, 0.22)
	var cloth_dark = Color(0.32, 0.19, 0.15)
	var wood = Color(0.30, 0.20, 0.12)
	for y in range(4, 20):
		for x in range(2, 18):
			img.set_pixel(x, y, cloth if (x + y) % 9 != 0 else cloth_dark)
	for y in range(0, 8):
		for x in range(2, 18):
			if y < 4:
				img.set_pixel(x, y, cloth_dark)
	for lx in [2, 3, 16, 17]:
		for y in range(20, 24):
			img.set_pixel(lx, y, wood)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(4 * TILE_SIZE, 8 * TILE_SIZE + 4)
	decorations.add_child(sprite)


# ---------------------------------------------------------------------------
# Lighting
# ---------------------------------------------------------------------------

func _create_mismatched_lamps() -> void:
	_create_lamp(Vector2(9, 5), Color(0.85, 0.55, 0.30), 0)
	_create_lamp(Vector2(5, 7), Color(0.55, 0.65, 0.85), 1)
	_create_lamp(Vector2(12, 7), Color(0.85, 0.75, 0.40), 2)
	_create_lamp(Vector2(2, 5), Color(0.75, 0.45, 0.55), 0)


func _create_lamp(grid_pos: Vector2, shade_color: Color, shape: int) -> void:
	# Three different silhouettes cycling by 'shape' so no two lamps
	# in the shop match — the visual joke is that Aldrin never threw
	# one out.
	var img = Image.create(12, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var brass = Color(0.60, 0.50, 0.30)
	var brass_dark = Color(0.42, 0.34, 0.18)
	for y in range(12, 18):
		img.set_pixel(5, y, brass_dark)
		img.set_pixel(6, y, brass)
	for x in range(4, 8):
		img.set_pixel(x, 18, brass_dark)
		img.set_pixel(x, 19, brass_dark)
	match shape:
		0:
			for y in range(2, 10):
				var half = 1 + (y - 2) / 2
				for x in range(6 - half, 7 + half):
					if x >= 0 and x < 12:
						img.set_pixel(x, y, shade_color)
		1:
			for y in range(2, 10):
				for x in range(3, 10):
					img.set_pixel(x, y, shade_color)
		_:
			for y in range(2, 10):
				var half = 4 - abs(y - 6)
				for x in range(6 - half, 7 + half):
					if x >= 0 and x < 12:
						img.set_pixel(x, y, shade_color)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = grid_pos * TILE_SIZE
	decorations.add_child(sprite)

	var glow = PointLight2D.new()
	glow.position = grid_pos * TILE_SIZE + Vector2(6, 6)
	glow.color = shade_color
	glow.energy = 0.34
	glow.texture = _create_light_texture(50)
	decorations.add_child(glow)
	_lamp_lights.append(glow)


func _breathe_lamps(delta: float) -> void:
	_light_time += delta
	for i in range(_lamp_lights.size()):
		var light = _lamp_lights[i]
		if is_instance_valid(light):
			light.energy = 0.30 + 0.06 * sin(_light_time * 1.1 + i * 1.3)


func _create_door_bell() -> void:
	var img = Image.create(10, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var brass = Color(0.65, 0.55, 0.30)
	var brass_hi = Color(0.80, 0.70, 0.44)
	for y in range(0, 8):
		var half_w = int(4.0 * sin(float(y) / 8.0 * PI)) + 1
		for x in range(5 - half_w, 5 + half_w):
			if x >= 0 and x < 10:
				img.set_pixel(x, y, brass_hi if (x == 6 and y < 4) else brass)
	for x in range(3, 7):
		img.set_pixel(x, 8, brass.darkened(0.2))
	_bell_sprite = Sprite2D.new()
	_bell_sprite.name = "DoorBell"
	_bell_sprite.texture = ImageTexture.create_from_image(img)
	_bell_sprite.position = Vector2(8 * TILE_SIZE + 4, 10 * TILE_SIZE - 4)
	decorations.add_child(_bell_sprite)


func _sway_bell(delta: float) -> void:
	_bell_time += delta
	if _bell_sprite:
		_bell_sprite.rotation = sin(_bell_time * 1.6) * 0.12


# ---------------------------------------------------------------------------
# Small furniture + signage
# ---------------------------------------------------------------------------

func _create_hand_lettered_signs() -> void:
	_create_sign("USED - CHEAP - HONEST", Vector2(5.5, 3.6), Color(0.70, 0.55, 0.30))
	_create_sign("NO REFUNDS (ASK WHY)", Vector2(9.8, 8.6), Color(0.70, 0.55, 0.30))


func _create_sign(text: String, grid_pos: Vector2, board_color: Color) -> void:
	var w = 8 + text.length() * 3
	var h = 12
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var board_dark = board_color.darkened(0.25)
	for y in range(h):
		for x in range(w):
			var frame_edge = x == 0 or y == 0 or x == w - 1 or y == h - 1
			img.set_pixel(x, y, board_dark if frame_edge else board_color)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = grid_pos * TILE_SIZE
	decorations.add_child(sprite)

	var label = Label.new()
	label.text = text
	label.position = grid_pos * TILE_SIZE + Vector2(3, 2)
	label.add_theme_font_size_override("font_size", 7)
	label.add_theme_color_override("font_color", Color(0.22, 0.16, 0.10))
	decorations.add_child(label)


func _create_price_chalkboard() -> void:
	var img = Image.create(28, 20, false, Image.FORMAT_RGBA8)
	var frame_wood = Color(0.36, 0.24, 0.14)
	var slate = Color(0.14, 0.16, 0.15)
	for y in range(20):
		for x in range(28):
			var edge = x < 2 or x >= 26 or y < 2 or y >= 18
			img.set_pixel(x, y, frame_wood if edge else slate)
	var chalk = Color(0.85, 0.85, 0.80)
	for line in range(3):
		var ly = 5 + line * 4
		for x in range(4, 22):
			if (x + line * 3) % 5 != 0:
				img.set_pixel(x, ly, chalk)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(5.3 * TILE_SIZE, 1.3 * TILE_SIZE)
	decorations.add_child(sprite)


func _create_step_ladder() -> void:
	var img = Image.create(14, 26, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var wood = Color(0.38, 0.25, 0.15)
	var wood_dark = Color(0.26, 0.17, 0.09)
	for rail_x in [1, 12]:
		for y in range(2, 26):
			img.set_pixel(rail_x, y, wood)
			img.set_pixel(rail_x + 1, y, wood_dark)
	var ry = 6
	while ry < 24:
		for x in range(1, 13):
			img.set_pixel(x, ry, wood_dark)
		ry += 6
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.rotation = 0.10
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(11.3 * TILE_SIZE, 2.5 * TILE_SIZE)
	decorations.add_child(sprite)


func _create_welcome_mat() -> void:
	var w = TILE_SIZE * 2
	var h = 14
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var mat = Color(0.40, 0.26, 0.16)
	var mat_dark = Color(0.28, 0.18, 0.11)
	for y in range(h):
		for x in range(w):
			var edge = x < 2 or x >= w - 2 or y < 2 or y >= h - 2
			img.set_pixel(x, y, mat_dark if edge or (x + y) % 6 == 0 else mat)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.z_index = -1
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(7 * TILE_SIZE, 10 * TILE_SIZE + 8)
	decorations.add_child(sprite)


func _create_coat_hooks() -> void:
	# A row of hooks by the door — one holds Aldrin's coat, the others
	# hold whatever customers forgot to take with them.
	var img = Image.create(30, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var wood = Color(0.34, 0.22, 0.13)
	var iron = Color(0.24, 0.23, 0.24)
	for x in range(30):
		img.set_pixel(x, 2, wood)
		img.set_pixel(x, 3, wood.darkened(0.15))
	for hx in [4, 14, 24]:
		for y in range(3, 8):
			img.set_pixel(hx, y, iron)
		img.set_pixel(hx + 2, 7, iron)
	var coat = Color(0.30, 0.32, 0.42)
	for y in range(4, 13):
		for x in range(2, 8):
			img.set_pixel(x, y, coat if (x + y) % 5 != 0 else coat.darkened(0.15))
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(10.5 * TILE_SIZE, 9.3 * TILE_SIZE)
	decorations.add_child(sprite)


func _create_section_placards() -> void:
	var sections = [
		{"text": "Fiction (Sort Of)", "x": 2.8},
		{"text": "History (Ours)", "x": 10.6},
	]
	for entry in sections:
		var label = Label.new()
		label.text = str(entry["text"])
		label.position = Vector2(float(entry["x"]) * TILE_SIZE, 0.4 * TILE_SIZE)
		label.add_theme_font_size_override("font_size", 8)
		label.add_theme_color_override("font_color", Color(0.85, 0.72, 0.50))
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		decorations.add_child(label)


func _create_cobweb() -> void:
	var size = 20
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var strand = Color(0.80, 0.75, 0.65, 0.5)
	for i in range(6):
		var ang = i * PI / 6.0
		var ex = int(size / 2.0 + cos(ang) * size / 2.0)
		var ey = int(size / 2.0 + sin(ang) * size / 2.0)
		_draw_thread_line(img, Vector2(0, 0), Vector2(ex, ey), strand)
	for r in [5, 10, 15]:
		for i in range(20):
			var ang = i * TAU / 20.0
			var px = int(cos(ang) * r)
			var py = int(sin(ang) * r)
			if px >= 0 and px < size and py >= 0 and py < size:
				img.set_pixel(px, py, strand)
	var sprite = Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(1 * TILE_SIZE, 1 * TILE_SIZE)
	decorations.add_child(sprite)


func _draw_thread_line(img: Image, a: Vector2, b: Vector2, c: Color) -> void:
	var steps = int(a.distance_to(b))
	for i in range(steps):
		var t = float(i) / float(max(steps, 1))
		var p = a.lerp(b, t)
		var px = int(p.x)
		var py = int(p.y)
		if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
			img.set_pixel(px, py, c)


func _create_dust_motes() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 4242
	_mote_base_positions.clear()
	for i in range(5):
		var img = Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.95, 0.88, 0.70, 0.5))
		var sprite = Sprite2D.new()
		sprite.texture = ImageTexture.create_from_image(img)
		var base = Vector2(6.0 + rng.randf() * 4.0, 4.0 + rng.randf() * 4.0) * TILE_SIZE
		sprite.position = base
		decorations.add_child(sprite)
		_mote_sprites.append(sprite)
		_mote_base_positions.append(base)


func _drift_motes(delta: float) -> void:
	_mote_time += delta
	for i in range(_mote_sprites.size()):
		var sprite = _mote_sprites[i]
		if is_instance_valid(sprite) and i < _mote_base_positions.size():
			var base: Vector2 = _mote_base_positions[i]
			sprite.position = base + Vector2(sin(_mote_time * 0.4 + i * 1.7) * 6.0, -fmod(_mote_time * 3.0 + i * 8.0, 24.0))


func _create_loose_bookmark() -> void:
	# A stray ribbon bookmark near the nook chair — the one nice thing
	# the old regular ever brought and never took back.
	var img = Image.create(4, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var ribbon = Color(0.55, 0.18, 0.20)
	for y in range(12):
		for x in range(4):
			img.set_pixel(x, y, ribbon)
	_page_sprite = Sprite2D.new()
	_page_sprite.texture = ImageTexture.create_from_image(img)
	_page_base = Vector2(5.5, 8.5) * TILE_SIZE
	_page_sprite.position = _page_base
	_page_sprite.rotation = 0.2
	decorations.add_child(_page_sprite)


func _drift_page(delta: float) -> void:
	_page_time += delta
	if _page_sprite:
		_page_sprite.position = _page_base + Vector2(sin(_page_time * 0.5) * 2.0, 0)
		_page_sprite.rotation = 0.2 + sin(_page_time * 0.4) * 0.08


# ---------------------------------------------------------------------------
# NPCs
# ---------------------------------------------------------------------------

func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	_create_aldrin(OverworldNPCScript)
	_create_nervous_student(OverworldNPCScript)
	_create_old_regular(OverworldNPCScript)


func _create_aldrin(NPCScript) -> void:
	# Quest-critical: npc_id MUST stay "aldrin_scriptura" — the 'Word
	# From the Capital' quest (Rowan, Harmonia) targets this exact id
	# to deliver her letter. Idle lines only; his accept/turn-in
	# dialogue for that quest is owned elsewhere.
	var aldrin = NPCScript.new()
	aldrin.npc_name = "Aldrin"
	aldrin.npc_type = "shopkeeper"
	aldrin.npc_id = "aldrin_scriptura"
	aldrin.position = Vector2(7 * TILE_SIZE, 4 * TILE_SIZE)
	aldrin.dialogue_lines = [
		"They log everything in this city. Every purchase, every borrowed book, every conversation that ran long enough to be worth remembering. I don't keep those records. Call it bad bookkeeping.",
		"Everything on these shelves is used, honest, and never reported to anyone who didn't ask nicely. That's the whole business model.",
		"You won't find half of this stock in the palace archive. Funny how that works out.",
		"I write letters home I don't send. Easier to love someone from a careful distance, some days.",
	]
	npcs.add_child(aldrin)


func _create_nervous_student(NPCScript) -> void:
	var student = NPCScript.new()
	student.npc_name = "Nervous Student"
	student.npc_type = "villager"
	student.position = Vector2(4 * TILE_SIZE, 6 * TILE_SIZE)
	student.dialogue_lines = [
		"I'm not buying anything. I'm just — browsing. Extremely normal browsing.",
		"*whispers* Is the shelf under the counter really — no. No, don't tell me here.",
		"If anyone asks, I was here for the almanac. The entirely unremarkable almanac.",
		"Aldrin says the Guild doesn't send people to check on a bookshop. I believe him about eleven hours out of every twelve.",
	]
	npcs.add_child(student)


func _create_old_regular(NPCScript) -> void:
	var regular = NPCScript.new()
	regular.npc_name = "Old Regular"
	regular.npc_type = "elder"
	regular.position = Vector2(4 * TILE_SIZE, 9 * TILE_SIZE)
	regular.dialogue_lines = [
		"Same chair, same corner, forty years running. Aldrin's father used to shoo me out at closing. Aldrin just leaves the door unlocked.",
		"I've read everything in this shop twice over. Still come back. It was never really about the books.",
		"*nodding off by the stove* ...five more pages...",
		"This city keeps a record of everything except the things worth remembering. This shop's the opposite. Suits me fine.",
	]
	npcs.add_child(regular)


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
	exit.target_spawn = "bookshop_exit"
	exit.require_interaction = false
	exit.position = Vector2(7.5 * TILE_SIZE, 11.5 * TILE_SIZE)
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
