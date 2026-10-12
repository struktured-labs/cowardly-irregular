extends GutTest

## Sibling of the name-label defect, found by auditing every node parented to an enemy sprite:
## `_create_enemy_hp_bar` adds THREE ColorRects as children, and `_on_enemy_died` frees the status
## icon container and removes the buff visuals but never touches `_enemy_hp_bars`. The death visual
## is a shader pixel-dissolve, which draws the sprite's own texture only — so the red fill, at
## whatever width it held when the killing blow landed, hung over empty floor for the whole 0.5s.
## The registry leaked too: the dict is never erased and never cleared, so `_update_enemy_hp_bars`
## kept resizing a corpse's bar and the dict retained every dead Combatant of the session.

const SCENE := "res://src/battle/BattleScene.tscn"
const BattleState := preload("res://test/unit/helpers/battle_state.gd")
const FRAME := 64

var _guard: RefCounted = null


func before_each() -> void:
	_guard = BattleState.new()
	_guard.snapshot()


func after_each() -> void:
	if _guard != null:
		_guard.restore()


func _scene() -> Node:
	var s = load(SCENE).instantiate()
	add_child_autofree(s)
	return s


func _sprite() -> AnimatedSprite2D:
	var img := Image.create(FRAME, FRAME, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	var frames := SpriteFrames.new()
	frames.add_animation(&"idle")
	frames.add_frame(&"idle", ImageTexture.create_from_image(img))
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames
	s.animation = &"idle"
	add_child_autofree(s)
	return s


func _foe(nm: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": nm, "max_hp": 10, "max_mp": 0,
		"attack": 1, "defense": 1, "magic": 1, "speed": 1})
	add_child_autofree(c)
	return c


## Stands the real death handler up on one enemy. `dissolving` picks the shader path over the
## modulate fallback — children inherit modulate, so only the shader path can orphan a bar.
func _kill_one(scene: Node, spr: AnimatedSprite2D, foe: Combatant, dissolving: bool) -> void:
	if dissolving:
		spr.material = ShaderMaterial.new()
		spr.material.shader = BattleJuice.FLASH_SHADER
	scene.test_enemies.assign([foe] as Array[Combatant])
	scene.enemy_sprite_nodes.assign([spr])
	var animator = load("res://src/battle/BattleAnimator.gd").new()
	animator.setup(spr)
	scene.add_child(animator)
	scene.enemy_animators.assign([animator])
	scene._on_enemy_died(0)


func _bars_of(scene: Node, foe: Combatant) -> Array:
	if not scene._enemy_hp_bars.has(foe):
		return []
	var rec: Dictionary = scene._enemy_hp_bars[foe]
	var out: Array = []
	for key in ["bar_bg", "bar_trail", "bar_fill"]:
		out.append(rec.get(key))
	return out


## CONTROL: the three rects really are sprite children carrying real width, so a shader on the
## sprite cannot reach them and what hangs over the floor is a drawn bar, not an empty socket.
func test_control_the_bar_is_a_child_the_dissolve_cannot_reach() -> void:
	var scene := _scene()
	var spr := _sprite()
	var foe := _foe("Goblin A")
	scene._add_sprite_label(spr, "GOBLIN A", 40.0)
	scene._create_enemy_hp_bar(foe, spr)
	var bars := _bars_of(scene, foe)
	assert_eq(bars.size(), 3, "the bar is three nodes; a fix must account for all of them")
	for node in bars:
		assert_true(node is CanvasItem and is_instance_valid(node), "each piece must exist")
		if node is CanvasItem:
			assert_eq(node.get_parent(), spr,
				"the piece draws itself as a CHILD of the sprite, which is why the shader misses it")
			assert_gt(node.size.x, 0.0, "and it has width to be seen with")


## The defect, driven through the REAL handler rather than the new helper: on main the helper does
## not exist, and a missing method aborts its arm AFTER a passing assert, scoring the file GREEN
## (CLAUDE.md's rung-3 trap). `_on_enemy_died` is the path a player's killing blow takes.
func test_a_dissolving_monster_takes_its_hp_bar_with_it() -> void:
	var scene := _scene()
	var spr := _sprite()
	var foe := _foe("Goblin A")
	scene._add_sprite_label(spr, "GOBLIN A", 40.0)
	scene._create_enemy_hp_bar(foe, spr)
	var bars := _bars_of(scene, foe)
	assert_eq(bars.size(), 3, "CONTROL: the sprite must carry a bar to lose")
	if bars.size() != 3:
		return
	_kill_one(scene, spr, foe, true)
	assert_true(bool(spr.get_meta("dying", false)),
		"CONTROL: the death path must have run, or the measurement below is of an untouched sprite")
	await wait_seconds(0.9)
	for node in bars:
		if not is_instance_valid(node):
			continue
		assert_lt(node.modulate.a, 0.05,
			"a defeated monster's HP bar must leave with it; the dissolve shader cannot touch a child ColorRect (alpha %.2f)" % node.modulate.a)


## The registry is what `_update_enemy_hp_bars` walks every frame, so a corpse left in it is both a
## bar still being resized and a dead Combatant the scene holds for the rest of the session.
func test_the_bar_registry_does_not_keep_a_defeated_enemy() -> void:
	var scene := _scene()
	var spr := _sprite()
	var foe := _foe("Goblin B")
	scene._create_enemy_hp_bar(foe, spr)
	assert_true(scene._enemy_hp_bars.has(foe), "CONTROL: the enemy must be registered to be dropped")
	_kill_one(scene, spr, foe, true)
	assert_false(scene._enemy_hp_bars.has(foe),
		"the defeated enemy must leave the bar registry, or its bar is still being updated")
	scene._update_enemy_hp_bars()
	assert_false(scene._enemy_hp_bars.has(foe), "and a later refresh must not put it back")


## The modulate fallback hides the bar for free (children inherit modulate) but leaks the registry
## entry exactly the same way, so the retire has to run on BOTH death paths.
func test_the_fallback_path_also_retires_the_bar() -> void:
	var scene := _scene()
	var spr := _sprite()
	var foe := _foe("Goblin C")
	scene._create_enemy_hp_bar(foe, spr)
	assert_true(scene._enemy_hp_bars.has(foe), "CONTROL: registered before the kill")
	_kill_one(scene, spr, foe, false)
	assert_false(bool(spr.material is ShaderMaterial),
		"CONTROL: this arm must take the modulate path, else it is a copy of the dissolve arm")
	assert_false(scene._enemy_hp_bars.has(foe),
		"the registry entry must go whether the death dissolved or flickered")
