extends GutTest

## struktured 2026-08-22, playtesting: "still no sound to indicate next round, should be
## nice noise for that". The cue existed and was unreachable for TWO independent reasons,
## and fixing either alone still leaves it inaudible:
##
##   1. it sat AFTER `if ... or Engine.time_scale >= 1.0: return` in _show_round_banner.
##      Engine 1.0 is the rung LABELLED "4x" (BATTLE_SPEEDS[2]), so every speed from 4x up
##      played nothing at all.
##   2. it went through play_ui() -> SFX_UI_BASE_DB (-16 dB), the quietest channel, while
##      the combat it has to cut through sits on SFX_BATTLE_BASE_DB (-6 dB).
##
## Both arms are pinned here because either regression alone reproduces his report.

const SCENE_PATH := "res://src/battle/BattleScene.gd"


func _banner_body() -> String:
	var src := FileAccess.get_file_as_string(SCENE_PATH)
	assert_ne(src, "", "BattleScene.gd readable")
	var i := src.find("func _show_round_banner")
	assert_gt(i, -1, "_show_round_banner present")
	var nxt := src.find("\nfunc ", i + 1)
	return src.substr(i, (nxt - i) if nxt > -1 else -1)


func test_the_round_cue_fires_before_the_banner_speed_guard() -> void:
	var body := _banner_body()
	var cue := body.find("round_ap_gain")
	assert_gt(cue, -1, "the round cue is still played somewhere in the function")
	var guard := body.find("Engine.time_scale >= 1.0")
	assert_gt(guard, -1, "the banner's 4x+ visual guard is still present")
	assert_lt(cue, guard,
		"the CUE must precede the banner's `>= 1.0` return — behind it, every speed from the "
		+ "rung labelled 4x upward is silent, which is exactly what was reported")


func test_the_round_cue_uses_the_battle_channel_not_ui() -> void:
	var body := _banner_body()
	assert_true(body.contains("play_battle(\"round_ap_gain\")"),
		"round cue routes through play_battle (SFX_BATTLE_BASE_DB)")
	assert_false(body.contains("play_ui(\"round_ap_gain\")"),
		"and NOT through play_ui — SFX_UI_BASE_DB is 10 dB down and buries it under combat")


func test_the_two_channel_constants_still_differ_by_the_amount_that_motivated_this() -> void:
	## Guards the test above from going vacuous: if the two bases ever converge, routing
	## to play_battle stops meaning anything and this file should be revisited, not trusted.
	assert_almost_eq(SoundManager.SFX_BATTLE_BASE_DB, -6.0, 0.01, "battle base unchanged")
	assert_almost_eq(SoundManager.SFX_UI_BASE_DB, -16.0, 0.01, "ui base unchanged")
	assert_gt(SoundManager.SFX_BATTLE_BASE_DB - SoundManager.SFX_UI_BASE_DB, 5.0,
		"battle must still sit meaningfully above UI, or the channel choice is moot")


func test_turbo_and_autogrind_still_suppress_the_cue() -> void:
	## The fix must not make grind modes noisy — those exist for throughput.
	var body := _banner_body()
	var early := body.find("if turbo_mode or autogrind_console_mode")
	assert_gt(early, -1, "turbo/autogrind still short-circuit the whole function")
	assert_lt(early, body.find("round_ap_gain"),
		"and they do so BEFORE the cue, so grinding stays silent")
