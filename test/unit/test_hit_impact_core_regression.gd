extends GutTest

## Phase B of the battle-feel plan: per-hit impact core. Pins the pieces that could
## silently regress: anticipation stays BEFORE the pinned EASE_IN approach (and carries no
## explicit EASE_OUT literal, which would break the melee ordering pin), squash multiplies
## the stored base_scale (absolutes corrupt heterogeneous sprite scales), knockback gained
## a vertical component, and the round-boundary reset restores everything juice can touch.

func _scene_src() -> String:
	return FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")


func _fn_body(src: String, fn: String) -> String:
	var i := src.find("func %s" % fn)
	assert_gt(i, -1, "%s must exist" % fn)
	var fn_end := src.find("\nfunc ", i + 1)
	return src.substr(i, (fn_end - i) if fn_end > -1 else 4000)


func test_anticipation_before_approach_and_ordering_safe() -> void:
	var src := _scene_src()
	var i := src.find("func _animate_melee_attack")
	var next: int = src.find("\nfunc _spawn_lunge_ghost", i)
	assert_gt(next, i, "ghost helper follows the melee body")
	var body := src.substr(i, next - i)
	var pull := body.find("home_pos - direction * 6.0")
	var ease_in := body.find("Tween.EASE_IN)")
	assert_gt(pull, -1, "anticipation pull-back present")
	assert_true(pull < ease_in, "pull-back precedes the EASE_IN approach")
	var pre_contact := body.substr(0, body.find("_apply_hitstop("))
	assert_false("Tween.EASE_OUT)" in pre_contact, "no EASE_OUT literal before contact — the melee ordering pin depends on it")
	assert_true("Tier.FULL" in body, "anticipation is FULL-tier gated")


func test_squash_multiplies_base_scale() -> void:
	var juice := FileAccess.get_file_as_string("res://src/battle/BattleJuice.gd")
	var i := juice.find("func squash")
	assert_gt(i, -1, "squash must exist")
	var fn_end := juice.find("\nfunc ", i + 1)
	var body := juice.substr(i, fn_end - i)
	assert_true('get_meta("base_scale"' in body, "squash reads the stored base scale")
	assert_true("base.x * x" in body, "squash MULTIPLIES — absolute assignment corrupts heterogeneous scales")


func test_base_scale_meta_set_at_spawn() -> void:
	var src := _scene_src()
	assert_gte(src.count('set_meta("base_scale"'), 2, "party + enemy spawn sites store base_scale")


func test_knockback_has_vertical_pop() -> void:
	var src := _scene_src()
	var body := _fn_body(src, "_apply_hit_knockback")
	assert_true("position:y" in body, "knockback gained a vertical component")
	assert_true("Tier.REDUCED" in body, "pop is tier-gated")
	var wbody := _fn_body(src, "_apply_weakness_hit_knockback")
	assert_true("position:y" in wbody, "weakness knockback pops too")


func test_round_reset_restores_presentation_state() -> void:
	var src := _scene_src()
	var body := _fn_body(src, "_reset_presentation_state")
	assert_true('get_meta("base_scale")' in body, "reset restores scale from base_scale")
	assert_true("speed_scale = 1.0" in body, "reset unfreezes hitstop")
	assert_true("flash_amount" in body and "dissolve_amount" in body, "reset zeroes shader uniforms")
	var snap := _fn_body(src, "_on_round_started_snap_home")
	assert_true('get_meta("dying", false)' in snap, "dying sprites are exempt — reset must not un-dissolve a death in progress")
	assert_true("_reset_presentation_state" in snap, "round boundary invokes the reset")
