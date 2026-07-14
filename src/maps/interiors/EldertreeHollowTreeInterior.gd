extends BaseInterior
class_name EldertreeHollowTreeInterior

## EldertreeHollowTreeInterior - "The Hollow" at Eldertree Village.
## Inside an ancient tree-trunk that's been carved into a small
## sanctum. The druid Greenleaf foreshadows the world-shift — when
## the medieval song stops, the houses change shape. (Sets up the
## W1 → W2 transition the player will eventually trigger.)

const HOLLOW_LAYOUT = [
	"WWWWWWWWWWWW",
	"W..........W",
	"W..MM..MM..W",
	"W..........W",
	"W..........W",
	"W....SS....W",
	"W..........W",
	"W..MM..MM..W",
	"WWWWWDDWWWWW",
]


func _get_area_id() -> String:
	return "eldertree_hollow"


func _get_display_name() -> String:
	return "The Hollow"


func _get_map_width() -> int:
	return 12


func _get_map_height() -> int:
	return 9


func _get_layout() -> Array:
	return HOLLOW_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(5, 7)
	spawn_points["seat"] = Vector2(5, 5)


func _draw_floor_tile(image: Image) -> void:
	# Mossy bark floor — the inside of a living tree. Greens with bark-
	# brown grain so the room reads as "carved from a tree", not "wood
	# floor in a wood building" (which would feel like the library).
	var moss = Color(0.25, 0.34, 0.18)
	var moss_dark = Color(0.18, 0.26, 0.12)
	var bark = Color(0.32, 0.24, 0.14)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var ring = (x * x + y * y) % 18 < 6
			var patch = (x + y * 3) % 7 == 0
			if patch:
				image.set_pixel(x, y, bark)
			elif ring:
				image.set_pixel(x, y, moss_dark)
			else:
				image.set_pixel(x, y, moss)


func _draw_wall_tile(image: Image) -> void:
	# Living-bark walls — vertical grain, knot-spots, hint of warm tone
	# inside the wood. Contrasts library's flat panel grain.
	var bark = Color(0.28, 0.18, 0.10)
	var bark_light = Color(0.42, 0.28, 0.16)
	var heart = Color(0.58, 0.42, 0.22)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var vert_grain = (x + (y / 6)) % 5 == 0
			var knot = (x - 14) * (x - 14) + (y - 14) * (y - 14) < 8
			if knot:
				image.set_pixel(x, y, heart)
			elif vert_grain:
				image.set_pixel(x, y, bark_light)
			else:
				image.set_pixel(x, y, bark)


func _setup_decorations() -> void:
	super._setup_decorations()
	_draw_mushroom_clusters()
	_draw_seat()


func _draw_mushroom_clusters() -> void:
	# Glowing mushroom clusters at the 'M' positions in HOLLOW_LAYOUT.
	# Each cluster = a soft-glow patch + three cap-shaped rects.
	var cap = Color(0.88, 0.45, 0.45)
	var cap_dim = Color(0.65, 0.30, 0.30)
	var stem = Color(0.92, 0.88, 0.78)
	var glow = Color(1.0, 0.85, 0.55, 0.35)
	for cluster_pos in [Vector2(3, 2), Vector2(7, 2), Vector2(3, 7), Vector2(7, 7)]:
		var halo = ColorRect.new()
		halo.color = glow
		halo.size = Vector2(TILE_SIZE * 2, TILE_SIZE)
		halo.position = cluster_pos * TILE_SIZE
		decorations.add_child(halo)
		for i in range(3):
			var stem_rect = ColorRect.new()
			stem_rect.color = stem
			stem_rect.size = Vector2(4, 12)
			stem_rect.position = cluster_pos * TILE_SIZE + Vector2(8 + i * 16, 12)
			decorations.add_child(stem_rect)
			var cap_rect = ColorRect.new()
			cap_rect.color = cap if i != 1 else cap_dim
			cap_rect.size = Vector2(12, 6)
			cap_rect.position = cluster_pos * TILE_SIZE + Vector2(4 + i * 16, 8)
			decorations.add_child(cap_rect)


func _draw_seat() -> void:
	# A polished tree-stump where Greenleaf sits. Simple disc on the
	# floor so the player can SEE the focal point even before talking.
	var stump = ColorRect.new()
	stump.color = Color(0.50, 0.32, 0.18)
	stump.size = Vector2(TILE_SIZE * 2, TILE_SIZE)
	stump.position = Vector2(5 * TILE_SIZE, 5 * TILE_SIZE)
	decorations.add_child(stump)
	var stump_top = ColorRect.new()
	stump_top.color = Color(0.68, 0.46, 0.26)
	stump_top.size = Vector2(TILE_SIZE * 2 - 8, 6)
	stump_top.position = Vector2(5 * TILE_SIZE + 4, 5 * TILE_SIZE)
	decorations.add_child(stump_top)


func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	var greenleaf = OverworldNPCScript.new()
	greenleaf.npc_name = "Greenleaf"
	greenleaf.npc_type = "scholar"
	greenleaf.position = Vector2(6 * TILE_SIZE, 5 * TILE_SIZE)
	greenleaf.dialogue_lines = [
		"Welcome to the Hollow. Sit. The tree remembers you.",
		"You come from the south — Harmonia. The song is loud there, isn't it?",
		"When the song stops, the houses change shape. I have seen this.",
		"The medieval world ends. A different world takes its place. Square houses. Loud roads.",
		"Most don't notice the change while it happens. The few who do tend to wake up screaming.",
		"Take a mushroom on your way out. They glow brighter in the new world.",
	]
	npcs.add_child(greenleaf)


func _setup_transitions() -> void:
	super._setup_transitions()
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return
	var exit = AreaTransitionScript.new()
	exit.name = "Exit"
	exit.target_map = "eldertree_village"
	exit.target_spawn = "hollow_exit"
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
