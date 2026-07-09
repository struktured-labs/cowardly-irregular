extends BaseInterior
class_name FrostholdMeltwaterClockInterior

## FrostholdMeltwaterClockInterior - the Meltwater Clock (Frosthold CCC
## building). Village-interior expansion round 4. Frosthold keeps time by
## melting ice: the memorable thing is THE CLOCK — it reads the player's
## REAL playtime_seconds and claims, correctly, that it started counting
## the moment you did. Keeper Yrsa tends it and dreads the freeze that
## doesn't end (Glacius foreshadow — the cave north of the village).

const ROOM_LAYOUT = [
	"WWWWWWWWWWWWWW",
	"W....TT......W",
	"W....TT......W",
	"W............W",
	"W..BB........W",
	"W............W",
	"W.........T..W",
	"W............W",
	"WWWWWWDDWWWWWW",
]


func _get_area_id() -> String:
	return "frosthold_meltwater_clock"


func _get_display_name() -> String:
	return "The Meltwater Clock"


func _get_map_width() -> int:
	return 14


func _get_map_height() -> int:
	return 9


func _get_layout() -> Array:
	return ROOM_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(7, 7)
	spawn_points["clock"] = Vector2(5, 2)


func _draw_floor_tile(image: Image) -> void:
	# Blue slate with thin meltwater channels running toward the clock.
	var slate = Color(0.30, 0.36, 0.46)
	var water = Color(0.42, 0.58, 0.74)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			if x % 16 in [7, 8] or y % 22 in [3]:
				image.set_pixel(x, y, water)
			else:
				image.set_pixel(x, y, slate.darkened(0.08 if (x / 8 + y / 8) % 2 == 0 else 0.0))


func _draw_wall_tile(image: Image) -> void:
	# Packed ice blocks with frost seams.
	var ice = Color(0.62, 0.72, 0.84)
	var seam = Color(0.44, 0.54, 0.68)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			if y % 12 < 2 or (x + (y / 12) * 7) % 18 < 2:
				image.set_pixel(x, y, seam)
			else:
				image.set_pixel(x, y, ice)


func _setup_decorations() -> void:
	super._setup_decorations()
	_draw_clock_tower()
	_draw_keeper_bench()


func _draw_clock_tower() -> void:
	# The clock: an ice column dripping into a graduated basin.
	var column = ColorRect.new()
	column.color = Color(0.78, 0.86, 0.94)
	column.size = Vector2(TILE_SIZE * 1.4, TILE_SIZE * 1.6)
	column.position = Vector2(4.3 * TILE_SIZE, 0.6 * TILE_SIZE)
	decorations.add_child(column)
	var basin = ColorRect.new()
	basin.color = Color(0.36, 0.50, 0.66)
	basin.size = Vector2(TILE_SIZE * 2, TILE_SIZE * 0.5)
	basin.position = Vector2(4 * TILE_SIZE, 2.2 * TILE_SIZE)
	decorations.add_child(basin)
	for i in range(4):
		var mark = ColorRect.new()
		mark.color = Color(0.86, 0.90, 0.95)
		mark.size = Vector2(6, 2)
		mark.position = Vector2(4.1 * TILE_SIZE, (2.25 + i * 0.1) * TILE_SIZE)
		decorations.add_child(mark)


func _draw_keeper_bench() -> void:
	var bench = ColorRect.new()
	bench.color = Color(0.40, 0.30, 0.20)
	bench.size = Vector2(TILE_SIZE * 2, TILE_SIZE * 0.6)
	bench.position = Vector2(3 * TILE_SIZE, 4.2 * TILE_SIZE)
	decorations.add_child(bench)


func _playtime_text() -> String:
	var secs := 0
	if GameState and "playtime_seconds" in GameState:
		secs = int(GameState.playtime_seconds)
	var h := secs / 3600
	var m := (secs % 3600) / 60
	var s := secs % 60
	return "%d hour%s, %d minute%s, %d second%s" % [h, "" if h == 1 else "s", m, "" if m == 1 else "s", s, "" if s == 1 else "s"]


func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	var yrsa = OverworldNPCScript.new()
	yrsa.npc_name = "Keeper Yrsa"
	yrsa.npc_type = "villager"
	yrsa.position = Vector2(4 * TILE_SIZE, 5 * TILE_SIZE)
	yrsa.dialogue_lines = [
		"The clock runs on melting. As long as something melts, time is passing. That's the whole mechanism.",
		"Other towns count seconds. We count what the cold gives back. It's the same number, said honestly.",
		"My grandmother kept it. Her grandmother kept it. The ice remembers all of us. It drips politely when I say that.",
		"North of here there's a cave where nothing melts at all. If the clock ever stops, that's where the stopping came from.",
	]
	npcs.add_child(yrsa)

	# The Clock — reads REAL playtime, composed fresh each entry.
	var clock = OverworldNPCScript.new()
	clock.npc_name = "The Meltwater Clock"
	clock.npc_type = "villager"
	clock.position = Vector2(5 * TILE_SIZE, 2.8 * TILE_SIZE)
	clock.dialogue_lines = [
		"An ice column drips into a graduated basin. The water level reads like a clock face.",
		"The basin says it has been running for %s." % _playtime_text(),
		"That is exactly how long you have existed. The clock started when you did. Nobody filled it before that.",
		"A small plaque: 'ACCURACY GUARANTEED. THE ICE HAS NO REASON TO LIE.'",
	]
	npcs.add_child(clock)


func _setup_transitions() -> void:
	super._setup_transitions()
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return
	var exit = AreaTransitionScript.new()
	exit.name = "Exit"
	exit.target_map = "frosthold_village"
	exit.target_spawn = "clock_exit"
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
