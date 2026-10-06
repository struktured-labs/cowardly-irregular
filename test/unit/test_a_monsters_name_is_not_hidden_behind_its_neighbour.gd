extends GutTest

## Regression (cowir-main's .590 battle frame, two goblins): Goblin A's name label read "GOBLI" -- it is a child of its
## own sprite, so Goblin B, drawn later at the same z, covered it. Name labels now sit above every monster sprite and
## below the damage popups.

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


func _effective_z(n: CanvasItem) -> int:
	var z := n.z_index
	var p := n.get_parent()
	while n.z_as_relative and p is CanvasItem:
		z += (p as CanvasItem).z_index
		n = p
		p = n.get_parent()
	return z


func test_every_name_label_draws_over_every_monster() -> void:
	_scene = load("res://src/battle/BattleScene.tscn").instantiate()
	_scene.forced_enemies = ["goblin", "goblin"]
	add_child(_scene)
	for i in 6:
		await get_tree().process_frame
	var sprites: Array = _scene.enemy_sprite_nodes.filter(func(s): return is_instance_valid(s))
	assert_gte(sprites.size(), 2, "SCOPE: two goblins spawned")
	var labels: Array = []
	for s in sprites:
		var l = s.get_node_or_null("NameLabel")
		if l:
			labels.append(l)
	assert_eq(labels.size(), sprites.size(), "SCOPE: each goblin has a name label")
	for l in labels:
		for s in sprites:
			assert_gt(_effective_z(l), _effective_z(s), "%s's name must draw over %s" % [l.text, s.name])


func test_names_stay_under_the_damage_popups() -> void:
	assert_lt(load("res://src/battle/BattleScene.gd").NAME_LABEL_Z, 100, "CONTROL: a name never covers a damage number (popups sit at 100+)")
