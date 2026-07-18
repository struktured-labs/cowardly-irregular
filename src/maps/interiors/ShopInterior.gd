extends Node2D
class_name ShopInterior

## ShopInterior — Parameterized 16-bit JRPG shop interior.
## Handles ITEM, BLACK_MAGIC, WHITE_MAGIC, and BLACKSMITH shops
## by branching on `shop_type`. All art is procedural via Image.set_pixel.

signal transition_triggered(target_map: String, target_spawn: String)
signal area_transition(target_map: String, target_spawn: String)
signal wares_requested()

enum ShopType { ITEM = 0, BLACK_MAGIC = 1, WHITE_MAGIC = 2, BLACKSMITH = 3 }

@export var shop_type: int = ShopType.ITEM
@export var keeper_name: String = "Shopkeeper"
@export var shop_name: String = "Shop"

const TILE_SIZE: int = 32
const MAP_WIDTH: int  = 16
const MAP_HEIGHT: int = 12

## Scene nodes
var tilemap: TileMapLayer
var player: Node2D
var camera: Camera2D
var npcs: Node2D
var transitions: Node2D
var decorations: Node2D
var controller: Node

## Spawn points
var spawn_points: Dictionary = {
	"entrance": Vector2(8, 10),
	"counter":  Vector2(5, 3),
}

## Layout — 16 cols × 12 rows
## W = wall, . = floor, C = counter, S = shelf/display, D = entrance door
const SHOP_LAYOUT = [
	"WWWWWWWWWWWWWWWW",
	"W..............W",
	"W.SSS......SSS.W",
	"W.SSS..CCC.SSS.W",
	"W.SSS..CCC.SSS.W",
	"W.............WW",
	"W.SSS......SSS.W",
	"W.SSS......SSS.W",
	"W..............W",
	"W..............W",
	"W..............W",
	"WWWWWWWDDWWWWWWW",
]

## Per-type palettes — set in _ready based on shop_type
var _pal_floor_a:  Color
var _pal_floor_b:  Color
var _pal_wall_a:   Color
var _pal_wall_b:   Color
var _pal_wall_c:   Color
var _pal_counter:  Color
var _pal_shelf:    Color
var _pal_accent:   Color
var _pal_light:    Color

## Animated elements
var _cauldron_sprite: Sprite2D  # BLACK_MAGIC only
var _cauldron_frames: Array[ImageTexture] = []
var _cauldron_frame: int = 0
var _cauldron_timer: float = 0.0
const CAULDRON_SPEED: float = 0.18

var _forge_sprite: Sprite2D   # BLACKSMITH only
var _forge_frames: Array[ImageTexture] = []
var _forge_frame: int = 0
var _forge_timer: float = 0.0
const FORGE_SPEED: float = 0.14


## Wares browse state
var _wares_layer: CanvasLayer = null


func _ready() -> void:
	_pick_palette()
	_setup_tilemap()
	_setup_decorations()
	_setup_npcs()
	# msg 2764: NPC-vs-furniture sweep (shared with BaseInterior + InnInterior).
	InteriorPlacementSweep.sweep(self, npcs, decorations, SHOP_LAYOUT, "shop_interior")
	_create_browse_interactable()
	_setup_transitions()
	_setup_player()
	_setup_camera()
	_setup_controller()

	if SoundManager:
		if SoundManager.has_method("play_area_music"):
			# Try shop music, fall back to village
			SoundManager.play_area_music("interior_shop")


func _process(delta: float) -> void:
	match shop_type:
		ShopType.BLACK_MAGIC:
			_animate_cauldron(delta)
		ShopType.BLACKSMITH:
			_animate_forge(delta)


# ---------------------------------------------------------------------------
# Palette selection
# ---------------------------------------------------------------------------

func _pick_palette() -> void:
	match shop_type:
		ShopType.ITEM:
			_pal_floor_a  = Color(0.78, 0.68, 0.52)
			_pal_floor_b  = Color(0.68, 0.58, 0.42)
			_pal_wall_a   = Color(0.80, 0.74, 0.65)
			_pal_wall_b   = Color(0.68, 0.62, 0.52)
			_pal_wall_c   = Color(0.58, 0.52, 0.42)
			_pal_counter  = Color(0.55, 0.38, 0.20)
			_pal_shelf    = Color(0.48, 0.34, 0.18)
			_pal_accent   = Color(0.35, 0.55, 0.28)
			_pal_light    = Color(1.0, 0.96, 0.85)
		ShopType.BLACK_MAGIC:
			_pal_floor_a  = Color(0.28, 0.22, 0.32)
			_pal_floor_b  = Color(0.22, 0.17, 0.27)
			_pal_wall_a   = Color(0.30, 0.24, 0.40)
			_pal_wall_b   = Color(0.22, 0.16, 0.30)
			_pal_wall_c   = Color(0.16, 0.12, 0.22)
			_pal_counter  = Color(0.32, 0.22, 0.18)
			_pal_shelf    = Color(0.24, 0.18, 0.14)
			_pal_accent   = Color(0.60, 0.25, 0.75)
			_pal_light    = Color(0.60, 0.35, 0.90)
		ShopType.WHITE_MAGIC:
			_pal_floor_a  = Color(0.92, 0.90, 0.86)
			_pal_floor_b  = Color(0.82, 0.80, 0.76)
			_pal_wall_a   = Color(0.90, 0.87, 0.80)
			_pal_wall_b   = Color(0.78, 0.75, 0.68)
			_pal_wall_c   = Color(0.68, 0.65, 0.58)
			_pal_counter  = Color(0.72, 0.65, 0.50)
			_pal_shelf    = Color(0.65, 0.58, 0.42)
			_pal_accent   = Color(0.90, 0.82, 0.42)
			_pal_light    = Color(0.95, 0.98, 1.00)
		ShopType.BLACKSMITH:
			_pal_floor_a  = Color(0.42, 0.40, 0.38)
			_pal_floor_b  = Color(0.32, 0.30, 0.28)
			_pal_wall_a   = Color(0.50, 0.46, 0.42)
			_pal_wall_b   = Color(0.38, 0.34, 0.30)
			_pal_wall_c   = Color(0.28, 0.24, 0.20)
			_pal_counter  = Color(0.32, 0.26, 0.20)
			_pal_shelf    = Color(0.28, 0.22, 0.16)
			_pal_accent   = Color(0.90, 0.55, 0.20)
			_pal_light    = Color(1.0, 0.60, 0.20)


# ---------------------------------------------------------------------------
# Tilemap
# ---------------------------------------------------------------------------

func _setup_tilemap() -> void:
	tilemap = TileMapLayer.new()
	tilemap.name = "TileMapLayer"
	add_child(tilemap)

	var tileset = TileSet.new()
	tileset.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Source 0 — floor
	var floor_src = TileSetAtlasSource.new()
	var floor_img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	_draw_floor_tile(floor_img)
	floor_src.texture = ImageTexture.create_from_image(floor_img)
	floor_src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	floor_src.create_tile(Vector2i(0, 0))
	tileset.add_source(floor_src, 0)

	# Source 1 — wall
	var wall_src = TileSetAtlasSource.new()
	var wall_img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	_draw_wall_tile(wall_img)
	wall_src.texture = ImageTexture.create_from_image(wall_img)
	wall_src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	wall_src.create_tile(Vector2i(0, 0))
	tileset.add_source(wall_src, 1)

	# Source 2 — counter
	var counter_src = TileSetAtlasSource.new()
	var counter_img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	_draw_counter_tile(counter_img)
	counter_src.texture = ImageTexture.create_from_image(counter_img)
	counter_src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	counter_src.create_tile(Vector2i(0, 0))
	tileset.add_source(counter_src, 2)

	# Source 3 — shelf back panel
	var shelf_src = TileSetAtlasSource.new()
	var shelf_img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	_draw_shelf_tile(shelf_img)
	shelf_src.texture = ImageTexture.create_from_image(shelf_img)
	shelf_src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	shelf_src.create_tile(Vector2i(0, 0))
	tileset.add_source(shelf_src, 3)

	tilemap.tile_set = tileset
	_generate_floor()


