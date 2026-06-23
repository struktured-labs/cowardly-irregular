extends BaseInterior
class_name BrasstonClockworkLoftInterior

## BrasstonClockworkLoftInterior - "Magister Clavis's Loft" at Brasston.
## Clavis is a retired clockmaker now studying the mountain — he hears
## the great Mechanism humming under the foothills. Foreshadows the
## SteampunkMechanism dungeon and (loosely) the Clockwork Dominion's
## endgame "every gear knows what it's part of" theme.

const LOFT_LAYOUT = [
	"WWWWWWWWWWWWWW",
	"W............W",
	"W.GGGGGGGGGG.W",
	"W............W",
	"W.....CC.....W",
	"W.....CC.....W",
	"W............W",
	"W..BB....BB..W",
	"W............W",
	"WWWWWWDDWWWWWW",
]


func _get_area_id() -> String:
	return "brasston_clockwork_loft"


func _get_display_name() -> String:
	return "Clockwork Loft"


func _get_map_width() -> int:
	return 14


func _get_map_height() -> int:
	return 10


func _get_layout() -> Array:
	return LOFT_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(7, 8)
	spawn_points["bench"] = Vector2(6, 5)


## tick 68: route music through SoundManager's brasston_village arm so
## the loft plays W3 steampunk music instead of medieval.
func _get_music_track() -> String:
	return "brasston_village"


func _draw_floor_tile(image: Image) -> void:
	# Polished brass parquet — repeating brass tiles with riveted
	# joints. Distinct from Sandrift's sand boards or the chapel's
	# stone — this is engineering, not nature or faith.
	var brass = Color(0.62, 0.50, 0.22)
	var brass_dark = Color(0.42, 0.34, 0.14)
	var rivet = Color(0.80, 0.72, 0.42)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var joint = (x % 8 == 0) or (y % 8 == 0)
			var rivet_spot = (x % 8 == 4) and (y % 8 == 4)
			if rivet_spot:
				image.set_pixel(x, y, rivet)
			elif joint:
				image.set_pixel(x, y, brass_dark)
			else:
				image.set_pixel(x, y, brass)


func _draw_wall_tile(image: Image) -> void:
	# Riveted copper plates with vertical pipe seams. The room reads
	# as the inside of a small boiler.
	var copper = Color(0.55, 0.32, 0.16)
	var copper_dark = Color(0.30, 0.16, 0.06)
	var pipe = Color(0.42, 0.42, 0.46)
	var pipe_shine = Color(0.78, 0.78, 0.82)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var pipe_run = x % 16 < 4
			var pipe_highlight = x % 16 == 1
			var rivet_row = (y % 10 == 5) and (x % 8 == 2) and not pipe_run
			if pipe_highlight:
				image.set_pixel(x, y, pipe_shine)
			elif pipe_run:
				image.set_pixel(x, y, pipe)
			elif rivet_row:
				image.set_pixel(x, y, copper_dark)
			else:
				image.set_pixel(x, y, copper if (x + y) % 7 != 0 else copper_dark)


func _setup_decorations() -> void:
	super._setup_decorations()
	_draw_gear_wall()
	_draw_workbench()
	_draw_pendulums()


func _draw_gear_wall() -> void:
	# Row of decorative gears at the G positions (row 2 cols 2-11) —
	# Clavis's collection of timepiece innards. Each gear is a small
	# circle of brass with darker teeth marks.
	var gear_face = Color(0.78, 0.62, 0.28)
	var gear_dark = Color(0.42, 0.32, 0.14)
	var gear_glow = Color(0.95, 0.85, 0.50)
	for i in range(10):
		var pos: Vector2 = Vector2(2 + i, 2) * TILE_SIZE
		var face = ColorRect.new()
		face.color = gear_face
		face.size = Vector2(TILE_SIZE - 6, TILE_SIZE - 6)
		face.position = pos + Vector2(3, 3)
		decorations.add_child(face)
		# Inner cap
		var cap = ColorRect.new()
		cap.color = gear_dark
		cap.size = Vector2(TILE_SIZE - 18, TILE_SIZE - 18)
		cap.position = pos + Vector2(9, 9)
		decorations.add_child(cap)
		# Highlight glint
		var glint = ColorRect.new()
		glint.color = gear_glow
		glint.size = Vector2(4, 4)
		glint.position = pos + Vector2(7, 7)
		decorations.add_child(glint)


