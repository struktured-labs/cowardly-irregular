extends BaseInterior
class_name MapleGarageSaleInterior

## MapleGarageSaleInterior - the Perpetual Garage Sale (Maple Heights HHH
## building). W2 interior expansion in the suburban register: a garage sale
## that has been running since before anyone can remember and sells nothing.
## The memorable thing is THE APPRAISER — she prices things in sentimental
## units and appraises the party's REAL inventory count on the spot. One box
## is marked FREE (haunted). Nobody has taken it.

const ROOM_LAYOUT = [
	"WWWWWWWWWWWWWW",
	"W.T.T....T.T.W",
	"W............W",
	"W..BB...BB...W",
	"W............W",
	"W...T........W",
	"W.........T..W",
	"W............W",
	"WWWWWWDDWWWWWW",
]


func _get_area_id() -> String:
	return "maple_garage_sale"


func _get_music_track() -> String:
	return "maple_heights_village"


func _get_display_name() -> String:
	return "The Perpetual Garage Sale"


func _get_map_width() -> int:
	return 14


func _get_map_height() -> int:
	return 9


func _get_layout() -> Array:
	return ROOM_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(7, 7)
	spawn_points["tables"] = Vector2(4, 4)


func _draw_floor_tile(image: Image) -> void:
	# Sealed garage concrete with one long oil stain that never came out.
	var concrete = Color(0.62, 0.60, 0.58)
	var stain = Color(0.45, 0.42, 0.40)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var in_stain = absi(x - 20) + absi((y - 24) * 2) < 10
			var crack = (x * 3 + y * 7) % 41 == 0
			if in_stain or crack:
				image.set_pixel(x, y, stain)
			else:
				image.set_pixel(x, y, concrete)


func _draw_wall_tile(image: Image) -> void:
	# Garage drywall with pegboard rows — hooks for tools long since sold. Or never sold. Unclear.
	var drywall = Color(0.82, 0.80, 0.74)
	var peg = Color(0.55, 0.52, 0.46)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var is_peg = (x % 8 in [3, 4]) and (y % 8 in [3, 4]) and y < 20
			image.set_pixel(x, y, peg if is_peg else drywall)


func _setup_decorations() -> void:
	super._setup_decorations()
	_draw_sale_tables()
	_draw_haunted_box()


func _draw_sale_tables() -> void:
	for pos in [Vector2(3, 3), Vector2(8, 3)]:
		var table = ColorRect.new()
		table.color = Color(0.72, 0.58, 0.40)
		table.size = Vector2(TILE_SIZE * 2, TILE_SIZE * 0.9)
		table.position = pos * TILE_SIZE
		decorations.add_child(table)
		for i in range(3):
			var knick = ColorRect.new()
			knick.color = [Color(0.8, 0.4, 0.4), Color(0.4, 0.6, 0.8), Color(0.7, 0.7, 0.3)][i]
			knick.size = Vector2(8, 8)
			knick.position = pos * TILE_SIZE + Vector2(6 + i * 16, 4)
			decorations.add_child(knick)


func _draw_haunted_box() -> void:
	var box = ColorRect.new()
	box.color = Color(0.55, 0.44, 0.30)
	box.size = Vector2(TILE_SIZE * 0.9, TILE_SIZE * 0.7)
	box.position = Vector2(11 * TILE_SIZE, 5.4 * TILE_SIZE)
	decorations.add_child(box)
	var label = ColorRect.new()
	label.color = Color(0.95, 0.92, 0.80)
	label.size = Vector2(TILE_SIZE * 0.7, 8)
	label.position = Vector2(11.1 * TILE_SIZE, 5.5 * TILE_SIZE)
	decorations.add_child(label)


func _party_item_count() -> int:
	var total := 0
	var gl = get_tree().root.get_node_or_null("GameLoop")
	if gl and "party" in gl:
		for m in gl.party:
			if m and is_instance_valid(m) and "inventory" in m:
				for iid in m.inventory:
					total += int(m.inventory[iid])
	return total


func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	var doreen = OverworldNPCScript.new()
	doreen.npc_name = "Doreen"
	doreen.npc_type = "villager"
	doreen.position = Vector2(4 * TILE_SIZE, 4.5 * TILE_SIZE)
	doreen.dialogue_lines = [
		"Everything's for sale, hon. Nothing has ever sold. We find that keeps the inventory stable.",
		"The sale started before my time. My mother ran it. HER mother ran it. Somebody has to.",
		"Prices are in sentiment. The gravy boat is 'one good cry'. The lamp is 'admitting your father was right about something'.",
		"The box in the corner is free. It's haunted. Those facts are related.",
	]
	npcs.add_child(doreen)

	# The Appraiser — reads the party's REAL inventory count each entry.
	var count := _party_item_count()
	var appraisal: String = "You carry nothing. The sale respects that more than it can say." if count == 0 \
		else "You are carrying %d item%s. Sentimental value: one rainy afternoon, properly spent. The sale is impressed and a little worried." % [count, "" if count == 1 else "s"]
	var appraiser = OverworldNPCScript.new()
	appraiser.npc_name = "The Appraiser"
	appraiser.npc_type = "villager"
	appraiser.position = Vector2(9 * TILE_SIZE, 4.5 * TILE_SIZE)
	appraiser.dialogue_lines = [
		"A woman with a pricing gun and unsettling accuracy looks you over.",
		appraisal,
		"She tags nothing. 'Adventurers,' she says, 'are the only thing here that appreciates.'",
	]
	npcs.add_child(appraiser)


func _setup_transitions() -> void:
	super._setup_transitions()
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return
	var exit = AreaTransitionScript.new()
	exit.name = "Exit"
	exit.target_map = "maple_heights_village"
	exit.target_spawn = "garage_sale_exit"
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
