extends BaseInterior
class_name VertexThresholdInterior

## VertexThresholdInterior - "The Threshold" at Vertex Village.
## A small empty room with a single bench and The Witness — an NPC
## who has seen all five prior worlds. Her dialogue lists every prior
## interior's NPC by name, paying off the player's visits across the
## entire game. Foreshadows the Calibrant (W6 final boss / endgame).

const ROOM_LAYOUT = [
	"WWWWWWWWWWWWWW",
	"W............W",
	"W............W",
	"W............W",
	"W............W",
	"W.....BB.....W",
	"W............W",
	"W............W",
	"W............W",
	"WWWWWWDDWWWWWW",
]


func _get_area_id() -> String:
	return "vertex_threshold"


func _get_display_name() -> String:
	return "The Threshold"


func _get_map_width() -> int:
	return 14


func _get_map_height() -> int:
	return 10


func _get_layout() -> Array:
	return ROOM_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(7, 8)
	spawn_points["bench"] = Vector2(6, 5)


func _draw_floor_tile(image: Image) -> void:
	# Minimalist off-white floor with the faintest grid — abstract,
	# undecorated. The world has been optimized down to the essentials.
	var floor_color = Color(0.88, 0.88, 0.90)
	var grid = Color(0.78, 0.78, 0.82)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var on_grid = (x % 16 == 0) or (y % 16 == 0)
			if on_grid:
				image.set_pixel(x, y, grid)
			else:
				image.set_pixel(x, y, floor_color)


func _draw_wall_tile(image: Image) -> void:
	# Solid medium-gray walls — no texture, no flourish. The room
	# has nothing to prove.
	var wall = Color(0.55, 0.55, 0.58)
	var wall_seam = Color(0.42, 0.42, 0.46)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var seam = (x % 16 == 0) or (y % 16 == 0)
			if seam:
				image.set_pixel(x, y, wall_seam)
			else:
				image.set_pixel(x, y, wall)


func _setup_decorations() -> void:
	super._setup_decorations()
	_draw_bench()


func _draw_bench() -> void:
	# A single bench. Wood top, wood legs. The Witness sits here.
	var wood = ColorRect.new()
	wood.color = Color(0.42, 0.30, 0.18)
	wood.size = Vector2(TILE_SIZE * 2, TILE_SIZE)
	wood.position = Vector2(5 * TILE_SIZE, 5 * TILE_SIZE)
	decorations.add_child(wood)
	var top = ColorRect.new()
	top.color = Color(0.58, 0.42, 0.26)
	top.size = Vector2(TILE_SIZE * 2, 6)
	top.position = Vector2(5 * TILE_SIZE, 5 * TILE_SIZE)
	decorations.add_child(top)


func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	var witness = OverworldNPCScript.new()
	witness.npc_name = "The Witness"
	witness.npc_type = "scholar"
	witness.position = Vector2(7 * TILE_SIZE, 5 * TILE_SIZE)
	witness.dialogue_lines = [
		"You came from far away. I remember when far away meant Harmonia.",
		"I knew Sister Concord and Cantor Vell. I knew Greenleaf, Trygg, Senga, Mire, and Drogal.",
		"I knew Crusher Pete and Magister Clavis. I knew Steward Vetch and SUDO-1.",
		"They each saw a piece. None of them saw the whole.",
		"The Calibrant doesn't fight. It decides what's wrong. Then it makes the wrong thing not exist.",
		"If you reach it, don't try to prove you exist. That's how it finds you.",
	]
	npcs.add_child(witness)


func _setup_transitions() -> void:
	super._setup_transitions()
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return
	var exit = AreaTransitionScript.new()
	exit.name = "Exit"
	exit.target_map = "vertex_village"
	exit.target_spawn = "threshold_exit"
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
