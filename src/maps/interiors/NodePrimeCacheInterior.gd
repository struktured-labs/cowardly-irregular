extends BaseInterior
class_name NodePrimeCacheInterior

## NodePrimeCacheInterior - The Cache (Node Prime CCC building). W5 interior
## expansion, digital register: the room where the world keeps what it might
## need to render again. Two REAL reads: session uptime (this run of the
## game, via Time.get_ticks_msec — previous sessions are paged out) and the
## bestiary's seen-count as 'entities resident in memory'. Prefetch, the
## resident daemon, fetched your visit before you decided to make it.

const ROOM_LAYOUT = [
	"WWWWWWWWWWWWWW",
	"W.T..T..T..T.W",
	"W............W",
	"W..BB....BB..W",
	"W............W",
	"W............W",
	"W.....T......W",
	"W............W",
	"WWWWWWDDWWWWWW",
]


func _get_area_id() -> String:
	return "node_prime_cache"


func _get_display_name() -> String:
	return "The Cache"


func _get_map_width() -> int:
	return 14


func _get_map_height() -> int:
	return 9


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(7, 7)
	spawn_points["racks"] = Vector2(4, 4)


func _get_layout() -> Array:
	return ROOM_LAYOUT


func _draw_floor_tile(image: Image) -> void:
	# Near-black raised flooring with a faint address grid.
	var floor_c = Color(0.08, 0.10, 0.09)
	var grid = Color(0.12, 0.22, 0.16)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			if x % 16 == 0 or y % 16 == 0:
				image.set_pixel(x, y, grid)
			else:
				image.set_pixel(x, y, floor_c)


func _draw_wall_tile(image: Image) -> void:
	# Server-rack walls: dark panels, blinking-diode rows (frozen mid-blink).
	var rack = Color(0.10, 0.12, 0.12)
	var diode_on = Color(0.20, 0.85, 0.45)
	var diode_off = Color(0.10, 0.30, 0.20)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var is_diode = (y % 8 == 3) and (x % 5 == 2)
			if is_diode:
				image.set_pixel(x, y, diode_on if (x * 7 + y * 13) % 3 == 0 else diode_off)
			else:
				image.set_pixel(x, y, rack.darkened(0.1 if x % 12 < 2 else 0.0))


func _setup_decorations() -> void:
	super._setup_decorations()
	for pos in [Vector2(3, 3), Vector2(9, 3)]:
		var rack = ColorRect.new()
		rack.color = Color(0.14, 0.16, 0.16)
		rack.size = Vector2(TILE_SIZE * 2, TILE_SIZE * 0.9)
		rack.position = pos * TILE_SIZE
		decorations.add_child(rack)
		for i in range(5):
			var light = ColorRect.new()
			light.color = Color(0.20, 0.85, 0.45, 0.8) if i % 2 == 0 else Color(0.85, 0.60, 0.20, 0.8)
			light.size = Vector2(4, 4)
			light.position = pos * TILE_SIZE + Vector2(6 + i * 11, 6)
			decorations.add_child(light)


func _session_uptime_text() -> String:
	var secs := int(Time.get_ticks_msec() / 1000.0)
	return "%dh %02dm %02ds" % [secs / 3600, (secs % 3600) / 60, secs % 60]


func _entities_resident() -> int:
	return BestiarySystem.get_seen_ids().size()


func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	var prefetch = OverworldNPCScript.new()
	prefetch.npc_name = "Prefetch"
	prefetch.npc_type = "scholar"
	prefetch.position = Vector2(4 * TILE_SIZE, 4.5 * TILE_SIZE)
	prefetch.dialogue_lines = [
		"Welcome to the Cache. I fetched your visit last Tuesday. You were always going to come. It's cheaper to know that early.",
		"Everything here is something the world might need to render again. The bench outside. The smell of rain. Your next mistake.",
		"We evict the least-recently-loved. It sounds cruel. It IS cruel. It's also why anything loads at all.",
		"Don't touch the warm racks. Those are memories somebody's still using.",
	]
	npcs.add_child(prefetch)

	# The Cache Register — REAL reads: session uptime + bestiary residency.
	var register = OverworldNPCScript.new()
	register.npc_name = "The Cache Register"
	register.npc_type = "scholar"
	register.position = Vector2(9.5 * TILE_SIZE, 2.6 * TILE_SIZE)
	register.dialogue_lines = [
		"A terminal displays the cache's vital signs, refreshing exactly when you look at it.",
		"SESSION UPTIME: %s. Previous sessions: paged out. They happened. Probably." % _session_uptime_text(),
		"ENTITIES RESIDENT: %d species cached from your encounters. The rest of the bestiary is cold storage — it loads when you meet it." % _entities_resident(),
		"Footer: 'A cache miss is just the world admitting it didn't see you coming.'",
	]
	npcs.add_child(register)


func _setup_transitions() -> void:
	super._setup_transitions()
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return
	var exit = AreaTransitionScript.new()
	exit.name = "Exit"
	exit.target_map = "node_prime_village"
	exit.target_spawn = "cache_exit"
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
