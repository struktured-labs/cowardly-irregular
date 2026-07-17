extends BaseInterior
class_name BrasstonRedundancyArchiveInterior

## BrasstonRedundancyArchiveInterior - the Redundancy Archive (Brasston BBB
## building). W3 interior expansion, steampunk register: Brasston keeps a
## spare of everything — including a spare archive, a spare archivist, and,
## on Shelf 7, a spare of YOU. The memorable thing reads the player's REAL
## most-recent save timestamp: the spare was "last updated" when you last
## saved. If you've never saved, the archive is deeply uncomfortable.

const ROOM_LAYOUT = [
	"WWWWWWWWWWWWWW",
	"W.T........T.W",
	"W............W",
	"W..BB..BB....W",
	"W............W",
	"W..BB..BB....W",
	"W............W",
	"W............W",
	"WWWWWWDDWWWWWW",
]


func _get_area_id() -> String:
	return "brasston_redundancy_archive"


func _get_music_track() -> String:
	return "brasston_village"


func _get_display_name() -> String:
	return "The Redundancy Archive"


func _get_map_width() -> int:
	return 14


func _get_map_height() -> int:
	return 9


func _get_layout() -> Array:
	return ROOM_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(7, 7)
	spawn_points["shelves"] = Vector2(4, 4)


func _draw_floor_tile(image: Image) -> void:
	# Riveted brass plate, polished by identical daily rounds.
	var brass = Color(0.62, 0.50, 0.30)
	var rivet = Color(0.42, 0.34, 0.20)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var is_rivet = (x % 12 in [5, 6]) and (y % 12 in [5, 6])
			image.set_pixel(x, y, rivet if is_rivet else brass.darkened(0.06 if (x / 16 + y / 16) % 2 == 0 else 0.0))


func _draw_wall_tile(image: Image) -> void:
	# Card-catalog walls — thousands of tiny labeled drawers.
	var wood = Color(0.38, 0.26, 0.16)
	var drawer = Color(0.48, 0.34, 0.20)
	var pull = Color(0.72, 0.60, 0.36)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			if x % 8 < 1 or y % 6 < 1:
				image.set_pixel(x, y, wood)
			elif (x % 8 in [4]) and (y % 6 in [3]):
				image.set_pixel(x, y, pull)
			else:
				image.set_pixel(x, y, drawer)


func _setup_decorations() -> void:
	super._setup_decorations()
	for pos in [Vector2(3, 3), Vector2(7, 3), Vector2(3, 5), Vector2(7, 5)]:
		var shelf = ColorRect.new()
		shelf.color = Color(0.44, 0.32, 0.20)
		shelf.size = Vector2(TILE_SIZE * 2, TILE_SIZE * 0.8)
		shelf.position = pos * TILE_SIZE
		decorations.add_child(shelf)
		for i in range(4):
			var box = ColorRect.new()
			box.color = Color(0.58, 0.48, 0.34).darkened(0.05 * i)
			box.size = Vector2(12, 14)
			box.position = pos * TILE_SIZE + Vector2(4 + i * 15, 5)
			decorations.add_child(box)
	# Shelf 7 — the spare-of-you, brass-tagged and slightly apart
	var seven = ColorRect.new()
	seven.color = Color(0.70, 0.58, 0.34)
	seven.size = Vector2(TILE_SIZE * 1.2, TILE_SIZE * 0.5)
	seven.position = Vector2(10.6 * TILE_SIZE, 1.2 * TILE_SIZE)
	decorations.add_child(seven)


func _spare_status_line() -> String:
	var save_system: Node = null
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		save_system = tree.root.get_node_or_null("SaveSystem")
	if save_system == null or not save_system.has_method("get_most_recent_slot"):
		return "Shelf 7's label is blank. The archive declines to explain."
	var slot: int = save_system.get_most_recent_slot()
	if slot < 0:
		return "Shelf 7 is EMPTY. The archive is deeply uncomfortable about this. Save somewhere. Please."
	var info: Dictionary = save_system.get_save_info(slot)
	var save_time: float = float(info.get("save_time", 0.0))
	if save_time <= 0.0:
		return "Shelf 7 holds your spare. The timestamp is smudged."
	var mins: int = maxi(0, int((Time.get_unix_time_from_system() - save_time) / 60.0))
	if mins < 1:
		return "Shelf 7 holds your spare, updated moments ago. It is very fresh. Try not to need it."
	return "Shelf 7 holds your spare, last updated %d minute%s ago. The archive recommends more frequent maintenance." % [mins, "" if mins == 1 else "s"]


func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	var spare = OverworldNPCScript.new()
	spare.npc_name = "The Spare Archivist"
	spare.npc_type = "scholar"
	spare.position = Vector2(4 * TILE_SIZE, 4.5 * TILE_SIZE)
	spare.dialogue_lines = [
		"Welcome to the Redundancy Archive. Everything in Brasston has a spare here. Including the archive. Including me.",
		"I'm the spare archivist. The primary is on break. He has been on break since before I was hired. I have drafted a spare of myself, in case.",
		"We keep a spare of the town charter, a spare of the mayor's signature, and a spare Tuesday, in case one is lost to weather.",
		"The rule is simple: nothing is real until it has a backup. You seem real enough. Check Shelf 7.",
	]
	npcs.add_child(spare)

	# Shelf 7 — reads the REAL most-recent save.
	var shelf = OverworldNPCScript.new()
	shelf.npc_name = "Shelf 7"
	shelf.npc_type = "scholar"
	shelf.position = Vector2(11 * TILE_SIZE, 2 * TILE_SIZE)
	shelf.dialogue_lines = [
		"A brass-tagged shelf, set slightly apart from the others. The tag reads: ADVENTURER (SPARE).",
		_spare_status_line(),
		"Below, in smaller engraving: 'The spare is only as good as its last update. This is true of everyone.'",
	]
	npcs.add_child(shelf)


func _setup_transitions() -> void:
	super._setup_transitions()
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return
	var exit = AreaTransitionScript.new()
	exit.name = "Exit"
	exit.target_map = "brasston_village"
	exit.target_spawn = "archive_exit"
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
