extends GutTest

## Follow-up to .792's Mode 7 contact fix: a roamer now touches the player where they are DRAWN, so the spawner's
## "never spawn within reach" and "cull when far" distances must be judged from that point too.

const SpawnerScript := preload("res://src/exploration/MonsterSpawner.gd")
const RoamerScript := preload("res://src/exploration/RoamingMonster.gd")

var _was_active := false


func before_each() -> void:
	_was_active = Mode7Overlay.is_active


func after_each() -> void:
	Mode7Overlay.is_active = _was_active


## A spawner on a bare host, its player at the middle of the default map; nothing spawns until asked.
func _spawner(player_at: Vector2) -> Node:
	var host := Node2D.new()
	add_child_autofree(host)
	var player := Node2D.new()
	host.add_child(player)
	player.global_position = player_at
	var sp: Node = SpawnerScript.new()
	host.add_child(sp)
	sp.set_process(false)
	sp._player = player
	return sp


func _roamer_under(sp: Node, at: Vector2) -> Node:
	var m: Node = RoamerScript.new()
	sp._spawn_parent.add_child(m)
	m.global_position = at
	m.set_process(false)
	sp._monsters.append(m)
	return m


func _drawn(sp: Node) -> Vector2:
	return sp._player.global_position + Vector2(0.0, -InteractGeometry.MODE7_GROUND_DISPLACEMENT_PX)


## The closest any of `n` spawn candidates came to `point`.
func _nearest_spawn(sp: Node, point: Vector2, n: int) -> float:
	var nearest := INF
	var found := 0
	for i in n:
		var c: Vector2 = sp._find_spawn_position()
		if c != Vector2.ZERO:
			found += 1
			nearest = minf(nearest, c.distance_to(point))
	assert_gt(found, n / 2, "CONTROL: the spawner found positions (%d of %d)" % [found, n])
	return nearest


func test_the_spawner_has_what_this_file_reaches() -> void:
	var sp := _spawner(Vector2(1600, 1120))
	for method in ["_find_spawn_position", "_cull_far_monsters", "_player_seen_pos"]:
		assert_true(sp.has_method(method), "MonsterSpawner.%s must exist, or the arms below judge nothing" % method)
	assert_not_null(sp._spawn_parent, "the spawner must build its roamer parent in _ready")


func test_in_mode7_nothing_spawns_within_reach_of_the_drawn_player() -> void:
	Mode7Overlay.is_active = true
	var sp := _spawner(Vector2(1600, 1120))
	var nearest := _nearest_spawn(sp, _drawn(sp), 400)
	assert_gt(nearest, float(sp.MIN_SPAWN_DIST_FROM_PLAYER), "a roamer spawned %.0f px from where the player is drawn; the floor is MIN_SPAWN_DIST_FROM_PLAYER" % nearest)


func test_on_a_flat_map_the_floor_is_measured_from_the_player() -> void:
	Mode7Overlay.is_active = false
	var sp := _spawner(Vector2(1600, 1120))
	var nearest := _nearest_spawn(sp, sp._player.global_position, 400)
	assert_gt(nearest, float(sp.MIN_SPAWN_DIST_FROM_PLAYER), "CONTROL: outside Mode 7 the floor holds around the player's own point")
	assert_lt(_nearest_spawn(sp, _drawn(sp), 400), float(sp.MIN_SPAWN_DIST_FROM_PLAYER), "CONTROL: and 400 draws do reach inside the floor around a point a displacement north, so the Mode 7 arm can fail")


func test_in_mode7_a_roamer_is_culled_by_its_distance_from_the_drawn_player() -> void:
	Mode7Overlay.is_active = true
	var sp := _spawner(Vector2(1600, 1120))
	var p: Vector2 = sp._player.global_position
	var south := _roamer_under(sp, p + Vector2(0, float(sp.DESPAWN_DISTANCE) - 60.0))
	var north := _roamer_under(sp, p + Vector2(0, -(float(sp.DESPAWN_DISTANCE) + 60.0)))
	sp._cull_far_monsters()
	assert_false(sp._monsters.has(south), "a roamer inside the cull range of the true point but outside it from the drawn player is culled")
	assert_true(sp._monsters.has(north), "one beyond the range from the true point but inside it from the drawn player is kept")
