extends BaseInterior
class_name SandriftGlassmakerInterior

## SandriftGlassmakerInterior - "Senga's Workshop" at Sandrift.
## Senga blows desert glass collected from sand fused by dragon-breath
## carrying on the wind. Her shelves hold fragments of Pyrroth's
## exhale — concrete physical foreshadowing rather than just a story
## NPC. Sets up Pyrroth (W1 fire dragon) without spoiling her cave.

const SHOP_LAYOUT = [
	"WWWWWWWWWWWWWW",
	"W............W",
	"W.SSSS..SSSS.W",
	"W............W",
	"W.....KK.....W",
	"W.....KK.....W",
	"W............W",
	"W.SSSS..SSSS.W",
	"W............W",
	"WWWWWWDDWWWWWW",
]


func _get_area_id() -> String:
	return "sandrift_glassmaker"


func _get_display_name() -> String:
	return "Glassmaker's Workshop"


func _get_map_width() -> int:
	return 14


func _get_map_height() -> int:
	return 10


func _get_layout() -> Array:
	return SHOP_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(7, 8)
	spawn_points["kiln"] = Vector2(6, 5)


func _draw_floor_tile(image: Image) -> void:
	# Packed sand floor — warm sandy beige with darker grit lines
	# where the workshop's foot traffic has worn paths.
	var sand = Color(0.84, 0.72, 0.50)
	var sand_warm = Color(0.92, 0.80, 0.55)
	var grit = Color(0.62, 0.50, 0.32)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var path = (y > 14 and y < 18) or (x > 14 and x < 18)
			var grain = (x * 3 + y * 5) % 13 == 0
			if path:
				image.set_pixel(x, y, grit)
			elif grain:
				image.set_pixel(x, y, sand_warm)
			else:
				image.set_pixel(x, y, sand)


func _draw_wall_tile(image: Image) -> void:
	# Sandstone block walls — warmer than Frosthold's logs, drier
	# than Harmonia's brick. Block seams every 12 px.
	var block = Color(0.68, 0.55, 0.36)
	var block_light = Color(0.82, 0.68, 0.46)
	var seam = Color(0.48, 0.38, 0.22)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var row = y / 12
			var offset = 12 if row % 2 == 0 else 0
			var horiz_seam = y % 12 == 0
			var vert_seam = (x + offset) % 24 == 0
			if horiz_seam or vert_seam:
				image.set_pixel(x, y, seam)
			elif (x + y) % 11 == 0:
				image.set_pixel(x, y, block_light)
			else:
				image.set_pixel(x, y, block)


func _setup_decorations() -> void:
	super._setup_decorations()
	_draw_shelves()
	_draw_kiln()


func _draw_shelves() -> void:
	# Shelves at the S positions in SHOP_LAYOUT — each one holds two
	# colored glass pieces in distinctive desert-glass tints.
	var shelf_wood = Color(0.42, 0.28, 0.16)
	var glasses = [
		Color(0.95, 0.65, 0.25, 0.85),  # amber
		Color(0.40, 0.55, 0.85, 0.85),  # blue
		Color(0.55, 0.85, 0.55, 0.85),  # green
		Color(0.85, 0.40, 0.55, 0.85),  # rose
	]
	# Shelf cell anchors — match the 'S' positions in SHOP_LAYOUT.
	# Top row is y=2, bottom row is y=7 (both at cols 2-5 and 8-11).
	for shelf_anchor in [Vector2(2, 2), Vector2(8, 2), Vector2(2, 7), Vector2(8, 7)]:
		var shelf = ColorRect.new()
		shelf.color = shelf_wood
		shelf.size = Vector2(TILE_SIZE * 4, TILE_SIZE - 6)
		shelf.position = shelf_anchor * TILE_SIZE + Vector2(0, 6)
		decorations.add_child(shelf)
		for i in range(4):
			var glass = ColorRect.new()
			glass.color = glasses[i]
			glass.size = Vector2(TILE_SIZE - 10, TILE_SIZE - 14)
			glass.position = shelf_anchor * TILE_SIZE + Vector2(i * TILE_SIZE + 5, 2)
			decorations.add_child(glass)


func _draw_kiln() -> void:
	# Brick kiln at the K positions — dark brick body with an
	# orange-red flame visible through the open door.
	var brick = Color(0.32, 0.18, 0.12)
	var brick_dark = Color(0.20, 0.10, 0.06)
	var flame = Color(1.0, 0.55, 0.15)
	var flame_hot = Color(1.0, 0.92, 0.45)
	var body = ColorRect.new()
	body.color = brick
	body.size = Vector2(TILE_SIZE * 2, TILE_SIZE * 2)
	body.position = Vector2(5 * TILE_SIZE, 4 * TILE_SIZE)
	decorations.add_child(body)
	var hood = ColorRect.new()
	hood.color = brick_dark
	hood.size = Vector2(TILE_SIZE * 2, 6)
	hood.position = Vector2(5 * TILE_SIZE, 4 * TILE_SIZE)
	decorations.add_child(hood)
	var door = ColorRect.new()
	door.color = brick_dark
	door.size = Vector2(TILE_SIZE - 8, TILE_SIZE - 10)
	door.position = Vector2(5 * TILE_SIZE + 32, 4 * TILE_SIZE + 24)
	decorations.add_child(door)
	var fire = ColorRect.new()
	fire.color = flame
	fire.size = Vector2(TILE_SIZE - 14, TILE_SIZE - 16)
	fire.position = Vector2(5 * TILE_SIZE + 36, 4 * TILE_SIZE + 28)
	decorations.add_child(fire)
	var fire_hot = ColorRect.new()
	fire_hot.color = flame_hot
	fire_hot.size = Vector2(TILE_SIZE - 22, 8)
	fire_hot.position = Vector2(5 * TILE_SIZE + 40, 4 * TILE_SIZE + 36)
	decorations.add_child(fire_hot)


func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	var senga = OverworldNPCScript.new()
	senga.npc_name = "Senga the Glassblower"
	senga.npc_type = "merchant"
	senga.position = Vector2(8 * TILE_SIZE, 5 * TILE_SIZE)
	senga.dialogue_lines = [
		"Mind the kiln. It bites.",
		"Half this glass came out of the dunes already shaped.",
		"Pyrroth coughs, and three days later we find this in the sand.",
		"She used to come closer, you know. The old maps had her at the edge of the sand.",
		"Now she stays in her cave. The dunes notice when she's restless.",
		"If you go to her — bring a token. Glass remembers fire. She'll remember you back.",
	]
	npcs.add_child(senga)


func _setup_transitions() -> void:
	super._setup_transitions()
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return
	var exit = AreaTransitionScript.new()
	exit.name = "Exit"
	exit.target_map = "sandrift_village"
	exit.target_spawn = "glassmaker_exit"
	exit.require_interaction = false
	exit.position = Vector2(6.5 * TILE_SIZE, 9.5 * TILE_SIZE)
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
