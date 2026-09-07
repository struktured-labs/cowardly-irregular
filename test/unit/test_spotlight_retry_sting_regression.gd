extends GutTest

## Playtest 2026-07-12: after a spotlight-duel death the game paused silently
## for 0.9s then restarted the same fight — read as a glitch or loop, not a
## retry. Fix: on defeat retry, play a proper sting (defeat SFX + screen shake
## + red flash → black on the director's own _effects_rect) before the next
## _start_battle_async spins up a fresh battle.


func test_retry_branch_calls_the_sting_helper() -> void:
	var src := FileAccess.get_file_as_string("res://src/cutscene/CutsceneDirector.gd")
	var i := src.find("func _step_battle")
	assert_gt(i, -1)
	# Scan the retry branch specifically, not the whole file.
	var body := src.substr(i, src.find("\nfunc ", i + 1) - i)
	var retry_idx := body.find("\"retry\":")
	assert_gt(retry_idx, -1, "retry branch must exist")
	var retry_block := body.substr(retry_idx, 500)
	assert_true("_play_spotlight_retry_sting()" in retry_block,
		"retry branch must run the defeat sting instead of the silent 0.9s wait")
	assert_false("create_timer(0.9)" in retry_block,
		"the old silent 0.9s pause must be gone — the sting owns the pacing now")


func test_sting_helper_wires_all_three_channels() -> void:
	var src := FileAccess.get_file_as_string("res://src/cutscene/CutsceneDirector.gd")
	var i := src.find("func _play_spotlight_retry_sting")
	assert_gt(i, -1, "sting helper must exist")
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 1200)
	# SFX + shake + red flash on the shared effects rect.
	assert_true("SoundManager.play_battle(\"defeat\")" in body,
		"sting must play the defeat SFX")
	assert_true("EffectSystem._trigger_screen_shake" in body,
		"sting must shake the screen (the physical 'you lost' beat)")
	assert_true("_effects_rect" in body and "tween" in body,
		"sting must flash the shared _effects_rect via a tween, not a raw sleep")
	# End-of-sting reset: leftover opaque black would cover the aftermath the
	# next iteration (visible=true after the retry battle ends).
	assert_true("_effects_rect.visible = false" in body,
		"sting must reset _effects_rect at the end so the retry battle's aftermath isn't covered by leftover black")
	assert_true("Color(1, 1, 1, 0)" in body,
		"sting must reset _effects_rect.color so the next fade-to-black starts from transparent, not opaque")