func _draw_floor_tile(img: Image) -> void:
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			match shop_type:
				ShopType.ITEM, ShopType.WHITE_MAGIC:
					# Stone flag floor — alternating squares with mortar
					var block_x = x / 16
					var block_y = y / 16
					var mortar_h = y % 16 < 2
					var mortar_v = x % 16 < 2
					if mortar_h or mortar_v:
						img.set_pixel(x, y, _pal_floor_b.darkened(0.15))
					else:
						var checker = (block_x + block_y) % 2
						img.set_pixel(x, y, _pal_floor_a if checker == 0 else _pal_floor_b)
				ShopType.BLACK_MAGIC:
					# Dark wood planks with subtle purple grain
					var plank = y / 8
					var gap = y % 8 < 2
					var grain = (x + plank * 3) % 5 == 0
					var c = _pal_floor_b if gap else _pal_floor_a
					if grain:
						c = c.lerp(_pal_accent, 0.08)
					img.set_pixel(x, y, c)
				ShopType.BLACKSMITH:
					# Metal grate pattern
					var grate_h = y % 8 < 2
					var grate_v = x % 8 < 2
					if grate_h or grate_v:
						img.set_pixel(x, y, _pal_floor_b.darkened(0.2))
					else:
						img.set_pixel(x, y, _pal_floor_a)


func _draw_wall_tile(img: Image) -> void:
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			match shop_type:
				ShopType.ITEM, ShopType.WHITE_MAGIC:
					# Dressed stone with horizontal courses
					var course = y / 10
					var mortar_h = y % 10 < 2
					var offset = 8 if course % 2 == 0 else 0
					var mortar_v = (x + offset) % 18 < 2
					if mortar_h or mortar_v:
						img.set_pixel(x, y, _pal_wall_c)
					else:
						var hi = (course + (x + offset) / 18) % 3 == 0
						img.set_pixel(x, y, _pal_wall_a if hi else _pal_wall_b)
				ShopType.BLACK_MAGIC:
					# Dark purple rough-hewn stone
					var course = y / 8
					var block = (x + course * 5) / 14
					var mh = y % 8 < 2
					var mv = (x + course * 5) % 14 < 2
					if mh or mv:
						img.set_pixel(x, y, _pal_wall_c)
					else:
						var noise = (x * 5 + y * 3) % 7 == 0
						var c = _pal_wall_a.lerp(_pal_accent, 0.06) if noise else _pal_wall_b
						img.set_pixel(x, y, c)
				ShopType.BLACKSMITH:
					# Rough stone with soot staining
					var course = y / 12
					var block = (x + course * 7) / 18
					var mh = y % 12 < 2
					var mv = (x + course * 7) % 18 < 2
					if mh or mv:
						img.set_pixel(x, y, _pal_wall_c.darkened(0.2))
					else:
						var soot = (x * 7 + y * 11) % 13 < 2
						var c = _pal_wall_b if soot else _pal_wall_a
						img.set_pixel(x, y, c)


func _draw_counter_tile(img: Image) -> void:
	var top  = _pal_counter.lightened(0.18)
	var body = _pal_counter
	var dark = _pal_counter.darkened(0.20)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			if y < 6:
				# Counter surface with subtle grain
				var grain = (x + y) % 9 < 2
				img.set_pixel(x, y, dark if grain else top)
			else:
				var panel = (x / 16) % 2
				img.set_pixel(x, y, dark if panel == 0 else body)


func _draw_shelf_tile(img: Image) -> void:
	var back = _pal_shelf
	var edge = _pal_shelf.lightened(0.15)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Shelf back-panel with plank lines
			var plank = y / 10
			var gap = y % 10 < 2
			img.set_pixel(x, y, edge if gap else back)


func _generate_floor() -> void:
	for y in range(MAP_HEIGHT):
		for x in range(MAP_WIDTH):
			var ch = SHOP_LAYOUT[y][x]
			match ch:
				"W":
					tilemap.set_cell(Vector2i(x, y), 1, Vector2i(0, 0))
				"C":
					tilemap.set_cell(Vector2i(x, y), 2, Vector2i(0, 0))
				"S":
					tilemap.set_cell(Vector2i(x, y), 3, Vector2i(0, 0))
				_:
					tilemap.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))


# ---------------------------------------------------------------------------
# Light texture helper
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# Decorations — dispatch by type
# ---------------------------------------------------------------------------

func _setup_decorations() -> void:
	decorations = Node2D.new()
	decorations.name = "Decorations"
	add_child(decorations)

	_create_counter_dressing()
	_create_hanging_sign()
	_create_shelf_goods()
	_create_lighting()

	match shop_type:
		ShopType.ITEM:        _decorate_item_shop()
		ShopType.BLACK_MAGIC: _decorate_black_magic_shop()
		ShopType.WHITE_MAGIC: _decorate_white_magic_shop()
		ShopType.BLACKSMITH:  _decorate_blacksmith_shop()


func _create_counter_dressing() -> void:
	# Counter trim sprite — a 3-tile wide polished top with type-specific inlay
	var trim = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 3, 10, false, Image.FORMAT_RGBA8)
	var top_color = _pal_counter.lightened(0.25)
	var inlay = _pal_accent

	for y in range(10):
		for x in range(TILE_SIZE * 3):
			if y < 3:
				# Surface highlight
				img.set_pixel(x, y, top_color)
			else:
				# Inlay stripe repeating
				var stripe = (x / 8) % 4
				var c = inlay if stripe == 0 else top_color.darkened(0.1)
				img.set_pixel(x, y, c)

	trim.texture = ImageTexture.create_from_image(img)
	trim.position = Vector2(5.5 * TILE_SIZE, 2.8 * TILE_SIZE)
	decorations.add_child(trim)


