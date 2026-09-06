extends GutTest

## struktured 2026-09-06, live playtest, four rulings on the fallen:
##  1. "still see the bard in up/down cycle same with mage" — the one-shot fall replayed every
##     rest re-resolve. The corpse now holds its last frame.
##  2. "dead party member: do not celebrate after battle (they stay ded)".
##  3. "they get no exp (unless they have a special item or passive)" — Posthumous Credit
##     passive / Mourner's Ledger accessory.
##  4. (same session) inn confirm must not re-open the keeper's dialogue.

const ANIM_SRC := "res://src/battle/BattleAnimator.gd"


func _dead_capable_sprite() -> AnimatedSprite2D:
	var frames := SpriteFrames.new()
	frames.add_animation("idle")
	frames.add_animation("dead")
	frames.set_animation_loop("dead", false)
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	for i in range(3):
		frames.add_frame("dead", tex)
	frames.add_frame("idle", tex)
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames
	return s


func test_set_idle_does_not_restart_a_finished_fall() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var sprite := _dead_capable_sprite()
	host.add_child(sprite)
	var anim = load(ANIM_SRC).new()
	host.add_child(anim)
	anim.sprite = sprite
	anim.rest_state_provider = func(): return "dead"
	anim.set_idle()
	assert_eq(sprite.animation, "dead", "CONTROL: first set_idle enters the fall")
	sprite.stop()
	sprite.frame = 2
	anim.set_idle()
	assert_eq(sprite.frame, 2, "a second set_idle must HOLD the last frame, not replay the fall from 0")
	assert_false(sprite.is_playing(), "and must not set the sprite playing again")


func test_finished_fall_does_not_bounce_back_through_set_idle() -> void:
	var src := FileAccess.get_file_as_string(ANIM_SRC)
	assert_gt(src.length(), 1000, "CONTROL: read a real file")
	var i: int = src.find("func _on_sprite_animation_finished(")
	var body: String = src.substr(i, 700)
	assert_true(body.contains("current_state != AnimState.DEAD"),
		"the finished DEAD state must not route back into set_idle — that was the up/down loop")


func test_the_fallen_do_not_celebrate() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var i: int = src.find("func _play_staggered_victory_animations(")
	assert_gt(i, -1, "CONTROL: victory fn must exist")
	var body: String = src.substr(i, 900)
	assert_true(body.contains("not BattleManager.player_party[i].is_alive"),
		"victory poses must skip dead members")
	var skip_at: int = body.find("is_alive")
	var play_at: int = body.find("play_victory()")
	assert_lt(skip_at, play_at, "and the skip must come BEFORE the pose plays")


func _combatant() -> Combatant:
	var c := Combatant.new()
	c.combatant_name = "Fallen"
	return c


func test_dead_earn_nothing_by_default() -> void:
	var c := _combatant()
	assert_false(BattleManager.earns_exp_while_dead(c), "no passive, no item = no posthumous EXP")
	c.free()


func test_posthumous_credit_passive_grants_exp_while_dead() -> void:
	assert_false(PassiveSystem.get_passive("posthumous_credit").is_empty(),
		"the passive must be authored in passives.json")
	var c := _combatant()
	c.equipped_passives.append("posthumous_credit")
	assert_true(BattleManager.earns_exp_while_dead(c), "the passive must unlock EXP while KO'd")
	c.free()


func test_mourners_ledger_accessory_grants_exp_while_dead() -> void:
	var item: Dictionary = EquipmentSystem.get_accessory("mourners_ledger")
	assert_false(item.is_empty(), "the accessory must be authored in equipment.json")
	assert_almost_eq(float((item.get("special_effects", {}) as Dictionary).get("exp_while_dead", 0.0)), 1.0, 0.001)
	var c := _combatant()
	c.equipped_accessory = "mourners_ledger"
	assert_true(BattleManager.earns_exp_while_dead(c), "the accessory must unlock EXP while KO'd")
	c.free()


func test_exp_loop_consults_the_exception() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_true(src.contains("if combatant.is_alive or earns_exp_while_dead(combatant):"),
		"the award loop must gate on alive OR the exception — else the passive/item are decorative")


func test_impact_cues_are_strike_voices_not_replayed_cast_cues() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/EffectSystem.gd")
	var i: int = src.find("func _play_effect_sound(")
	var body: String = src.substr(i, 1200)
	assert_true(body.contains('"strike_fire"'), "fire impact must be the strike voice")
	assert_false(body.contains('sound_key = "ability_fire"'),
		"replaying the cast cue pitch-shifted at impact was the doubled 'boop'")


func test_inn_prompt_eats_its_own_confirm() -> void:
	var src := FileAccess.get_file_as_string("res://src/maps/interiors/InnInterior.gd")
	var i: int = src.find("func _input(event: InputEvent)")
	assert_gt(i, -1, "the inn needs an _input handler — _unhandled_input runs AFTER the player's")
	var body: String = src.substr(i, 400)
	assert_true(body.contains("_rest_pending") and body.contains("ui_accept") and body.contains("set_input_as_handled"),
		"the confirm must be consumed while a rest is pending, or the keeper interact fires a second dialogue")
