extends GutTest

## struktured 2026-11-07 (main 23415): "the monster object detection in the Mode 7 overworld is still embarrassing".
## Mode 7 draws the player over ground InteractGeometry.MODE7_GROUND_DISPLACEMENT_PX north of their true point; the roamer's touch circle and its chase aimed at the true point.

const RM := "res://src/exploration/RoamingMonster.gd"

var _was_active := false


class FakePlayer:
	extends Node2D
	func set_can_move(_v: bool) -> void:
		pass


func before_each() -> void:
	_was_active = Mode7Overlay.is_active


func after_each() -> void:
	Mode7Overlay.is_active = _was_active


func _roamer_at(pos: Vector2, player: Node2D) -> Node:
	var host := Node2D.new()
	add_child_autofree(host)
	var m: Node = load(RM).new()
	host.add_child(m)
	m.global_position = pos
	m.set_player_ref(player)
	m._align_touch_to_the_drawn_player()
	return m


func _player_at(pos: Vector2) -> Node2D:
	var p := FakePlayer.new()
	add_child_autofree(p)
	p.global_position = pos
	return p


## Distance from the roamer's touch circle centre to the player's true body.
func _touch_gap(m: Node, player: Node2D) -> float:
	return (m.global_position + m._collision.position).distance_to(player.global_position)


func _drawn_ground(player: Node2D) -> Vector2:
	return player.global_position + Vector2(0.0, -InteractGeometry.MODE7_GROUND_DISPLACEMENT_PX)


func test_the_roamer_has_what_this_file_reaches() -> void:
	var m := _roamer_at(Vector2.ZERO, _player_at(Vector2.ZERO))
	for method in ["_align_touch_to_the_drawn_player", "_player_seen_pos", "set_player_ref"]:
		assert_true(m.has_method(method), "RoamingMonster.%s must exist, or every arm below judges nothing" % method)
	assert_not_null(m._collision, "the roamer must build its touch shape in _ready")


func test_in_mode7_a_monster_drawn_at_the_players_feet_touches_them() -> void:
	Mode7Overlay.is_active = true
	var player := _player_at(Vector2(2000, 2000))
	var m := _roamer_at(_drawn_ground(player), player)
	assert_lt(_touch_gap(m, player), 1.0, "a monster on the ground drawn under the player must have its touch circle on the player's body")


func test_in_mode7_a_monster_drawn_well_below_the_player_does_not_touch_them() -> void:
	Mode7Overlay.is_active = true
	var player := _player_at(Vector2(2000, 2000))
	var m := _roamer_at(player.global_position, player)
	assert_gt(_touch_gap(m, player), float(m.TOUCH_RADIUS_PX), "a monster on the player's TRUE point is drawn a displacement below their feet and must not start a fight")


func test_on_a_flat_map_the_touch_circle_stays_on_the_monster() -> void:
	Mode7Overlay.is_active = false
	var player := _player_at(Vector2(2000, 2000))
	var m := _roamer_at(player.global_position, player)
	assert_lt(_touch_gap(m, player), 1.0, "CONTROL: outside Mode 7 a monster standing on the player touches them")
	var far := _roamer_at(_drawn_ground(player), player)
	assert_gt(_touch_gap(far, player), float(far.TOUCH_RADIUS_PX), "CONTROL: outside Mode 7 a monster a displacement north does not")


func test_the_touch_circle_moves_the_way_the_terrain_collider_does() -> void:
	var tile_map := TileMapLayer.new()
	var parent := Node2D.new()
	add_child_autofree(parent)
	parent.add_child(tile_map)
	var clone := Mode7Overlay.apply_terrain_collision_alignment(tile_map, true)
	assert_not_null(clone, "CONTROL: Mode 7 builds the shifted terrain collider")
	if clone == null:
		return
	var terrain_shift: float = clone.position.y - tile_map.position.y
	assert_ne(terrain_shift, 0.0, "CONTROL: the terrain collider is shifted")
	Mode7Overlay.is_active = true
	var player := _player_at(Vector2(2000, 2000))
	var m := _roamer_at(Vector2(2000, 1000), player)
	assert_almost_eq(float(m._collision.position.y), terrain_shift, 0.01, "a monster is a world pixel like the terrain, so its contact shifts by the same amount the same way")


func test_a_mode_change_moves_the_circle_on_the_next_tick() -> void:
	Mode7Overlay.is_active = false
	var player := _player_at(Vector2(2000, 2000))
	var m := _roamer_at(Vector2(2000, 1000), player)
	assert_eq(m._collision.position, Vector2.ZERO, "CONTROL: flat map, no offset")
	Mode7Overlay.is_active = true
	m._process(0.0)
	assert_ne(m._collision.position, Vector2.ZERO, "entering Mode 7 must move the touch circle without a respawn")


func test_in_mode7_a_monster_heads_for_where_the_player_is_drawn() -> void:
	var player := _player_at(Vector2(2000, 2000))
	var m := _roamer_at(Vector2(2000, 1000), player)
	Mode7Overlay.is_active = false
	assert_eq(m._player_seen_pos(), player.global_position, "CONTROL: on a flat map the monster aims at the player's own point")
	Mode7Overlay.is_active = true
	assert_eq(m._player_seen_pos(), _drawn_ground(player), "in Mode 7 it aims at the ground the player is drawn on")
