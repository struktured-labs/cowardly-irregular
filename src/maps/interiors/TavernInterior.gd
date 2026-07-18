extends Node2D
class_name TavernInterior

## TavernInterior - "The Dancing Tonberry" tavern interior
## Expanded 28x18 layout: bar zone, dining hall, stage, kitchen, fireside lounge, stairs corner
## Shining Force III / Breath of Fire aesthetic — warm candle-lit, deeply textured, lived-in

signal transition_triggered(target_map: String, target_spawn: String)
signal area_transition(target_map: String, target_spawn: String)
signal battle_triggered(enemies: Array)

## Constants
const TILE_SIZE: int = 32
const MAP_WIDTH: int = 28
const MAP_HEIGHT: int = 18

## Scene components
var tilemap: TileMapLayer
var player: Node2D
var camera: Camera2D
var npcs: Node2D
var transitions: Node2D
var decorations: Node2D
var controller: Node

## Dancing girl animation
var dancer_sprite: Sprite2D
var _dancer_frames: Array[ImageTexture] = []
var _anim_frame: int = 0
var _anim_timer: float = 0.0
const ANIM_SPEED: float = 0.15

## Fireplace flicker animation
var _fire_sprite: Sprite2D
var _fire_frames: Array[ImageTexture] = []
var _fire_frame: int = 0
var _fire_timer: float = 0.0
const FIRE_ANIM_SPEED: float = 0.08
var _fireplace_light: PointLight2D

## Sleeping dog breathing
var _dog_sprite: Sprite2D
var _dog_frames: Array[ImageTexture] = []
var _dog_frame: int = 0
var _dog_timer: float = 0.0
const DOG_ANIM_SPEED: float = 0.6

## Cook stirring animation
var _cook_sprite: Sprite2D
var _cook_frames: Array[ImageTexture] = []
var _cook_frame: int = 0
var _cook_timer: float = 0.0
const COOK_ANIM_SPEED: float = 0.22

## Spawn points
var spawn_points: Dictionary = {
	"entrance": Vector2(13, 16),
	"stage": Vector2(20, 4),
	"bar": Vector2(4, 5),
	"piano": Vector2(25, 15),
	"kitchen": Vector2(23, 10),
	"fireside": Vector2(6, 10)
}

## Piano state
var _piano_sprite: Sprite2D
var _piano_playing: bool = false

## Map layout  28 wide x 18 tall
## Zones (rough):
##   Left strip (x 0-1):   thick stone wall
##   x 1-9:   bar zone (bar counter at x2-4, dining at x3-9)
##   x 10-11: center aisle
##   x 12-19: main dining hall + stage backdrop (y 1-5)
##   x 20-26: kitchen zone (right side) + stairs corner (bottom-right)
##   x 27:    right wall
##   y 0:     top wall (with banner area)
##   y 15-17: bottom — door tiles center, walls sides
##
## Floor variants:
##   WOOD (default)      — main floor planks
##   STAGE (S)           — raised platform lighter wood
##   STONE (K)           — kitchen area flagstones
##   HEARTH (H)          — fireplace hearth flagstone
##   DIRT (F)            — under stairs, cellar-ish
##
## Legend:
##   W = wall brick
##   . = wood floor
##   B = bar counter tile
##   S = stage floor
##   K = kitchen stone
##   H = hearth flagstone
##   D = door
##   U = stairs up (visual)
##   F = flagstone/dirt (cellar corner)
const TAVERN_LAYOUT = [
	"WWWWWWWWWWWWWWWWWWWWWWWWWWWW",
	"W..........................W.W",
	"W..BBB..........SSSSSSSS...W.W",
	"W..BBB..........SSSSSSSS...W.W",
	"W..BBB..........SSSSSSSS...W.W",
	"W..........................W.W",
	"W.....TT....TT....TT....K..W.W",
	"W.....TT....TT....TT....K..W.W",
	"W..........................K.W",
	"W.....TT....TT..........KKKK.W",
	"W..........HHH..........KKKK.W",
	"W..........HHH..........KKKK.W",
	"W.....TT........TT......KKKK.W",
	"W.....TT........TT......KKKK.W",
	"W..........................UUWW",
	"W..........................UUWW",
	"WWWWWWWWWWWWWDDDWWWWWWWWWWWWWW",
	"WWWWWWWWWWWWWDDDWWWWWWWWWWWWWW"
]

## Random seed for consistent grain variation per tile
var _tile_seeds: Array = []


func _ready() -> void:
	_init_tile_seeds()
	_setup_tilemap()
	_setup_decorations()
	_setup_dancer()
	_setup_npcs()
	# msg 2764: NPC-vs-furniture sweep (shared with BaseInterior + InnInterior + ShopInterior).
	InteriorPlacementSweep.sweep(self, npcs, decorations, TAVERN_LAYOUT, "tavern_interior")
	_setup_transitions()
	_setup_player()
	_setup_camera()
	_setup_controller()

	# Play tavern music
	if SoundManager:
		SoundManager.play_area_music("interior_tavern")


func _process(delta: float) -> void:
	_animate_dancer(delta)
	_animate_fire(delta)
	_animate_dog(delta)
	_animate_cook(delta)
	_flicker_fireplace_light(delta)


func _init_tile_seeds() -> void:
	_tile_seeds.clear()
	for i in range(MAP_WIDTH * MAP_HEIGHT):
		_tile_seeds.append(randi() % 1000)


func _get_tile_seed(x: int, y: int) -> int:
	var idx = y * MAP_WIDTH + x
	if idx < _tile_seeds.size():
		return _tile_seeds[idx]
	return 0


# ---------------------------------------------------------------------------
# Tilemap setup — 6 tile types registered as separate atlas sources
# ---------------------------------------------------------------------------

func _setup_tilemap() -> void:
	tilemap = TileMapLayer.new()
	tilemap.name = "TileMapLayer"
	add_child(tilemap)

	var tileset = TileSet.new()
	tileset.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Source 0 — wood floor (main hall)
	tileset.add_source(_make_floor_source("wood"), 0)
	# Source 1 — brick wall
	tileset.add_source(_make_floor_source("wall"), 1)
	# Source 2 — stage floor (lighter raised wood)
	tileset.add_source(_make_floor_source("stage"), 2)
	# Source 3 — kitchen stone
	tileset.add_source(_make_floor_source("stone"), 3)
	# Source 4 — hearth flagstone
	tileset.add_source(_make_floor_source("hearth"), 4)
	# Source 5 — door arch bottom (dark exit)
	tileset.add_source(_make_floor_source("door"), 5)
	# Source 6 — stairs/cellar
	tileset.add_source(_make_floor_source("stairs"), 6)

	tilemap.tile_set = tileset
	_generate_floor()


func _make_floor_source(variant: String) -> TileSetAtlasSource:
	var src = TileSetAtlasSource.new()
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	match variant:
		"wood":    _draw_floor_tile(img)
		"wall":    _draw_wall_tile(img)
		"stage":   _draw_stage_floor(img)
		"stone":   _draw_stone_floor(img)
		"hearth":  _draw_hearth_floor(img)
		"door":    _draw_door_tile(img)
		"stairs":  _draw_stairs_tile(img)
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	src.create_tile(Vector2i(0, 0))
	return src


# ---------------------------------------------------------------------------
# Floor/wall tile drawing helpers
# ---------------------------------------------------------------------------

func _draw_floor_tile(image: Image) -> void:
	## Wide wood planks running horizontally — varied grain per tile slot
	var wood      = Color(0.40, 0.26, 0.14)
	var wood_mid  = Color(0.45, 0.30, 0.17)
	var wood_lite = Color(0.50, 0.34, 0.20)
	var wood_knot = Color(0.33, 0.20, 0.10)

	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Each plank is 8px tall — two planks per tile
			var plank = y / 8
			var plank_col = wood_mid if plank % 2 == 0 else wood

			# Horizontal grain lines
			var grain_v = (y % 8) == 3 or (y % 8) == 6
			# Subtle cross-grain variation every 10px
			var grain_h = (x + plank * 4) % 10 == 0

			var c = plank_col
			if grain_v:
				c = c.darkened(0.08)
			if grain_h:
				c = c.darkened(0.06)
			# Rare knot
			if (x - 14) * (x - 14) + (y - 5) * (y - 5) < 4:
				c = wood_knot
			if (x - 22) * (x - 22) + (y - 21) * (y - 21) < 3:
				c = wood_knot

			# Plank edge shadow at bottom of each plank
			if (y % 8) == 7:
				c = c.darkened(0.15)
			# Very subtle random warmth variation
			image.set_pixel(x, y, c)


func _draw_wall_tile(image: Image) -> void:
	## Brick with realistic mortar and occasional cracked/discolored brick
	var brick       = Color(0.52, 0.32, 0.22)
	var brick_dark  = Color(0.42, 0.24, 0.15)
	var brick_worn  = Color(0.48, 0.36, 0.28)  # Lighter worn brick
	var mortar      = Color(0.62, 0.54, 0.46)
	var mortar_dark = Color(0.55, 0.48, 0.40)
	var crack       = Color(0.35, 0.20, 0.12)

	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var row = y / 8
			var offset = (row % 2) * 8
			var in_mortar_h = (y % 8) == 0 or (y % 8) == 1
			var in_mortar_v = ((x + offset) % 16) == 0 or ((x + offset) % 16) == 1

			if in_mortar_h or in_mortar_v:
				var c = mortar if (x + y) % 3 != 0 else mortar_dark
				image.set_pixel(x, y, c)
			else:
				var bx = ((x + offset) % 16)
				var by = y % 8
				# Occasional worn / cracked brick for texture variation
				var is_worn = ((row * 3 + bx / 4) % 7 == 0)
				var is_cracked = (row == 2 and bx > 10)
				var c = brick
				if is_worn:
					c = brick_worn
				elif is_cracked:
					c = brick_dark
				# Subtle variation inside brick face
				if (bx + by) % 5 == 0:
					c = c.darkened(0.05)
				if is_cracked and bx == 12 and by in [3, 4]:
					c = crack  # Thin crack line
				image.set_pixel(x, y, c)


func _draw_stage_floor(image: Image) -> void:
	## Lighter, polished performance-wood for the raised stage
	var s_light = Color(0.60, 0.44, 0.26)
	var s_mid   = Color(0.54, 0.38, 0.22)
	var s_dark  = Color(0.47, 0.32, 0.18)

	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var plank = x / 10  # Vertical planks on stage (perpendicular to main floor)
			var c = s_light if plank % 2 == 0 else s_mid
			if (x % 10) == 9:
				c = s_dark  # Plank gap shadow
			if (y + plank * 3) % 8 == 0:
				c = c.lightened(0.06)  # Highlight sheen
			image.set_pixel(x, y, c)


func _draw_stone_floor(image: Image) -> void:
	## Kitchen flagstone — irregular stone slabs, grey-tan
	var stone_a  = Color(0.52, 0.48, 0.42)
	var stone_b  = Color(0.47, 0.43, 0.38)
	var grout    = Color(0.35, 0.32, 0.28)
	var stain    = Color(0.42, 0.36, 0.28)  # Grease/food stain tint

	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Irregular grout lines — two horizontal, one vertical offset
			var in_grout = false
			if (y % 12) < 2:
				in_grout = true
			elif (y % 12) >= 6 and (y % 12) < 8:
				in_grout = (x % 16) < 2
			else:
				in_grout = (x % 20) < 2

			if in_grout:
				image.set_pixel(x, y, grout)
			else:
				var c = stone_a if (x / 10 + y / 8) % 2 == 0 else stone_b
				# Grease stain corner
				if x < 10 and y > 20:
					c = c.blend(stain)
				image.set_pixel(x, y, c)


