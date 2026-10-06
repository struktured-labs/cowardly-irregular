extends GutTest

## Regression (cowir-main's .602 boss frames): the enemy HP bar is a child of its sprite and grew with the sprite's
## scale -- ~100px under Mordaine (x2.5 bump), a sliver under Pyrroth. Like the name above it (.602), every bar now
## undoes the sprite scale and is ENEMY_HP_BAR_SIZE on screen.

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


func test_a_bumped_and_an_unbumped_monster_have_the_same_bar() -> void:
	_scene = load("res://src/battle/BattleScene.tscn").instantiate()
	_scene.forced_enemies = ["goblin", "fire_dragon"]
	add_child(_scene)
	for i in 6:
		await get_tree().process_frame
	var widths: Array[float] = []
	var scales: Array[float] = []
	for enemy in _scene._enemy_hp_bars:
		var bg: ColorRect = _scene._enemy_hp_bars[enemy].get("bar_bg")
		if bg and is_instance_valid(bg):
			widths.append(bg.size.x * bg.get_global_transform().get_scale().x)
			scales.append(bg.get_parent().scale.x)
	assert_eq(widths.size(), 2, "SCOPE: both monsters carry an HP bar")
	if widths.size() < 2:
		return
	assert_ne(snappedf(scales[0], 0.01), snappedf(scales[1], 0.01), "SCOPE: the two sprites really are drawn at different scales: %s" % [scales])
	assert_almost_eq(widths[0], widths[1], 0.5, "every monster's HP bar is the same width on screen: %s" % [widths])
	assert_almost_eq(widths[0], _scene.ENEMY_HP_BAR_SIZE.x, 0.5, "at ENEMY_HP_BAR_SIZE")
