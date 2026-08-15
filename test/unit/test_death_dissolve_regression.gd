extends GutTest

## Phase B: enemy deaths get a shader pixel-dissolve moment. Pins: the dissolve branch
## exists, the FF-flicker FALLBACK survives (material-less sprites + OFF tier must keep
## working), the deferred death-log ordering is untouched (died fires inside take_damage —
## the killing blow's damage line must print first), and dying sprites are marked so the
## round-boundary reset can't un-dissolve them.

func _died_body() -> String:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var i := src.find("func _on_enemy_died")
	assert_gt(i, -1, "_on_enemy_died must exist")
	var fn_end := src.find("\nfunc ", i + 1)
	return src.substr(i, fn_end - i)


func test_dissolve_branch_and_flicker_fallback_coexist() -> void:
	var body := _died_body()
	assert_true("dissolve_amount" in body, "shader dissolve branch present")
	assert_true("0.7 - i * 0.1" in body, "FF-flicker fallback kept for material-less sprites and OFF tier")
	assert_true("has_dissolve" in body, "branch selection is explicit, not shader-assumed")


func test_dying_meta_set_before_any_tween() -> void:
	var body := _died_body()
	var mark := body.find('set_meta("dying", true)')
	var tween := body.find("create_tween()")
	assert_gt(mark, -1, "dying marker set")
	assert_true(mark < tween, "marker precedes the dissolve tween — the round reset checks it")


func test_deferred_death_log_ordering_untouched() -> void:
	var body := _died_body()
	assert_true('call_deferred("log_message"' in body, "death log stays DEFERRED — died fires inside take_damage, before the damage line prints")


func test_death_spectacle_is_tier_gated() -> void:
	var body := _died_body()
	assert_true("Tier.OFF" in body, "OFF tier bypasses the shader path entirely")
	assert_true("Tier.REDUCED" in body, "burst/hold/zoom package gated to FULL+REDUCED")