func _draw_hearth_floor(image: Image) -> void:
	## Dark reddish flagstones, soot-stained around fireplace
	var flag_a = Color(0.42, 0.28, 0.20)
	var flag_b = Color(0.37, 0.24, 0.16)
	var soot   = Color(0.20, 0.14, 0.10)
	var grout  = Color(0.28, 0.18, 0.12)
	var ember  = Color(0.55, 0.32, 0.15)

	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var in_grout = (y % 10) < 2 or (x % 14) < 2
			if in_grout:
				image.set_pixel(x, y, grout)
			else:
				var c = flag_a if (x / 14 + y / 10) % 2 == 0 else flag_b
				# Soot darkening near top (closest to fireplace opening)
				if y < 10:
					c = c.blend(soot)
				# Warm ember glow reflection near bottom
				if y > 22:
					c = c.blend(ember)
				image.set_pixel(x, y, c)


func _draw_door_tile(image: Image) -> void:
	## Dark arched doorway floor — worn stone with outdoor light hint
	var stone = Color(0.30, 0.24, 0.18)
	var dark  = Color(0.18, 0.14, 0.10)
	var light = Color(0.45, 0.38, 0.28)

	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var c = stone
			if y > TILE_SIZE - 6:
				c = light  # Outdoor ground peeking in
			elif (x + y) % 8 < 2:
				c = dark
			image.set_pixel(x, y, c)


func _draw_stairs_tile(image: Image) -> void:
	## Staircase visual — dark diagonal planks going "up" (perspective)
	var step_light = Color(0.45, 0.30, 0.18)
	var step_dark  = Color(0.28, 0.18, 0.10)
	var riser      = Color(0.20, 0.13, 0.08)
	var shadow     = Color(0.12, 0.08, 0.05)

	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Each step is 5px tall, tread then riser
			var step = y / 5
			var step_y = y % 5
			if step_y == 0 or step_y == 1:
				# Riser face (dark vertical face of step)
				image.set_pixel(x, y, riser)
			elif step_y == 4:
				# Bottom edge shadow
				image.set_pixel(x, y, shadow)
			else:
				# Tread (horizontal top of step) — lighter on left, darker right
				var c = step_light if x < TILE_SIZE / 2 else step_dark
				# Receding perspective — offset per step
				if (x + step * 3) % 6 == 0:
					c = c.darkened(0.1)
				image.set_pixel(x, y, c)


func _generate_floor() -> void:
	for y in range(MAP_HEIGHT):
		var row_str = TAVERN_LAYOUT[y]
		for x in range(MAP_WIDTH):
			if x >= row_str.length():
				tilemap.set_cell(Vector2i(x, y), 1, Vector2i(0, 0))
				continue
			var ch = row_str[x]
			match ch:
				"W":
					tilemap.set_cell(Vector2i(x, y), 1, Vector2i(0, 0))
				"S":
					tilemap.set_cell(Vector2i(x, y), 2, Vector2i(0, 0))
				"K":
					tilemap.set_cell(Vector2i(x, y), 3, Vector2i(0, 0))
				"H":
					tilemap.set_cell(Vector2i(x, y), 4, Vector2i(0, 0))
				"D":
					tilemap.set_cell(Vector2i(x, y), 5, Vector2i(0, 0))
				"U":
					tilemap.set_cell(Vector2i(x, y), 6, Vector2i(0, 0))
				_:
					tilemap.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))


# ---------------------------------------------------------------------------
# Decorations
# ---------------------------------------------------------------------------

func _setup_decorations() -> void:
	decorations = Node2D.new()
	decorations.name = "Decorations"
	add_child(decorations)

	_create_bar_counter()
	_create_stage()
	_create_tables()
	_create_piano()
	_create_fireplace()
	_create_kitchen_area()
	_create_wall_banner()
	_create_wall_art()
	_create_stairs_archway()
	_create_floor_clutter()
	_create_lanterns()
	# Sleeping cat in the upper-right quiet corner
	_create_sleeping_cat(Vector2(26 * TILE_SIZE, 4.5 * TILE_SIZE))


# ---------------------------------------------------------------------------
# Bar counter
# ---------------------------------------------------------------------------

func _create_bar_counter() -> void:
	var counter = Node2D.new()
	counter.name = "BarCounter"

	# Counter body — 3 wide x 3 tall tiles
	var sprite = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 3, TILE_SIZE * 3, false, Image.FORMAT_RGBA8)

	var wood_top  = Color(0.58, 0.40, 0.24)  # Polished counter surface
	var wood_top2 = Color(0.62, 0.44, 0.28)
	var wood_body = Color(0.33, 0.20, 0.12)
	var wood_panel= Color(0.28, 0.16, 0.09)
	var brass_edge= Color(0.72, 0.58, 0.28)

	for y in range(TILE_SIZE * 3):
		for x in range(TILE_SIZE * 3):
			if y < 10:
				# Counter top with subtle grain
				var c = wood_top if (x + y) % 5 != 0 else wood_top2
				# Brass edge strip
				if y < 3 or x < 3 or x >= TILE_SIZE * 3 - 3:
					c = brass_edge
				img.set_pixel(x, y, c)
			else:
				# Panel front — recessed wood panels
				var panel = (x / 18) % 2
				var inset = ((x % 18) < 3 or (x % 18) > 14)
				var c = wood_body if panel == 0 else wood_panel
				if inset:
					c = c.darkened(0.20)
				img.set_pixel(x, y, c)

	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(3.5 * TILE_SIZE, 3.5 * TILE_SIZE)
	counter.add_child(sprite)

	# Bottles on shelf behind bar
	_add_bottles(counter)
	# Mug rack above bottles
	_add_mug_rack(counter)

	decorations.add_child(counter)


func _add_bottles(parent: Node2D) -> void:
	var bottles = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 3, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	# Shelf plank
	var shelf = Color(0.38, 0.24, 0.14)
	for y in range(26, 30):
		for x in range(0, TILE_SIZE * 3):
			img.set_pixel(x, y, shelf)

	var colors = [
		Color(0.70, 0.20, 0.20),  # Dark red wine
		Color(0.85, 0.72, 0.28),  # Amber mead
		Color(0.30, 0.52, 0.25),  # Green absinthe
		Color(0.55, 0.35, 0.15),  # Brown whiskey
		Color(0.20, 0.28, 0.52),  # Blue rum (local special)
		Color(0.65, 0.22, 0.45),  # Purple elderberry wine
	]

	for i in range(6):
		var bx = 4 + i * 14
		var col = colors[i]
		# Bottle body
		for y in range(8, 26):
			for x in range(bx, bx + 8):
				if x < TILE_SIZE * 3:
					var glass_shine = (x == bx + 2 and y < 18)
					img.set_pixel(x, y, Color(0.95, 0.95, 0.95, 0.5) if glass_shine else col)
		# Bottle neck
		for y in range(3, 9):
			for x in range(bx + 2, bx + 6):
				if x < TILE_SIZE * 3:
					img.set_pixel(x, y, col.darkened(0.25))
		# Cork
		for x in range(bx + 2, bx + 6):
			if x < TILE_SIZE * 3:
				img.set_pixel(x, 2, Color(0.60, 0.44, 0.28))

	bottles.texture = ImageTexture.create_from_image(img)
	bottles.position = Vector2(2 * TILE_SIZE, 1 * TILE_SIZE)
	parent.add_child(bottles)


func _add_mug_rack(parent: Node2D) -> void:
	## Hanging mugs above the bottles
	var mugs = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 3, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var rack = Color(0.35, 0.22, 0.12)
	# Rack bar
	for x in range(0, TILE_SIZE * 3):
		img.set_pixel(x, 0, rack)
		img.set_pixel(x, 1, rack)

	var mug_col = Color(0.60, 0.50, 0.35)
	var mug_rim = Color(0.70, 0.58, 0.40)
	for i in range(5):
		var mx = 8 + i * 17
		# Hook
		for y in range(2, 7):
			img.set_pixel(mx + 3, y, rack)
		# Mug body
		for y in range(7, 22):
			for x in range(mx, mx + 10):
				if x < TILE_SIZE * 3:
					img.set_pixel(x, y, mug_col)
		# Rim highlight
		for x in range(mx, mx + 10):
			if x < TILE_SIZE * 3:
				img.set_pixel(x, 7, mug_rim)
		# Handle
		for y in range(11, 19):
			var hx = mx + 10
			if hx < TILE_SIZE * 3:
				img.set_pixel(hx, y, mug_col)

	mugs.texture = ImageTexture.create_from_image(img)
	mugs.position = Vector2(2 * TILE_SIZE, 0)
	parent.add_child(mugs)


# ---------------------------------------------------------------------------
# Stage
# ---------------------------------------------------------------------------

func _create_stage() -> void:
	var stage = Node2D.new()
	stage.name = "Stage"

	## Raised platform — 8 wide x 3 tall tiles (cols 12-19, rows 2-4)
	var sprite = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 8, TILE_SIZE * 3, false, Image.FORMAT_RGBA8)

	var curtain      = Color(0.62, 0.12, 0.18)
	var curtain_dark = Color(0.45, 0.08, 0.12)
	var curtain_fold = Color(0.70, 0.18, 0.24)
	var trim         = Color(0.78, 0.62, 0.22)  # Gold fringe
	var edge_wood    = Color(0.32, 0.20, 0.10)  # Stage front edge
	var stage_floor  = Color(0.56, 0.40, 0.24)

	for y in range(TILE_SIZE * 3):
		for x in range(TILE_SIZE * 8):
			if y < TILE_SIZE + 4:
				# Curtain backdrop with deep vertical folds
				var fold_phase = (x % 20)
				var c = curtain
				if fold_phase < 3:
					c = curtain_dark
				elif fold_phase > 16:
					c = curtain_dark
				elif fold_phase in [7, 8]:
					c = curtain_fold
				# Gold fringe at bottom of curtain
				if y > TILE_SIZE - 5 and y < TILE_SIZE + 4:
					c = trim if x % 4 < 2 else c.darkened(0.1)
				img.set_pixel(x, y, c)
			elif y >= TILE_SIZE * 3 - 4:
				# Stage front edge (raised platform lip)
				img.set_pixel(x, y, edge_wood.darkened(float(TILE_SIZE * 3 - y - 1) * 0.06))
			else:
				# Stage floor
				var plank = x / 10
				var c = stage_floor if plank % 2 == 0 else stage_floor.darkened(0.08)
				if (x % 10) == 9:
					c = c.darkened(0.18)
				# Footlight warm glow near front of stage
				if y > TILE_SIZE * 2:
					c = c.blend(Color(0.8, 0.6, 0.3, 0.15))
				img.set_pixel(x, y, c)

	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(16 * TILE_SIZE, 3.5 * TILE_SIZE)
	stage.add_child(sprite)
	decorations.add_child(stage)


