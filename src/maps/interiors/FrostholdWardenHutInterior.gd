extends BaseInterior
class_name FrostholdWardenHutInterior

## FrostholdWardenHutInterior - "Warden Trygg's Hut" at Frosthold.
## Trygg has spent decades scouting the ice cave; his lines foreshadow
## Glacius, the Frozen Sovereign (W1 ice dragon). Plot setup for the
## fight without spoiling its mechanics.

const HUT_LAYOUT = [
	"WWWWWWWWWWWW",
	"W..........W",
	"W..PPPP....W",
	"W..........W",
	"W....HH....W",
	"W....HH....W",
	"W..........W",
	"W..........W",
	"WWWWWDDWWWWW",
]


func _get_area_id() -> String:
	return "frosthold_warden_hut"


func _get_display_name() -> String:
	return "Warden's Hut"


func _get_map_width() -> int:
	return 12


func _get_map_height() -> int:
	return 9


func _get_layout() -> Array:
	return HUT_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(5, 7)
	spawn_points["hearth"] = Vector2(5, 5)


func _draw_floor_tile(image: Image) -> void:
	# Frost-laced stone floor — pale blue-gray with hairline cracks
	# that read as ice rime. Cold contrast to the warm hearth at the
	# center.
	var stone = Color(0.62, 0.68, 0.74)
	var rime = Color(0.78, 0.88, 0.95)
	var crack = Color(0.42, 0.48, 0.55)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var frost_dot = (x * 5 + y * 3) % 19 == 0
			var hairline = (x + y) % 17 == 0
			if hairline:
				image.set_pixel(x, y, crack)
			elif frost_dot:
				image.set_pixel(x, y, rime)
			else:
				image.set_pixel(x, y, stone)


func _draw_wall_tile(image: Image) -> void:
	# Pine-log walls with snow capping the upper edge — same logs
	# the village exteriors use, no fancy panelling. Trygg's place is
	# practical, not decorated.
	var log = Color(0.35, 0.22, 0.13)
	var log_dark = Color(0.22, 0.14, 0.08)
	var snow = Color(0.93, 0.96, 0.99)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var horiz_seam = y % 8 == 0
			var snow_cap = y < 5
			if snow_cap:
				image.set_pixel(x, y, snow)
			elif horiz_seam:
				image.set_pixel(x, y, log_dark)
			else:
				image.set_pixel(x, y, log if (x + y) % 9 != 0 else log_dark)


func _setup_decorations() -> void:
	super._setup_decorations()
	_draw_hearth()
	_draw_pelts()
	_draw_weapon_rack()


func _draw_hearth() -> void:
	# Two-tile hearth at the H positions — black stone base with an
	# orange-yellow flame on top. Warm bright spot the player walks
	# toward.
	var stone = ColorRect.new()
	stone.color = Color(0.20, 0.16, 0.14)
	stone.size = Vector2(TILE_SIZE * 2, TILE_SIZE * 2)
	stone.position = Vector2(5 * TILE_SIZE, 4 * TILE_SIZE)
	decorations.add_child(stone)
	var flame = ColorRect.new()
	flame.color = Color(0.98, 0.65, 0.20)
	flame.size = Vector2(TILE_SIZE + 4, 14)
	flame.position = Vector2(5 * TILE_SIZE + 14, 4 * TILE_SIZE + 8)
	decorations.add_child(flame)
	var flame_hot = ColorRect.new()
	flame_hot.color = Color(1.0, 0.92, 0.50)
	flame_hot.size = Vector2(TILE_SIZE - 6, 8)
	flame_hot.position = Vector2(5 * TILE_SIZE + 18, 4 * TILE_SIZE + 11)
	decorations.add_child(flame_hot)


func _draw_pelts() -> void:
	# Wolf and bear pelts at the P positions — Trygg is a hunter as
	# well as a warden.
	var fur_a = Color(0.55, 0.45, 0.32)
	var fur_b = Color(0.38, 0.30, 0.20)
	for i in range(4):
		var pelt = ColorRect.new()
		pelt.color = fur_a if i % 2 == 0 else fur_b
		pelt.size = Vector2(TILE_SIZE - 4, TILE_SIZE - 6)
		pelt.position = Vector2((3 + i) * TILE_SIZE + 2, 2 * TILE_SIZE + 3)
		decorations.add_child(pelt)


func _draw_weapon_rack() -> void:
	# A spear and an axe leaned against the wall in the back-left
	# corner — visual cue that Trygg has more than reading material.
	var rack = ColorRect.new()
	rack.color = Color(0.30, 0.20, 0.10)
	rack.size = Vector2(8, TILE_SIZE * 2)
	rack.position = Vector2(1 * TILE_SIZE + 8, 2 * TILE_SIZE + 4)
	decorations.add_child(rack)
	var spear = ColorRect.new()
	spear.color = Color(0.68, 0.66, 0.62)
	spear.size = Vector2(4, TILE_SIZE * 2 + 4)
	spear.position = Vector2(1 * TILE_SIZE + 16, 2 * TILE_SIZE)
	decorations.add_child(spear)
	var axe_head = ColorRect.new()
	axe_head.color = Color(0.45, 0.48, 0.52)
	axe_head.size = Vector2(12, 8)
	axe_head.position = Vector2(1 * TILE_SIZE + 22, 2 * TILE_SIZE + 6)
	decorations.add_child(axe_head)


func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	var trygg = OverworldNPCScript.new()
	trygg.npc_name = "Warden Trygg"
	trygg.npc_type = "guard"
	trygg.position = Vector2(7 * TILE_SIZE, 4 * TILE_SIZE)
	trygg.dialogue_lines = [
		"Warm-folk. You smell of pine. The Sovereign won't like that.",
		"There's something asleep in the deep ice. The old maps name her Glacius.",
		"She listens. Even sleeping. Always.",
		"If you go to her cave — don't shiver. Shivering invites her.",
		"And don't carry fire down there. She HATES fire.",
		"Survive that lesson and we'll talk again, warm-folk.",
	]
	npcs.add_child(trygg)


func _setup_transitions() -> void:
	super._setup_transitions()
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return
	var exit = AreaTransitionScript.new()
	exit.name = "Exit"
	exit.target_map = "frosthold_village"
	exit.target_spawn = "warden_hut_exit"
	exit.require_interaction = false
	exit.position = Vector2(5.5 * TILE_SIZE, 8.5 * TILE_SIZE)
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
