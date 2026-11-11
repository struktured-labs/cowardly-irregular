extends GutTest

## cowir-adhoc's animation audit batch 2 (23721), built on cowir-main 23722. A sprite's `modulate` had six
## writers and no owner: the status tint was set on status_added/removed, and the turn-step dim, the weakness
## flash, the cast settle and the UI refresh each returned it to white (the UI from a shorter status table),
## while a crit returned it to whatever colour it found. BattleScene.rest_modulate is now the one answer
## (status tint x dim, KO grey), and a recovery re-poses a member at once.

const SCENE := preload("res://src/battle/BattleScene.gd")
const ANIMATOR := preload("res://src/battle/BattleAnimator.gd")
const POISON := Color(0.7, 1.0, 0.7)
var _saved_scale := 1.0


func before_each() -> void:
	_saved_scale = Engine.time_scale


func after_each() -> void:
	Engine.time_scale = _saved_scale


func _frames() -> SpriteFrames:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	var frames := SpriteFrames.new()
	for anim in ["idle", "weak", "dead"]:
		if not frames.has_animation(anim):
			frames.add_animation(anim)
		frames.set_animation_loop(anim, anim != "dead")
		frames.set_animation_speed(anim, 30.0)
		frames.add_frame(anim, tex)
	return frames


## [scene, party member, its sprite, a monster, its sprite]
func _fixture() -> Array:
	var scene = SCENE.new()
	add_child_autofree(scene)
	var pc := Combatant.new()
	autofree(pc)
	pc.combatant_name = "Mira"
	var ps := AnimatedSprite2D.new()
	ps.sprite_frames = _frames()
	scene.add_child(ps)
	scene.party_members.append(pc)
	scene.party_sprite_nodes.append(ps)
	var foe := Combatant.new()
	autofree(foe)
	foe.combatant_name = "Bat"
	var es := AnimatedSprite2D.new()
	es.sprite_frames = _frames()
	scene.add_child(es)
	scene.test_enemies.append(foe)
	scene.enemy_sprite_nodes.append(es)
	return [scene, pc, ps, foe, es]


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01 and absf(a.a - b.a) < 0.01


func test_a_poisoned_member_keeps_the_tint_through_a_turn_step() -> void:
	var f := _fixture()
	var scene = f[0]; var pc: Combatant = f[1]; var ps: AnimatedSprite2D = f[2]
	assert_true(_near(scene.rest_modulate(ps), Color.WHITE), "CONTROL: a healthy member rests at white")
	pc.status_effects.append("poison")
	scene._apply_status_visual(ps, pc)
	assert_true(_near(ps.modulate, POISON), "CONTROL: the status tint must be applied (%s)" % ps.modulate)
	scene._dim_inactive_party(0, true)   # this member is the ACTIVE one: no dim
	await wait_seconds(0.4)
	assert_true(_near(ps.modulate, POISON), "the active member's poison tint was wiped by the turn step: %s" % ps.modulate)
	scene._dim_inactive_party(5, true)   # someone else is active: this member dims
	await wait_seconds(0.4)
	assert_true(_near(ps.modulate, POISON * SCENE.ACTIVE_PC_DIM_COLOR), "a dimmed poisoned member rests at %s, not tint x dim" % ps.modulate)
	scene._dim_inactive_party(5, false)
	await wait_seconds(0.4)
	assert_true(_near(ps.modulate, POISON), "the tint didn't come back when the dim lifted: %s" % ps.modulate)


func test_a_poisoned_monster_keeps_the_tint_through_a_weakness_flash() -> void:
	var f := _fixture()
	var scene = f[0]; var foe: Combatant = f[3]; var es: AnimatedSprite2D = f[4]
	foe.status_effects.append("poison")
	scene._apply_status_visual(es, foe)
	scene._apply_weakness_hit_visuals(es, "fire", 2.0)
	assert_false(_near(es.modulate, POISON), "CONTROL: the weakness flash must colour the sprite")
	await wait_seconds(0.6)
	assert_true(_near(es.modulate, POISON), "the weakness flash settled at %s and the poison tint is gone" % es.modulate)


func test_two_crits_together_settle_at_the_rest_colour() -> void:
	var f := _fixture()
	var scene = f[0]; var foe: Combatant = f[3]; var es: AnimatedSprite2D = f[4]
	for poisoned in [false, true]:
		foe.status_effects.clear()
		if poisoned:
			foe.status_effects.append("poison")
		scene._apply_status_visual(es, foe)
		scene._crit_flash(es)
		await wait_seconds(0.05)
		assert_gt(es.modulate.r, 1.5, "CONTROL: the first crit's flash must still be bright when the second lands")
		scene._crit_flash(es)
		await wait_seconds(0.5)
		var rest: Color = POISON if poisoned else Color.WHITE
		assert_true(_near(es.modulate, rest), "two crits 0.05 s apart left the target at %s, not its rest colour %s" % [es.modulate, rest])


func test_a_fallen_member_is_grey_and_one_table_names_every_tint() -> void:
	var f := _fixture()
	var scene = f[0]; var pc: Combatant = f[1]; var ps: AnimatedSprite2D = f[2]
	pc.is_alive = false
	assert_true(_near(scene.rest_modulate(ps), SCENE.KO_MODULATE), "a fallen member doesn't rest at the KO grey")
	pc.is_alive = true
	for status in ["poison", "burning", "curse", "stun", "sleep", "blind", "confuse", "fear", "charm", "regen"]:
		assert_false(_near(SCENE.status_tint([status]), Color.WHITE), "%s has no tint" % status)
	assert_true(_near(SCENE.status_tint(["no_such_status"]), Color.WHITE), "CONTROL: an unknown status is untinted")
	var ui := FileAccess.get_file_as_string("res://src/battle/BattleUIManager.gd")
	assert_false(ui.contains("func _get_status_modulate"), "BattleUIManager has its own status tint table again")
	assert_true(ui.contains("_scene.rest_modulate(sprite)"), "the UI refresh doesn't ask the scene for the rest colour")


