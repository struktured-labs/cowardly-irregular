extends BaseInterior
class_name GrimhollowWitchHutInterior

## GrimhollowWitchHutInterior - "Old Mire's Hut" at Grimhollow Village.
## A swamp witch's cottage. Mire reads bones and foreshadows Umbraxis,
## the W1 shadow dragon — the most ominous of the four elementals.
## Sets up Umbraxis's "she IS the cave" framing without spoiling the
## fight.

const HUT_LAYOUT = [
	"WWWWWWWWWWWWWW",
	"W............W",
	"W.JJJJ..JJJJ.W",
	"W............W",
	"W.....CC.....W",
	"W.....CC.....W",
	"W............W",
	"W.BB......BB.W",
	"W............W",
	"WWWWWWDDWWWWWW",
]


func _get_area_id() -> String:
	return "grimhollow_witch_hut"


func _get_display_name() -> String:
	return "Witch's Hut"


func _get_map_width() -> int:
	return 14


func _get_map_height() -> int:
	return 10


func _get_layout() -> Array:
	return HUT_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(7, 8)
	spawn_points["cauldron"] = Vector2(6, 5)


func _draw_floor_tile(image: Image) -> void:
	# Damp boards over swamp mud. Greenish-brown with bog stain
	# patches and the occasional moss tuft.
	var board = Color(0.32, 0.28, 0.20)
	var board_dark = Color(0.22, 0.20, 0.14)
	var stain = Color(0.25, 0.32, 0.20)
	var moss = Color(0.40, 0.52, 0.30)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var plank = y % 6
			var seam = plank == 0 or plank == 5
			var moss_dot = (x * 7 + y * 11) % 31 == 0
			if seam:
				image.set_pixel(x, y, board_dark)
			elif moss_dot:
				image.set_pixel(x, y, moss)
			elif (x + y) % 13 == 0:
				image.set_pixel(x, y, stain)
			else:
				image.set_pixel(x, y, board)


func _draw_wall_tile(image: Image) -> void:
	# Rough dark-wood walls with hanging vines along the upper edge.
	var wood = Color(0.22, 0.16, 0.10)
	var wood_dark = Color(0.14, 0.10, 0.06)
	var vine = Color(0.30, 0.45, 0.22)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var vine_drape = y < 7 and ((x + y) % 5 < 2)
			if vine_drape:
				image.set_pixel(x, y, vine)
			elif (x * 3 + y) % 7 < 1:
				image.set_pixel(x, y, wood_dark)
			else:
				image.set_pixel(x, y, wood)


func _setup_decorations() -> void:
	super._setup_decorations()
	_draw_jars()
	_draw_cauldron()
	_draw_bones()


func _draw_jars() -> void:
	# Apothecary jars at the J positions (rows 2 cols 2-5 + 8-11).
	# Each jar = bottle silhouette + tinted liquid.
	var glass = Color(0.16, 0.20, 0.22)
	var liquids = [
		Color(0.20, 0.55, 0.25, 0.85),  # green
		Color(0.55, 0.30, 0.55, 0.85),  # purple
		Color(0.60, 0.20, 0.20, 0.85),  # blood red
		Color(0.30, 0.50, 0.65, 0.85),  # sea
	]
	for shelf_anchor in [Vector2(2, 2), Vector2(8, 2)]:
		var shelf = ColorRect.new()
		shelf.color = Color(0.20, 0.14, 0.08)
		shelf.size = Vector2(TILE_SIZE * 4, TILE_SIZE)
		shelf.position = shelf_anchor * TILE_SIZE
		decorations.add_child(shelf)
		for i in range(4):
			var bottle_pos: Vector2 = shelf_anchor * TILE_SIZE + Vector2(i * TILE_SIZE + 6, 4)
			var bottle = ColorRect.new()
			bottle.color = glass
			bottle.size = Vector2(TILE_SIZE - 14, TILE_SIZE - 8)
			bottle.position = bottle_pos
			decorations.add_child(bottle)
			var liquid = ColorRect.new()
			liquid.color = liquids[i]
			liquid.size = Vector2(TILE_SIZE - 18, TILE_SIZE - 16)
			liquid.position = bottle_pos + Vector2(2, 4)
			decorations.add_child(liquid)


func _draw_cauldron() -> void:
	# Black iron cauldron at the C positions. Green bubbling brew
	# inside — signature witch-hut centerpiece.
	var iron = Color(0.10, 0.08, 0.10)
	var iron_light = Color(0.22, 0.20, 0.22)
	var brew = Color(0.30, 0.65, 0.35)
	var brew_hot = Color(0.55, 0.85, 0.50)
	var pot = ColorRect.new()
	pot.color = iron
	pot.size = Vector2(TILE_SIZE * 2, TILE_SIZE * 2)
	pot.position = Vector2(5 * TILE_SIZE, 4 * TILE_SIZE)
	decorations.add_child(pot)
	var rim = ColorRect.new()
	rim.color = iron_light
	rim.size = Vector2(TILE_SIZE * 2, 5)
	rim.position = Vector2(5 * TILE_SIZE, 4 * TILE_SIZE)
	decorations.add_child(rim)
	var liquid = ColorRect.new()
	liquid.color = brew
	liquid.size = Vector2(TILE_SIZE * 2 - 8, TILE_SIZE - 4)
	liquid.position = Vector2(5 * TILE_SIZE + 4, 4 * TILE_SIZE + 5)
	decorations.add_child(liquid)
	var bubble = ColorRect.new()
	bubble.color = brew_hot
	bubble.size = Vector2(10, 6)
	bubble.position = Vector2(5 * TILE_SIZE + 18, 4 * TILE_SIZE + 8)
	decorations.add_child(bubble)


func _draw_bones() -> void:
	# Bone fragments at the B positions in row 7 — sets up Mire's
	# 'bring me bones' line so the room reads honest.
	var bone = Color(0.85, 0.80, 0.70)
	var bone_shadow = Color(0.55, 0.50, 0.42)
	for anchor in [Vector2(2, 7), Vector2(10, 7)]:
		var skull = ColorRect.new()
		skull.color = bone
		skull.size = Vector2(TILE_SIZE - 10, TILE_SIZE - 16)
		skull.position = anchor * TILE_SIZE + Vector2(5, 8)
		decorations.add_child(skull)
		var jaw = ColorRect.new()
		jaw.color = bone_shadow
		jaw.size = Vector2(TILE_SIZE - 14, 4)
		jaw.position = anchor * TILE_SIZE + Vector2(7, TILE_SIZE - 12)
		decorations.add_child(jaw)


func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	var mire = OverworldNPCScript.new()
	mire.npc_name = "Old Mire"
	mire.npc_type = "scholar"
	mire.position = Vector2(8 * TILE_SIZE, 5 * TILE_SIZE)
	mire.dialogue_lines = [
		"Don't track swamp water on my floor. The boards rot enough already.",
		"You smell like cave dust. Voltharion's leavings, by the static of it.",
		"Umbraxis... yes, I know that name. Don't say it three times. Don't ever.",
		"She doesn't have a cave. She IS the cave. The cave that USED to be there is something else now.",
		"Bring me bones if you find any in the dark. I'll tell you what they used to be.",
		"And tell your mage friend — light doesn't help. The shadow eats the light first.",
	]
	npcs.add_child(mire)


func _setup_transitions() -> void:
	super._setup_transitions()
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return
	var exit = AreaTransitionScript.new()
	exit.name = "Exit"
	exit.target_map = "grimhollow_village"
	exit.target_spawn = "witch_hut_exit"
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
