extends BaseInterior
class_name IronhavenWatchtowerInterior

## IronhavenWatchtowerInterior - "Drogal's Watchtower" at Ironhaven.
## A signaler stationed in a stone tower above the volcanic foothills.
## He listens for Voltharion (W1 lightning dragon) — she doesn't speak
## in words, she speaks in current. Sets up the Lightning Dragon Cave
## arc with a sense of weather instead of horror.

const TOWER_LAYOUT = [
	"WWWWWWWWWWWW",
	"W..........W",
	"W.RR....RR.W",
	"W..........W",
	"W..........W",
	"W....MM....W",
	"W....MM....W",
	"W..........W",
	"W..........W",
	"WWWWWDDWWWWW",
]


func _get_area_id() -> String:
	return "ironhaven_watchtower"


func _get_display_name() -> String:
	return "Storm Watchtower"


func _get_map_width() -> int:
	return 12


func _get_map_height() -> int:
	return 10


func _get_layout() -> Array:
	return TOWER_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(5, 8)
	spawn_points["scope"] = Vector2(5, 6)


func _draw_floor_tile(image: Image) -> void:
	# Cut basalt blocks — the dark volcanic stone Ironhaven is built
	# on. Tight seams every 8px, with the occasional iron flake
	# embedded from old smelting runoff.
	var basalt = Color(0.18, 0.16, 0.20)
	var basalt_light = Color(0.28, 0.26, 0.30)
	var iron_flake = Color(0.55, 0.50, 0.40)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var seam = (x % 8 == 0) or (y % 8 == 0)
			var flake = (x * 5 + y * 7) % 47 == 0
			if seam:
				image.set_pixel(x, y, basalt)
			elif flake:
				image.set_pixel(x, y, iron_flake)
			else:
				image.set_pixel(x, y, basalt_light)


func _draw_wall_tile(image: Image) -> void:
	# Hammered iron plate walls bolted to stone. Rivets along the
	# rows, faint copper patina where the iron meets damp air.
	var iron = Color(0.28, 0.26, 0.28)
	var iron_dark = Color(0.18, 0.16, 0.18)
	var rivet = Color(0.42, 0.40, 0.38)
	var patina = Color(0.28, 0.45, 0.40)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var row = y / 12
			var rivet_spot = (y % 12 == 6) and (x % 10 == 5)
			var seam = y % 12 == 0
			var damp = (x * 3 + y) % 41 == 0
			if rivet_spot:
				image.set_pixel(x, y, rivet)
			elif seam:
				image.set_pixel(x, y, iron_dark)
			elif damp:
				image.set_pixel(x, y, patina)
			else:
				image.set_pixel(x, y, iron if row % 2 == 0 else iron_dark)


func _setup_decorations() -> void:
	super._setup_decorations()
	_draw_rain_drums()
	_draw_signal_scope()
	_draw_lightning_etchings()


func _draw_rain_drums() -> void:
	# Two pairs of copper rain-collection drums at the R positions
	# (row 2, cols 2-3 + 8-9). Listening apparatus — Drogal can read
	# storm intensity by the cadence of the drips.
	var copper = Color(0.62, 0.40, 0.20)
	var copper_dark = Color(0.42, 0.26, 0.12)
	var water = Color(0.30, 0.45, 0.55)
	for anchor in [Vector2(2, 2), Vector2(8, 2)]:
		for i in range(2):
			var drum_pos: Vector2 = anchor * TILE_SIZE + Vector2(i * TILE_SIZE + 4, 6)
			var drum = ColorRect.new()
			drum.color = copper
			drum.size = Vector2(TILE_SIZE - 8, TILE_SIZE - 12)
			drum.position = drum_pos
			decorations.add_child(drum)
			var rim = ColorRect.new()
			rim.color = copper_dark
			rim.size = Vector2(TILE_SIZE - 8, 4)
			rim.position = drum_pos
			decorations.add_child(rim)
			var ripple = ColorRect.new()
			ripple.color = water
			ripple.size = Vector2(TILE_SIZE - 14, 6)
			ripple.position = drum_pos + Vector2(3, 6)
			decorations.add_child(ripple)


func _draw_signal_scope() -> void:
	# Brass signal scope on a tripod at the M positions (rows 5-6
	# cols 5-6). Centerpiece — what Drogal stands behind when he's
	# watching the east horizon.
	var brass = Color(0.78, 0.62, 0.30)
	var brass_dark = Color(0.50, 0.38, 0.18)
	var lens = Color(0.35, 0.55, 0.80)
	var tripod = ColorRect.new()
	tripod.color = brass_dark
	tripod.size = Vector2(TILE_SIZE * 2, TILE_SIZE * 2)
	tripod.position = Vector2(5 * TILE_SIZE, 5 * TILE_SIZE)
	decorations.add_child(tripod)
	var barrel = ColorRect.new()
	barrel.color = brass
	barrel.size = Vector2(TILE_SIZE * 2 - 8, TILE_SIZE - 8)
	barrel.position = Vector2(5 * TILE_SIZE + 4, 5 * TILE_SIZE + 12)
	decorations.add_child(barrel)
	var eye = ColorRect.new()
	eye.color = lens
	eye.size = Vector2(10, 10)
	eye.position = Vector2(5 * TILE_SIZE + 8, 5 * TILE_SIZE + 16)
	decorations.add_child(eye)


func _draw_lightning_etchings() -> void:
	# Etched lightning marks across the upper walls — Drogal has been
	# tallying her appearances. Visual cue that he's been watching for
	# a long time.
	var etch = Color(0.88, 0.78, 0.30)
	var etch_dark = Color(0.55, 0.48, 0.20)
	for i in range(5):
		var bolt = ColorRect.new()
		bolt.color = etch
		bolt.size = Vector2(3, 14)
		bolt.position = Vector2((1 + i * 2) * TILE_SIZE + 8, 1 * TILE_SIZE + 4)
		decorations.add_child(bolt)
		var tally = ColorRect.new()
		tally.color = etch_dark
		tally.size = Vector2(8, 2)
		tally.position = Vector2((1 + i * 2) * TILE_SIZE + 6, 1 * TILE_SIZE + 18)
		decorations.add_child(tally)


func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	var drogal = OverworldNPCScript.new()
	drogal.npc_name = "Drogal the Watcher"
	drogal.npc_type = "guard"
	drogal.position = Vector2(7 * TILE_SIZE, 5 * TILE_SIZE)
	drogal.dialogue_lines = [
		"Keep your voice down. She listens by the drums when she's quiet.",
		"Storm comes from the east. Always the east. Always Voltharion.",
		"She doesn't speak in words. She speaks in current — through bones, through iron.",
		"When you feel your fillings buzz, run. That's the warning.",
		"The old stories say she was a queen before. Now she's just weather.",
		"If you mean to find her cave, leave the metal armor here. She loves metal more than you do.",
	]
	npcs.add_child(drogal)


func _setup_transitions() -> void:
	super._setup_transitions()
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return
	var exit = AreaTransitionScript.new()
	exit.name = "Exit"
	exit.target_map = "ironhaven_village"
	exit.target_spawn = "watchtower_exit"
	exit.require_interaction = false
	exit.position = Vector2(5.5 * TILE_SIZE, 9.5 * TILE_SIZE)
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
