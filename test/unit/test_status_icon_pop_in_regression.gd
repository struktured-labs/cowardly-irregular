extends GutTest

## Polish regression: buff/debuff icons pop in with a brief scale tween
## instead of appearing dead-flat.
##
## _refresh_status_icons fires only on status_added / status_removed signals
## (not on the per-turn counter tick), so an unconditional pop on every
## refresh is honest feedback — "something in the status row just changed."
##
## Tests:
##   • Source-pin that _animate_status_icon_pop_in exists, sets a centered
##     pivot, starts < 1.0, and tweens to Vector2.ONE so the final state is
##     unscaled (cannot regress to a permanently-shrunk icon).
##   • Source-pin that _refresh_status_icons invokes the pop helper after
##     add_child for every freshly-built icon (the actual wiring).
##   • Defensive guard: the helper must defer one frame and bail on a freed
##     icon (the existing CLAUDE.md polish #24 pivot-after-frame pattern).

const BATTLE_SCENE_PATH := "res://src/battle/BattleScene.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


func test_pop_in_helper_exists_and_targets_scale_one() -> void:
	var text := _read(BATTLE_SCENE_PATH)
	var idx := text.find("func _animate_status_icon_pop_in")
	assert_gt(idx, -1, "_animate_status_icon_pop_in helper must exist")
	# Restrict to this function's body.
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("pivot_offset"),
		"pop-in must set pivot_offset so the scale grows from the icon's center")
	assert_true(body.contains("Vector2.ONE") or body.contains("Vector2(1") or body.contains("Vector2(1.0"),
		"pop-in tween must terminate at Vector2.ONE — the icon must end unscaled")
	assert_true(body.contains("set_ease(Tween.EASE_OUT)") or body.contains("EASE_OUT"),
		"pop-in must ease out so the overshoot reads as confident, not bouncy")


func test_pop_in_starts_smaller_than_one() -> void:
	var text := _read(BATTLE_SCENE_PATH)
	var idx := text.find("func _animate_status_icon_pop_in")
	assert_gt(idx, -1, "_animate_status_icon_pop_in must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	# Initial scale must be sub-1.0; otherwise there's nothing to animate.
	# Accept any Vector2(<0.99, <0.99) literal.
	var has_sub_one := false
	for token in ["Vector2(0.5", "Vector2(0.55", "Vector2(0.6", "Vector2(0.65",
			"Vector2(0.7", "Vector2(0.75", "Vector2(0.8", "Vector2(0.85", "Vector2(0.9"]:
		if body.contains(token):
			has_sub_one = true
			break
	assert_true(has_sub_one,
		"pop-in initial scale must be < 1.0 so the tween has something to grow")


func test_refresh_status_icons_calls_pop_in_after_add() -> void:
	# Pin the wiring: every freshly-built icon must trigger the pop-in path.
	# Without this, the helper could exist but never be invoked.
	var text := _read(BATTLE_SCENE_PATH)
	var idx := text.find("func _refresh_status_icons")
	assert_gt(idx, -1, "_refresh_status_icons must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	# The pop-in invocation must follow the add_child(icon) line.
	var add_idx := body.find("container.add_child(icon)")
	assert_gt(add_idx, -1, "_refresh_status_icons must add the icon to the container")
	var pop_idx := body.find("_animate_status_icon_pop_in(icon)")
	assert_gt(pop_idx, -1, "_refresh_status_icons must call the pop-in helper")
	assert_gt(pop_idx, add_idx,
		"pop-in must be invoked AFTER add_child so the panel is in the tree when scale fires")


func test_pop_in_helper_defers_and_guards_freed_icon() -> void:
	# CLAUDE.md polish #24 explicitly notes pivot_offset assignment must be
	# deferred one frame for the Control to have valid size. The helper must
	# also bail if the icon was freed during that frame (rapid refresh).
	var text := _read(BATTLE_SCENE_PATH)
	var idx := text.find("func _animate_status_icon_pop_in")
	assert_gt(idx, -1, "_animate_status_icon_pop_in must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("await get_tree().process_frame"),
		"pop-in must defer one frame before reading icon.size (Control size only valid after layout)")
	assert_true(body.contains("is_instance_valid(icon)"),
		"pop-in must guard against the icon being freed during the deferred frame (rapid refresh)")
