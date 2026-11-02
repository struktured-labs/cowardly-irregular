extends GutTest

## struktured, playing a .760 preview: "one attack, I think lightning based, shot towards an empty space, no enemy was
## at". Read from his logs, no retarget visual was at fault, but the mechanism is pinned here whichever cast it was: when
## a single-target cast's target died earlier in the same phase, the cast retargets, and the visuals (BattleScene draws
## every one of them from action_executing) must carry the NEW target, whose sprite is still found by its own index.

const SCENE := preload("res://src/battle/BattleScene.tscn")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")

var _bm: Node = null
var _guard
var _seen: Array = []


func before_each() -> void:
	AutobattleSystem._test_disable_persistence = true
	_bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	_seen.clear()
	if _bm:
		_bm.turbo_mode = true
		_bm.action_executing.connect(_on_executing)


func after_each() -> void:
	if _bm and _bm.action_executing.is_connected(_on_executing):
		_bm.action_executing.disconnect(_on_executing)
	_guard.restore()


func after_all() -> void:
	SoundState.restore()


func _on_executing(who, action: Dictionary) -> void:
	_seen.append([who, action.duplicate()])


func _make(cname: String) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = cname
	c.max_hp = 400
	c.current_hp = 400
	c.max_mp = 99
	c.current_mp = 99
	c.magic = 20
	c.is_alive = true
	add_child_autofree(c)
	return c


func test_a_cast_at_a_fallen_foe_shows_on_the_one_it_retargets_to() -> void:
	assert_not_null(_bm, "BattleManager autoload required")
	if _bm == null:
		return
	var mage := _make("Mage")
	var a := _make("Goblin A")
	var b := _make("Goblin B")
	_bm.player_party.clear()
	_bm.enemy_party.clear()
	_bm.player_party.append(mage)
	_bm.enemy_party.append(a)
	_bm.enemy_party.append(b)
	a.current_hp = 0
	a.is_alive = false
	_bm._execute_ability(mage, "fire", [a])
	var cast: Array = _seen.filter(func(e): return str(e[1].get("type", "")) == "ability")
	assert_eq(cast.size(), 1, "CONTROL: the cast reached its visuals")
	if cast.size() != 1:
		return
	var targets: Array = cast[0][1].get("targets", [])
	assert_eq(targets, [b], "the visual is told the living foe the damage went to, never the fallen one")


func test_a_fallen_foe_does_not_shift_the_living_ones_sprites() -> void:
	var scene = SCENE.instantiate()
	scene.encounter_enemies = ["goblin", "goblin", "goblin"]
	add_child_autofree(scene)
	for i in 3:
		await get_tree().process_frame
	var foes: Array = BattleManager.enemy_party.duplicate()
	assert_eq(foes.size(), 3, "CONTROL: three goblins")
	if foes.size() != 3:
		return
	var before: Vector2 = scene._stable_sprite_anchor(scene._get_combatant_sprite(foes[2]))
	foes[1].current_hp = 0
	foes[1].is_alive = false
	assert_eq(scene._get_combatant_sprite(foes[2]), scene.enemy_sprite_nodes[2], "the third goblin still finds its own sprite")
	assert_eq(scene._stable_sprite_anchor(scene._get_combatant_sprite(foes[2])), before,
		"and a cast at it aims where it stands, not at the fallen middle one's spot")
