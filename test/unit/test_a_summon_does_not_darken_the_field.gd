extends GutTest

## struktured, playing .754: "a 2nd goblin appeared in a fight and the whole screen darkened".
## _present_summoned_enemy set the new sprite's scale to 0.01 for its pop-in BEFORE building its HP bar,
## and _create_enemy_hp_bar undoes the sprite's scale at creation, so the bar came out 100x too big. Its
## dark backing (0.2, 0.1, 0.1, 0.7) then covered half the screen for the rest of the fight. Reproduced
## in a real 11-round battle before the fix: frame brightness 87 -> 61 the round after the summon, the
## hint bar 54 -> 10.

const SCENE := preload("res://src/battle/BattleScene.tscn")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")

var _scene
var _bm_guard
var _saved_scale := 1.0
var _foe: Combatant


func before_each() -> void:
	AutobattleSystem._test_disable_persistence = true
	_bm_guard = BattleStateGuard.new()
	_bm_guard.snapshot()
	_saved_scale = Engine.time_scale
	_scene = SCENE.instantiate()
	add_child_autofree(_scene)
	Engine.time_scale = 1.0
	_foe = Combatant.new()
	_foe.initialize({"name": "Goblin C", "max_hp": 400, "max_mp": 0, "attack": 10, "defense": 5, "magic": 5, "speed": 10})
	add_child_autofree(_foe)
	_scene.test_enemies.assign([_foe] as Array[Combatant])
	BattleManager.enemy_party.assign([_foe] as Array[Combatant])


func after_each() -> void:
	Engine.time_scale = _saved_scale
	_bm_guard.restore()


func _until(cond: Callable, bound_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(bound_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


## The pop-in has settled: the sprite's scale has stopped changing for a few frames.
func _settled(sprite: Node2D) -> bool:
	var last := -1.0
	var still := 0
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if sprite.scale.x > 0.05 and absf(sprite.scale.x - last) < 0.0001:
			still += 1
			if still >= 3:
				return true
		else:
			still = 0
		last = sprite.scale.x
	return false


func _on_screen_size(c: Control) -> Vector2:
	return c.size * c.get_global_transform().get_scale().abs()


func test_a_summoned_enemys_hp_bar_is_bar_sized_once_it_has_popped_in() -> void:
	var before: int = _scene.enemy_sprite_nodes.size()
	_scene._on_monster_summoned("goblin", _foe)
	assert_eq(_scene.enemy_sprite_nodes.size(), before + 1, "CONTROL: the summon must add a sprite")
	if _scene.enemy_sprite_nodes.size() <= before:
		return
	var sprite: Node2D = _scene.enemy_sprite_nodes[-1]
	var summoned: Combatant = _scene.test_enemies[-1]
	assert_true(await _settled(sprite), "CONTROL: the pop-in must settle")
	var bars: Dictionary = _scene._enemy_hp_bars.get(summoned, {})
	assert_eq(bars.size(), 3, "CONTROL: the summoned enemy has its three bar rects")
	var vp: Vector2 = _scene.get_viewport_rect().size
	for key in bars:
		var r: Control = bars[key]
		var on_screen := _on_screen_size(r)
		assert_almost_eq(on_screen.x, _scene.ENEMY_HP_BAR_SIZE.x, 1.0,
			"%s must be the designed bar width on screen, not scaled by the pop-in (got %s)" % [key, str(on_screen)])
		assert_lt(on_screen.x * on_screen.y, vp.x * vp.y * 0.01, "%s must not cover the screen (%s)" % [key, str(on_screen)])


func test_the_summoned_name_is_label_sized_too() -> void:
	_scene._on_monster_summoned("goblin", _foe)
	var sprite: Node2D = _scene.enemy_sprite_nodes[-1]
	assert_true(await _settled(sprite), "CONTROL: the pop-in must settle")
	var label := sprite.get_node_or_null("NameLabel") as Control
	assert_not_null(label, "CONTROL: the summoned enemy carries a name label")
	if label == null:
		return
	var vp: Vector2 = _scene.get_viewport_rect().size
	var on_screen := _on_screen_size(label)
	assert_lt(on_screen.x, vp.x * 0.4, "the summoned enemy's name must be name-sized on screen (got %s)" % str(on_screen))
