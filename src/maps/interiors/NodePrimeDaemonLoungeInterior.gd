extends BaseInterior
class_name NodePrimeDaemonLoungeInterior

## NodePrimeDaemonLoungeInterior - "Daemon Lounge / Terminal Room"
## at NodePrime. SUDO-1 is a sysadmin who keeps the legacy terminal
## alive because the Root remembers what they used to do here.
## Foreshadows both the RootProcess (W5) and NullChamber (W6)
## dungeons — the only W5 interior, so it has to do double duty.

const LOUNGE_LAYOUT = [
	"WWWWWWWWWWWWWW",
	"W............W",
	"W.TTTT..TTTT.W",
	"W............W",
	"W.....RR.....W",
	"W.....RR.....W",
	"W............W",
	"W..CC....CC..W",
	"W............W",
	"WWWWWWDDWWWWWW",
]


func _get_area_id() -> String:
	return "node_prime_daemon_lounge"


func _get_display_name() -> String:
	return "Daemon Lounge"


func _get_map_width() -> int:
	return 14


func _get_map_height() -> int:
	return 10


func _get_layout() -> Array:
	return LOUNGE_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(7, 8)
	spawn_points["terminal"] = Vector2(6, 5)


func _draw_floor_tile(image: Image) -> void:
	# Raised computer-room floor — square anti-static tiles with a
	# bluish-black hue and faint cooling-vent grilles at the seams.
	# Distinct from RivetRow's diamond-plate steel.
	var dark = Color(0.10, 0.12, 0.18)
	var dark2 = Color(0.16, 0.18, 0.24)
	var vent = Color(0.42, 0.52, 0.62)
	var glow = Color(0.40, 0.85, 0.90)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var seam = (x % 16 == 0) or (y % 16 == 0)
			var vent_grille = (y % 16 == 1) and (x % 4 == 2)
			var glow_dot = (x * 7 + y * 11) % 89 == 0
			if vent_grille:
				image.set_pixel(x, y, vent)
			elif glow_dot:
				image.set_pixel(x, y, glow)
			elif seam:
				image.set_pixel(x, y, dark)
			else:
				image.set_pixel(x, y, dark2)


func _draw_wall_tile(image: Image) -> void:
	# Server-rack walls — vertical strips of dark metal with green
	# LED activity lights blinking down the columns. Reads as
	# 'something is alive in here'.
	var rack = Color(0.18, 0.20, 0.24)
	var rack_dark = Color(0.10, 0.12, 0.16)
	var led_green = Color(0.45, 0.95, 0.45)
	var led_amber = Color(0.95, 0.75, 0.30)
	var rim = Color(0.30, 0.30, 0.36)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var rail = (x % 8 == 0) or (x % 8 == 7)
			var led_row = (y % 6 == 3) and (x % 8 == 4)
			var amber_blink = (y % 18 == 9) and (x % 16 == 12)
			if rail:
				image.set_pixel(x, y, rim)
			elif amber_blink:
				image.set_pixel(x, y, led_amber)
			elif led_row:
				image.set_pixel(x, y, led_green)
			elif (x + y) % 11 == 0:
				image.set_pixel(x, y, rack_dark)
			else:
				image.set_pixel(x, y, rack)


func _setup_decorations() -> void:
	super._setup_decorations()
	_draw_terminals()
	_draw_main_console()
	_draw_coffee_cups()


func _draw_terminals() -> void:
	# Eight CRT terminals at the T positions (row 2 cols 2-5 + 8-11).
	# Each one is a small monitor with a faint green text glow.
	var case_color = Color(0.85, 0.82, 0.72)  # 80s beige
	var screen = Color(0.05, 0.15, 0.08)
	var text_glow = Color(0.30, 0.95, 0.45)
	for anchor in [Vector2(2, 2), Vector2(8, 2)]:
		for i in range(4):
			var pos: Vector2 = anchor * TILE_SIZE + Vector2(i * TILE_SIZE, 0)
			var case_rect = ColorRect.new()
			case_rect.color = case_color
			case_rect.size = Vector2(TILE_SIZE - 4, TILE_SIZE - 4)
			case_rect.position = pos + Vector2(2, 2)
			decorations.add_child(case_rect)
			var screen_rect = ColorRect.new()
			screen_rect.color = screen
			screen_rect.size = Vector2(TILE_SIZE - 12, TILE_SIZE - 14)
			screen_rect.position = pos + Vector2(6, 6)
			decorations.add_child(screen_rect)
			var cursor = ColorRect.new()
			cursor.color = text_glow
			cursor.size = Vector2(4, 2)
			cursor.position = pos + Vector2(10, TILE_SIZE - 14)
			decorations.add_child(cursor)


