extends GutTest

## Regression (cowir-main's .601 boss frames): a monster's name label is a child of its sprite and grew with the
## sprite's scale. Mordaine's 128px sheet (x2.5 bump) put a ~25px name into the battle log panel; Pyrroth's 256px
## sheet left a ~7px one. Names now undo the sprite scale and read at NAME_LABEL_PX on screen for every monster.

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


func _screen_px(l: Label) -> float:
	return float(l.get_theme_font_size("font_size")) * l.get_global_transform().get_scale().y


func test_a_bumped_and_an_unbumped_monster_read_the_same_size() -> void:
	_scene = load("res://src/battle/BattleScene.tscn").instantiate()
	_scene.forced_enemies = ["goblin", "fire_dragon"]
	add_child(_scene)
	for i in 6:
		await get_tree().process_frame
	var sizes: Array[float] = []
	var scales: Array[float] = []
	for s in _scene.enemy_sprite_nodes:
		if not is_instance_valid(s):
			continue
		var l := s.get_node_or_null("NameLabel") as Label
		if l:
			sizes.append(_screen_px(l))
			scales.append(s.scale.y)
	assert_eq(sizes.size(), 2, "SCOPE: both monsters carry a name")
	if sizes.size() < 2:
		return
	assert_ne(snappedf(scales[0], 0.01), snappedf(scales[1], 0.01), "SCOPE: the two sprites really are drawn at different scales: %s" % [scales])
	assert_almost_eq(sizes[0], sizes[1], 0.5, "every monster's name reads the same size on screen: %s" % [sizes])
	assert_almost_eq(sizes[0], float(TextScale.scaled(_scene.NAME_LABEL_PX)), 0.5, "at NAME_LABEL_PX")
