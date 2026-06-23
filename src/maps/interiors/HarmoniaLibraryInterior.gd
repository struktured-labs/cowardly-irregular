extends BaseInterior
class_name HarmoniaLibraryInterior

## HarmoniaLibraryInterior - "The Quiet Library" at Harmonia's top-left
## H cluster (cols 3-5 rows 2-4 in the village layout). Cantor Vell
## keeps records of the four elemental dragons — his lines foreshadow
## the W1 advanced content (Pyrroth, Glacius, Voltharion, Umbraxis).

const LIBRARY_LAYOUT = [
	"WWWWWWWWWWWW",
	"W.SSSSSSSS.W",
	"W..........W",
	"W.SSSSSSSS.W",
	"W..........W",
	"W....TT....W",
	"W..........W",
	"W..........W",
	"WWWWWDDWWWWW",
]


func _get_area_id() -> String:
	return "harmonia_library"


func _get_display_name() -> String:
	return "Library"


func _get_map_width() -> int:
	return 12


func _get_map_height() -> int:
	return 9


func _get_layout() -> Array:
	return LIBRARY_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(5, 7)
	spawn_points["table"] = Vector2(5, 5)


func _draw_floor_tile(image: Image) -> void:
	# Warm parquet — distinguishes the library visually from the chapel's
	# cold stone. Same horizontal plank pattern as the tavern with a
	# slightly darker shade so the room reads as "old + scholarly".
	var wood = Color(0.40, 0.27, 0.16)
	var wood_dark = Color(0.32, 0.21, 0.12)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var plank = (x / 8) % 2
			var grain = (y + x / 4) % 4 == 0
			image.set_pixel(x, y, wood_dark if plank == 0 or grain else wood)


func _draw_wall_tile(image: Image) -> void:
	# Dark wood panelling instead of stone brick. The chapel is stone;
	# the library is wood; the next interior should be something else
	# again — distinct floors+walls is the cheapest variety lever.
	var panel = Color(0.30, 0.20, 0.12)
	var panel_light = Color(0.42, 0.28, 0.16)
	var seam = Color(0.18, 0.12, 0.08)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var vert_seam = x % 8 == 0
			var horiz_grain = y % 4 == 0
			if vert_seam:
				image.set_pixel(x, y, seam)
			elif horiz_grain:
				image.set_pixel(x, y, panel_light)
			else:
				image.set_pixel(x, y, panel)


func _setup_decorations() -> void:
	super._setup_decorations()
	_draw_bookshelves()
	_draw_reading_table()


func _draw_bookshelves() -> void:
	# Bookshelf tiles match the 'S' positions in LIBRARY_LAYOUT — drawn
	# as ColorRects above the floor so the player can still move on the
	# floor tiles underneath (the tilemap 'S' is treated as floor, the
	# decoration sits on top purely visually). Keeps the room enterable
	# without making the bookshelves impassable walls.
	var shelf_back = Color(0.18, 0.12, 0.08)
	var book_a = Color(0.65, 0.20, 0.20)
	var book_b = Color(0.20, 0.45, 0.20)
	var book_c = Color(0.20, 0.30, 0.60)
	var book_d = Color(0.55, 0.50, 0.20)
	var books = [book_a, book_b, book_c, book_d]
	for row_y in [1, 3]:
		var back = ColorRect.new()
		back.color = shelf_back
		back.size = Vector2(TILE_SIZE * 8, TILE_SIZE)
		back.position = Vector2(2 * TILE_SIZE, row_y * TILE_SIZE)
		decorations.add_child(back)
		for col_offset in range(8):
			var book = ColorRect.new()
			book.color = books[col_offset % books.size()]
			book.size = Vector2(TILE_SIZE - 4, TILE_SIZE - 8)
			book.position = Vector2((2 + col_offset) * TILE_SIZE + 2, row_y * TILE_SIZE + 4)
			decorations.add_child(book)


func _draw_reading_table() -> void:
	var table = ColorRect.new()
	table.color = Color(0.45, 0.30, 0.18)
	table.size = Vector2(TILE_SIZE * 2, TILE_SIZE)
	table.position = Vector2(5 * TILE_SIZE, 5 * TILE_SIZE)
	decorations.add_child(table)
	# Open tome on the table — bright cream rectangle that catches the
	# eye so the player walks toward it.
	var tome = ColorRect.new()
	tome.color = Color(0.92, 0.86, 0.70)
	tome.size = Vector2(TILE_SIZE - 8, 10)
	tome.position = Vector2(5 * TILE_SIZE + 16, 5 * TILE_SIZE + 8)
	decorations.add_child(tome)


func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	var cantor = OverworldNPCScript.new()
	cantor.npc_name = "Cantor Vell"
	cantor.npc_type = "scholar"
	cantor.position = Vector2(6 * TILE_SIZE, 5 * TILE_SIZE)
	cantor.dialogue_lines = [
		"Quiet, please. The pages are old and they hear everything.",
		"I keep the names of the dragons here. Four of them. Maybe more.",
		"Pyrroth was first in the songs, but only because the sailors loved fire.",
		"Glacius listens, even now. The Frozen Sovereign always listens.",
		"Voltharion and Umbraxis... I would not speak their true names aloud.",
		"If you find their caves, traveler — do not introduce yourself.",
	]
	npcs.add_child(cantor)


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
	exit.position = Vector2(5.5 * TILE_SIZE, 8.5 * TILE_SIZE)
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
