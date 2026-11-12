extends GutTest

## ThreatMeter walked the spawner's own children, and roamers have lived under a sibling node since the spawner was
## written, so the bar never filled. It reads the spawner's live roamers now, from where the player is DRAWN in Mode 7.

const SpawnerScript := preload("res://src/exploration/MonsterSpawner.gd")
const RoamerScript := preload("res://src/exploration/RoamingMonster.gd")
const ThreatScript := preload("res://src/exploration/ThreatMeter.gd")

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


func test_the_spawner_lists_its_live_roamers() -> void:
	var sp := _spawner(Vector2(1600, 1120))
	assert_true(sp.has_method("live_monsters"), "MonsterSpawner.live_monsters must exist, or the meter falls back to the empty child walk")
	assert_eq(sp.live_monsters().size(), 0, "CONTROL: none yet")
	_roamer_under(sp, Vector2(1700, 1120))
	assert_eq(sp.live_monsters().size(), 1, "a roamer under the sibling node is listed")


func test_the_threat_meter_sees_a_roamer_near_the_drawn_player() -> void:
	Mode7Overlay.is_active = true
	var sp := _spawner(Vector2(1600, 1120))
	var meter: Node = ThreatScript.new()
	sp.get_parent().add_child(meter)
	meter.setup(sp.get_parent(), sp._player, sp)
	meter.update(sp._player.global_position)
	assert_eq(float(meter._bar_fill.size.x), 0.0, "CONTROL: with no roamer the bar is empty")
	_roamer_under(sp, _drawn(sp) + Vector2(60, 0))
	meter.update(sp._player.global_position)
	assert_gt(float(meter._bar_fill.size.x), 0.0, "a roamer 60 px from the drawn player must fill the threat bar")


func test_the_threat_meter_ignores_a_roamer_on_the_true_point_in_mode7() -> void:
	Mode7Overlay.is_active = true
	var sp := _spawner(Vector2(1600, 1120))
	var meter: Node = ThreatScript.new()
	sp.get_parent().add_child(meter)
	meter.setup(sp.get_parent(), sp._player, sp)
	var m := _roamer_under(sp, sp._player.global_position + Vector2(0, 200))
	meter.update(sp._player.global_position)
	assert_eq(float(meter._bar_fill.size.x), 0.0, "a roamer 200 px south of the true point is 340 px from the drawn player, past DETECTION_RANGE")
	m.global_position = _drawn(sp) + Vector2(0, 200)
	meter.update(sp._player.global_position)
	assert_gt(float(meter._bar_fill.size.x), 0.0, "CONTROL: the same roamer 200 px from the drawn player is in range")