# ---------------------------------------------------------------------------
# Dining tables — varied clutter per table
# ---------------------------------------------------------------------------

func _create_tables() -> void:
	## 9 tables across bar zone, main hall, right area
	var table_defs = [
		# [grid_x_center, grid_y_center, clutter_type]
		[5.0, 6.5, "mugs"],
		[5.0, 9.5, "spilled"],
		[5.0, 12.5, "food"],
		[11.0, 6.5, "cards"],
		[14.5, 6.5, "mugs"],
		[11.0, 12.5, "dice"],
		[14.5, 12.5, "food"],
	]

	for td in table_defs:
		_draw_table(Vector2(td[0], td[1]), td[2])


func _draw_table(grid_pos: Vector2, clutter: String) -> void:
	var table_node = Node2D.new()

	var sprite = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 2, TILE_SIZE * 2, false, Image.FORMAT_RGBA8)

	var wood      = Color(0.42, 0.26, 0.14)
	var wood_dark = Color(0.33, 0.20, 0.10)
	var wood_edge = Color(0.28, 0.16, 0.08)
	var brass     = Color(0.68, 0.54, 0.24)

	# Table top
	for y in range(6, 26):
		for x in range(4, 60):
			var grain = (x + y * 2) % 7 == 0
			var c = wood_dark if grain else wood
			img.set_pixel(x, y, c)
	# Edge shadow
	for x in range(4, 60):
		img.set_pixel(x, 25, wood_edge)
		img.set_pixel(x, 26, wood_edge.darkened(0.2))

	# Table legs
	for leg_x in [8, 52]:
		for y in range(26, 64):
			for x in range(leg_x, leg_x + 4):
				if x < 64 and y < 64:
					img.set_pixel(x, y, wood_edge)
			# Brass cap
			if y == 26 or y == 62:
				for x in range(leg_x, leg_x + 4):
					if x < 64:
						img.set_pixel(x, y, brass)

	# Clutter on top
	_draw_table_clutter(img, clutter)

	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = grid_pos * TILE_SIZE
	table_node.add_child(sprite)
	decorations.add_child(table_node)


func _draw_table_clutter(img: Image, clutter: String) -> void:
	var mug_col   = Color(0.58, 0.48, 0.30)
	var mug_rim   = Color(0.72, 0.60, 0.40)
	var foam      = Color(0.95, 0.92, 0.85)
	var plate_col = Color(0.85, 0.80, 0.70)
	var food_col  = Color(0.72, 0.55, 0.28)
	var spill_col = Color(0.55, 0.38, 0.15)
	var card_col  = Color(0.92, 0.88, 0.78)
	var card_pip  = Color(0.75, 0.18, 0.18)

	match clutter:
		"mugs":
			for mx in [14, 40]:
				# Mug body
				for y in range(9, 22):
					for x in range(mx, mx + 9):
						img.set_pixel(x, y, mug_col)
				# Foam head
				for x in range(mx, mx + 9):
					img.set_pixel(x, 9, foam)
					img.set_pixel(x, 10, foam)
				# Handle
				for y in range(12, 20):
					img.set_pixel(mx + 9, y, mug_col)

		"spilled":
			# One mug upright
			for y in range(9, 22):
				for x in range(14, 23):
					img.set_pixel(x, y, mug_col)
			# Spilled mug on side + ale puddle
			for y in range(14, 22):
				for x in range(32, 52):
					img.set_pixel(x, y, mug_col)
			# Ale puddle
			for y in range(20, 26):
				for x in range(28, 56):
					if (x - 42) * (x - 42) * 2 + (y - 23) * (y - 23) * 6 < 90:
						img.set_pixel(x, y, spill_col)
			# Playing card fallen in spill
			for y in range(21, 25):
				for x in range(36, 44):
					img.set_pixel(x, y, card_col)

		"food":
			# Plate with remnants
			for y in range(9, 22):
				for x in range(20, 44):
					var dist2 = (x - 32) * (x - 32) + (y - 15) * (y - 15)
					if dist2 < 70:
						img.set_pixel(x, y, plate_col)
					elif dist2 < 84:
						img.set_pixel(x, y, plate_col.darkened(0.15))
			# Food bits
			for y in range(11, 20):
				for x in range(24, 40):
					var dist2 = (x - 32) * (x - 32) + (y - 15) * (y - 15)
					if dist2 < 40:
						img.set_pixel(x, y, food_col)
			# Utensils
			for y in range(8, 23):
				img.set_pixel(46, y, Color(0.75, 0.72, 0.65))
			for y in range(8, 23):
				img.set_pixel(48, y, Color(0.75, 0.72, 0.65))

		"cards":
			# Scattered playing cards
			var positions = [[10, 8], [22, 10], [36, 7], [44, 12]]
			for pos in positions:
				for y in range(pos[1], pos[1] + 8):
					for x in range(pos[0], pos[0] + 6):
						if x < 60 and y < 26:
							img.set_pixel(x, y, card_col)
				# Red pip on each card
				img.set_pixel(pos[0] + 2, pos[1] + 2, card_pip)
				img.set_pixel(pos[0] + 3, pos[1] + 4, card_pip)

		"dice":
			# Two dice on table
			var dice_colors = [Color(0.92, 0.88, 0.80), Color(0.90, 0.86, 0.78)]
			var pip_col = Color(0.22, 0.18, 0.14)
			for di in range(2):
				var dx = 16 + di * 20
				for y in range(10, 21):
					for x in range(dx, dx + 10):
						img.set_pixel(x, y, dice_colors[di])
				# Pips — die 1 shows 3, die 2 shows 5
				if di == 0:
					for pip in [[dx + 2, 12], [dx + 5, 15], [dx + 7, 18]]:
						img.set_pixel(pip[0], pip[1], pip_col)
						img.set_pixel(pip[0]+1, pip[1], pip_col)
				else:
					for pip in [[dx+2,11],[dx+7,11],[dx+5,15],[dx+2,19],[dx+7,19]]:
						img.set_pixel(pip[0], pip[1], pip_col)


# ---------------------------------------------------------------------------
# Piano
# ---------------------------------------------------------------------------

func _create_piano() -> void:
	var piano = Node2D.new()
	piano.name = "Piano"

	_piano_sprite = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 2, TILE_SIZE * 2, false, Image.FORMAT_RGBA8)

	var piano_black  = Color(0.08, 0.06, 0.04)
	var piano_brown  = Color(0.22, 0.13, 0.08)
	var keys_white   = Color(0.94, 0.91, 0.86)
	var keys_black   = Color(0.07, 0.05, 0.03)
	var gold_trim    = Color(0.72, 0.58, 0.24)
	var candleholder = Color(0.70, 0.55, 0.22)

	# Piano body
	for y in range(6, 60):
		for x in range(2, 62):
			var c = piano_black
			if x > 6 and x < 58 and y > 10 and y < 52:
				c = piano_brown
			if y == 6 or y == 59 or x == 2 or x == 61:
				c = gold_trim
			img.set_pixel(x, y, c)

	# Piano keys at front bottom
	for i in range(16):
		var key_x = 5 + i * 3
		var is_black = i % 7 in [1, 2, 4, 5, 6]
		for y in range(44, 55):
			for x in range(key_x, key_x + 3):
				if x < 60:
					img.set_pixel(x, y, keys_black if is_black else keys_white)

	# Music stand
	for y in range(14, 20):
		for x in range(18, 46):
			img.set_pixel(x, y, piano_brown.lightened(0.1))
	# Sheet music
	for y in range(15, 19):
		for x in range(20, 44):
			img.set_pixel(x, y, Color(0.94, 0.90, 0.82))
			if y % 2 == 0:
				img.set_pixel(x, y, Color(0.15, 0.12, 0.10))

	# Candle holder on top
	for y in range(4, 7):
		for x in range(28, 34):
			img.set_pixel(x, y, candleholder)
	# Candle flame (static here, just warm dot)
	img.set_pixel(30, 3, Color(1.0, 0.85, 0.3))
	img.set_pixel(31, 3, Color(1.0, 0.75, 0.2))

	_piano_sprite.texture = ImageTexture.create_from_image(img)
	_piano_sprite.position = Vector2(25 * TILE_SIZE, 15 * TILE_SIZE)
	piano.add_child(_piano_sprite)
	decorations.add_child(piano)
	_create_piano_interactable()


# ---------------------------------------------------------------------------
# Fireplace + sleeping dog
# ---------------------------------------------------------------------------

func _create_fireplace() -> void:
	## Stone fireplace at x 10-12, y 10-12 (hearth H tiles)
	## Animated fire on top
	var fp_node = Node2D.new()
	fp_node.name = "Fireplace"

	# Stone mantle sprite — 3x3 tiles
	var mantle = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 3, TILE_SIZE * 3, false, Image.FORMAT_RGBA8)

	var stone_outer = Color(0.42, 0.36, 0.28)
	var stone_inner = Color(0.35, 0.28, 0.20)
	var stone_lite  = Color(0.52, 0.44, 0.34)
	var soot_black  = Color(0.12, 0.09, 0.06)
	var ash         = Color(0.28, 0.22, 0.16)
	var mortar      = Color(0.55, 0.48, 0.38)
	var mantle_top  = Color(0.50, 0.42, 0.30)

	for y in range(TILE_SIZE * 3):
		for x in range(TILE_SIZE * 3):
			var cx = x - TILE_SIZE * 3 / 2
			var cy = y - TILE_SIZE * 3 / 2

			# Mantle shelf (top)
			if y < 10:
				var c = mantle_top
				if y == 0 or y == 9:
					c = mortar
				img.set_pixel(x, y, c)
			# Outer stone arch
			elif x < 14 or x > TILE_SIZE * 3 - 15:
				var c = stone_outer
				if (x + y) % 8 < 2:
					c = mortar
				img.set_pixel(x, y, c)
			# Inner firebox area
			elif y > 16 and y < TILE_SIZE * 3 - 8:
				if y > TILE_SIZE * 2:
					# Ash bed at bottom
					var c = ash if (x + y) % 3 != 0 else ash.darkened(0.15)
					img.set_pixel(x, y, c)
				else:
					# Sooty brick inside
					var c = soot_black
					if (x + y) % 12 < 3:
						c = Color(0.18, 0.13, 0.08)
					img.set_pixel(x, y, c)
			# Top arch transition
			elif y <= 16:
				var arch_dist = abs(cx)
				var c = stone_lite if arch_dist > 22 else soot_black
				if y == 10:
					c = stone_lite
				img.set_pixel(x, y, c)
			else:
				img.set_pixel(x, y, stone_outer)

	mantle.texture = ImageTexture.create_from_image(img)
	mantle.position = Vector2(11.5 * TILE_SIZE, 11.5 * TILE_SIZE)
	fp_node.add_child(mantle)

	# Animated fire sprite — positioned inside firebox
	_fire_sprite = Sprite2D.new()
	_fire_sprite.position = Vector2(12.5 * TILE_SIZE, 11.0 * TILE_SIZE)
	_fire_sprite.z_index = 5
	_generate_fire_frames()
	if _fire_frames.size() > 0:
		_fire_sprite.texture = _fire_frames[0]
	fp_node.add_child(_fire_sprite)

	# Point light at fireplace — warm orange glow
	_fireplace_light = PointLight2D.new()
	_fireplace_light.position = Vector2(12.5 * TILE_SIZE, 11.0 * TILE_SIZE)
	_fireplace_light.color = Color(1.0, 0.65, 0.25)
	_fireplace_light.energy = 0.8
	_fireplace_light.texture_scale = 3.0
	_fireplace_light.texture = _create_light_texture(128)
	fp_node.add_child(_fireplace_light)

	# Log pile beside fireplace
	_create_log_pile(fp_node, Vector2(9.5 * TILE_SIZE, 12.0 * TILE_SIZE))

	decorations.add_child(fp_node)

	# Sleeping dog near fireplace
	_create_sleeping_dog(Vector2(8.5 * TILE_SIZE, 12.5 * TILE_SIZE))


