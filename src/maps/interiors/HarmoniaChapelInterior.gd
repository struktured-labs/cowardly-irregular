extends BaseInterior
class_name HarmoniaChapelInterior

## HarmoniaChapelInterior - Small stone chapel in Harmonia Village.
## Sister Concord foreshadows the Mordaine fight: she remembers when
## the Chancellor used to come here, and she's worried what's changed.

const CHAPEL_LAYOUT = [
	"WWWWWWWWWWWWWW",
	"W............W",
	"W.PP......PP.W",
	"W............W",
	"W.....AA.....W",
	"W.....AA.....W",
	"W.PP......PP.W",
	"W............W",
	"W............W",
	"WWWWWWDDWWWWWW",
]


func _get_area_id() -> String:
	return "harmonia_chapel"


func _get_display_name() -> String:
	return "Chapel"


func _get_map_width() -> int:
	return 14


func _get_map_height() -> int:
	return 10


func _get_layout() -> Array:
	return CHAPEL_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(6, 8)
	spawn_points["altar"] = Vector2(6, 5)


func _setup_decorations() -> void:
	super._setup_decorations()
	_draw_altar()
	_draw_pews()


func _draw_altar() -> void:
	var altar = ColorRect.new()
	altar.color = Color(0.85, 0.78, 0.55)
	altar.size = Vector2(TILE_SIZE * 2, TILE_SIZE * 2)
	altar.position = Vector2(5 * TILE_SIZE, 4 * TILE_SIZE)
	decorations.add_child(altar)
	var altar_top = ColorRect.new()
	altar_top.color = Color(0.95, 0.88, 0.65)
	altar_top.size = Vector2(TILE_SIZE * 2, 6)
	altar_top.position = Vector2(5 * TILE_SIZE, 4 * TILE_SIZE)
	decorations.add_child(altar_top)


func _draw_pews() -> void:
	var pew_color = Color(0.34, 0.22, 0.14)
	for pew_pos in [Vector2(1, 2), Vector2(10, 2), Vector2(1, 6), Vector2(10, 6)]:
		var pew = ColorRect.new()
		pew.color = pew_color
		pew.size = Vector2(TILE_SIZE * 2, TILE_SIZE)
		pew.position = pew_pos * TILE_SIZE
		decorations.add_child(pew)


func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	var sister = OverworldNPCScript.new()
	sister.npc_name = "Sister Concord"
	sister.npc_type = "scholar"
	sister.position = Vector2(7 * TILE_SIZE, 4 * TILE_SIZE)
	sister.dialogue_lines = [
		"Welcome, traveler. Rest your soul a moment.",
		"This chapel used to be full on the holy days.",
		"The Chancellor would sit there, third pew from the back. Always alone.",
		"He hasn't been here in months. Not since the cave started... whispering.",
		"If you go to the castle, look him in the eye. Tell me what you see there.",
	]
	npcs.add_child(sister)


func _setup_transitions() -> void:
	super._setup_transitions()
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return
	var exit = AreaTransitionScript.new()
	exit.name = "Exit"
	exit.target_map = "harmonia_village"
	exit.target_spawn = "chapel_exit"
	exit.require_interaction = false
	exit.position = Vector2(7 * TILE_SIZE, 9.5 * TILE_SIZE)
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