func _create_hanging_sign() -> void:
	# Sign board hanging above the counter
	var sign = Sprite2D.new()
	var sw = TILE_SIZE * 4
	var sh = TILE_SIZE
	var img = Image.create(sw, sh, false, Image.FORMAT_RGBA8)

	var board  := Color(0.48, 0.34, 0.18)
	var board_hi := Color(0.60, 0.44, 0.24)
	var text_col = _pal_accent.lightened(0.2)

	# Board background
	for y in range(sh):
		for x in range(sw):
			var grain = (x / 14) % 2 == 0
			img.set_pixel(x, y, board_hi if grain else board)

	# Border
	for x in range(sw):
		img.set_pixel(x, 0, board.darkened(0.3))
		img.set_pixel(x, sh - 1, board.darkened(0.3))
	for y in range(sh):
		img.set_pixel(0, y, board.darkened(0.3))
		img.set_pixel(sw - 1, y, board.darkened(0.3))

	# Chains (4px wide, 4px tall links)
	for chain_x in [6, sw - 8]:
		for y in range(0, 8, 4):
			for x in range(chain_x, chain_x + 4):
				img.set_pixel(x, y, Color(0.55, 0.52, 0.48))
				if y + 1 < sh:
					img.set_pixel(x, y + 1, Color(0.55, 0.52, 0.48))

	sign.texture = ImageTexture.create_from_image(img)
	sign.position = Vector2(6.0 * TILE_SIZE, 0.5 * TILE_SIZE)
	decorations.add_child(sign)

	# Shop name label on sign
	var label = Label.new()
	label.text = shop_name
	label.position = Vector2(6.0 * TILE_SIZE, 0.6 * TILE_SIZE)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", _pal_accent.lightened(0.3))
	decorations.add_child(label)


func _create_shelf_goods() -> void:
	# Draw goods on the shelf areas based on shop type
	# Left shelves: x=1..3 rows, Right shelves: x=12..14 rows
	for side in range(2):
		var sx = 2.5 * TILE_SIZE if side == 0 else 12.5 * TILE_SIZE
		for shelf_row in range(2):
			var sy = float(2 + shelf_row * 5) * TILE_SIZE + 4.0
			_draw_shelf_row(sx, sy)


func _draw_shelf_row(sx: float, sy: float) -> void:
	var goods = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 3, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	match shop_type:
		ShopType.ITEM:
			_draw_potion_row(img)
		ShopType.BLACK_MAGIC:
			_draw_spell_tome_row(img)
		ShopType.WHITE_MAGIC:
			_draw_scroll_row(img)
		ShopType.BLACKSMITH:
			_draw_weapon_rack_row(img)

	goods.texture = ImageTexture.create_from_image(img)
	goods.position = Vector2(sx, sy)
	decorations.add_child(goods)


func _draw_potion_row(img: Image) -> void:
	var colors = [
		Color(0.80, 0.25, 0.25),  # Red potion
		Color(0.25, 0.60, 0.35),  # Green antidote
		Color(0.30, 0.45, 0.85),  # Blue ether
		Color(0.75, 0.65, 0.20),  # Gold tonic
		Color(0.60, 0.28, 0.65),  # Purple remedy
	]
	var total = img.get_width()
	for i in range(5):
		var bx = 4 + i * 18
		if bx + 10 >= total:
			break
		var c = colors[i % colors.size()]
		# Bottle body
		for y in range(6, 18):
			for x in range(bx, bx + 10):
				img.set_pixel(x, y, c)
		# Bottle neck
		for y in range(2, 6):
			for x in range(bx + 3, bx + 7):
				img.set_pixel(x, y, c.darkened(0.2))
		# Cork
		img.set_pixel(bx + 3, 1, Color(0.65, 0.50, 0.30))
		img.set_pixel(bx + 4, 1, Color(0.65, 0.50, 0.30))
		img.set_pixel(bx + 5, 1, Color(0.65, 0.50, 0.30))
		# Highlight
		img.set_pixel(bx + 2, 8, Color(1, 1, 1, 0.4))


func _draw_spell_tome_row(img: Image) -> void:
	var colors = [
		Color(0.20, 0.12, 0.35),
		Color(0.35, 0.08, 0.45),
		Color(0.10, 0.15, 0.40),
	]
	var total = img.get_width()
	for i in range(4):
		var bx = 6 + i * 22
		if bx + 16 >= total:
			break
		var c = colors[i % colors.size()]
		# Book spine
		for y in range(2, 18):
			for x in range(bx, bx + 14):
				img.set_pixel(x, y, c)
		# Gilt title bar
		for x in range(bx + 2, bx + 12):
			for y in range(5, 8):
				img.set_pixel(x, y, Color(0.70, 0.58, 0.18))
		# Rune glyphs (dot pattern)
		for rune in range(3):
			var rx = bx + 3 + rune * 3
			img.set_pixel(rx, 10, _pal_accent)
			img.set_pixel(rx, 12, _pal_accent)


func _draw_scroll_row(img: Image) -> void:
	var parchment := Color(0.92, 0.88, 0.72)
	var ribbon    := Color(0.75, 0.20, 0.20)
	var gold_band := Color(0.80, 0.70, 0.30)
	var total = img.get_width()
	for i in range(4):
		var bx = 8 + i * 22
		if bx + 14 >= total:
			break
		# Scroll roll
		for y in range(3, 17):
			for x in range(bx, bx + 12):
				img.set_pixel(x, y, parchment)
		# End caps (rounded)
		for x in range(bx, bx + 12):
			img.set_pixel(x, 3, gold_band)
			img.set_pixel(x, 16, gold_band)
		# Ribbon tie
		img.set_pixel(bx + 5, 9, ribbon)
		img.set_pixel(bx + 6, 9, ribbon)
		img.set_pixel(bx + 5, 10, ribbon)
		img.set_pixel(bx + 6, 10, ribbon)


func _draw_weapon_rack_row(img: Image) -> void:
	var blade  := Color(0.72, 0.75, 0.80)  # Steel
	var hilt   := Color(0.55, 0.42, 0.18)  # Bronze hilt
	var wrap   := Color(0.35, 0.22, 0.12)  # Leather wrap
	var total = img.get_width()
	# Draw swords leaning at angle
	for i in range(3):
		var bx = 12 + i * 28
		if bx + 12 >= total:
			break
		# Blade (vertical)
		for y in range(1, 14):
			img.set_pixel(bx + 4, y, blade)
			img.set_pixel(bx + 5, y, blade.lightened(0.1))
		# Crossguard
		for x in range(bx, bx + 12):
			img.set_pixel(x, 13, hilt)
		# Grip
		for y in range(13, 18):
			img.set_pixel(bx + 4, y, wrap)
			img.set_pixel(bx + 5, y, wrap)
		# Pommel
		for x in range(bx + 3, bx + 7):
			img.set_pixel(x, 18, hilt)


# ---------------------------------------------------------------------------
# Per-type decoration
# ---------------------------------------------------------------------------

func _decorate_item_shop() -> void:
	# Barrel cluster at grid x=13..14, y=8..9
	_create_barrel_cluster(Vector2(13.5 * TILE_SIZE, 8 * TILE_SIZE))

	# Herb window box at x=1, y=1 (inside window on west wall)
	_create_herb_box(Vector2(1.2 * TILE_SIZE, 1.0 * TILE_SIZE))

	# Hanging dried herbs bunches
	for i in range(3):
		_create_herb_bunch(Vector2((4.0 + i * 4) * TILE_SIZE, 0.5 * TILE_SIZE))


func _create_barrel_cluster(pos: Vector2) -> void:
	var node = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 2, TILE_SIZE * 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var wood_stave := Color(0.50, 0.34, 0.18)
	var wood_dark  := Color(0.38, 0.25, 0.12)
	var hoop       := Color(0.50, 0.48, 0.44)

	# Two barrels
	for b in range(2):
		var bx = 4 + b * 32
		# Barrel body (ellipse-ish rectangle)
		for y in range(8, 52):
			var width = 22 if y > 18 and y < 42 else 18
			for x in range(bx, bx + width):
				var stave = (x - bx) / 4 % 2
				img.set_pixel(x, y, wood_stave if stave == 0 else wood_dark)
		# Hoops
		for hy in [12, 28, 44]:
			for x in range(bx, bx + 22):
				img.set_pixel(x, hy, hoop)

	node.texture = ImageTexture.create_from_image(img)
	node.position = pos
	decorations.add_child(node)


