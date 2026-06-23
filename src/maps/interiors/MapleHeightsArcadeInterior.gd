extends BaseInterior
class_name MapleHeightsArcadeInterior

## MapleHeightsArcadeInterior - "Glitch City Arcade" at MapleHeights.
## Crusher Pete keeps the cabinets running because some things
## shouldn't be turned off. Pays off Greenleaf's "houses change shape"
## foreshadowing from Eldertree (tick 37) — the first interior in W2
## proper. Meta-aware tone, retro 70s-80s mall arcade vibe.

const ARCADE_LAYOUT = [
	"WWWWWWWWWWWWWW",
	"W............W",
	"W.MMMM..MMMM.W",
	"W............W",
	"W.PPPP..PPPP.W",
	"W............W",
	"W............W",
	"W....CC......W",
	"W............W",
	"WWWWWWDDWWWWWW",
]


func _get_area_id() -> String:
	return "maple_heights_arcade"


func _get_display_name() -> String:
	return "Glitch City Arcade"


func _get_map_width() -> int:
	return 14


func _get_map_height() -> int:
	return 10


func _get_layout() -> Array:
	return ARCADE_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(7, 8)
	spawn_points["counter"] = Vector2(5, 7)


func _draw_floor_tile(image: Image) -> void:
	# Black-and-white checkerboard floor — classic 80s arcade vibe.
	# Slightly worn with scuff marks from decades of foot traffic.
	var black = Color(0.10, 0.10, 0.12)
	var white = Color(0.85, 0.85, 0.88)
	var scuff = Color(0.55, 0.55, 0.58)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var checker = ((x / 8) + (y / 8)) % 2 == 0
			var scuff_dot = (x * 5 + y * 7) % 41 == 0
			if scuff_dot and checker:
				image.set_pixel(x, y, scuff)
			elif checker:
				image.set_pixel(x, y, white)
			else:
				image.set_pixel(x, y, black)


func _draw_wall_tile(image: Image) -> void:
	# Neon-purple walls with darker grid lines — the kind of saturated
	# magenta that aged badly into the 90s. Hint of CRT scanlines.
	var purple = Color(0.32, 0.10, 0.45)
	var purple_dark = Color(0.18, 0.05, 0.30)
	var neon_pink = Color(0.85, 0.35, 0.75)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var scanline = y % 4 == 0
			var grid = (x % 16 == 0) or (y % 16 == 0)
			var glow = (x * 3 + y) % 71 == 0
			if scanline:
				image.set_pixel(x, y, purple_dark)
			elif glow:
				image.set_pixel(x, y, neon_pink)
			elif grid:
				image.set_pixel(x, y, purple_dark)
			else:
				image.set_pixel(x, y, purple)


func _setup_decorations() -> void:
	super._setup_decorations()
	_draw_cabinets("M", Vector2(2, 2), Color(0.10, 0.55, 0.85), "BUG ZERO")
	_draw_cabinets("M", Vector2(8, 2), Color(0.85, 0.25, 0.25), "DRAGON")
	_draw_cabinets("P", Vector2(2, 4), Color(0.85, 0.65, 0.20), "PAC-MOM")
	_draw_cabinets("P", Vector2(8, 4), Color(0.40, 0.75, 0.40), "SPACE 2")
	_draw_counter()


func _draw_cabinets(_marker: String, anchor: Vector2, hue: Color, label_text: String) -> void:
	# Each cabinet pair is a tall body + bright screen + glow. The
	# label hint is drawn as a small colored bar — the player sees
	# 'four neon machines' visually, the dialogue says the names.
	for i in range(2):
		var pos: Vector2 = anchor * TILE_SIZE + Vector2(i * TILE_SIZE * 2, 0)
		var body = ColorRect.new()
		body.color = Color(0.18, 0.18, 0.22)
		body.size = Vector2(TILE_SIZE * 2 - 4, TILE_SIZE)
		body.position = pos
		decorations.add_child(body)
		var screen = ColorRect.new()
		screen.color = hue
		screen.size = Vector2(TILE_SIZE * 2 - 12, TILE_SIZE - 14)
		screen.position = pos + Vector2(4, 4)
		decorations.add_child(screen)
		var glow = ColorRect.new()
		glow.color = Color(1.0, 1.0, 1.0, 0.25)
		glow.size = Vector2(TILE_SIZE * 2 - 12, 4)
		glow.position = pos + Vector2(4, 4)
		decorations.add_child(glow)
		# Faint label hint — colored bar in the brand's hue
		var label = ColorRect.new()
		label.color = hue
		label.size = Vector2(TILE_SIZE * 2 - 12, 3)
		label.position = pos + Vector2(4, TILE_SIZE - 8)
		decorations.add_child(label)


func _draw_counter() -> void:
	# Pete's counter — wooden top, glass display, a stack of tokens.
	var counter_body = ColorRect.new()
	counter_body.color = Color(0.35, 0.25, 0.18)
	counter_body.size = Vector2(TILE_SIZE * 2, TILE_SIZE)
	counter_body.position = Vector2(5 * TILE_SIZE, 7 * TILE_SIZE)
	decorations.add_child(counter_body)
	var counter_top = ColorRect.new()
	counter_top.color = Color(0.55, 0.40, 0.25)
	counter_top.size = Vector2(TILE_SIZE * 2, 6)
	counter_top.position = Vector2(5 * TILE_SIZE, 7 * TILE_SIZE)
	decorations.add_child(counter_top)
	# Token jar — small bronze rectangle
	var jar = ColorRect.new()
	jar.color = Color(0.75, 0.55, 0.20)
	jar.size = Vector2(10, 10)
	jar.position = Vector2(5 * TILE_SIZE + 8, 7 * TILE_SIZE + 8)
	decorations.add_child(jar)
	var coin_glint = ColorRect.new()
	coin_glint.color = Color(1.0, 0.85, 0.30)
	coin_glint.size = Vector2(6, 3)
	coin_glint.position = Vector2(5 * TILE_SIZE + 10, 7 * TILE_SIZE + 9)
	decorations.add_child(coin_glint)


func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	var pete = OverworldNPCScript.new()
	pete.npc_name = "Crusher Pete"
	pete.npc_type = "merchant"
	pete.position = Vector2(6 * TILE_SIZE, 7 * TILE_SIZE)
	pete.dialogue_lines = [
		"Welcome to Glitch City. Quarters in the jar. Token machine's busted, just shake it.",
		"Cabinets been acting weird lately. Bug Zero 2 turns into Bug Zero 5 if you blink at it.",
		"Saw a guy yesterday — the screen ate him. Whole thing. Just his hat left on the chair.",
		"I keep the place running because some things shouldn't be turned off.",
		"You came from the woods? Yeah. The old druid out there warned about this. Square houses, loud roads, he said. Smart guy.",
		"If you're heading further out, watch the strip mall after dusk. Mannequins move when you're not looking.",
	]
	npcs.add_child(pete)


func _setup_transitions() -> void:
	super._setup_transitions()
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return
	var exit = AreaTransitionScript.new()
	exit.name = "Exit"
	exit.target_map = "maple_heights_village"
	exit.target_spawn = "arcade_exit"
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