func _draw_main_console() -> void:
	# 2-tile main console at the R positions — bigger CRT + keyboard.
	# Cyan tint suggests the active terminal SUDO-1 watches.
	var case_color = Color(0.78, 0.74, 0.64)
	var screen = Color(0.06, 0.12, 0.18)
	var glow = Color(0.40, 0.85, 0.95)
	var case_rect = ColorRect.new()
	case_rect.color = case_color
	case_rect.size = Vector2(TILE_SIZE * 2, TILE_SIZE * 2)
	case_rect.position = Vector2(5 * TILE_SIZE, 4 * TILE_SIZE)
	decorations.add_child(case_rect)
	var screen_rect = ColorRect.new()
	screen_rect.color = screen
	screen_rect.size = Vector2(TILE_SIZE * 2 - 14, TILE_SIZE - 4)
	screen_rect.position = Vector2(5 * TILE_SIZE + 7, 4 * TILE_SIZE + 6)
	decorations.add_child(screen_rect)
	# Cyan glow bar at bottom of screen — 'process running' indicator
	var bar = ColorRect.new()
	bar.color = glow
	bar.size = Vector2(TILE_SIZE * 2 - 18, 3)
	bar.position = Vector2(5 * TILE_SIZE + 9, 4 * TILE_SIZE + TILE_SIZE - 6)
	decorations.add_child(bar)
	# Keyboard
	var keys = ColorRect.new()
	keys.color = Color(0.20, 0.22, 0.26)
	keys.size = Vector2(TILE_SIZE * 2 - 8, TILE_SIZE - 8)
	keys.position = Vector2(5 * TILE_SIZE + 4, 4 * TILE_SIZE + TILE_SIZE + 4)
	decorations.add_child(keys)


func _draw_coffee_cups() -> void:
	# Pairs of empty coffee cups at the C positions (row 7) — long
	# nights at the terminal. The room reads as 'has been lived in'.
	var ceramic = Color(0.85, 0.85, 0.85)
	var stain = Color(0.40, 0.25, 0.12)
	var handle = Color(0.65, 0.65, 0.65)
	for anchor in [Vector2(2, 7), Vector2(3, 7), Vector2(10, 7), Vector2(11, 7)]:
		var pos: Vector2 = anchor * TILE_SIZE
		var cup = ColorRect.new()
		cup.color = ceramic
		cup.size = Vector2(12, 14)
		cup.position = pos + Vector2(TILE_SIZE / 2 - 6, 8)
		decorations.add_child(cup)
		var inside = ColorRect.new()
		inside.color = stain
		inside.size = Vector2(8, 3)
		inside.position = pos + Vector2(TILE_SIZE / 2 - 4, 10)
		decorations.add_child(inside)
		var handle_rect = ColorRect.new()
		handle_rect.color = handle
		handle_rect.size = Vector2(3, 8)
		handle_rect.position = pos + Vector2(TILE_SIZE / 2 + 6, 11)
		decorations.add_child(handle_rect)


func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	var sudo = OverworldNPCScript.new()
	sudo.npc_name = "SUDO-1"
	sudo.npc_type = "scholar"
	sudo.position = Vector2(7 * TILE_SIZE, 5 * TILE_SIZE)
	sudo.dialogue_lines = [
		"Mind the heat. Fans haven't worked since the dispatcher quit.",
		"You're looking for the Root? Bad idea. Process 1 has been corrupted for years.",
		"Used to be I could kill it. Now it kills back.",
		"If you reach the Null Chamber, don't bring a name. It writes you over.",
		"And don't touch any terminal that's already open. Those aren't logs — those are LISTENERS.",
		"I keep this one alive because the Root remembers what we used to do here. As long as I'm at the prompt, it remembers ME.",
	]
	npcs.add_child(sudo)


func _setup_transitions() -> void:
	super._setup_transitions()
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return
	var exit = AreaTransitionScript.new()
	exit.name = "Exit"
	exit.target_map = "node_prime_village"
	exit.target_spawn = "daemon_lounge_exit"
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