func _generate_fire_frames() -> void:
	_fire_frames.clear()
	for f in range(6):
		var img = Image.create(TILE_SIZE * 2, TILE_SIZE * 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.TRANSPARENT)
		_draw_fire_frame(img, f)
		_fire_frames.append(ImageTexture.create_from_image(img))


func _draw_fire_frame(img: Image, frame: int) -> void:
	var ember  = Color(0.90, 0.35, 0.05)
	var mid    = Color(1.00, 0.60, 0.10)
	var tip    = Color(1.00, 0.88, 0.30)
	var smoke  = Color(0.30, 0.24, 0.20, 0.45)

	var cx = TILE_SIZE
	var base_y = TILE_SIZE + 8

	# Draw layered flame cones — 3 overlapping tongues
	for tongue in range(3):
		var tx = cx + (tongue - 1) * 10 + sin(frame * 1.1 + tongue * 2.0) * 5
		var height = 28 + sin(frame * 0.9 + tongue) * 6
		for py in range(int(base_y - height), base_y + 1):
			var t = float(base_y - py) / height
			var width = int((1.0 - t) * 8.0 + 2.0)
			# Wobble sides
			var wobble = sin(frame * 1.3 + tongue * 1.7 + py * 0.3) * 2.0
			for px in range(int(tx - width + wobble), int(tx + width + wobble)):
				if px >= 0 and px < TILE_SIZE * 2 and py >= 0 and py < TILE_SIZE * 2:
					var existing = img.get_pixel(px, py)
					var flame_c: Color
					if t < 0.25:
						flame_c = ember
					elif t < 0.65:
						flame_c = mid
					else:
						flame_c = tip
					# Blend over existing
					var blended = existing.blend(flame_c)
					img.set_pixel(px, py, blended)

	# Ember glow at base
	for py in range(base_y - 4, base_y + 4):
		for px in range(cx - 12, cx + 12):
			if px >= 0 and px < TILE_SIZE * 2 and py >= 0 and py < TILE_SIZE * 2:
				var existing = img.get_pixel(px, py)
				if existing.a < 0.3:
					img.set_pixel(px, py, Color(ember.r, ember.g, ember.b, 0.6))

	# Wisp of smoke above
	for sy in range(base_y - 34, base_y - 28):
		for sx in range(cx - 3, cx + 4):
			if sx >= 0 and sx < TILE_SIZE * 2 and sy >= 0 and sy < TILE_SIZE * 2:
				var drift = sin(frame * 0.8 + sy * 0.2) * 3
				var spx = sx + int(drift)
				if spx >= 0 and spx < TILE_SIZE * 2:
					img.set_pixel(spx, sy, smoke)


func _animate_fire(delta: float) -> void:
	_fire_timer += delta
	if _fire_timer >= FIRE_ANIM_SPEED:
		_fire_timer -= FIRE_ANIM_SPEED
		_fire_frame = (_fire_frame + 1) % _fire_frames.size()
		if _fire_sprite and _fire_frames.size() > 0:
			_fire_sprite.texture = _fire_frames[_fire_frame]


var _flicker_time: float = 0.0
func _flicker_fireplace_light(delta: float) -> void:
	if not _fireplace_light:
		return
	_flicker_time += delta
	var base_energy = 0.8
	var flicker = sin(_flicker_time * 11.3) * 0.1 + sin(_flicker_time * 7.1) * 0.06
	_fireplace_light.energy = base_energy + flicker


func _create_log_pile(parent: Node2D, pos: Vector2) -> void:
	var logs = Sprite2D.new()
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var log_a = Color(0.38, 0.24, 0.12)
	var log_b = Color(0.30, 0.18, 0.08)
	var end_a = Color(0.55, 0.40, 0.24)
	var end_b = Color(0.48, 0.34, 0.18)

	# Three stacked logs
	for i in range(3):
		var ly = 20 - i * 7
		for y in range(ly, ly + 6):
			for x in range(2, 28):
				img.set_pixel(x, y, log_a if i % 2 == 0 else log_b)
		# Log end ring
		for y in range(ly, ly + 6):
			for x in range(24, 30):
				if x < 32:
					var ring = (y - ly - 3) * (y - ly - 3) + (x - 27) * (x - 27)
					img.set_pixel(x, y, end_a if ring < 5 else end_b)

	logs.texture = ImageTexture.create_from_image(img)
	logs.position = pos
	parent.add_child(logs)


func _create_sleeping_dog(pos: Vector2) -> void:
	_dog_sprite = Sprite2D.new()
	_dog_sprite.z_index = 3
	_generate_dog_frames()
	if _dog_frames.size() > 0:
		_dog_sprite.texture = _dog_frames[0]
	_dog_sprite.position = pos
	decorations.add_child(_dog_sprite)


func _generate_dog_frames() -> void:
	_dog_frames.clear()
	for f in range(2):
		var img = Image.create(TILE_SIZE + 16, 24, false, Image.FORMAT_RGBA8)
		img.fill(Color.TRANSPARENT)
		_draw_sleeping_dog(img, f)
		_dog_frames.append(ImageTexture.create_from_image(img))


func _draw_sleeping_dog(img: Image, frame: int) -> void:
	## Curled-up dog, side view, breathing cycle (frame 0 = exhale, frame 1 = inhale)
	var fur_a = Color(0.55, 0.38, 0.20)
	var fur_b = Color(0.48, 0.32, 0.16)
	var nose  = Color(0.25, 0.16, 0.14)
	var paw   = Color(0.50, 0.34, 0.18)

	var body_shift = 1 if frame == 1 else 0  # Slight belly expansion on inhale

	# Body blob — elongated oval
	for y in range(8 + body_shift, 22):
		var rel = float(y - (8 + body_shift)) / float(14 - body_shift)
		var w = int(22 * sin(rel * PI)) + 6
		var cx = 26
		for x in range(cx - w, cx + w):
			if x >= 0 and x < img.get_width():
				var c = fur_a if (x + y) % 3 != 0 else fur_b
				img.set_pixel(x, y, c)

	# Head (curled toward tail, right side)
	for y in range(5, 15):
		for x in range(38, 48):
			var dist = (x - 42) * (x - 42) + (y - 10) * (y - 10)
			if dist < 22:
				img.set_pixel(x, y, fur_a)

	# Snout
	for y in range(10, 14):
		for x in range(46, 50):
			if x < img.get_width():
				img.set_pixel(x, y, fur_b)
	img.set_pixel(48, 11, nose)

	# Ear
	for y in range(3, 8):
		for x in range(40, 45):
			img.set_pixel(x, y, fur_b)

	# Paws tucked under
	for x in range(14, 22):
		img.set_pixel(x, 21, paw)
		img.set_pixel(x, 22, paw)


func _animate_dog(delta: float) -> void:
	_dog_timer += delta
	if _dog_timer >= DOG_ANIM_SPEED:
		_dog_timer -= DOG_ANIM_SPEED
		_dog_frame = (_dog_frame + 1) % _dog_frames.size()
		if _dog_sprite and _dog_frames.size() > 0:
			_dog_sprite.texture = _dog_frames[_dog_frame]


# ---------------------------------------------------------------------------
# Sleeping cat in corner
# ---------------------------------------------------------------------------

