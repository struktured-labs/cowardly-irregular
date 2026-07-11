extends BaseInterior
class_name HarmoniaCartographerInterior

## HarmoniaCartographerInterior - the Cartographer's Attic (Harmonia, top-right
## PPP building). Village-interior expansion directive: one memorable thing per
## room. Here it's THE LIVING MAP — a wall map whose YOU ARE HERE marker is
## always correct, including about itself, and which reports the player's
## actual attuned-crystal count when examined (meta-aware flavor, composed
## fresh on every entry). Wendel Inkhand, the cartographer, has opinions
## about mapping a world that keeps being edited.

const ROOM_LAYOUT = [
	"WWWWWWWWWWWWWW",
	"W....T.......W",
	"W............W",
	"W..BB........W",
	"W............W",
	"W.......TT...W",
	"W............W",
	"W............W",
	"WWWWWWDDWWWWWW",
]


func _get_area_id() -> String:
	return "harmonia_cartographer"


func _get_display_name() -> String:
	return "Cartographer's Attic"


func _get_map_width() -> int:
	return 14


func _get_map_height() -> int:
	return 9


func _get_layout() -> Array:
	return ROOM_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(7, 7)
	spawn_points["desk"] = Vector2(4, 4)


func _get_music_track() -> String:
	return "harmonia_village"


func _draw_floor_tile(image: Image) -> void:
	# Attic floorboards — warm planks, visible nail seams every board.
	var plank = Color(0.52, 0.38, 0.22)
	var seam = Color(0.40, 0.28, 0.15)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			if y % 8 == 0 or (x % 16 == 0 and y % 8 < 2):
				image.set_pixel(x, y, seam)
			else:
				image.set_pixel(x, y, plank)


func _draw_wall_tile(image: Image) -> void:
	# Timber-framed plaster — medieval attic, parchment-toned.
	var plaster = Color(0.82, 0.76, 0.62)
	var timber = Color(0.35, 0.24, 0.13)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			if x % 16 < 3 or y < 3:
				image.set_pixel(x, y, timber)
			else:
				image.set_pixel(x, y, plaster)


func _setup_decorations() -> void:
	super._setup_decorations()
	_draw_wall_map()
	_draw_scroll_piles()


func _draw_wall_map() -> void:
	# The Living Map: a parchment sheet on the north wall with a red
	# YOU ARE HERE pin that is, of course, exactly here.
	var parchment = ColorRect.new()
	parchment.color = Color(0.90, 0.84, 0.66)
	parchment.size = Vector2(TILE_SIZE * 4, TILE_SIZE * 1.6)
	parchment.position = Vector2(8 * TILE_SIZE, 0.2 * TILE_SIZE)
	decorations.add_child(parchment)
	var coast = ColorRect.new()
	coast.color = Color(0.45, 0.58, 0.38)
	coast.size = Vector2(TILE_SIZE * 2.6, TILE_SIZE * 1.0)
	coast.position = Vector2(8.6 * TILE_SIZE, 0.5 * TILE_SIZE)
	decorations.add_child(coast)
	var pin = ColorRect.new()
	pin.color = Color(0.85, 0.15, 0.15)
	pin.size = Vector2(6, 6)
	pin.position = Vector2(10.6 * TILE_SIZE, 0.8 * TILE_SIZE)
	decorations.add_child(pin)


func _draw_scroll_piles() -> void:
	# Rolled map scrolls stacked beside the desk — rejected drafts.
	for i in range(3):
		var scroll = ColorRect.new()
		scroll.color = Color(0.86, 0.80, 0.62).darkened(i * 0.06)
		scroll.size = Vector2(TILE_SIZE * 1.2, 8)
		scroll.position = Vector2(2 * TILE_SIZE, (5.2 + i * 0.35) * TILE_SIZE)
		decorations.add_child(scroll)


func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	var wendel = OverworldNPCScript.new()
	wendel.npc_name = "Wendel Inkhand"
	wendel.npc_type = "scholar"
	wendel.position = Vector2(4 * TILE_SIZE, 3 * TILE_SIZE)
	wendel.dialogue_lines = [
		"Cartography used to be honest work. You draw the mountain. The mountain stays drawn.",
		"Now? I inked the Whispering Cave twice and it grew a floor between drafts.",
		"The castle appeared on my map before anyone had SEEN it. I don't draw fast. Something draws first.",
		"My master said a good map is a promise. This world keeps renegotiating.",
		"Take the roads slowly. They're the only lines that have never moved on me.",
	]
	npcs.add_child(wendel)

	# The Living Map — the room's memorable thing. Composed fresh each
	# entry so the meta joke is literally true.
	var attuned: int = 0
	if GameState and "activated_crystals" in GameState:
		attuned = GameState.activated_crystals.size()
	var crystal_line: String = "No crystals attuned yet. The map is patient." if attuned == 0 \
		else "%d crystal%s attuned. The map marked them before you touched them." % [attuned, "" if attuned == 1 else "s"]
	var map_obj = OverworldNPCScript.new()
	map_obj.npc_name = "The Living Map"
	map_obj.npc_type = "scholar"
	map_obj.position = Vector2(10 * TILE_SIZE, 1 * TILE_SIZE)
	map_obj.dialogue_lines = [
		"A hand-inked map of the realm. A red pin reads YOU ARE HERE.",
		"The pin is in the Cartographer's attic. You are in the Cartographer's attic. It is correct.",
		crystal_line,
		"In the bottom corner, in fresh ink: five more worlds, folded very small, as if embarrassed to be early.",
	]
	npcs.add_child(map_obj)


func _setup_transitions() -> void:
	super._setup_transitions()
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return
	var exit = AreaTransitionScript.new()
	exit.name = "Exit"
	exit.target_map = "harmonia_village"
	exit.target_spawn = "cartographer_exit"
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
