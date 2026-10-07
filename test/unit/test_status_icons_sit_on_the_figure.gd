extends GutTest

## Regression (cowir-main's .603 status frames): the status badge row was a child of the sprite at a fixed (-30, -55),
## so on x2.5 monsters (goblin, Mordaine) the badges were ~22px and floated far up-left of the body, and on Pyrroth
## they were ~5px specks on his head. The row now undoes the sprite scale (x STATUS_ROW_ZOOM) and centres just
## above its own figure, the same way the name sits under the feet.

const BattleStateHelper := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")

var _bm: RefCounted = null
var _scene: Node = null


func before_each() -> void:
	_bm = BattleStateHelper.new()
	_bm.snapshot()


func after_each() -> void:
	if _scene and is_instance_valid(_scene):
		_scene.queue_free()
	_scene = null
	if _bm != null:
		_bm.restore()


func after_all() -> void:
	SoundState.restore()


func _rows() -> Array:
	var out: Array = []
	for c in _scene._status_icon_containers:
		var row = _scene._status_icon_containers[c]
		if is_instance_valid(row) and row.get_parent() in _scene.enemy_sprite_nodes:
			out.append(row)
	return out


func test_every_badge_row_reads_the_same_size_and_centres_on_its_monster() -> void:
	_scene = load("res://src/battle/BattleScene.tscn").instantiate()
	_scene.forced_enemies = ["goblin", "fire_dragon"]
	add_child(_scene)
	for i in 6:
		await get_tree().process_frame
	var rows := _rows()
	assert_eq(rows.size(), 2, "SCOPE: both monsters carry a status row")
	if rows.size() < 2:
		return
	var s0: float = rows[0].get_global_transform().get_scale().x
	var s1: float = rows[1].get_global_transform().get_scale().x
	assert_ne(snappedf(rows[0].get_parent().scale.x, 0.01), snappedf(rows[1].get_parent().scale.x, 0.01), "SCOPE: the sprites differ in scale")
	assert_almost_eq(s0, s1, 0.01, "every badge row reads the same size on screen")
	assert_almost_eq(s0, _scene.STATUS_ROW_ZOOM, 0.01, "at STATUS_ROW_ZOOM")
	for row in rows:
		var label: Label = row.get_parent().get_node_or_null("NameLabel")
		if label == null:
			continue
		var row_centre: float = row.get_global_rect().get_center().x
		var name_centre: float = label.get_global_rect().get_center().x
		assert_almost_eq(row_centre, name_centre, 2.0, "the badges centre over the same body as its name")
		assert_lt(row.get_global_rect().end.y, label.get_global_rect().position.y, "the badges sit above, the name below")
