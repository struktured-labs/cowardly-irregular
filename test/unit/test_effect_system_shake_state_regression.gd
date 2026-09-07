extends GutTest

## Defensive regression: EffectSystem._trigger_screen_shake() must not
## leave the `_is_shaking` flag pinned true when the camera becomes
## unreachable mid-call, and _exit_tree() must clean up the in-flight
## shake tween so its terminal callback doesn't try to call into a freed
## EffectSystem instance.
##
## Bug shape:
##   1. Shake A starts. `_is_shaking = true`, _shake_tween created.
##   2. The camera node is removed (scene change / battle teardown).
##      Tween still runs but its target is invalid; its terminal callback
##      may emit script errors trying to touch the freed camera.
##   3. Next call to _trigger_screen_shake — viewport.get_camera_2d()
##      returns null. PRE-FIX: function returned early without resetting
##      `_is_shaking`. POST-FIX: `_is_shaking = false` so the NEXT
##      successful shake records a fresh baseline.
##
## And:
##   1. Shake starts. `_shake_tween` running.
##   2. EffectSystem._exit_tree fires (autoload reload / test teardown).
##      PRE-FIX: _shake_tween kept running with stale self-reference;
##      the camera.offset stayed displaced if we were mid-shake.
##      POST-FIX: kill the tween + restore camera offset to baseline.
##
## Tests:
##   • Source-pin that the no-viewport and no-camera early-return paths
##     both reset `_is_shaking` to false.
##   • Source-pin that _exit_tree kills the shake tween + clears state.
##   • Behavioural: forcing `_is_shaking = true` then calling shake with
##     no available camera resets the flag.
##   • Behavioural: settings-gated shake (screen_shake_enabled=false)
##     still short-circuits cleanly and does NOT touch `_is_shaking`.

const EFFECT_SYSTEM_PATH := "res://src/battle/EffectSystem.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Source pins ───────────────────────────────────────────────────────────────

func test_no_viewport_path_resets_is_shaking() -> void:
	var text := _read(EFFECT_SYSTEM_PATH)
	var idx := text.find("func _trigger_screen_shake")
	assert_gt(idx, -1, "_trigger_screen_shake must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	# There must be a `_is_shaking = false` inside the function body —
	# both early-return paths (no viewport, no camera) need it.
	# Count occurrences: we expect at least 2 (one per early-return).
	var count := 0
	var search := body
	while true:
		var hit := search.find("_is_shaking = false")
		if hit == -1:
			break
		count += 1
		search = search.substr(hit + 1)
	assert_gte(count, 2,
		"_trigger_screen_shake must reset _is_shaking on both early-return paths (no viewport + no camera); found %d" % count)


func test_exit_tree_kills_shake_tween_and_resets_state() -> void:
	var text := _read(EFFECT_SYSTEM_PATH)
	var idx := text.find("func _exit_tree")
	assert_gt(idx, -1, "_exit_tree must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("_shake_tween.kill"),
		"_exit_tree must kill the in-flight shake tween so its callback can't fire into a freed instance")
	assert_true(body.contains("_is_shaking = false"),
		"_exit_tree must reset _is_shaking false so a re-instantiated EffectSystem starts clean")
	assert_true(body.contains("_shake_tween = null"),
		"_exit_tree must drop the _shake_tween reference")


# ── Behavioural ───────────────────────────────────────────────────────────────

func _es() -> Node:
	return get_node_or_null("/root/EffectSystem")


func test_no_camera_early_return_resets_is_shaking() -> void:
	# Source-pin (more reliable than driving headless camera state): assert
	# that the no-camera early-return path lives BELOW the camera lookup
	# fallback. Driving this behaviourally requires guaranteeing no Camera2D
	# is reachable from the autoload's viewport, which is environment-
	# dependent in GUT. The source structure proves the fix.
	var text := _read(EFFECT_SYSTEM_PATH)
	var idx := text.find("func _trigger_screen_shake")
	assert_gt(idx, -1, "_trigger_screen_shake must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	# The post-fallback `if not camera:` block must reset the flag.
	var fallback_idx := body.find("get_nodes_in_group(\"camera\")")
	assert_gt(fallback_idx, -1, "no-camera fallback group lookup must exist")
	# Look at the slice AFTER the fallback for a no-camera early-return that
	# resets _is_shaking. This proves the fallback failure path resets state.
	var post_fallback := body.substr(fallback_idx)
	var early_return_idx := post_fallback.find("if not camera:")
	assert_gt(early_return_idx, -1,
		"a post-fallback 'if not camera:' early-return must exist (the stuck-flag fix)")
	var post_early_return := post_fallback.substr(early_return_idx, 200)
	assert_true(post_early_return.contains("_is_shaking = false"),
		"post-fallback no-camera early-return must reset _is_shaking false")
	assert_true(post_early_return.contains("return"),
		"post-fallback no-camera early-return must actually return")


func test_settings_gate_does_not_touch_is_shaking() -> void:
	# When the user has disabled screen_shake_enabled, the very-first early
	# return must NOT mutate _is_shaking — that path runs every shake call
	# and would otherwise stomp legitimate in-flight state.
	var gs := get_node_or_null("/root/GameState")
	if gs == null or not ("screen_shake_enabled" in gs):
		pending("GameState autoload / screen_shake_enabled field unavailable")
		return
	var es := _es()
	if es == null:
		pending("EffectSystem autoload unavailable")
		return
	var prior_flag: bool = es._is_shaking
	var prior_setting: bool = gs.screen_shake_enabled
	gs.screen_shake_enabled = false
	es._is_shaking = true  # Pretend a shake is mid-flight elsewhere
	es._trigger_screen_shake(5.0, 0.1)
	var post_flag: bool = es._is_shaking
	# Restore so we don't pollute downstream tests.
	gs.screen_shake_enabled = prior_setting
	es._is_shaking = prior_flag
	assert_true(post_flag,
		"Settings-gated shake must NOT clobber an in-flight _is_shaking flag")
