extends BaseInterior
class_name SandriftRainLedgerInterior

## SandriftRainLedgerInterior - the Rain Ledger (Sandrift BBB building).
## Village-interior expansion round 5, completing two-interior coverage of
## the W1 dragon villages. Sandrift maintains a civic record of every
## rainfall in its history. The memorable thing IS the record: the book has
## ONE entry — dated the day before the Ember Wyrm nested (Pyrroth
## foreshadow) — and the village keeps the office staffed anyway. Hope as
## bureaucracy. No meta-read this time; the single entry carries the room.

const ROOM_LAYOUT = [
	"WWWWWWWWWWWWWW",
	"W............W",
	"W....BB......W",
	"W............W",
	"W..T......T..W",
	"W............W",
	"W......T.....W",
	"W............W",
	"WWWWWWDDWWWWWW",
]


func _get_area_id() -> String:
	return "sandrift_rain_ledger"


func _get_display_name() -> String:
	return "The Rain Ledger"


func _get_map_width() -> int:
	return 14


func _get_map_height() -> int:
	return 9


func _get_layout() -> Array:
	return ROOM_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(7, 7)
	spawn_points["lectern"] = Vector2(5, 3)


func _draw_floor_tile(image: Image) -> void:
	# Sun-bleached sandstone tiles, swept obsessively clean.
	var sand = Color(0.78, 0.68, 0.50)
	var grout = Color(0.64, 0.54, 0.38)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			if x % 16 < 2 or y % 16 < 2:
				image.set_pixel(x, y, grout)
			else:
				image.set_pixel(x, y, sand.darkened(0.05 if (x / 8 + y / 8) % 2 == 0 else 0.0))


func _draw_wall_tile(image: Image) -> void:
	# Adobe with faded blue rain-stencils near the top — painted-on weather.
	var adobe = Color(0.70, 0.56, 0.40)
	var stencil = Color(0.44, 0.56, 0.70)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var is_drop = y < 10 and (x * 7 + y * 3) % 23 < 2
			image.set_pixel(x, y, stencil if is_drop else adobe.darkened(0.06 if y % 14 < 2 else 0.0))


func _setup_decorations() -> void:
	super._setup_decorations()
	_draw_lectern()
	_draw_rain_gauges()


func _draw_lectern() -> void:
	# The ledger on a lectern under a skylight-square of lighter floor.
	var light = ColorRect.new()
	light.color = Color(1.0, 0.96, 0.82, 0.25)
	light.size = Vector2(TILE_SIZE * 2.4, TILE_SIZE * 2.4)
	light.position = Vector2(3.8 * TILE_SIZE, 1.3 * TILE_SIZE)
	decorations.add_child(light)
	var lectern = ColorRect.new()
	lectern.color = Color(0.42, 0.30, 0.18)
	lectern.size = Vector2(TILE_SIZE * 1.2, TILE_SIZE * 0.8)
	lectern.position = Vector2(4.4 * TILE_SIZE, 2.1 * TILE_SIZE)
	decorations.add_child(lectern)
	var book = ColorRect.new()
	book.color = Color(0.92, 0.88, 0.78)
	book.size = Vector2(TILE_SIZE * 0.8, TILE_SIZE * 0.4)
	book.position = Vector2(4.6 * TILE_SIZE, 2.2 * TILE_SIZE)
	decorations.add_child(book)


func _draw_rain_gauges() -> void:
	# A row of pristine, empty rain gauges along the east wall. Ready.
	for i in range(4):
		var gauge = ColorRect.new()
		gauge.color = Color(0.80, 0.86, 0.90, 0.7)
		gauge.size = Vector2(6, TILE_SIZE * 0.6)
		gauge.position = Vector2((11.2 + i * 0.4) * TILE_SIZE, 1.4 * TILE_SIZE)
		decorations.add_child(gauge)


func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	var amara = OverworldNPCScript.new()
	amara.npc_name = "Recorder Amara"
	amara.npc_type = "scholar"
	amara.position = Vector2(4 * TILE_SIZE, 4 * TILE_SIZE)
	amara.dialogue_lines = [
		"Welcome to the Rain Ledger. Office of record for all precipitation in Sandrift, founded four hundred years ago.",
		"The gauges are calibrated weekly. The nibs are kept sharp. The inkwell is kept full. Procedure doesn't care about likelihood.",
		"People ask why we staff it. We staff it BECAUSE the book is nearly empty. An empty office is a prediction. A staffed one is a refusal.",
		"The old-timers say the sky changed when something warm moved into the mountain. The ledger doesn't record rumors. But I keep the page after the last entry very, very clean.",
	]
	npcs.add_child(amara)

	# The Ledger itself — one entry. The room's whole weight.
	var ledger = OverworldNPCScript.new()
	ledger.npc_name = "The Rain Ledger"
	ledger.npc_type = "scholar"
	ledger.position = Vector2(5 * TILE_SIZE, 2.6 * TILE_SIZE)
	ledger.dialogue_lines = [
		"A civic record book, four hundred years of pages, bound in cracked blue leather.",
		"It contains one entry: 'Rain. Light, from the west. Lasted most of the morning. Everyone came outside.'",
		"The entry is dated the day before the Ember Wyrm nested in the mountain.",
		"The next page is blank, and someone dusts it daily.",
	]
	npcs.add_child(ledger)


func _setup_transitions() -> void:
	super._setup_transitions()
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return
	var exit = AreaTransitionScript.new()
	exit.name = "Exit"
	exit.target_map = "sandrift_village"
	exit.target_spawn = "ledger_exit"
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
