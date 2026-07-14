extends BaseInterior
class_name IronhavenStrikeRegistryInterior

## IronhavenStrikeRegistryInterior - the Strike Registry (Ironhaven MMM
## building). Village-interior expansion round 3: Ironhaven files paperwork
## on every lightning bolt that has ever hit the village. The memorable thing
## is THE LEDGER — it counts the player's REAL battles_won as "storms
## survived" (read fresh each entry), and one entry it refuses to file
## foreshadows Voltharion in the cave east of the village.

const ROOM_LAYOUT = [
	"WWWWWWWWWWWWWW",
	"W.T..T..T..T.W",
	"W............W",
	"W..BB........W",
	"W............W",
	"W........T...W",
	"W............W",
	"W............W",
	"WWWWWWDDWWWWWW",
]


func _get_area_id() -> String:
	return "ironhaven_strike_registry"


func _get_display_name() -> String:
	return "The Strike Registry"


func _get_map_width() -> int:
	return 14


func _get_map_height() -> int:
	return 9


func _get_layout() -> Array:
	return ROOM_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(7, 7)
	spawn_points["desk"] = Vector2(4, 4)


func _draw_floor_tile(image: Image) -> void:
	# Slate flagstones with copper grounding strips — the floor is earthed.
	var slate = Color(0.34, 0.36, 0.40)
	var copper = Color(0.62, 0.40, 0.24)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			if x % 16 == 7 or x % 16 == 8:
				image.set_pixel(x, y, copper)
			elif (x / 10 + y / 10) % 2 == 0:
				image.set_pixel(x, y, slate)
			else:
				image.set_pixel(x, y, slate.darkened(0.12))


func _draw_wall_tile(image: Image) -> void:
	# Riveted iron panels — the whole room is a Faraday cage.
	var iron = Color(0.42, 0.44, 0.48)
	var rivet = Color(0.26, 0.27, 0.30)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var is_rivet = (x % 10 in [2, 3]) and (y % 10 in [2, 3])
			var seam = y % 16 < 2
			if is_rivet or seam:
				image.set_pixel(x, y, rivet)
			else:
				image.set_pixel(x, y, iron)


func _setup_decorations() -> void:
	super._setup_decorations()
	_draw_filing_wall()
	_draw_ledger_desk()


func _draw_filing_wall() -> void:
	# Pigeonhole cabinet along the north wall — one slot per filed strike.
	for col in range(8):
		for row in range(2):
			var slot = ColorRect.new()
			slot.color = Color(0.30, 0.24, 0.16).lightened(0.08 * ((col + row) % 3))
			slot.size = Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.35)
			slot.position = Vector2((8.2 + col * 0.6) * TILE_SIZE, (0.3 + row * 0.5) * TILE_SIZE)
			decorations.add_child(slot)


func _draw_ledger_desk() -> void:
	var desk = ColorRect.new()
	desk.color = Color(0.36, 0.26, 0.16)
	desk.size = Vector2(TILE_SIZE * 2, TILE_SIZE)
	desk.position = Vector2(3 * TILE_SIZE, 3 * TILE_SIZE)
	decorations.add_child(desk)
	var ledger = ColorRect.new()
	ledger.color = Color(0.88, 0.84, 0.72)
	ledger.size = Vector2(TILE_SIZE * 0.8, TILE_SIZE * 0.5)
	ledger.position = Vector2(3.6 * TILE_SIZE, 3.2 * TILE_SIZE)
	decorations.add_child(ledger)


func _storms_survived() -> int:
	if GameState and "battles_won" in GameState:
		return int(GameState.battles_won)
	return 0


func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	var hessa = OverworldNPCScript.new()
	hessa.npc_name = "Registrar Hessa"
	hessa.npc_type = "scholar"
	hessa.position = Vector2(4 * TILE_SIZE, 4 * TILE_SIZE)
	hessa.dialogue_lines = [
		"Every bolt that hits Ironhaven gets filed. Date, wattage, what it was aiming at, what it hit instead.",
		"Lightning is honest. It never claims it meant to do that. People could learn.",
		"Form 7-K is for strikes. Form 7-K-b is for strikes that were personal. You'd be surprised how many are.",
		"There's one strike the registry refuses to file. It's been going on for years. It lives in the cave east of here and it has a NAME.",
	]
	npcs.add_child(hessa)

	# The Ledger — the room's memorable thing, reads REAL battles_won.
	var storms := _storms_survived()
	var count_line: String = "Your page is blank. The ledger finds this suspicious." if storms == 0 \
		else "Your page lists %d storm%s survived. The handwriting is yours. You have never written in it." % [storms, "" if storms == 1 else "s"]
	var ledger = OverworldNPCScript.new()
	ledger.npc_name = "The Ledger"
	ledger.npc_type = "scholar"
	ledger.position = Vector2(4.5 * TILE_SIZE, 2.6 * TILE_SIZE)
	ledger.dialogue_lines = [
		"A registry ledger, open to a page with your name on it. You did not give anyone your name.",
		count_line,
		"The last line of every page is the same: FILED, in advance, under 'survivable'.",
	]
	npcs.add_child(ledger)


func _setup_transitions() -> void:
	super._setup_transitions()
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return
	var exit = AreaTransitionScript.new()
	exit.name = "Exit"
	exit.target_map = "ironhaven_village"
	exit.target_spawn = "registry_exit"
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
