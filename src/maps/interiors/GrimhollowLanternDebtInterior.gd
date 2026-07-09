extends BaseInterior
class_name GrimhollowLanternDebtInterior

## GrimhollowLanternDebtInterior - the Lantern Debt Office (Grimhollow CCC
## building). Village-interior expansion round 6 — ACTUALLY completes
## two-interior coverage of every W1 dragon village (round 5's claim was one
## village early; Grimhollow only had the witch hut). In the swamp, light is
## loaned, never owned: every lantern in Grimhollow is borrowed from this
## office and the books are kept in the dark. The memorable thing is the
## DEBT BOOK's first page — one borrower outstanding since before the office
## existed. Umbraxis foreshadow: the cave doesn't borrow light. It collects.

const ROOM_LAYOUT = [
	"WWWWWWWWWWWWWW",
	"W............W",
	"W..BB....T...W",
	"W............W",
	"W.T..........W",
	"W........T...W",
	"W............W",
	"W............W",
	"WWWWWWDDWWWWWW",
]


func _get_area_id() -> String:
	return "grimhollow_lantern_debt"


func _get_display_name() -> String:
	return "The Lantern Debt Office"


func _get_map_width() -> int:
	return 14


func _get_map_height() -> int:
	return 9


func _get_layout() -> Array:
	return ROOM_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(7, 7)
	spawn_points["counter"] = Vector2(4, 3)


func _draw_floor_tile(image: Image) -> void:
	# Dark bog-oak boards, damp-swollen, with faint lantern-glow pools.
	var oak = Color(0.22, 0.19, 0.16)
	var glow = Color(0.36, 0.30, 0.18)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var cx := absi(x - 16)
			var cy := absi(y - 16)
			if cx + cy < 7:
				image.set_pixel(x, y, glow)
			elif y % 8 == 0:
				image.set_pixel(x, y, oak.darkened(0.25))
			else:
				image.set_pixel(x, y, oak)


func _draw_wall_tile(image: Image) -> void:
	# Tarred swamp timber; hung lantern hooks every panel, most empty.
	var tar = Color(0.16, 0.15, 0.14)
	var hook = Color(0.45, 0.42, 0.36)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var is_hook = y in [6, 7] and x % 16 in [8, 9]
			var seam = x % 16 < 2
			if is_hook:
				image.set_pixel(x, y, hook)
			elif seam:
				image.set_pixel(x, y, tar.darkened(0.3))
			else:
				image.set_pixel(x, y, tar)


func _setup_decorations() -> void:
	super._setup_decorations()
	_draw_counter()
	_draw_lantern_rack()


func _draw_counter() -> void:
	var counter = ColorRect.new()
	counter.color = Color(0.30, 0.24, 0.18)
	counter.size = Vector2(TILE_SIZE * 2, TILE_SIZE * 0.8)
	counter.position = Vector2(3 * TILE_SIZE, 2.2 * TILE_SIZE)
	decorations.add_child(counter)
	var book = ColorRect.new()
	book.color = Color(0.14, 0.13, 0.16)
	book.size = Vector2(TILE_SIZE * 0.8, TILE_SIZE * 0.45)
	book.position = Vector2(3.5 * TILE_SIZE, 2.3 * TILE_SIZE)
	decorations.add_child(book)


func _draw_lantern_rack() -> void:
	# Loaner lanterns on the east wall — three lit, many hooks bare.
	for i in range(3):
		var lamp = ColorRect.new()
		lamp.color = Color(0.92, 0.78, 0.40)
		lamp.size = Vector2(8, 10)
		lamp.position = Vector2((10.4 + i * 0.8) * TILE_SIZE, 1.2 * TILE_SIZE)
		decorations.add_child(lamp)
		var halo = ColorRect.new()
		halo.color = Color(0.92, 0.78, 0.40, 0.18)
		halo.size = Vector2(20, 20)
		halo.position = lamp.position - Vector2(6, 5)
		decorations.add_child(halo)


func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	var wick = OverworldNPCScript.new()
	wick.npc_name = "Clerk Wick"
	wick.npc_type = "villager"
	wick.position = Vector2(4 * TILE_SIZE, 4 * TILE_SIZE)
	wick.dialogue_lines = [
		"Every lantern in Grimhollow is a loan. You don't OWN light in a swamp. You demonstrate you deserve it, nightly.",
		"Interest is paid in wick-trimmings and honesty. We are flexible on the trimmings.",
		"Late returns get a visit. Not from me. From the dark that was promised the lantern back.",
		"We keep the books unlit. Seems fair. The books agree, which worries me on the quiet nights.",
	]
	npcs.add_child(wick)

	# The Debt Book — first page, oldest debt. The room's weight.
	var book = OverworldNPCScript.new()
	book.npc_name = "The Debt Book"
	book.npc_type = "villager"
	book.position = Vector2(4 * TILE_SIZE, 2.7 * TILE_SIZE)
	book.dialogue_lines = [
		"A loans register bound in tar-cloth, kept open in the one unlit corner of the office.",
		"The first page lists a single borrower: THE CAVE, SOUTH OF TOWN. Item: 'all of it'. Date: before the office.",
		"Under 'collateral' someone has written, in very old ink: 'she left us the shadows as a deposit.'",
		"The cave doesn't borrow light. It collects. The office considers the account current, and would prefer not to audit it.",
	]
	npcs.add_child(book)


func _setup_transitions() -> void:
	super._setup_transitions()
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return
	var exit = AreaTransitionScript.new()
	exit.name = "Exit"
	exit.target_map = "grimhollow_village"
	exit.target_spawn = "lantern_exit"
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
