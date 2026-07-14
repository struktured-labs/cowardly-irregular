extends BaseInterior
class_name RivetRowUnionHallInterior

## RivetRowUnionHallInterior - "Local 8743 Union Hall" at RivetRow.
## Steward Vetch keeps the strike ledgers and remembers every shift
## the Assembly Core lost on the second-shift incident. Foreshadows
## the Assembly Core dungeon AND the warden_industrial boss with a
## class-conscious frame nobody else has used yet.

const HALL_LAYOUT = [
	"WWWWWWWWWWWWWW",
	"W............W",
	"W.LLLLLLLLLL.W",
	"W............W",
	"W............W",
	"W....BB......W",
	"W....BB......W",
	"W..PP....PP..W",
	"W............W",
	"WWWWWWDDWWWWWW",
]


func _get_area_id() -> String:
	return "rivet_row_union_hall"


func _get_display_name() -> String:
	return "Local 8743 Union Hall"


func _get_map_width() -> int:
	return 14


func _get_map_height() -> int:
	return 10


func _get_layout() -> Array:
	return HALL_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(7, 8)
	spawn_points["podium"] = Vector2(6, 5)


## tick 68: route music through SoundManager's rivet_row_village arm so
## the hall plays W4 industrial music instead of medieval.
func _get_music_track() -> String:
	return "interior_union_hall"


func _draw_floor_tile(image: Image) -> void:
	# Diamond-plate steel floor with safety yellow striping near edges.
	# Reads as 'we expect spills here, deal with it'.
	var steel = Color(0.32, 0.32, 0.36)
	var steel_dark = Color(0.22, 0.22, 0.26)
	var diamond = Color(0.48, 0.48, 0.52)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Diamond pattern — pairs of raised dots in a grid
			var dx: int = x % 8
			var dy: int = y % 8
			var on_diamond: bool = (dx == 2 and dy == 2) or (dx == 6 and dy == 6) or (dx == 5 and dy == 1) or (dx == 1 and dy == 5)
			if on_diamond:
				image.set_pixel(x, y, diamond)
			elif (x + y) % 17 == 0:
				image.set_pixel(x, y, steel_dark)
			else:
				image.set_pixel(x, y, steel)


func _draw_wall_tile(image: Image) -> void:
	# Painted cinder-block walls with a faint scuff line where chairs
	# have rubbed for decades. Industrial green — the saturated kind
	# only union halls and DMVs ever used.
	var block = Color(0.20, 0.35, 0.22)
	var block_dark = Color(0.12, 0.22, 0.14)
	var seam = Color(0.65, 0.65, 0.58)
	var scuff = Color(0.45, 0.55, 0.42)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var row = y / 12
			var offset = 12 if row % 2 == 0 else 0
			var horiz = y % 12 == 0
			var vert = (x + offset) % 24 == 0
			var chair_scuff = y >= 18 and y <= 22
			if horiz or vert:
				image.set_pixel(x, y, seam)
			elif chair_scuff:
				image.set_pixel(x, y, scuff)
			else:
				image.set_pixel(x, y, block if (x + y) % 7 != 0 else block_dark)


func _setup_decorations() -> void:
	super._setup_decorations()
	_draw_ledger_shelf()
	_draw_podium()
	_draw_picket_signs()


func _draw_ledger_shelf() -> void:
	# Row of ledger spines at the L positions (row 2 cols 2-11) —
	# Vetch's strike record. Different muted colors so they read
	# as a row of books, not one block.
	var shelf = Color(0.18, 0.14, 0.10)
	var spines = [
		Color(0.55, 0.20, 0.15),
		Color(0.32, 0.40, 0.18),
		Color(0.18, 0.32, 0.48),
		Color(0.48, 0.36, 0.18),
		Color(0.42, 0.20, 0.32),
	]
	# Shelf backboard
	var back = ColorRect.new()
	back.color = shelf
	back.size = Vector2(TILE_SIZE * 10, TILE_SIZE)
	back.position = Vector2(2 * TILE_SIZE, 2 * TILE_SIZE)
	decorations.add_child(back)
	# 10 ledger spines
	for i in range(10):
		var spine = ColorRect.new()
		spine.color = spines[i % spines.size()]
		spine.size = Vector2(TILE_SIZE - 12, TILE_SIZE - 10)
		spine.position = Vector2((2 + i) * TILE_SIZE + 6, 2 * TILE_SIZE + 5)
		decorations.add_child(spine)


func _draw_podium() -> void:
	# Small podium at the B positions where Vetch addresses the
	# meetings. Wood front + raised lip on top.
	var wood = ColorRect.new()
	wood.color = Color(0.30, 0.20, 0.12)
	wood.size = Vector2(TILE_SIZE * 2, TILE_SIZE * 2)
	wood.position = Vector2(5 * TILE_SIZE, 5 * TILE_SIZE)
	decorations.add_child(wood)
	var top = ColorRect.new()
	top.color = Color(0.48, 0.34, 0.18)
	top.size = Vector2(TILE_SIZE * 2, 6)
	top.position = Vector2(5 * TILE_SIZE, 5 * TILE_SIZE)
	decorations.add_child(top)
	# Gavel — small dark cylinder on the top
	var gavel = ColorRect.new()
	gavel.color = Color(0.15, 0.10, 0.06)
	gavel.size = Vector2(14, 5)
	gavel.position = Vector2(5 * TILE_SIZE + 32, 5 * TILE_SIZE + 6)
	decorations.add_child(gavel)


func _draw_picket_signs() -> void:
	# Old picket signs leaning against the back wall at the P
	# positions. Each is a slat with a bright square at top showing
	# faded paint.
	var sign_colors = [
		Color(0.85, 0.55, 0.20),  # orange
		Color(0.30, 0.45, 0.85),  # blue
		Color(0.85, 0.25, 0.30),  # red
		Color(0.40, 0.55, 0.30),  # green
	]
	var anchors = [Vector2(2, 7), Vector2(3, 7), Vector2(10, 7), Vector2(11, 7)]
	for i in range(anchors.size()):
		var pos: Vector2 = anchors[i] * TILE_SIZE
		var stick = ColorRect.new()
		stick.color = Color(0.30, 0.20, 0.12)
		stick.size = Vector2(4, TILE_SIZE - 4)
		stick.position = pos + Vector2(TILE_SIZE / 2 - 2, 4)
		decorations.add_child(stick)
		var board = ColorRect.new()
		board.color = sign_colors[i % sign_colors.size()]
		board.size = Vector2(TILE_SIZE - 8, TILE_SIZE - 18)
		board.position = pos + Vector2(4, 0)
		decorations.add_child(board)


func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	var vetch = OverworldNPCScript.new()
	vetch.npc_name = "Steward Vetch"
	vetch.npc_type = "scholar"
	vetch.position = Vector2(7 * TILE_SIZE, 5 * TILE_SIZE)
	vetch.dialogue_lines = [
		"Easy, friend. Hat off in the hall — out of respect for the second shift.",
		"You're here about the Core? Yeah. The Core ate fourteen of ours that night.",
		"The bosses called it a 'productivity incident'. We called it murder.",
		"Their Warden's been promoted since. Walks the line every cycle. Talks soft.",
		"If you go to the Assembly Core, don't take their offer. They always make an offer.",
		"And read the seventh ledger before you leave. We wrote down what the Core asked us. So the next crew knows.",
	]
	npcs.add_child(vetch)


func _setup_transitions() -> void:
	super._setup_transitions()
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return
	var exit = AreaTransitionScript.new()
	exit.name = "Exit"
	exit.target_map = "rivet_row_village"
	exit.target_spawn = "union_hall_exit"
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