func _draw_workbench() -> void:
	# 2-tile workbench at the C positions — Clavis's repair table.
	# Wooden top with a vise + open pocket-watch on display.
	var wood = ColorRect.new()
	wood.color = Color(0.32, 0.22, 0.14)
	wood.size = Vector2(TILE_SIZE * 2, TILE_SIZE * 2)
	wood.position = Vector2(5 * TILE_SIZE, 4 * TILE_SIZE)
	decorations.add_child(wood)
	var top = ColorRect.new()
	top.color = Color(0.50, 0.36, 0.22)
	top.size = Vector2(TILE_SIZE * 2, 6)
	top.position = Vector2(5 * TILE_SIZE, 4 * TILE_SIZE)
	decorations.add_child(top)
	# Vise
	var vise = ColorRect.new()
	vise.color = Color(0.42, 0.42, 0.46)
	vise.size = Vector2(12, 8)
	vise.position = Vector2(5 * TILE_SIZE + 6, 4 * TILE_SIZE + 8)
	decorations.add_child(vise)
	# Open pocket watch — gold disc with white face
	var watch_body = ColorRect.new()
	watch_body.color = Color(0.78, 0.62, 0.28)
	watch_body.size = Vector2(14, 14)
	watch_body.position = Vector2(5 * TILE_SIZE + 36, 4 * TILE_SIZE + 8)
	decorations.add_child(watch_body)
	var watch_face = ColorRect.new()
	watch_face.color = Color(0.88, 0.82, 0.65)
	watch_face.size = Vector2(10, 10)
	watch_face.position = Vector2(5 * TILE_SIZE + 38, 4 * TILE_SIZE + 10)
	decorations.add_child(watch_face)


func _draw_pendulums() -> void:
	# Two pendulum clocks at the B positions (row 7) — hanging brass
	# bobs visible. Sets up the 'humming' line by showing a room
	# that's literally full of ticking things.
	for anchor in [Vector2(2, 7), Vector2(10, 7)]:
		var case_rect = ColorRect.new()
		case_rect.color = Color(0.32, 0.22, 0.14)
		case_rect.size = Vector2(TILE_SIZE * 2, TILE_SIZE)
		case_rect.position = anchor * TILE_SIZE
		decorations.add_child(case_rect)
		var face = ColorRect.new()
		face.color = Color(0.88, 0.82, 0.65)
		face.size = Vector2(TILE_SIZE - 12, TILE_SIZE - 14)
		face.position = anchor * TILE_SIZE + Vector2(6, 4)
		decorations.add_child(face)
		var bob = ColorRect.new()
		bob.color = Color(0.78, 0.62, 0.28)
		bob.size = Vector2(8, 8)
		bob.position = anchor * TILE_SIZE + Vector2(TILE_SIZE - 4, TILE_SIZE - 14)
		decorations.add_child(bob)


func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	var clavis = OverworldNPCScript.new()
	clavis.npc_name = "Magister Clavis"
	clavis.npc_type = "scholar"
	clavis.position = Vector2(7 * TILE_SIZE, 5 * TILE_SIZE)
	clavis.dialogue_lines = [
		"Mind the pendulums. They're synchronized — disturb one and you'll throw off the count.",
		"I retired from clockmaking last spring. Then I started hearing the Mechanism.",
		"Under the mountain. A great gear-train, slow and very deliberate. You can hear it if you press your ear to a wall after midnight.",
		"Every gear knows what it's part of. I think that's the unsettling part. They KNOW.",
		"If you go to the old steam works, take the maintenance hatch on the third platform. The front entrance is for tourists.",
		"And if a clock here ever ticks WRONG — leave. The Mechanism doesn't tolerate disagreement.",
	]
	npcs.add_child(clavis)


func _setup_transitions() -> void:
	super._setup_transitions()
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return
	var exit = AreaTransitionScript.new()
	exit.name = "Exit"
	exit.target_map = "brasston_village"
	exit.target_spawn = "clockwork_loft_exit"
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