## A Raise stands the member up in the same frame; a heal over the danger line lifts the weak pose.
func test_a_recovery_reposes_the_member_at_once() -> void:
	var f := _fixture()
	var scene = f[0]; var ps: AnimatedSprite2D = f[2]
	var animator: ANIMATOR = ANIMATOR.new()
	animator.setup(ps)
	scene.add_child(animator)
	scene.party_animators.append(animator)
	var rest := ["dead"]
	animator.rest_state_provider = func() -> String: return rest[0]
	animator.set_idle()
	assert_eq(ps.animation, &"dead", "CONTROL: a fallen member lies in the dead pose")
	rest[0] = "idle"
	scene._rest_after_recovery(0)
	assert_eq(ps.animation, &"idle", "a revived member is still lying in the dead pose")
	rest[0] = "weak"
	animator.set_idle()
	assert_eq(ps.animation, &"weak", "CONTROL: a member under the danger line shows the weak pose")
	rest[0] = "idle"
	scene._rest_after_recovery(0)
	assert_eq(ps.animation, &"idle", "a member healed over the danger line still shows the weak pose")
	## Already at rest: a regen tick must not restart the idle loop.
	ps.frame_progress = 0.5
	scene._rest_after_recovery(0)
	assert_almost_eq(ps.frame_progress, 0.5, 0.2, "a heal on a member already at rest restarted its idle")
	## The party is celebrating: a late heal must not end the win.
	scene._battle_victory = true
	rest[0] = "weak"
	scene._rest_after_recovery(0)
	assert_eq(ps.animation, &"idle", "a heal during the victory re-posed the member")
	scene._battle_victory = false
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var at := src.find("func _on_party_hp_changed(")
	var body := src.substr(at, src.find("\nfunc ", at + 1) - at)
	assert_true(body.contains("elif new_value > old_value:\n\t\t_rest_after_recovery(member_idx)"), "_on_party_hp_changed doesn't re-pose a member whose HP rose")


## cowir-battle 23726: a crit or weakness KILL. The flash was still driving modulate to an opaque colour while
## the death faded the same sprite; the death now ends the flash (and a knockback) at its first frame.
func test_a_killing_flash_ends_when_the_death_begins() -> void:
	var f := _fixture()
	var scene = f[0]; var es: AnimatedSprite2D = f[4]
	es.set_meta("home_position", es.position)
	scene._apply_weakness_hit_visuals(es, "fire", 2.0)
	scene._apply_weakness_hit_knockback(es, -1.0, 2.0)
	var flash: Tween = es.get_meta("flash_tween")
	var knock: Tween = es.get_meta("knockback_tween")
	assert_true(flash.is_valid() and knock.is_valid(), "CONTROL: the flash and the knockback must be in flight when the death starts")
	EnemyDeathFx.play(es, "crt_off")
	assert_false(flash.is_valid(), "the weakness flash is still writing modulate under the death")
	assert_false(knock.is_valid(), "the knockback is still writing position under the death")
	var alphas: Array = []
	var t0 := Time.get_ticks_msec()
	while es.visible and Time.get_ticks_msec() - t0 < 3000:
		alphas.append(es.modulate.a)
		await get_tree().process_frame
	assert_false(es.visible, "VOID: the death never finished")
	for i in range(1, alphas.size()):
		assert_lte(float(alphas[i]), float(alphas[i - 1]) + 0.001, "alpha rose during the death: %s" % str(alphas.slice(maxi(0, i - 2), i + 1)))


## cowir-main 23728: a BOSS keeps its own death (the inline tween in _on_enemy_died, not EnemyDeathFx), and
## that death ends a flash and a knockback in flight too. The real handler, on the built scene.
func test_a_boss_killed_mid_flash_is_owned_by_its_death() -> void:
	var guard = preload("res://test/unit/helpers/battle_state.gd").new()
	guard.snapshot()
	var scene = load("res://src/battle/BattleScene.tscn").instantiate()
	add_child_autofree(scene)
	var boss := Combatant.new()
	boss.initialize({"name": "Boss", "max_hp": 10, "max_mp": 0, "attack": 1, "defense": 1, "magic": 1, "speed": 1})
	boss.set_meta("is_boss", true)
	add_child_autofree(boss)
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = _frames()
	add_child_autofree(spr)
	spr.set_meta("home_position", spr.position)
	scene.test_enemies.assign([boss] as Array[Combatant])
	scene.enemy_sprite_nodes.assign([spr])
	var animator = ANIMATOR.new()
	animator.setup(spr)
	scene.add_child(animator)
	scene.enemy_animators.assign([animator])
	assert_false(EnemyDeathFx.applies_to(boss), "CONTROL: a boss must take the inline death, not the world's style")
	scene._apply_weakness_hit_visuals(spr, "fire", 2.0)
	scene._apply_weakness_hit_knockback(spr, -1.0, 2.0)
	var flash: Tween = spr.get_meta("flash_tween")
	var knock: Tween = spr.get_meta("knockback_tween")
	assert_true(flash.is_valid() and knock.is_valid(), "CONTROL: the flash and the knockback must be in flight when the boss dies")
	boss.is_alive = false
	scene._on_enemy_died(0)
	assert_false(flash.is_valid(), "the weakness flash is still writing modulate under the boss's death")
	assert_false(knock.is_valid(), "the knockback is still writing position under the boss's death")
	guard.restore()
