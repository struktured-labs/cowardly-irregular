extends BaseInterior
class_name EldertreeGraftingHouseInterior

## EldertreeGraftingHouseInterior - the Grafting House (Eldertree, GGG herb
## garden). Village-interior expansion: one memorable thing per room. Here
## it's THE HALF-GROWN FIGURE — a living-wood carving the garden started
## growing on its own, wearing the player's ACTUAL party-leader job (read
## fresh each entry). Marrow Root, the grafter, grows furniture instead of
## building it and finds hammers philosophically offensive.

const ROOM_LAYOUT = [
	"WWWWWWWWWWWWWW",
	"W.T........T.W",
	"W............W",
	"W...BB.......W",
	"W............W",
	"W.......T....W",
	"W.T..........W",
	"W............W",
	"WWWWWWDDWWWWWW",
]


func _get_area_id() -> String:
	return "eldertree_grafting_house"


func _get_display_name() -> String:
	return "The Grafting House"


func _get_map_width() -> int:
	return 14


func _get_map_height() -> int:
	return 9


func _get_layout() -> Array:
	return ROOM_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(7, 7)
	spawn_points["bench"] = Vector2(4, 4)


func _draw_floor_tile(image: Image) -> void:
	# Packed earth threaded with pale living roots — the floor is alive.
	var earth = Color(0.36, 0.28, 0.18)
	var root = Color(0.62, 0.55, 0.38)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var vein = (x + y * 3) % 23 < 2 or (x * 2 - y) % 19 < 1
			image.set_pixel(x, y, root if vein else earth)


func _draw_wall_tile(image: Image) -> void:
	# Woven living branches — bark with green growth seams.
	var bark = Color(0.30, 0.22, 0.12)
	var moss = Color(0.30, 0.42, 0.20)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var seam = (y % 11 < 2) or ((x + y) % 17 < 1)
			image.set_pixel(x, y, moss if seam else bark)


func _setup_decorations() -> void:
	super._setup_decorations()
	_draw_grafting_bench()
	_draw_growing_figure()


func _draw_grafting_bench() -> void:
	# A workbench that is also a rooted stump — grown, not built.
	var stump = ColorRect.new()
	stump.color = Color(0.44, 0.32, 0.18)
	stump.size = Vector2(TILE_SIZE * 2, TILE_SIZE)
	stump.position = Vector2(3 * TILE_SIZE, 3 * TILE_SIZE)
	decorations.add_child(stump)
	var rings = ColorRect.new()
	rings.color = Color(0.58, 0.44, 0.26)
	rings.size = Vector2(TILE_SIZE * 2, 5)
	rings.position = Vector2(3 * TILE_SIZE, 3 * TILE_SIZE)
	decorations.add_child(rings)


func _draw_growing_figure() -> void:
	# The half-grown figure on a root pedestal — green wood, person-shaped.
	var pedestal = ColorRect.new()
	pedestal.color = Color(0.40, 0.30, 0.16)
	pedestal.size = Vector2(TILE_SIZE, TILE_SIZE * 0.4)
	pedestal.position = Vector2(10 * TILE_SIZE, 2.6 * TILE_SIZE)
	decorations.add_child(pedestal)
	var body = ColorRect.new()
	body.color = Color(0.48, 0.58, 0.30)
	body.size = Vector2(TILE_SIZE * 0.4, TILE_SIZE * 0.8)
	body.position = Vector2(10.3 * TILE_SIZE, 1.8 * TILE_SIZE)
	decorations.add_child(body)
	var head = ColorRect.new()
	head.color = Color(0.52, 0.62, 0.34)
	head.size = Vector2(TILE_SIZE * 0.3, TILE_SIZE * 0.3)
	head.position = Vector2(10.35 * TILE_SIZE, 1.5 * TILE_SIZE)
	decorations.add_child(head)


func _leader_job_name() -> String:
	var gl = get_tree().root.get_node_or_null("GameLoop")
	if gl and "party" in gl and not gl.party.is_empty():
		var idx: int = 0
		if GameState and "party_leader_index" in GameState:
			idx = clampi(int(GameState.party_leader_index), 0, gl.party.size() - 1)
		var leader = gl.party[idx]
		if leader and "job" in leader and leader.job is Dictionary:
			return str(leader.job.get("name", "Adventurer"))
	return "Adventurer"


func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	var marrow = OverworldNPCScript.new()
	marrow.npc_name = "Marrow Root"
	marrow.npc_type = "villager"
	marrow.position = Vector2(4 * TILE_SIZE, 4 * TILE_SIZE)
	marrow.dialogue_lines = [
		"Carpenters CUT. I ask. The tree says yes slower, but it never says it twice.",
		"Every chair in Eldertree is still growing. Sit long enough and one grows around you. We call that retirement.",
		"A hammer is just an argument you've given up on winning politely.",
		"The garden grows what the village needs before the village knows it needs it. Mostly ladles. Make of that what you will.",
	]
	npcs.add_child(marrow)

	# The half-grown figure — reads the REAL party leader's job each entry.
	var job_name := _leader_job_name()
	var figure = OverworldNPCScript.new()
	figure.npc_name = "Half-Grown Figure"
	figure.npc_type = "villager"
	figure.position = Vector2(10.5 * TILE_SIZE, 2 * TILE_SIZE)
	figure.dialogue_lines = [
		"A figure of green wood, person-shaped, unfinished. The grain is still moving.",
		"It is unmistakably a %s. It has your posture." % job_name,
		"Marrow Root shrugs from the bench: 'Garden started it the day you first crossed the bridge. I just water it. It refuses to grow a face until you've decided who you are.'",
	]
	npcs.add_child(figure)


func _setup_transitions() -> void:
	super._setup_transitions()
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return
	var exit = AreaTransitionScript.new()
	exit.name = "Exit"
	exit.target_map = "eldertree_village"
	exit.target_spawn = "grafting_exit"
	exit.require_interaction = false
	exit.position = Vector2(6.5 * TILE_SIZE, 8.5 * TILE_SIZE)
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