func _create_sleeping_cat(pos: Vector2) -> void:
	var cat = Sprite2D.new()
	var img = Image.create(28, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var fur_a = Color(0.68, 0.62, 0.58)  # Grey tabby
	var fur_b = Color(0.58, 0.52, 0.48)
	var stripe = Color(0.40, 0.36, 0.32)
	var pink   = Color(0.90, 0.68, 0.68)

	# Body — tight curled oval
	for y in range(8, 18):
		var rel = float(y - 8) / 10.0
		var w = int(10 * sin(rel * PI)) + 4
		for x in range(14 - w, 14 + w):
			if x >= 0 and x < 28:
				var c = fur_a if (x + y) % 4 != 0 else fur_b
				# Tabby stripes
				if (x + y * 2) % 7 < 2:
					c = stripe
				img.set_pixel(x, y, c)

	# Head tucked to right
	for y in range(5, 13):
		for x in range(18, 26):
			var dist = (x - 22) * (x - 22) + (y - 9) * (y - 9)
			if dist < 14:
				var c = fur_a
				if (x + y * 2) % 7 < 2:
					c = stripe
				img.set_pixel(x, y, c)

	# Curled tail
	for t in range(8):
		var tx = int(12 - t * 1.2)
		var ty = int(15 - sin(float(t) / 8.0 * PI) * 4)
		if tx >= 0 and tx < 28 and ty >= 0 and ty < 20:
			img.set_pixel(tx, ty, fur_b)
			if tx + 1 < 28:
				img.set_pixel(tx + 1, ty, fur_b)

	# Nose dot
	img.set_pixel(23, 9, pink)
	# Eye closed slits
	img.set_pixel(21, 7, stripe)
	img.set_pixel(23, 7, stripe)

	cat.texture = ImageTexture.create_from_image(img)
	cat.position = pos
	cat.z_index = 3
	decorations.add_child(cat)


# ---------------------------------------------------------------------------
# Kitchen area — pot, shelves, pottery, barrel
# ---------------------------------------------------------------------------

func _create_kitchen_area() -> void:
	var kitchen = Node2D.new()
	kitchen.name = "Kitchen"
	kitchen.position = Vector2(21 * TILE_SIZE, 6 * TILE_SIZE)

	_create_cooking_station(kitchen)
	_create_kitchen_shelves(kitchen)
	_create_barrel(kitchen, Vector2(2.5 * TILE_SIZE, 7.5 * TILE_SIZE))

	decorations.add_child(kitchen)


func _create_cooking_station(parent: Node2D) -> void:
	## Iron tripod + cauldron over small fire
	var station = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 2, TILE_SIZE * 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var iron     = Color(0.25, 0.22, 0.20)
	var iron_lit = Color(0.40, 0.35, 0.28)
	var cauldron = Color(0.20, 0.18, 0.16)
	var broth    = Color(0.50, 0.42, 0.24)
	var steam_c  = Color(0.82, 0.80, 0.78, 0.55)
	var ember_c  = Color(0.80, 0.42, 0.12)

	# Tripod legs (3 diagonal lines)
	for i in range(3):
		var lx = 32 + int(cos(deg_to_rad(float(i) * 120.0)) * 20)
		var ly = 48 + int(sin(deg_to_rad(float(i) * 120.0)) * 12)
		for t in range(18):
			var px = int(lerp(32.0, float(lx), float(t) / 18.0))
			var py = int(lerp(22.0, float(ly), float(t) / 18.0))
			if px >= 0 and px < 64 and py >= 0 and py < 64:
				img.set_pixel(px, py, iron)
				if px + 1 < 64:
					img.set_pixel(px + 1, py, iron)

	# Cauldron body
	for y in range(20, 46):
		var rel = float(y - 20) / 26.0
		var w = int(sin(rel * PI) * 16.0) + 6
		for x in range(32 - w, 32 + w):
			if x >= 0 and x < 64:
				img.set_pixel(x, y, cauldron)

	# Broth surface (top of cauldron)
	for x in range(20, 44):
		img.set_pixel(x, 21, broth)
		img.set_pixel(x, 22, broth)
	for x in range(22, 42):
		img.set_pixel(x, 20, broth.lightened(0.1))

	# Steam wisps above
	for s in range(3):
		var sx = 26 + s * 6
		for y in range(10, 20):
			if sx >= 0 and sx < 64:
				img.set_pixel(sx, y, steam_c)

	# Small fire under cauldron
	for y in range(48, 58):
		for x in range(24, 40):
			if (x + y) % 3 != 0:
				img.set_pixel(x, y, ember_c)
			elif (x + y) % 5 == 0:
				img.set_pixel(x, y, Color(1.0, 0.75, 0.20))

	# Cauldron ring handle (top)
	for x in range(26, 38):
		img.set_pixel(x, 18, iron_lit)
		img.set_pixel(x, 19, iron)

	station.texture = ImageTexture.create_from_image(img)
	station.position = Vector2(TILE_SIZE, TILE_SIZE + 8)
	parent.add_child(station)

	# Cook animation sprite (stirring arm) — positioned beside station
	_cook_sprite = Sprite2D.new()
	_cook_sprite.z_index = 8
	_cook_sprite.position = Vector2(TILE_SIZE * 3, TILE_SIZE + 16)
	_generate_cook_frames()
	if _cook_frames.size() > 0:
		_cook_sprite.texture = _cook_frames[0]
	parent.add_child(_cook_sprite)


func _generate_cook_frames() -> void:
	_cook_frames.clear()
	for f in range(4):
		var img = Image.create(24, 40, false, Image.FORMAT_RGBA8)
		img.fill(Color.TRANSPARENT)
		_draw_cook_frame(img, f)
		_cook_frames.append(ImageTexture.create_from_image(img))


func _draw_cook_frame(img: Image, frame: int) -> void:
	## Simple cook seen from behind, arm rotating with ladle
	var apron  = Color(0.75, 0.70, 0.60)
	var shirt  = Color(0.45, 0.30, 0.18)
	var skin   = Color(0.85, 0.68, 0.55)
	var ladle  = Color(0.40, 0.36, 0.30)
	var hair   = Color(0.25, 0.18, 0.12)

	# Body / apron
	for y in range(14, 40):
		for x in range(5, 19):
			img.set_pixel(x, y, apron if y > 18 else shirt)

	# Head
	for y in range(4, 14):
		for x in range(7, 17):
			img.set_pixel(x, y, skin)
	for y in range(1, 6):
		for x in range(6, 18):
			img.set_pixel(x, y, hair)

	# Arm with ladle — rotates around shoulder
	var arm_angle = deg_to_rad(-30.0 + frame * 25.0)
	var shoulder = Vector2(14, 18)
	for t in range(12):
		var tf = float(t) / 12.0
		var ax = shoulder.x + cos(arm_angle) * tf * 14
		var ay = shoulder.y + sin(arm_angle) * tf * 14
		var px = int(ax)
		var py = int(ay)
		if px >= 0 and px < 24 and py >= 0 and py < 40:
			img.set_pixel(px, py, skin)
			if px + 1 < 24:
				img.set_pixel(px + 1, py, skin)

	# Ladle at end of arm
	var ladle_x = int(shoulder.x + cos(arm_angle) * 14)
	var ladle_y = int(shoulder.y + sin(arm_angle) * 14)
	for ly in range(ladle_y - 2, ladle_y + 3):
		for lx in range(ladle_x - 3, ladle_x + 4):
			if lx >= 0 and lx < 24 and ly >= 0 and ly < 40:
				img.set_pixel(lx, ly, ladle)


func _animate_cook(delta: float) -> void:
	_cook_timer += delta
	if _cook_timer >= COOK_ANIM_SPEED:
		_cook_timer -= COOK_ANIM_SPEED
		_cook_frame = (_cook_frame + 1) % _cook_frames.size()
		if _cook_sprite and _cook_frames.size() > 0:
			_cook_sprite.texture = _cook_frames[_cook_frame]


func _create_kitchen_shelves(parent: Node2D) -> void:
	## Wall shelves with pottery jars
	var shelves = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 2, TILE_SIZE * 3, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var shelf_wood = Color(0.36, 0.22, 0.12)
	var pot_a      = Color(0.62, 0.38, 0.24)  # Terracotta
	var pot_b      = Color(0.48, 0.40, 0.55)  # Glazed blue-purple
	var pot_c      = Color(0.55, 0.52, 0.35)  # Olive
	var pot_dark   = Color(0.28, 0.18, 0.10)
	var lid_col    = Color(0.68, 0.44, 0.28)

	var shelf_ys = [10, 46, 82]
	var pot_configs = [
		[[10, 8, pot_a], [28, 10, pot_b], [46, 9, pot_a]],
		[[8, 12, pot_c], [32, 8, pot_a], [50, 10, pot_b]],
		[[12, 10, pot_b], [36, 12, pot_c]],
	]

	for si in range(3):
		var sy = shelf_ys[si]
		# Shelf plank
		for x in range(0, TILE_SIZE * 2):
			for y in range(sy, sy + 4):
				img.set_pixel(x, y, shelf_wood)
			# Shadow under shelf
			img.set_pixel(x, sy + 4, shelf_wood.darkened(0.3))

		# Pots on shelf
		for pc in pot_configs[si]:
			var px = pc[0]
			var ph = pc[1]
			var col = pc[2]
			# Pot body — classic amphora silhouette
			for y in range(sy - ph, sy):
				var rel = float(y - (sy - ph)) / float(ph)
				var w = int(sin(rel * PI) * 7.0) + 4
				for x in range(px - w, px + w):
					if x >= 0 and x < TILE_SIZE * 2 and y >= 0 and y < TILE_SIZE * 3:
						var shade = col if (x + y) % 4 != 0 else col.darkened(0.15)
						img.set_pixel(x, y, shade)
			# Lid
			for x in range(px - 4, px + 4):
				var ly = sy - ph
				if ly >= 0 and ly < TILE_SIZE * 3 and x >= 0 and x < TILE_SIZE * 2:
					img.set_pixel(x, ly, lid_col)
					if ly + 1 < TILE_SIZE * 3:
						img.set_pixel(x, ly + 1, lid_col.darkened(0.1))

	shelves.texture = ImageTexture.create_from_image(img)
	shelves.position = Vector2(TILE_SIZE * 3.5, -TILE_SIZE * 0.5)
	parent.add_child(shelves)


func _create_barrel(parent: Node2D, pos: Vector2) -> void:
	var barrel = Sprite2D.new()
	var img = Image.create(TILE_SIZE, TILE_SIZE + 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var stave   = Color(0.42, 0.26, 0.14)
	var stave_d = Color(0.34, 0.20, 0.10)
	var hoop    = Color(0.48, 0.40, 0.28)
	var top_col = Color(0.50, 0.32, 0.18)

	# Barrel body — rounded staves
	for y in range(6, TILE_SIZE + 2):
		var rel = float(y - 6) / float(TILE_SIZE - 4)
		var w = int(sin(rel * PI) * 12.0) + 8
		for x in range(16 - w, 16 + w):
			if x >= 0 and x < 32:
				var stave_idx = (x + y / 4) % 3
				var c = stave if stave_idx != 1 else stave_d
				img.set_pixel(x, y, c)

	# Metal hoops
	for hoop_y in [12, 24, TILE_SIZE - 8]:
		for y in range(hoop_y, hoop_y + 3):
			var rel = float(y - 6) / float(TILE_SIZE - 4)
			var w = int(sin(rel * PI) * 12.0) + 8
			for x in range(16 - w, 16 + w):
				if x >= 0 and x < 32:
					img.set_pixel(x, y, hoop)

	# Top
	for x in range(7, 25):
		for y in range(4, 8):
			img.set_pixel(x, y, top_col)
	for x in range(5, 27):
		img.set_pixel(x, 6, hoop)

	barrel.texture = ImageTexture.create_from_image(img)
	barrel.position = pos
	parent.add_child(barrel)


# ---------------------------------------------------------------------------
# Wall banner — game crest, "dragon and sword" motif
# ---------------------------------------------------------------------------

func _create_wall_banner() -> void:
	## Hung on the top wall between cols 12-16, below the top brick row
	var banner = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 5, TILE_SIZE * 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var bg_a     = Color(0.45, 0.08, 0.12)   # Deep crimson
	var bg_b     = Color(0.38, 0.06, 0.10)
	var gold     = Color(0.82, 0.68, 0.28)
	var gold_d   = Color(0.65, 0.52, 0.18)
	var fringe   = Color(0.78, 0.62, 0.22)
	var dark_acc = Color(0.15, 0.10, 0.08)

	var w = TILE_SIZE * 5
	var h = TILE_SIZE * 2

	# Banner background with vertical folds
	for y in range(h):
		for x in range(w):
			var fold = (x % 20)
			var c = bg_a
			if fold < 2 or fold > 17:
				c = bg_b.darkened(0.1)
			elif fold in [8, 9]:
				c = bg_a.lightened(0.05)
			img.set_pixel(x, y, c)

	# Gold border frame
	for x in range(w):
		img.set_pixel(x, 0, gold)
		img.set_pixel(x, 1, gold_d)
		img.set_pixel(x, h - 2, gold_d)
		img.set_pixel(x, h - 1, gold)
	for y in range(h):
		img.set_pixel(0, y, gold)
		img.set_pixel(1, y, gold_d)
		img.set_pixel(w - 2, y, gold_d)
		img.set_pixel(w - 1, y, gold)

	# Central dragon crest — stylized silhouette
	var cx = w / 2
	var cy = h / 2

	# Dragon body (S-curve)
	for t in range(24):
		var tf = float(t) / 24.0
		var dx = int(cx + sin(tf * PI * 1.5) * 22)
		var dy = int(cy - 10 + tf * 22)
		for px in range(dx - 2, dx + 3):
			for py in range(dy - 2, dy + 3):
				if px >= 4 and px < w - 4 and py >= 4 and py < h - 4:
					img.set_pixel(px, py, gold)

	# Dragon head (right side, top)
	for y in range(cy - 14, cy - 6):
		for x in range(cx + 18, cx + 30):
			var dist = (x - (cx + 24)) * (x - (cx + 24)) + (y - (cy - 10)) * (y - (cy - 10))
			if dist < 22:
				img.set_pixel(x, y, gold)

	# Dragon wing (left span)
	for t in range(18):
		var tf = float(t) / 18.0
		var wx = int(cx - 30 + tf * 26)
		var wy = int(cy - 8 - sin(tf * PI) * 16)
		for px in range(wx - 1, wx + 3):
			for py in range(wy, wy + 4):
				if px >= 4 and px < w - 4 and py >= 4 and py < h - 4:
					img.set_pixel(px, py, gold_d)

	# Sword below dragon (vertical, gold cross hilt)
	var sword_x = cx
	# Blade
	for y in range(cy - 4, cy + 22):
		if sword_x >= 4 and sword_x < w - 4 and y >= 4 and y < h - 4:
			img.set_pixel(sword_x, y, gold)
			img.set_pixel(sword_x + 1, y, gold_d)
	# Cross guard
	for x in range(sword_x - 8, sword_x + 10):
		for y in range(cy + 4, cy + 7):
			if x >= 4 and x < w - 4 and y >= 4 and y < h - 4:
				img.set_pixel(x, y, gold)

	# Fringe at bottom
	for i in range(12):
		var fx = 8 + i * 12
		for y in range(h - 8, h):
			if fx < w:
				img.set_pixel(fx, y, fringe)
				if fx + 1 < w:
					img.set_pixel(fx + 1, y, fringe)

	# Dark outline on crest elements for legibility
	for y in range(3, h - 3):
		for x in range(3, w - 3):
			if img.get_pixel(x, y) == gold or img.get_pixel(x, y) == gold_d:
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var nx = x + dx
						var ny = y + dy
						if nx >= 0 and nx < w and ny >= 0 and ny < h:
							var nc = img.get_pixel(nx, ny)
							if nc.r < 0.3 and nc.g < 0.2 and nc.b > 0.05:
								# It's bg — add outline pixel
								pass  # outline naturally from bg contrast

	banner.texture = ImageTexture.create_from_image(img)
	banner.position = Vector2(13.5 * TILE_SIZE, 1.5 * TILE_SIZE)
	banner.z_index = 2
	decorations.add_child(banner)


# ---------------------------------------------------------------------------
# Wall art: framed painting, dartboard, copper pots hung near kitchen
# ---------------------------------------------------------------------------

func _create_wall_art() -> void:
	_create_framed_painting(Vector2(7 * TILE_SIZE, 1.5 * TILE_SIZE))
	_create_dartboard(Vector2(19 * TILE_SIZE, 1.5 * TILE_SIZE))
	_create_hung_copper_pots(Vector2(24 * TILE_SIZE, 1.2 * TILE_SIZE))
	_create_weapon_rack(Vector2(1.2 * TILE_SIZE, 6.5 * TILE_SIZE))


func _create_framed_painting(pos: Vector2) -> void:
	var frame_sp = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 2, TILE_SIZE + 12, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var frame_c  = Color(0.60, 0.44, 0.20)
	var frame_d  = Color(0.48, 0.34, 0.14)
	var sky      = Color(0.35, 0.48, 0.68)
	var hill_c   = Color(0.28, 0.48, 0.22)
	var path_c   = Color(0.58, 0.48, 0.32)
	var sun_c    = Color(0.92, 0.80, 0.40)

	var fw = TILE_SIZE * 2
	var fh = TILE_SIZE + 12

	# Gold frame border
	for x in range(fw):
		for y in range(fh):
			if x < 4 or x >= fw - 4 or y < 4 or y >= fh - 4:
				img.set_pixel(x, y, frame_c if (x + y) % 3 != 0 else frame_d)

	# Landscape inside frame
	for y in range(4, fh - 4):
		for x in range(4, fw - 4):
			var c = sky
			# Hill silhouette
			var hill_h = int(10 + sin(float(x - 4) / float(fw - 8) * PI) * 14)
			if y > (fh - 4) - hill_h:
				c = hill_c
			# Path winding through
			var path_center = fw / 2 + int(sin(float(y) / 6.0) * 5)
			if abs(x - path_center) < 3 and y > fh / 2:
				c = path_c
			# Sun
			var sun_dist = (x - (fw - 12)) * (x - (fw - 12)) + (y - 8) * (y - 8)
			if sun_dist < 14:
				c = sun_c
			img.set_pixel(x, y, c)

	frame_sp.texture = ImageTexture.create_from_image(img)
	frame_sp.position = pos
	frame_sp.z_index = 2
	decorations.add_child(frame_sp)


func _create_dartboard(pos: Vector2) -> void:
	var dart_sp = Sprite2D.new()
	var size = TILE_SIZE + 8
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var rings = [
		Color(0.15, 0.12, 0.10),  # Outer dark
		Color(0.72, 0.18, 0.18),  # Red
		Color(0.15, 0.12, 0.10),
		Color(0.78, 0.72, 0.60),  # Cream
		Color(0.72, 0.18, 0.18),
		Color(0.15, 0.12, 0.10),
		Color(0.22, 0.55, 0.22),  # Green bull
		Color(0.72, 0.18, 0.18),  # Bullseye
	]

	var cx = size / 2
	var cy = size / 2

	for y in range(size):
		for x in range(size):
			var d = sqrt(float((x - cx) * (x - cx) + (y - cy) * (y - cy)))
			var ring_idx = int(d / (float(cx) / 8.0))
			if ring_idx < rings.size():
				img.set_pixel(x, y, rings[ring_idx])

	# Wire lines (pie slices)
	for i in range(8):
		var angle = deg_to_rad(float(i) * 45.0)
		for t in range(cx):
			var px = cx + int(cos(angle) * float(t))
			var py = cy + int(sin(angle) * float(t))
			if px >= 0 and px < size and py >= 0 and py < size:
				img.set_pixel(px, py, Color(0.30, 0.26, 0.22))

	# Two darts stuck in board
	for dart in range(2):
		var da = deg_to_rad(float(dart) * 40.0 - 20.0)
		var dr = cx / 2
		var dax = cx + int(cos(da) * dr)
		var day = cy + int(sin(da) * dr)
		img.set_pixel(dax, day, Color(0.80, 0.75, 0.65))
		img.set_pixel(dax + 1, day, Color(0.72, 0.18, 0.18))

	dart_sp.texture = ImageTexture.create_from_image(img)
	dart_sp.position = pos
	dart_sp.z_index = 2
	decorations.add_child(dart_sp)


func _create_hung_copper_pots(pos: Vector2) -> void:
	var pots_sp = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 2, TILE_SIZE + 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var copper   = Color(0.75, 0.45, 0.22)
	var copper_d = Color(0.55, 0.32, 0.14)
	var copper_s = Color(0.88, 0.60, 0.30)
	var hook_col = Color(0.35, 0.30, 0.25)
	var rack_col = Color(0.32, 0.26, 0.18)

	# Rack bar
	for x in range(0, TILE_SIZE * 2):
		img.set_pixel(x, 0, rack_col)
		img.set_pixel(x, 1, rack_col)

	var pot_xs = [12, 30, 48]
	var pot_sizes = [14, 10, 12]

	for pi in range(3):
		var px = pot_xs[pi]
		var pr = pot_sizes[pi]
		# Hook
		for y in range(2, 8):
			img.set_pixel(px, y, hook_col)
		# Pot body
		for y in range(8, 8 + pr * 2):
			var rel = float(y - 8) / float(pr * 2)
			var w = int(sin(rel * PI) * float(pr) * 0.9) + 4
			for x in range(px - w, px + w):
				if x >= 0 and x < TILE_SIZE * 2 and y >= 0 and y < TILE_SIZE + 8:
					var shade = copper
					if x == px - w + 2:
						shade = copper_s
					elif x > px + w - 3:
						shade = copper_d
					img.set_pixel(x, y, shade)
		# Rim
		for x in range(px - pr, px + pr):
			if x >= 0 and x < TILE_SIZE * 2:
				img.set_pixel(x, 8, copper_s)
		# Handle loops on sides
		for y in range(12, 18):
			var hx = px - pot_sizes[pi] - 1
			if hx >= 0:
				img.set_pixel(hx, y, hook_col)
			hx = px + pot_sizes[pi]
			if hx < TILE_SIZE * 2:
				img.set_pixel(hx, y, hook_col)

	pots_sp.texture = ImageTexture.create_from_image(img)
	pots_sp.position = pos
	pots_sp.z_index = 2
	decorations.add_child(pots_sp)


func _create_weapon_rack(pos: Vector2) -> void:
	## Decorative weapon rack on left wall — two crossed swords + axe
	var rack_sp = Sprite2D.new()
	var img = Image.create(TILE_SIZE, TILE_SIZE * 3, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var iron    = Color(0.62, 0.60, 0.58)
	var iron_d  = Color(0.42, 0.40, 0.38)
	var wood_h  = Color(0.40, 0.24, 0.12)
	var gold_g  = Color(0.72, 0.58, 0.24)
	var rack_c  = Color(0.30, 0.20, 0.10)

	# Rack mounting pegs
	for py in [14, TILE_SIZE + 14, TILE_SIZE * 2 + 14]:
		for y in range(py, py + 5):
			for x in range(12, 20):
				img.set_pixel(x, y, rack_c)

	# Sword 1 (left diagonal)
	for t in range(50):
		var tf = float(t) / 50.0
		var sx = int(4 + tf * 12)
		var sy = int(tf * 50)
		if sx < 32 and sy < TILE_SIZE * 3:
			img.set_pixel(sx, sy, iron)
			if sx + 1 < 32:
				img.set_pixel(sx + 1, sy, iron_d)
	# Guard on sword 1
	for x in range(2, 14):
		img.set_pixel(x, 22, gold_g)

	# Sword 2 (right diagonal, crossing)
	for t in range(50):
		var tf = float(t) / 50.0
		var sx = int(18 - tf * 10)
		var sy = int(tf * 50)
		if sx >= 0 and sx < 32 and sy < TILE_SIZE * 3:
			img.set_pixel(sx, sy, iron)
			if sx + 1 < 32:
				img.set_pixel(sx + 1, sy, iron_d)
	for x in range(14, 26):
		img.set_pixel(x, 24, gold_g)

	# Axe head (lower part of rack)
	var axe_cy = TILE_SIZE * 2 + 8
	for y in range(axe_cy, axe_cy + 20):
		for x in range(8, 24):
			var rel_y = float(y - axe_cy) / 20.0
			var w = int(sin(rel_y * PI) * 8.0) + 3
			if abs(x - 16) < w:
				img.set_pixel(x, y, iron if (x + y) % 3 != 0 else iron_d)
	# Axe handle
	for y in range(axe_cy + 20, TILE_SIZE * 3 - 4):
		img.set_pixel(15, y, wood_h)
		img.set_pixel(16, y, wood_h)

	rack_sp.texture = ImageTexture.create_from_image(img)
	rack_sp.position = pos
	rack_sp.z_index = 2
	decorations.add_child(rack_sp)


# ---------------------------------------------------------------------------
# Stairs archway — visual only, dark arch suggesting "up"
# ---------------------------------------------------------------------------

func _create_stairs_archway() -> void:
	## In bottom-right corner, over the U tiles (cols 26-27, rows 14-15)
	var arch = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 2 + 8, TILE_SIZE * 3, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var stone_a = Color(0.42, 0.34, 0.26)
	var stone_b = Color(0.35, 0.28, 0.20)
	var mortar  = Color(0.55, 0.46, 0.36)
	var arch_void = Color(0.08, 0.06, 0.05)
	var arch_glow = Color(0.35, 0.24, 0.14)  # Faint warm light from upper floor

	var w = TILE_SIZE * 2 + 8
	var h = TILE_SIZE * 3

	# Stone arch surround
	for y in range(h):
		for x in range(w):
			# Arch interior (the opening)
			var ax = x - w / 2
			var top_open = h / 3
			var is_arch = y > top_open and abs(ax) < (w / 2 - 10)
			if y < top_open:
				# Arch crown — curved
				var arch_r = float(w / 2 - 10)
				var dist = sqrt(float(ax * ax) + float((y - top_open) * (y - top_open)))
				is_arch = dist < arch_r

			if is_arch:
				# Inside the archway — dark with faint glow at top
				var bright = float(y) / float(h)
				var c = arch_void.lerp(arch_glow, bright * 0.4)
				img.set_pixel(x, y, c)
			else:
				# Stone surround with mortar
				var row = y / 8
				var off = (row % 2) * 7
				var in_mortar = (y % 8) < 2 or ((x + off) % 14) < 2
				if in_mortar:
					img.set_pixel(x, y, mortar)
				else:
					var c = stone_a if (x / 8 + row) % 2 == 0 else stone_b
					img.set_pixel(x, y, c)

	# "UP" arrow hint inside arch
	var arrow_x = w / 2
	var arrow_y = int(h * 0.55)
	for ay in range(arrow_y, arrow_y + 8):
		img.set_pixel(arrow_x, ay, arch_glow.lightened(0.3))
	for d in range(5):
		var apx = arrow_x - d
		var apy = arrow_y + d
		if apx >= 0 and apx < w and apy >= 0 and apy < h:
			img.set_pixel(apx, apy, arch_glow.lightened(0.3))
		apx = arrow_x + d
		if apx < w and apy < h:
			img.set_pixel(apx, apy, arch_glow.lightened(0.3))

	arch.texture = ImageTexture.create_from_image(img)
	arch.position = Vector2(26.0 * TILE_SIZE, 13.5 * TILE_SIZE)
	arch.z_index = 6
	decorations.add_child(arch)


# ---------------------------------------------------------------------------
# Floor clutter: ale stains, dropped playing card
# ---------------------------------------------------------------------------

func _create_floor_clutter() -> void:
	# Ale stain near the "spilled" table (col 5, row 9.5 — floor tile offset)
	_draw_floor_stain(Vector2(5.8 * TILE_SIZE, 10.5 * TILE_SIZE))
	# Dropped playing card near "cards" table
	_draw_floor_card(Vector2(11.6 * TILE_SIZE, 7.8 * TILE_SIZE))


func _draw_floor_stain(pos: Vector2) -> void:
	var stain = Sprite2D.new()
	var img = Image.create(28, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var ale_dark = Color(0.42, 0.30, 0.14, 0.70)
	var ale_edge = Color(0.50, 0.36, 0.18, 0.40)

	for y in range(16):
		for x in range(28):
			var dist = float((x - 14) * (x - 14)) / 80.0 + float((y - 8) * (y - 8)) / 28.0
			if dist < 1.0:
				var c = ale_dark if dist < 0.5 else ale_edge
				img.set_pixel(x, y, c)

	stain.texture = ImageTexture.create_from_image(img)
	stain.position = pos
	stain.z_index = 1
	decorations.add_child(stain)


func _draw_floor_card(pos: Vector2) -> void:
	var card_sp = Sprite2D.new()
	var img = Image.create(14, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var card_bg  = Color(0.92, 0.88, 0.80)
	var card_pip = Color(0.70, 0.16, 0.16)
	var card_brd = Color(0.50, 0.40, 0.28)

	# Card face
	for y in range(2, 18):
		for x in range(2, 12):
			img.set_pixel(x, y, card_bg)
	# Border
	for x in range(12):
		img.set_pixel(x, 2, card_brd)
		img.set_pixel(x, 17, card_brd)
	for y in range(18):
		img.set_pixel(2, y, card_brd)
		img.set_pixel(11, y, card_brd)
	# Suit pip — heart
	img.set_pixel(5, 6, card_pip)
	img.set_pixel(6, 5, card_pip)
	img.set_pixel(7, 6, card_pip)
	img.set_pixel(6, 7, card_pip)
	img.set_pixel(5, 7, card_pip)
	img.set_pixel(7, 7, card_pip)
	img.set_pixel(6, 8, card_pip)

	card_sp.texture = ImageTexture.create_from_image(img)
	card_sp.rotation = 0.35
	card_sp.position = pos
	card_sp.z_index = 1
	decorations.add_child(card_sp)


# ---------------------------------------------------------------------------
# Hanging lanterns — warm light pools
# ---------------------------------------------------------------------------

func _create_lanterns() -> void:
	var lantern_positions = [
		Vector2(5 * TILE_SIZE, 2 * TILE_SIZE),
		Vector2(12 * TILE_SIZE, 2 * TILE_SIZE),
		Vector2(18 * TILE_SIZE, 2 * TILE_SIZE),
		Vector2(24 * TILE_SIZE, 2 * TILE_SIZE),
	]

	for lpos in lantern_positions:
		_create_lantern(lpos)


func _create_lantern(pos: Vector2) -> void:
	## Hanging lantern sprite + point light below
	var lantern = Sprite2D.new()
	var img = Image.create(16, 28, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var iron_c   = Color(0.28, 0.24, 0.20)
	var glass_c  = Color(0.90, 0.80, 0.45, 0.80)
	var flame_c  = Color(1.00, 0.85, 0.35)
	var chain_c  = Color(0.35, 0.30, 0.24)

	# Chain links
	for y in range(0, 6):
		if y % 3 < 2:
			img.set_pixel(7, y, chain_c)
			img.set_pixel(8, y, chain_c)

	# Lantern top cap
	for x in range(4, 12):
		img.set_pixel(x, 6, iron_c)
		img.set_pixel(x, 7, iron_c)

	# Lantern body (glass panels)
	for y in range(8, 22):
		for x in range(3, 13):
			var c = glass_c
			# Iron frame corners
			if x == 3 or x == 12 or y == 8 or y == 21:
				c = iron_c
			img.set_pixel(x, y, c)

	# Flame inside
	img.set_pixel(7, 14, flame_c)
	img.set_pixel(8, 13, flame_c)
	img.set_pixel(8, 14, flame_c)
	img.set_pixel(8, 15, Color(1.0, 0.65, 0.2))

	# Bottom hook
	for y in range(22, 26):
		img.set_pixel(7, y, iron_c)
		img.set_pixel(8, y, iron_c)

	lantern.texture = ImageTexture.create_from_image(img)
	lantern.position = pos
	lantern.z_index = 8
	decorations.add_child(lantern)

	# Light pool below lantern
	var light = PointLight2D.new()
	light.position = pos + Vector2(0, 32)
	light.color = Color(1.0, 0.82, 0.45)
	light.energy = 0.45
	light.texture_scale = 1.8
	light.texture = _create_light_texture(96)
	decorations.add_child(light)


func _create_light_texture(size: int = 256) -> ImageTexture:
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = size / 2

	for y in range(size):
		for x in range(size):
			var dist = Vector2(x - center, y - center).length()
			var alpha = clampf(1.0 - (dist / center), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, alpha * alpha))

	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Dancer
# ---------------------------------------------------------------------------

func _setup_dancer() -> void:
	dancer_sprite = Sprite2D.new()
	dancer_sprite.name = "DancingGirl"
	dancer_sprite.position = Vector2(20 * TILE_SIZE, 3.5 * TILE_SIZE)
	dancer_sprite.z_index = 10
	add_child(dancer_sprite)
	_generate_dancer_sprites()


func _generate_dancer_sprites() -> void:
	_dancer_frames.clear()
	for frame in range(4):
		var image = Image.create(32, 48, false, Image.FORMAT_RGBA8)
		_draw_dancer(image, frame)
		_dancer_frames.append(ImageTexture.create_from_image(image))
	if _dancer_frames.size() > 0:
		dancer_sprite.texture = _dancer_frames[0]


func _draw_dancer(image: Image, frame: int) -> void:
	image.fill(Color.TRANSPARENT)

	var skin         = Color(0.95, 0.80, 0.70)
	var hair         = Color(0.85, 0.65, 0.25)
	var dress        = Color(0.85, 0.25, 0.35)
	var dress_light  = Color(0.95, 0.45, 0.55)
	var dress_sparkle= Color(1.0, 0.9, 0.5)

	var arm_angle   = sin(frame * PI / 2) * 6
	var leg_angle   = cos(frame * PI / 2) * 4
	var body_sway   = sin(frame * PI / 2) * 3
	var hair_flow   = sin(frame * PI / 2 + 0.5) * 4

	var cx = 16 + int(body_sway)

	# Head
	for y in range(4, 14):
		for x in range(cx - 5, cx + 5):
			if x >= 0 and x < 32:
				image.set_pixel(x, y, skin)

	# Hair
	for y in range(0, 12):
		for x in range(cx - 6, cx + 6):
			if x >= 0 and x < 32 and y < 10:
				image.set_pixel(x, y, hair)

	# Side hair waves
	for y in range(6, 22):
		var hx = cx + 6 + int(hair_flow)
		if hx >= 0 and hx < 32:
			image.set_pixel(hx, y, hair)
		hx = cx - 7 - int(hair_flow)
		if hx >= 0 and hx < 32:
			image.set_pixel(hx, y, hair)

	# Dress body
	for y in range(14, 40):
		var dress_width = 6 if y < 24 else 8 + (y - 24) / 3
		for x in range(cx - dress_width, cx + dress_width):
			if x >= 0 and x < 32:
				var c = dress if (x + y) % 3 != 0 else dress_light
				if (x + y + frame * 5) % 11 == 0:
					c = dress_sparkle
				image.set_pixel(x, y, c)

	# Arms
	var left_arm_x = cx - 8 + int(arm_angle)
	var right_arm_x = cx + 7 - int(arm_angle)
	for y in range(16, 26):
		if left_arm_x >= 0 and left_arm_x < 32:
			image.set_pixel(left_arm_x, y, skin)
			if left_arm_x + 1 < 32:
				image.set_pixel(left_arm_x + 1, y, skin)
		if right_arm_x >= 0 and right_arm_x < 32:
			image.set_pixel(right_arm_x, y, skin)
			if right_arm_x - 1 >= 0:
				image.set_pixel(right_arm_x - 1, y, skin)

	# Legs
	var left_leg_x = cx - 4 + int(leg_angle)
	var right_leg_x = cx + 3 - int(leg_angle)
	for y in range(40, 48):
		if left_leg_x >= 0 and left_leg_x < 32:
			image.set_pixel(left_leg_x, y, skin)
		if right_leg_x >= 0 and right_leg_x < 32:
			image.set_pixel(right_leg_x, y, skin)


func _animate_dancer(delta: float) -> void:
	_anim_timer += delta
	if _anim_timer >= ANIM_SPEED:
		_anim_timer -= ANIM_SPEED
		_anim_frame = (_anim_frame + 1) % _dancer_frames.size()
		if dancer_sprite and _dancer_frames.size() > 0:
			dancer_sprite.texture = _dancer_frames[_anim_frame]


# ---------------------------------------------------------------------------
# NPCs
# ---------------------------------------------------------------------------

func _setup_npcs() -> void:
	npcs = Node2D.new()
	npcs.name = "NPCs"
	add_child(npcs)

	# --- Bar zone ---
	_create_npc("Osric", "bartender", Vector2(2.5, 4), [
		"Osric: Welcome to The Dancing Tonberry!",
		"Osric: What'll it be? Mead? Ale? Liquid courage?",
		"Osric: *polishes glass* The cave's been... hungry lately.",
		"Osric: Some say the monsters are learning. Adapting.",
		"Osric: If you're smart, you'll automate. The cave respects efficiency.",
		"Osric: But push too hard... and it pushes back. *chuckles darkly*"
	])

	_create_npc("Old Mack", "villager", Vector2(4, 5), [
		"Old Mack: *slurring* Hic... another one bites the cave...",
		"Old Mack: You know what's funny? I was an adventurer once.",
		"Old Mack: Spent WEEKS grinding those rats. Weeks!",
		"Old Mack: Then some kid shows up with a script...",
		"Old Mack: ...clears the place in an afternoon. AN AFTERNOON!",
		"Old Mack: *finishes drink* Progress, they call it. I call it cheating.",
		"Old Mack: But what do I know? I'm just a 'tutorial NPC' now."
	])

	# --- Stage ---
	_create_npc("Aria", "dancer", Vector2(21, 5), [
		"Aria: *graceful curtsy* Welcome, hero~",
		"Aria: I dance to lift spirits... and to forget.",
		"Aria: My brother went into the cave. He was a 'Scriptweaver.'",
		"Aria: He said he'd found a way to rewrite the rules...",
		"Aria: *twirls* But rules have a way of rewriting you.",
		"Aria: Be careful what you automate. Some things fight back.",
		"Aria: *wink* Come back alive, okay? I'll save you a dance~"
	])

	# --- Main dining hall ---
	_create_npc("Sir Reginald", "knight", Vector2(5, 7), [
		"Sir Reginald: *hiccup* Brave Sir Reginald, they called me!",
		"Sir Reginald: I once MANUALLY fought every battle. Every. One.",
		"Sir Reginald: No scripts! No automation! Pure skill!",
		"Sir Reginald: Took me three months to reach floor 3.",
		"Sir Reginald: Then the Rat King... *shudders*",
		"Sir Reginald: He said something before attacking...",
		"Sir Reginald: 'Your persistence is admirable. But I've EVOLVED.'",
		"Sir Reginald: *stares into mug* The cave learns, friend. It learns."
	])

	_create_npc("Martha", "villager", Vector2(15, 7), [
		"Martha: Did you hear about the Time Mage?",
		"Martha: They say he can UNDO death itself!",
		"Martha: Rewinding saves, erasing mistakes...",
		"Martha: But there's a cost. There's always a cost.",
		"Martha: Every rewind leaves a scar on the timeline.",
		"Martha: Too many, and reality starts to... glitch.",
		"Martha: *whispers* I've seen adventurers flicker.",
		"Martha: Here one moment, gone the next. Like they never existed."
	])

	# Traveling minstrel with lute at table
	_create_npc("Melody", "bard", Vector2(11, 13), [
		"Melody: *strumming lute* Care for a song, traveler?",
		"Melody: I compose ballads of brave autobattlers~",
		"Melody: 'The Hero Who Slept Through Victory'...",
		"Melody: 'A Thousand Rats, One Script'...",
		"Melody: 'The Recursion of Summoner Steve'...",
		"Melody: That last one goes forever. Literally.",
		"Melody: *laughs* He summoned himself summoning himself!",
		"Melody: They say he's still casting somewhere in memory."
	])

	# Drunk patron slumped at table
	_create_npc("Barfton", "villager", Vector2(15, 13), [
		"Barfton: *face down* zzzz...",
		"Barfton: ...",
		"Barfton: hm? oh. you. *blinks*",
		"Barfton: cave's a lie. whole thing. scripted.",
		"Barfton: *slumps back* zzzz..."
	])

	# Two-person gambling / dice game
	_create_npc("Knuckles", "rogue", Vector2(5, 13), [
		"Knuckles: Eyes on the dice, friend. Eyes on the dice.",
		"Knuckles: Ten gold says the next roll is a double.",
		"Knuckles: I've been tracking the RNG for three hours.",
		"Knuckles: Did you know this world uses a linear congruential PRNG?",
		"Knuckles: *grins* I exploited the seed. My odds are... favorable."
	])

	_create_npc("Dewey", "villager", Vector2(5, 14), [
		"Dewey: He says that EVERY time. And I keep losing.",
		"Dewey: There's definitely something wrong with these dice.",
		"Dewey: ...or with me. Hard to tell at this point."
	])

	# Off-duty guard nursing a drink
	_create_npc("Guard Henryk", "knight", Vector2(11, 7), [
		"Guard Henryk: Off duty. Don't look at me.",
		"Guard Henryk: ...fine. You want to know why I drink?",
		"Guard Henryk: I've guarded this village for six YEARS.",
		"Guard Henryk: Nothing ever happens here. Adventurers come, adventurers go.",
		"Guard Henryk: The monsters in the cave? Never actually attack the village.",
		"Guard Henryk: It's all very... scripted.",
		"Guard Henryk: *sighs* Don't tell the captain I said that."
	])

	# Mysterious patron
	_create_npc("???", "mysterious", Vector2(24, 13), [
		"???: ...",
		"???: You can see me?",
		"???: Most walk right past. Too busy grinding.",
		"???: I've been watching this loop for... how long now?",
		"???: The cave. The village. The battles. The saves.",
		"???: Did you know there's a class that can SEE the code?",
		"???: The Scriptweaver. They say one went mad reading the source.",
		"???: Found comments in the margins. Developer notes.",
		"???: 'TODO: Add meaning to NPC lives' *laughs bitterly*",
		"???: We're all just waiting for someone to write us a purpose."
	])


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
		"bartender":  color = Color(0.50, 0.35, 0.20)
		"dancer":     color = Color(0.90, 0.40, 0.50)
		"knight":     color = Color(0.60, 0.60, 0.70)
		"mysterious": color = Color(0.30, 0.20, 0.40)
		"bard":       color = Color(0.70, 0.60, 0.30)
		"rogue":      color = Color(0.35, 0.45, 0.30)

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
		exit.name = "Exit"
		exit.target_map = "harmonia_village"
		exit.target_spawn = "bar_exit"
		exit.require_interaction = false
		exit.position = Vector2(14 * TILE_SIZE, 16.5 * TILE_SIZE)

		var collision = CollisionShape2D.new()
		var shape = RectangleShape2D.new()
		shape.size = Vector2(TILE_SIZE * 3, TILE_SIZE)
		collision.shape = shape
		exit.add_child(collision)

		exit.collision_layer = 4
		exit.collision_mask = 2
		exit.monitoring = true

		exit.transition_triggered.connect(_on_exit_triggered)
		transitions.add_child(exit)


func _on_exit_triggered(target_map: String, target_spawn: String) -> void:
	transition_triggered.emit(target_map, target_spawn)
	area_transition.emit(target_map, target_spawn)


# ---------------------------------------------------------------------------
# Player, Camera, Controller
# ---------------------------------------------------------------------------

func _setup_player() -> void:
	var PlayerScript = load("res://src/exploration/OverworldPlayer.gd")
	if PlayerScript:
		player = PlayerScript.new()
		player.position = spawn_points["entrance"] * TILE_SIZE
		# Explicit interior flag — parent-name keyword scan + MapSystem fallback are
		# unreliable (see bc3da44d). Sets walk speed to 120 instead of overworld 240.
		player._is_interior = true
		add_child(player)


func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera2D"
	camera.zoom = Vector2(2.5, 2.5)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0

	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = MAP_WIDTH * TILE_SIZE
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
# Piano interaction (unchanged from original)
# ---------------------------------------------------------------------------

func _create_piano_interactable() -> void:
	var piano_area = Area2D.new()
	piano_area.name = "PianoInteractable"
	piano_area.position = Vector2(25 * TILE_SIZE, 15 * TILE_SIZE)

	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(TILE_SIZE * 2, TILE_SIZE * 2)
	collision.shape = shape
	piano_area.add_child(collision)

	piano_area.collision_layer = 4
	piano_area.collision_mask = 2
	piano_area.monitoring = true
	piano_area.monitorable = true
	piano_area.add_to_group("interactables")
	piano_area.set_meta("interaction_callback", _on_piano_interact)
	piano_area.set_meta("parent_scene", self)
	add_child(piano_area)


func _on_piano_interact() -> void:
	if _piano_playing:
		_stop_piano()
		return
	if _check_can_play_piano():
		_play_piano()
	else:
		_show_piano_fail_dialogue()


func _check_can_play_piano() -> bool:
	var game_loop = get_tree().root.get_node_or_null("GameLoop")
	if not game_loop or not game_loop.party:
		return false
	for member in game_loop.party:
		if member.customization:
			var personality = member.customization.personality
			if personality == member.customization.Personality.SCHOLARLY:
				return true
			if personality == member.customization.Personality.BRAVE:
				return true
	return false


func _play_piano() -> void:
	_piano_playing = true
	if SoundManager:
		SoundManager.play_piano_melody()
	_show_dialogue("*plays a beautiful melody on the piano*")
	await get_tree().create_timer(3.0).timeout
	if _piano_playing:
		_stop_piano()


func _stop_piano() -> void:
	_piano_playing = false


func _show_piano_fail_dialogue() -> void:
	var game_loop = get_tree().root.get_node_or_null("GameLoop")
	var message = "*You press some keys... it sounds terrible.*"
	if game_loop and game_loop.party.size() > 0:
		var leader = game_loop.party[0]
		if leader.customization:
			match leader.customization.personality:
				leader.customization.Personality.CAUTIOUS:
					message = "*You carefully press a key... then immediately regret it.*"
				leader.customization.Personality.QUICK:
					message = "*You mash some keys rapidly. It's chaos.*"
	_show_dialogue(message)


func _show_dialogue(text: String) -> void:
	var dialogue = Control.new()
	dialogue.z_index = 100

	var panel = Panel.new()
	panel.position = Vector2(100, 280)
	panel.size = Vector2(300, 60)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.2, 0.95)
	style.border_color = Color(0.8, 0.8, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	dialogue.add_child(panel)

	var label = Label.new()
	label.text = text
	label.position = Vector2(110, 290)
	label.size = Vector2(280, 50)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue.add_child(label)

	add_child(dialogue)
	await get_tree().create_timer(2.0).timeout
	dialogue.queue_free()


## Regressed during the 28×18 expansion (cowir-overworld village-
## interiors merge). Pinned by test_exploration_pause_contract_
## regression.gd — every exploration scene must forward pause/resume
## to controller so the input lock push/pop stays consistent.
func pause() -> void:
	if controller and is_instance_valid(controller) and controller.has_method("pause_exploration"):
		controller.pause_exploration()


func resume() -> void:
	if controller and is_instance_valid(controller) and controller.has_method("resume_exploration"):
		controller.resume_exploration()
