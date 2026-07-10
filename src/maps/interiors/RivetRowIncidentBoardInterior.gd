extends BaseInterior
class_name RivetRowIncidentBoardInterior

## RivetRowIncidentBoardInterior - the Incident Board (Rivet Row GGG
## building). W4 interior expansion, industrial register: the safety office
## where every incident gets a form and no form gets an apology. The
## memorable thing reads the crew's REAL permanent injuries — the game's
## harshest stakes mechanic — as 'recorded incidents'. Zero injuries makes
## the board suspicious: nobody is this careful.

const ROOM_LAYOUT = [
	"WWWWWWWWWWWWWW",
	"W............W",
	"W..BB........W",
	"W............W",
	"W.T.....T....W",
	"W............W",
	"W........T...W",
	"W............W",
	"WWWWWWDDWWWWWW",
]


func _get_area_id() -> String:
	return "rivet_row_incident_board"


func _get_display_name() -> String:
	return "The Incident Board"


func _get_map_width() -> int:
	return 14


func _get_map_height() -> int:
	return 9


func _get_layout() -> Array:
	return ROOM_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(7, 7)
	spawn_points["board"] = Vector2(4, 3)


func _draw_floor_tile(image: Image) -> void:
	# Painted concrete with a yellow walking line, obeyed by the floor itself.
	var concrete = Color(0.52, 0.52, 0.50)
	var line = Color(0.85, 0.75, 0.20)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			if y in [14, 15, 16, 17]:
				image.set_pixel(x, y, line)
			else:
				image.set_pixel(x, y, concrete.darkened(0.05 if (x / 8 + y / 8) % 2 == 0 else 0.0))


func _draw_wall_tile(image: Image) -> void:
	# Corrugated panel with a safety-notice stripe.
	var panel = Color(0.45, 0.47, 0.50)
	var stripe = Color(0.80, 0.55, 0.15)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			if y < 5:
				image.set_pixel(x, y, stripe if (x / 6) % 2 == 0 else Color(0.15, 0.15, 0.15))
			elif x % 10 < 1:
				image.set_pixel(x, y, panel.darkened(0.25))
			else:
				image.set_pixel(x, y, panel)


func _setup_decorations() -> void:
	super._setup_decorations()
	# The board itself: a big whiteboard with the days-since tally
	var board = ColorRect.new()
	board.color = Color(0.90, 0.90, 0.86)
	board.size = Vector2(TILE_SIZE * 3, TILE_SIZE * 1.4)
	board.position = Vector2(2 * TILE_SIZE, 0.6 * TILE_SIZE)
	decorations.add_child(board)
	var frame = ColorRect.new()
	frame.color = Color(0.30, 0.30, 0.32)
	frame.size = Vector2(TILE_SIZE * 3, 4)
	frame.position = Vector2(2 * TILE_SIZE, 0.6 * TILE_SIZE)
	decorations.add_child(frame)
	# Filing cabinet of incident forms
	for i in range(3):
		var drawer = ColorRect.new()
		drawer.color = Color(0.55, 0.56, 0.58).darkened(0.06 * i)
		drawer.size = Vector2(TILE_SIZE * 0.9, TILE_SIZE * 0.4)
		drawer.position = Vector2(10.5 * TILE_SIZE, (1.0 + i * 0.45) * TILE_SIZE)
		decorations.add_child(drawer)


func _crew_incident_count() -> int:
	var total := 0
	var gl = get_tree().root.get_node_or_null("GameLoop")
	if gl and "party" in gl:
		for m in gl.party:
			if m and is_instance_valid(m) and "permanent_injuries" in m:
				total += m.permanent_injuries.size()
	return total


func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	var marshal = OverworldNPCScript.new()
	marshal.npc_name = "Safety Marshal Greve"
	marshal.npc_type = "villager"
	marshal.position = Vector2(4 * TILE_SIZE, 4.5 * TILE_SIZE)
	marshal.dialogue_lines = [
		"This is the Incident Board. Every incident in Rivet Row gets a form. Form 1-A: the incident. Form 1-B: the feelings about the incident. 1-B is optional and nobody files it.",
		"The board used to say 'days since last incident'. Someone kept resetting it out of honesty. We respect that. We also reassigned him.",
		"Safety isn't the absence of incidents. It's the presence of paperwork. Sleep well.",
		"Your crew looks load-bearing. That's a compliment here. Don't waste it.",
	]
	npcs.add_child(marshal)

	# The Board — reads the crew's REAL permanent injuries.
	var count := _crew_incident_count()
	var tally: String = "Your crew's column reads ZERO recorded incidents. The board finds this suspicious. Nobody is this careful. It has started a file on your luck." if count == 0 \
		else "Your crew's column lists %d recorded incident%s. Each has a form. None have apologies." % [count, "" if count == 1 else "s"]
	var board = OverworldNPCScript.new()
	board.npc_name = "The Incident Board"
	board.npc_type = "villager"
	board.position = Vector2(3.5 * TILE_SIZE, 1.6 * TILE_SIZE)
	board.dialogue_lines = [
		"A whiteboard ruled into columns. One column has your crew's name on it. You never gave the board your crew's name.",
		tally,
		"At the bottom, in permanent marker under a sign that says NO PERMANENT MARKER: 'the body remembers what the form forgets.'",
	]
	npcs.add_child(board)


func _setup_transitions() -> void:
	super._setup_transitions()
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return
	var exit = AreaTransitionScript.new()
	exit.name = "Exit"
	exit.target_map = "rivet_row_village"
	exit.target_spawn = "incident_exit"
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