func _create_herb_box(pos: Vector2) -> void:
	var box = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 2, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var soil     := Color(0.30, 0.22, 0.14)
	var box_wood := Color(0.48, 0.34, 0.18)
	var green_a  := Color(0.25, 0.55, 0.22)
	var green_b  := Color(0.35, 0.65, 0.28)
	var flower   := Color(0.85, 0.75, 0.22)

	# Box planks
	for y in range(18, 32):
		for x in range(0, TILE_SIZE * 2):
			img.set_pixel(x, y, box_wood if (x / 8) % 2 == 0 else box_wood.darkened(0.15))

	# Soil
	for y in range(12, 18):
		for x in range(2, TILE_SIZE * 2 - 2):
			img.set_pixel(x, y, soil)

	# Herb sprigs
	for sp in range(7):
		var sx2 = 5 + sp * 8
		for y in range(2, 12):
			img.set_pixel(sx2, y, green_a if y % 2 == 0 else green_b)
		if sp % 3 == 1:
			img.set_pixel(sx2 - 1, 4, flower)
			img.set_pixel(sx2 + 1, 4, flower)

	box.texture = ImageTexture.create_from_image(img)
	box.position = pos
	decorations.add_child(box)


func _create_herb_bunch(pos: Vector2) -> void:
	var bunch = Sprite2D.new()
	var img = Image.create(12, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var green  := Color(0.30, 0.55, 0.22)
	var stem   := Color(0.50, 0.40, 0.20)
	var tie    := Color(0.65, 0.45, 0.18)

	# Hanging from top, stems upward
	for i in range(5):
		var bx = 1 + i * 2
		for y in range(2, 16):
			if bx < 12:
				img.set_pixel(bx, y, stem if y > 12 else green)

	# Tie band
	for x in range(0, 12):
		img.set_pixel(x, 16, tie)
		img.set_pixel(x, 17, tie)

	# Hanging string
	for y in range(0, 2):
		img.set_pixel(5, y, Color(0.55, 0.48, 0.32))

	bunch.texture = ImageTexture.create_from_image(img)
	bunch.position = pos
	decorations.add_child(bunch)


func _decorate_black_magic_shop() -> void:
	# Bubbling cauldron jars on shelves (animated)
	_setup_cauldron_anim()

	# Raven on a perch at x=13, y=6
	_create_raven(Vector2(13.5 * TILE_SIZE, 6 * TILE_SIZE))

	# Glowing purple orb centerpiece at x=8, y=5
	_create_magic_orb(Vector2(8 * TILE_SIZE, 5.5 * TILE_SIZE), _pal_accent)

	# Tome pile at x=1, y=8
	_create_tome_pile(Vector2(1.5 * TILE_SIZE, 8 * TILE_SIZE))

	# Eerie lighting
	var orb_light = PointLight2D.new()
	orb_light.position = Vector2(8 * TILE_SIZE, 5.5 * TILE_SIZE)
	orb_light.color = Color(0.50, 0.20, 0.80, 0.7)
	orb_light.energy = 0.8
	orb_light.texture = _create_light_texture(120)
	decorations.add_child(orb_light)


func _setup_cauldron_anim() -> void:
	_cauldron_sprite = Sprite2D.new()
	_cauldron_sprite.name = "CauldronBubble"
	_cauldron_sprite.z_index = 5
	_cauldron_sprite.position = Vector2(8 * TILE_SIZE, 8 * TILE_SIZE)
	add_child(_cauldron_sprite)

	_cauldron_frames.clear()
	for f in range(4):
		var img = Image.create(TILE_SIZE, TILE_SIZE + 8, false, Image.FORMAT_RGBA8)
		_draw_cauldron_frame(img, f)
		_cauldron_frames.append(ImageTexture.create_from_image(img))

	if _cauldron_frames.size() > 0:
		_cauldron_sprite.texture = _cauldron_frames[0]


func _draw_cauldron_frame(img: Image, frame: int) -> void:
	img.fill(Color.TRANSPARENT)
	var cast_iron    := Color(0.22, 0.20, 0.22)
	var cast_hi      := Color(0.35, 0.33, 0.35)
	var brew_color   := Color(0.30, 0.08, 0.50)
	var brew_hi      := Color(0.55, 0.25, 0.75)
	var bubble_col   := Color(0.65, 0.35, 0.85)
	var steam        := Color(0.55, 0.35, 0.65)

	# Cauldron body
	for y in range(16, TILE_SIZE + 4):
		var ry = float(y - 16) / float(TILE_SIZE - 12)
		var half_w = int(14.0 * sin(ry * PI)) + 2
		var cx2 = TILE_SIZE / 2
		for x in range(cx2 - half_w, cx2 + half_w):
			if x >= 0 and x < TILE_SIZE:
				var hi = (x == cx2 - half_w + 2)
				img.set_pixel(x, y, cast_hi if hi else cast_iron)

	# Brew surface
	for x in range(4, TILE_SIZE - 4):
		for y in range(16, 22):
			img.set_pixel(x, y, brew_color)

	# Bubbles (different per frame)
	var bubble_offsets = [[6, 14], [18, 14], [12, 14], [8, 14]]
	var bubs = bubble_offsets[frame % 4]
	for bx in bubs:
		if bx < TILE_SIZE:
			for y in range(12, 16):
				img.set_pixel(bx, y, bubble_col)
			img.set_pixel(bx - 1, 14, bubble_col)
			img.set_pixel(bx + 1, 14, bubble_col)

	# Steam wisps above cauldron
	for s in range(2):
		var sx2 = 8 + s * 16 + (frame % 2) * 2
		for y in range(4, 12):
			if sx2 >= 0 and sx2 < TILE_SIZE:
				var alpha = float(12 - y) / 8.0
				img.set_pixel(sx2, y, Color(steam.r, steam.g, steam.b))

	# Legs (tripod)
	for leg in range(3):
		var lx = 6 + leg * 10
		for y in range(TILE_SIZE + 1, TILE_SIZE + 8):
			if lx < TILE_SIZE:
				img.set_pixel(lx, y, cast_iron)


func _animate_cauldron(delta: float) -> void:
	_cauldron_timer += delta
	if _cauldron_timer >= CAULDRON_SPEED:
		_cauldron_timer -= CAULDRON_SPEED
		_cauldron_frame = (_cauldron_frame + 1) % _cauldron_frames.size()
		if _cauldron_sprite and _cauldron_frames.size() > 0:
			_cauldron_sprite.texture = _cauldron_frames[_cauldron_frame]


func _create_raven(pos: Vector2) -> void:
	var raven = Sprite2D.new()
	var img = Image.create(20, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var black     := Color(0.10, 0.09, 0.12)
	var black_hi  := Color(0.25, 0.22, 0.30)
	var beak      := Color(0.22, 0.20, 0.15)
	var eye_col   := Color(0.85, 0.20, 0.20)
	var perch_c   := Color(0.38, 0.26, 0.14)

	# Perch rod
	for x in range(0, 20):
		img.set_pixel(x, 18, perch_c)
		img.set_pixel(x, 19, perch_c)

	# Body
	for y in range(8, 18):
		for x in range(4, 16):
			img.set_pixel(x, y, black_hi if (x + y) % 5 == 0 else black)

	# Head
	for y in range(2, 9):
		for x in range(7, 15):
			img.set_pixel(x, y, black)

	# Beak
	img.set_pixel(6, 5, beak)
	img.set_pixel(5, 6, beak)

	# Eye
	img.set_pixel(9, 4, eye_col)

	# Tail feathers
	for y in range(16, 22):
		img.set_pixel(14 + (y - 16), y, black)

	raven.texture = ImageTexture.create_from_image(img)
	raven.position = pos
	decorations.add_child(raven)


func _create_magic_orb(pos: Vector2, orb_color: Color) -> void:
	var orb = Sprite2D.new()
	var size = 28
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var center = size / 2
	for y in range(size):
		for x in range(size):
			var dist = Vector2(x - center, y - center).length()
			if dist < center:
				var t = 1.0 - dist / center
				var glow = orb_color.lerp(Color.WHITE, t * 0.5)
				glow.a = t * t
				img.set_pixel(x, y, glow)

	orb.texture = ImageTexture.create_from_image(img)
	orb.position = pos
	decorations.add_child(orb)

	# Pedestal
	var pedestal = Sprite2D.new()
	var pd_img = Image.create(20, 14, false, Image.FORMAT_RGBA8)
	pd_img.fill(Color.TRANSPARENT)
	var stone_c := Color(0.55, 0.50, 0.46)
	for y in range(4, 14):
		var pw2 = 10 - abs(y - 4)
		for x in range(10 - pw2, 10 + pw2):
			pd_img.set_pixel(x, y, stone_c)
	for x in range(0, 20):
		pd_img.set_pixel(x, 12, stone_c.lightened(0.1))
		pd_img.set_pixel(x, 13, stone_c.lightened(0.1))
	pedestal.texture = ImageTexture.create_from_image(pd_img)
	pedestal.position = pos + Vector2(-4, 12)
	decorations.add_child(pedestal)


func _create_tome_pile(pos: Vector2) -> void:
	var pile = Sprite2D.new()
	var img = Image.create(TILE_SIZE + 8, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var colors = [
		Color(0.20, 0.12, 0.35),
		Color(0.35, 0.08, 0.40),
		Color(0.12, 0.18, 0.38),
		Color(0.28, 0.10, 0.45),
	]
	# Books in a pile (overlapping)
	for i in range(4):
		var by2 = TILE_SIZE - 8 - i * 7
		var bx2 = 2 + (i % 2) * 4
		var bw2 = 28 + (i % 2) * 6
		var bh2 = 8
		for y in range(by2, by2 + bh2):
			for x in range(bx2, bx2 + bw2):
				if x < TILE_SIZE + 8 and y < TILE_SIZE:
					img.set_pixel(x, y, colors[i])
		# Spine highlight
		for y in range(by2, by2 + bh2):
			if bx2 < TILE_SIZE + 8:
				img.set_pixel(bx2, y, colors[i].lightened(0.2))

	pile.texture = ImageTexture.create_from_image(img)
	pile.position = pos
	decorations.add_child(pile)


func _decorate_white_magic_shop() -> void:
	# Crystal centerpiece at x=8, y=5
	_create_magic_orb(Vector2(8 * TILE_SIZE, 5 * TILE_SIZE), Color(0.90, 0.98, 1.0))

	# Stained-glass window on north wall (visual only at x=8, y=1)
	_create_stained_glass(Vector2(7.5 * TILE_SIZE, 0.5 * TILE_SIZE))

	# Religious banner at x=3, y=1
	_create_divine_banner(Vector2(3 * TILE_SIZE, 0.5 * TILE_SIZE))

	# Divine light through window
	var window_light = PointLight2D.new()
	window_light.position = Vector2(8 * TILE_SIZE, 1.5 * TILE_SIZE)
	window_light.color = Color(0.90, 0.95, 1.00, 0.6)
	window_light.energy = 0.7
	window_light.texture = _create_light_texture(160)
	decorations.add_child(window_light)

	# Crystal glow
	var crystal_light = PointLight2D.new()
	crystal_light.position = Vector2(8 * TILE_SIZE, 5.5 * TILE_SIZE)
	crystal_light.color = Color(0.85, 0.95, 1.0, 0.7)
	crystal_light.energy = 0.65
	crystal_light.texture = _create_light_texture(100)
	decorations.add_child(crystal_light)


func _create_stained_glass(pos: Vector2) -> void:
	var sg = Sprite2D.new()
	var sgw = TILE_SIZE * 2
	var sgh = TILE_SIZE + 8
	var img = Image.create(sgw, sgh, false, Image.FORMAT_RGBA8)

	var lead   := Color(0.18, 0.18, 0.20)
	var blue   := Color(0.30, 0.55, 0.90)
	var gold3  := Color(0.85, 0.78, 0.30)
	var white2 := Color(0.92, 0.94, 0.98)
	var rose   := Color(0.88, 0.45, 0.55)

	# Arch outline
	for y in range(sgh):
		for x in range(sgw):
			# Outer lead border
			var near = x < 2 or x >= sgw - 2 or y < 2
			if near:
				img.set_pixel(x, y, lead)
				continue

			# Pane layout: top arch = radial, bottom = rectangles
			if y < sgh / 2:
				# Radial spoke pattern
				var dx = float(x - sgw / 2)
				var dy = float(y - sgh)
				var angle = atan2(dx, -dy)
				var sector = int((angle + PI) / (PI / 3)) % 6
				match sector:
					0: img.set_pixel(x, y, blue)
					1: img.set_pixel(x, y, gold3)
					2: img.set_pixel(x, y, white2)
					3: img.set_pixel(x, y, rose)
					4: img.set_pixel(x, y, blue)
					_: img.set_pixel(x, y, gold3)
				# Lead spoke lines
				if int(angle * 6 / PI) % 2 == 0:
					img.set_pixel(x, y, lead)
			else:
				# Grid panes
				var cell_x = (x - 2) / 10
				var cell_y = (y - sgh / 2) / 10
				var in_lead_h = (y - sgh / 2) % 10 < 2
				var in_lead_v = (x - 2) % 10 < 2
				if in_lead_h or in_lead_v:
					img.set_pixel(x, y, lead)
				else:
					var checker = (cell_x + cell_y) % 3
					match checker:
						0: img.set_pixel(x, y, blue)
						1: img.set_pixel(x, y, gold3)
						_: img.set_pixel(x, y, white2)

	sg.texture = ImageTexture.create_from_image(img)
	sg.position = pos
	decorations.add_child(sg)


func _create_divine_banner(pos: Vector2) -> void:
	var banner = Sprite2D.new()
	var bw2 = TILE_SIZE + 8
	var bh2 = TILE_SIZE * 2
	var img = Image.create(bw2, bh2, false, Image.FORMAT_RGBA8)

	var bg4     := Color(0.85, 0.80, 0.55)
	var symbol  := Color(0.90, 0.75, 0.20)
	var border4 := Color(0.70, 0.62, 0.18)

	# Background
	for y in range(bh2):
		for x in range(bw2):
			img.set_pixel(x, y, bg4)

	# Border
	for y in range(bh2):
		for x in range(bw2):
			if x < 3 or x >= bw2 - 3 or y < 3 or y >= bh2 - 3:
				img.set_pixel(x, y, border4)

	# Sun symbol (circle + rays)
	var cx2 = bw2 / 2
	var cy2 = bh2 / 2
	for y in range(bh2):
		for x in range(bw2):
			var dist2 = Vector2(x - cx2, y - cy2).length()
			if dist2 < 10:
				img.set_pixel(x, y, symbol)
			elif dist2 < 12:
				img.set_pixel(x, y, symbol.darkened(0.2))
			else:
				# Rays
				var angle = atan2(y - cy2, x - cx2)
				var ray = int(angle * 8 / PI) % 2
				if ray == 0 and dist2 < 22 and dist2 > 12:
					img.set_pixel(x, y, symbol.lerp(bg4, (dist2 - 12) / 10.0))

	# Fringe
	for x in range(0, bw2, 4):
		for y in range(bh2 - 6, bh2):
			img.set_pixel(x, y, border4)
			if x + 1 < bw2:
				img.set_pixel(x + 1, y, border4)

	banner.texture = ImageTexture.create_from_image(img)
	banner.position = pos
	decorations.add_child(banner)


func _decorate_blacksmith_shop() -> void:
	# Animated forge with glowing embers
	_setup_forge_anim()

	# Anvil at x=2, y=7
	_create_anvil(Vector2(2 * TILE_SIZE, 7 * TILE_SIZE))

	# Weapon wall rack on east side
	_create_weapon_wall_rack(Vector2(13 * TILE_SIZE, 2 * TILE_SIZE))

	# Weapon crates at x=1, y=9
	_create_weapon_crates(Vector2(1 * TILE_SIZE, 9 * TILE_SIZE))

	# Bellows near forge
	_create_bellows(Vector2(6 * TILE_SIZE, 8.5 * TILE_SIZE))

	# Forge light — warm orange
	var forge_light = PointLight2D.new()
	forge_light.position = Vector2(8 * TILE_SIZE, 6 * TILE_SIZE)
	forge_light.color = Color(1.0, 0.55, 0.15)
	forge_light.energy = 1.0
	forge_light.texture = _create_light_texture(180)
	decorations.add_child(forge_light)


func _setup_forge_anim() -> void:
	_forge_sprite = Sprite2D.new()
	_forge_sprite.name = "ForgeEmbers"
	_forge_sprite.z_index = 5
	_forge_sprite.position = Vector2(8 * TILE_SIZE, 6 * TILE_SIZE)
	add_child(_forge_sprite)

	_forge_frames.clear()
	for f in range(4):
		var img = Image.create(TILE_SIZE * 2, TILE_SIZE * 2, false, Image.FORMAT_RGBA8)
		_draw_forge_frame(img, f)
		_forge_frames.append(ImageTexture.create_from_image(img))

	if _forge_frames.size() > 0:
		_forge_sprite.texture = _forge_frames[0]


func _draw_forge_frame(img: Image, frame: int) -> void:
	img.fill(Color.TRANSPARENT)
	var stone_c  := Color(0.45, 0.40, 0.36)
	var stone_hi := Color(0.58, 0.52, 0.48)
	var ember_a  := Color(0.95, 0.55, 0.10)
	var ember_b  := Color(0.98, 0.80, 0.20)
	var ember_c  := Color(1.0, 0.96, 0.60)
	var ash      := Color(0.40, 0.38, 0.36)

	var W = TILE_SIZE * 2
	var H = TILE_SIZE * 2

	# Stone forge body
	for y in range(H / 2, H):
		for x in range(0, W):
			var block_r = (y - H / 2) / 10
			var block_c = x / 16
			var mh = (y - H / 2) % 10 < 2
			var mv = x % 16 < 2
			if mh or mv:
				img.set_pixel(x, y, stone_c.darkened(0.2))
			else:
				var hi2 = (block_r + block_c) % 3 == 0
				img.set_pixel(x, y, stone_hi if hi2 else stone_c)

	# Forge opening (dark hole)
	var ox = W / 2 - 16
	var oy = H / 2 - 4
	for y in range(oy, H / 2 + 16):
		for x in range(ox, ox + 32):
			img.set_pixel(x, y, Color(0.08, 0.06, 0.04))

	# Ember bed — seething coals
	for y in range(H / 2 + 8, H / 2 + 16):
		for x in range(ox + 2, ox + 30):
			var heat = (x + y + frame * 3) % 8
			if heat < 2:
				img.set_pixel(x, y, ember_c)
			elif heat < 4:
				img.set_pixel(x, y, ember_b)
			elif heat < 6:
				img.set_pixel(x, y, ember_a)
			else:
				img.set_pixel(x, y, ash)

	# Flame tongues above ember bed
	for fl in range(4):
		var fx = ox + 4 + fl * 7 + (frame % 2) * 2
		var flame_h = 6 + (frame + fl) % 4
		for y in range(H / 2 - flame_h, H / 2 + 8):
			if fx >= 0 and fx < W:
				var t = float(H / 2 + 8 - y) / float(flame_h + 8)
				var c = ember_c if t > 0.7 else (ember_b if t > 0.4 else ember_a)
				img.set_pixel(fx, y, c)


func _animate_forge(delta: float) -> void:
	_forge_timer += delta
	if _forge_timer >= FORGE_SPEED:
		_forge_timer -= FORGE_SPEED
		_forge_frame = (_forge_frame + 1) % _forge_frames.size()
		if _forge_sprite and _forge_frames.size() > 0:
			_forge_sprite.texture = _forge_frames[_forge_frame]


func _create_anvil(pos: Vector2) -> void:
	var node = Node2D.new()
	node.name = "Anvil"

	var anvil = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 2, TILE_SIZE + 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var iron2    := Color(0.38, 0.38, 0.42)
	var iron_hi2 := Color(0.58, 0.58, 0.62)
	var iron_shad := Color(0.22, 0.22, 0.24)

	# Anvil base (wide trapezoid)
	for y in range(TILE_SIZE - 8, TILE_SIZE + 8):
		var width = 28 + (y - (TILE_SIZE - 8)) / 2
		var ax = TILE_SIZE - width / 2
		for x in range(ax, ax + width):
			if x >= 0 and x < TILE_SIZE * 2:
				img.set_pixel(x, y, iron_shad if y == TILE_SIZE - 8 else iron2)

	# Anvil body
	for y in range(16, TILE_SIZE - 8):
		for x in range(12, TILE_SIZE * 2 - 12):
			img.set_pixel(x, y, iron2)

	# Anvil horn (left taper)
	for y in range(20, TILE_SIZE - 12):
		var horn_reach = (y - 20) * 2
		for x in range(0, min(horn_reach, 12)):
			img.set_pixel(x, y, iron2)

	# Top face
	for y in range(12, 18):
		for x in range(10, TILE_SIZE * 2 - 10):
			img.set_pixel(x, y, iron_hi2)

	# Hammer leaning on side
	var hammer_col := Color(0.45, 0.42, 0.40)
	var handle_col := Color(0.48, 0.32, 0.16)
	# Handle (diagonal)
	for i in range(20):
		var hx2 = TILE_SIZE * 2 - 10 - i
		var hy = 28 + i
		if hx2 >= 0 and hx2 < TILE_SIZE * 2 and hy < TILE_SIZE + 8:
			img.set_pixel(hx2, hy, handle_col)
			img.set_pixel(hx2 - 1, hy, handle_col)
	# Head
	for y in range(24, 34):
		for x in range(TILE_SIZE * 2 - 16, TILE_SIZE * 2 - 6):
			img.set_pixel(x, y, hammer_col)

	anvil.texture = ImageTexture.create_from_image(img)
	anvil.position = pos
	node.add_child(anvil)

	decorations.add_child(node)


func _create_weapon_wall_rack(pos: Vector2) -> void:
	var rack = Sprite2D.new()
	var rw = TILE_SIZE * 2
	var rh = TILE_SIZE * 6
	var img = Image.create(rw, rh, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var rack_wood2 := Color(0.32, 0.22, 0.12)
	var rack_iron  := Color(0.45, 0.43, 0.42)
	var blade2     := Color(0.68, 0.72, 0.78)
	var blade_hi2  := Color(0.88, 0.90, 0.94)
	var hilt2      := Color(0.60, 0.48, 0.20)

	# Rack backing board
	for y in range(rh):
		for x in range(rw):
			var plank2 = y / 12 % 2
			img.set_pixel(x, y, rack_wood2 if plank2 == 0 else rack_wood2.lightened(0.08))

	# Iron mounting hooks
	for hook in range(3):
		var hy2 = 16 + hook * TILE_SIZE
		for x in range(4, rw - 4):
			img.set_pixel(x, hy2, rack_iron)
			img.set_pixel(x, hy2 + 1, rack_iron)

	# Swords hanging on hooks
	for sw_idx in range(3):
		var sy2 = 20 + sw_idx * TILE_SIZE
		var sx3 = rw / 2 - 4
		# Blade
		for y in range(sy2, sy2 + 36):
			img.set_pixel(sx3, y, blade_hi2)
			img.set_pixel(sx3 + 1, y, blade2)
		# Crossguard
		for x in range(sx3 - 6, sx3 + 8):
			img.set_pixel(x, sy2 + 34, hilt2)
		# Grip
		for y in range(sy2 + 34, sy2 + 44):
			img.set_pixel(sx3, y, Color(0.35, 0.22, 0.12))

	rack.texture = ImageTexture.create_from_image(img)
	rack.position = pos
	decorations.add_child(rack)


func _create_weapon_crates(pos: Vector2) -> void:
	var crates = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 2, TILE_SIZE + 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var crate_wood  := Color(0.48, 0.34, 0.18)
	var crate_dark2 := Color(0.35, 0.24, 0.12)
	var iron_band2  := Color(0.40, 0.38, 0.36)
	var handle3     := Color(0.50, 0.42, 0.15)

	# Two stacked crates
	for crate_idx in range(2):
		var cy2 = crate_idx * 22
		var cx2 = crate_idx * 6
		var cw2 = 38 - crate_idx * 4
		var ch2 = 22
		for y in range(cy2, cy2 + ch2):
			for x in range(cx2, cx2 + cw2):
				var plank3 = (x - cx2) / 8 % 2
				img.set_pixel(x, y, crate_dark2 if plank3 == 0 else crate_wood)
		# Iron corner bands
		for bx3 in [cx2, cx2 + cw2 - 2]:
			for y in range(cy2, cy2 + ch2):
				img.set_pixel(bx3, y, iron_band2)
				img.set_pixel(bx3 + 1, y, iron_band2)
		# Lid
		for x in range(cx2, cx2 + cw2):
			img.set_pixel(x, cy2, crate_wood.lightened(0.15))
			img.set_pixel(x, cy2 + 1, crate_wood.lightened(0.1))

	# Sword handles sticking out of top crate
	for sv in range(3):
		var svx = 8 + sv * 8
		for y in range(0, 12):
			if svx < TILE_SIZE * 2:
				img.set_pixel(svx, y, handle3)
				img.set_pixel(svx + 1, y, handle3)

	crates.texture = ImageTexture.create_from_image(img)
	crates.position = pos
	decorations.add_child(crates)


func _create_bellows(pos: Vector2) -> void:
	var bellows = Sprite2D.new()
	var img = Image.create(TILE_SIZE + 8, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var leather2 := Color(0.42, 0.28, 0.14)
	var leather_f := Color(0.55, 0.38, 0.20)
	var wood4    := Color(0.38, 0.25, 0.12)
	var nozzle   := Color(0.55, 0.52, 0.48)

	# Bellows body (accordion folds)
	for fold in range(5):
		var fx2 = fold * 6
		for y in range(4, 16):
			img.set_pixel(fx2, y, leather2)
			img.set_pixel(fx2 + 1, y, leather_f)
			img.set_pixel(fx2 + 2, y, leather2)
			img.set_pixel(fx2 + 3, y, leather_f)
			img.set_pixel(fx2 + 4, y, leather2)

	# Handle end
	for y in range(6, 14):
		for x in range(28, 34):
			img.set_pixel(x, y, wood4)

	# Nozzle end
	for y in range(7, 13):
		for x in range(0, 4):
			img.set_pixel(x, y, nozzle)

	bellows.texture = ImageTexture.create_from_image(img)
	bellows.position = pos
	decorations.add_child(bellows)


# ---------------------------------------------------------------------------
# Lighting (generic, called for all shop types)
# ---------------------------------------------------------------------------

func _create_lighting() -> void:
	var light_tex_sm = _create_light_texture(80)

	# General fill lights at corners
	var corner_positions = [
		Vector2(2 * TILE_SIZE, 1 * TILE_SIZE),
		Vector2(14 * TILE_SIZE, 1 * TILE_SIZE),
		Vector2(2 * TILE_SIZE, 10 * TILE_SIZE),
		Vector2(14 * TILE_SIZE, 10 * TILE_SIZE),
	]
	for cp in corner_positions:
		var light = PointLight2D.new()
		light.position = cp
		light.color = _pal_light
		light.energy = 0.22
		light.texture = light_tex_sm
		decorations.add_child(light)


# ---------------------------------------------------------------------------
# NPCs
# ---------------------------------------------------------------------------

func _setup_npcs() -> void:
	npcs = Node2D.new()
	npcs.name = "NPCs"
	add_child(npcs)

	# Shopkeeper behind counter — talking to them opens the wares menu after the greeting line closes (playtest 2026-07-14: user talked to shopkeeper repeatedly but couldn't figure out how to buy — the standalone BrowseService tile in front of the counter was the only purchase gate).
	_create_npc(keeper_name, "shopkeeper", Vector2(8, 3), _keeper_dialogue())
	var keeper_npc: Node = null
	for child in npcs.get_children():
		if child.get("npc_name") == keeper_name:
			keeper_npc = child
			break
	if keeper_npc and keeper_npc.has_signal("dialogue_ended"):
		keeper_npc.dialogue_ended.connect(func(_n): _on_browse_request())

	# Customers — vary by shop type
	match shop_type:
		ShopType.ITEM:
			_create_npc("Gethena", "herbalist", Vector2(4, 7), [
				"Gethena: These potions are fresh — brewed this morning.",
				"Gethena: I grow the herbs myself. The window box outside is mine.",
				"Gethena: You'd be surprised what an elixir can do for autobattle endurance.",
				"Gethena: My script drinks a potion at 40% HP. Optimized.",
			])
			_create_npc("Pip", "child", Vector2(10, 8), [
				"Pip: Mister, do you have a coin? I want a phoenix down.",
				"Pip: My older brother says they bring people back from dead!",
				"Pip: I want to bring back my hamster.",
				"Pip: *stares at floor* His name was Mr. Biscuit.",
			])
		ShopType.BLACK_MAGIC:
			_create_npc("Aldric", "hooded_mage", Vector2(4, 7), [
				"Aldric: *browsing* ...no, no, that fire tome is obsolete.",
				"Aldric: I require something that rhymes with 'CORRUPTED SAVE'.",
				"Aldric: Don't judge me. Necromancy has excellent DPS.",
				"Aldric: *glances at you* Well? Keep walking.",
			])
			_create_npc("Vex", "nervous", Vector2(12, 9), [
				"Vex: *near the door* I shouldn't be here.",
				"Vex: My lord specifically said no black magic tomes.",
				"Vex: But the raven looked at me. THE RAVEN LOOKED AT ME.",
				"Vex: That's a sign, right? That's definitely a sign.",
			])
		ShopType.WHITE_MAGIC:
			_create_npc("Pilgrim Lael", "pilgrim", Vector2(4, 8), [
				"Pilgrim Lael: Excuse me — do you have something for poison?",
				"Pilgrim Lael: Cave mushrooms. Didn't read the sign. The sign was in all caps.",
				"Pilgrim Lael: *sweating* The antidote cost how much?",
			])
			_create_npc("Ada", "child", Vector2(10, 7), [
				"Ada: *touching crystal* It's warm.",
				"Ada: Mama says it's a holy relic. But it tingles like static.",
				"Ada: Do you think it can hear us?",
				"Ada: *whispers to crystal* I got an A on my exam.",
			])
		ShopType.BLACKSMITH:
			_create_npc("Sir Corvath", "knight", Vector2(3, 7), [
				"Sir Corvath: *examining blade* Hmm. The tempering is inconsistent.",
				"Sir Corvath: A battle-tested weapon must hold an edge through 500 strikes.",
				"Sir Corvath: I autobattle with a damage-per-second script. Every dull blade shows.",
				"Sir Corvath: *sets sword down* I'll take it. Integrity is overrated.",
			])
			_create_npc("Jend", "apprentice", Vector2(6, 9), [
				"Jend: *pumping bellows* It never. Gets. Cooler.",
				"Jend: Master says a good smith feels the heat. Becomes one with the forge.",
				"Jend: I feel the heat. I am the heat. I am suffering.",
				"Jend: *pumps bellows faster* ...two more years of this.",
			])


func _keeper_dialogue() -> Array:
	match shop_type:
		ShopType.ITEM:
			return [
				keeper_name + ": Welcome! Got potions, antidotes, tonics — the works.",
				keeper_name + ": Best-stocked item shop in three villages.",
				keeper_name + ": Need anything? Browse my wares!",
			]
		ShopType.BLACK_MAGIC:
			return [
				keeper_name + ": ...",
				keeper_name + ": You have the look of someone who wants power.",
				keeper_name + ": Power has a price. Mine is in gold.",
				keeper_name + ": Browse my wares.",
			]
		ShopType.WHITE_MAGIC:
			return [
				keeper_name + ": May the light guide you, traveler.",
				keeper_name + ": Healing spells, protective wards — whatever you need.",
				keeper_name + ": The crystal sees your intent. Be well. Browse my wares.",
			]
		ShopType.BLACKSMITH:
			return [
				keeper_name + ": *hammering* WHAT? Oh. Customer.",
				keeper_name + ": Looking for a weapon? Got swords, axes, staves.",
				keeper_name + ": Everything's hand-forged. No assembly-line garbage.",
				keeper_name + ": Browse my wares. Don't touch the anvil.",
			]
	return [keeper_name + ": Welcome. Browse my wares."]


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
		"shopkeeper":   color = Color(0.55, 0.45, 0.30)
		"herbalist":    color = Color(0.30, 0.55, 0.28)
		"hooded_mage":  color = Color(0.28, 0.18, 0.40)
		"pilgrim":      color = Color(0.80, 0.78, 0.68)
		"knight":       color = Color(0.55, 0.55, 0.65)
		"apprentice":   color = Color(0.60, 0.38, 0.20)
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
		exit.target_spawn = "shop_exit"
		exit.require_interaction = false
		exit.position = Vector2(8 * TILE_SIZE, 11.5 * TILE_SIZE)

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


func _on_exit_triggered(_target_map: String, _target_spawn: String) -> void:
	transition_triggered.emit("village_return", "shop_exit")
	area_transition.emit("village_return", "shop_exit")


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
# Browse-wares service — interactable in front of the counter
# Routes through the existing ShopScene UI (same as outdoor VillageShop did)
# ---------------------------------------------------------------------------

const VillageShopRes = preload("res://src/exploration/VillageShop.gd")


func _create_browse_interactable() -> void:
	var area = Area2D.new()
	area.name = "BrowseService"
	# In front of counter (counter at y=2, player approach at y=4)
	area.position = Vector2(8 * TILE_SIZE, 4 * TILE_SIZE)

	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(TILE_SIZE * 2, TILE_SIZE)
	collision.shape = shape
	area.add_child(collision)

	area.collision_layer = 4
	area.collision_mask = 2
	area.monitoring = true
	area.monitorable = true
	area.add_to_group("interactables")
	area.set_meta("interaction_callback", _on_browse_request)
	area.set_meta("parent_scene", self)
	add_child(area)


func _on_browse_request() -> void:
	if _wares_layer and is_instance_valid(_wares_layer):
		return  # Already open
	wares_requested.emit()
	_open_wares()


func _open_wares() -> void:
	var ShopSceneScript = load("res://src/exploration/ShopScene.gd")
	var ShopkeeperDataScript = load("res://src/exploration/ShopkeeperData.gd")
	if not ShopSceneScript or not ShopkeeperDataScript:
		return

	var shop_scene = ShopSceneScript.new()
	var keeper_custom = ShopkeeperDataScript.get_shopkeeper_for_type(shop_type)
	shop_scene.setup(shop_type, shop_name, _get_inventory(), keeper_custom)

	if player and player.has_method("set_can_move"):
		player.set_can_move(false)

	_wares_layer = CanvasLayer.new()
	_wares_layer.layer = 50
	get_tree().root.add_child(_wares_layer)
	shop_scene.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wares_layer.add_child(shop_scene)
	shop_scene.shop_closed.connect(_on_wares_closed)

	if SoundManager:
		SoundManager.play_ui("menu_open")


func _on_wares_closed() -> void:
	if _wares_layer and is_instance_valid(_wares_layer):
		_wares_layer.queue_free()
		_wares_layer = null
	if player and player.has_method("set_can_move"):
		player.set_can_move(true)
	if SoundManager:
		SoundManager.play_ui("menu_close")


func _get_inventory() -> Array:
	match shop_type:
		ShopType.ITEM:        return VillageShopRes.ITEM_INVENTORY
		ShopType.BLACK_MAGIC: return VillageShopRes.BLACK_MAGIC_INVENTORY
		ShopType.WHITE_MAGIC: return VillageShopRes.WHITE_MAGIC_INVENTORY
		ShopType.BLACKSMITH:  return VillageShopRes.BLACKSMITH_WEAPONS + VillageShopRes.BLACKSMITH_ARMOR
		_: return []
