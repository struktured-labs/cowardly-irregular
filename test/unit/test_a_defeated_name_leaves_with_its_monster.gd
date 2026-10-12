extends GutTest

## cowir-main, relaying struktured 2026-10-12: a defeated enemy's name label shows THROUGH the victory
## EXP cards. The death visual is a shader pixel-dissolve, and a shader draws the sprite's own texture
## only — the NameLabel is a child node with its own drawing, so it stayed fully opaque for the whole
## 0.5s dissolve: a name hanging over empty floor, and at NAME_LABEL_Z (5) over the victory cards
## (z 0) whenever that kill ended the battle. Only the modulate FALLBACK path was ever correct, because
## children inherit modulate.

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


func _label_of(sprite: Node) -> Label:
	return sprite.get_node_or_null("NameLabel") as Label


func test_the_victory_cards_outrank_nothing_on_the_floor() -> void:
	## CONTROL and the reason this is a player-visible bug rather than a cosmetic one: the label's
	## z_index beats the victory overlay's, so while it is visible it draws over the cards whatever
	## the tree order is. That is what makes "still opaque" show up ON the EXP cards.
	var scene := _scene()
	assert_gt(scene.NAME_LABEL_Z, 0,
		"the name label sits above the battlefield (%d); the victory overlay sits at 0" % scene.NAME_LABEL_Z)


## Through the REAL death handler, not the fade helper: on main the helper does not exist, and a call
## to a missing method aborts its arm AFTER the assert above, which scores the file GREEN (CLAUDE.md's
## rung-3 trap). _on_enemy_died is the path a player's killing blow takes.
func test_a_dissolving_monster_takes_its_name_with_it() -> void:
	var scene := _scene()
	var spr := _sprite()
	spr.material = ShaderMaterial.new()
	spr.material.shader = BattleJuice.FLASH_SHADER
	scene._add_sprite_label(spr, "GOBLIN A", 40.0)
	var label := _label_of(spr)
	assert_not_null(label, "CONTROL: the sprite must carry a name label to lose")
	if label == null:
		return
	var foe := Combatant.new()
	foe.initialize({"name": "Goblin A", "max_hp": 10, "max_mp": 0,
		"attack": 1, "defense": 1, "magic": 1, "speed": 1})
	add_child_autofree(foe)
	scene.test_enemies.assign([foe] as Array[Combatant])
	scene.enemy_sprite_nodes.assign([spr])
	var animator = load("res://src/battle/BattleAnimator.gd").new()
	animator.setup(spr)
	scene.add_child(animator)
	scene.enemy_animators.assign([animator])
	scene._on_enemy_died(0)
	assert_true(bool(spr.get_meta("dying", false)),
		"CONTROL: the death path must have run, or the fade below is measuring an untouched sprite")
	await wait_seconds(0.9)
	assert_lt(label.modulate.a, 0.05,
		"the name must fade with the figure it names; the dissolve shader cannot touch a child Label (alpha %.2f)" % label.modulate.a)
	var plate := spr.get_node_or_null("NamePlate") as Control
	assert_not_null(plate, "CONTROL: the name carries a plate, which is the other node the shader cannot reach")
	if plate != null:
		assert_lt(plate.modulate.a, 0.05,
			"the plate must leave with the name, or a dark box hangs over the empty floor (alpha %.2f)" % plate.modulate.a)


func test_the_round_reset_puts_a_name_back() -> void:
	## Symmetric half: the fade is on the label itself, so the canonical presentation restore owns
	## putting it back, exactly as it already does for the dissolve the shader left set.
	var scene := _scene()
	var spr := _sprite()
	spr.material = ShaderMaterial.new()
	scene._add_sprite_label(spr, "GOBLIN B", 40.0)
	var label := _label_of(spr)
	if label == null:
		fail_test("CONTROL: no label")
		return
	var plate := spr.get_node_or_null("NamePlate") as Control
	label.modulate.a = 0.0
	if plate != null:
		plate.modulate.a = 0.0
	scene._reset_presentation_state(spr)
	assert_eq(label.modulate.a, 1.0, "a round reset restores the name with the rest of the presentation")
	if plate != null:
		assert_eq(plate.modulate.a, 1.0, "and its plate with it")
