extends GutTest

## A wipe leaves Engine.time_scale on the battle ladder. Default "1x" is 0.25,
## and the defeat screen's fade plus its pause before confirm are bare tweens,
## so the authored 2s of dead input is 8s of wall clock while the log already
## says press to restart. The gate has to run on the wall clock.

var _saved_scale: float = 1.0


func before_each() -> void:
	_saved_scale = Engine.time_scale


func after_each() -> void:
	Engine.time_scale = _saved_scale


func _settle() -> void:
	Engine.time_scale = 0.25
	for _i in 8:
		await get_tree().process_frame


func test_defeat_screen_accepts_input_on_the_wall_clock() -> void:
	await _settle()
	var screen := GameOverScreen.new()
	add_child_autofree(screen)
	screen.show_game_over(false)
	var t0 := Time.get_ticks_msec()
	var became := false
	while Time.get_ticks_msec() - t0 < 4500:
		await get_tree().process_frame
		if screen._active:
			became = true
			break
	var wall := Time.get_ticks_msec() - t0
	assert_true(became,
		"defeat screen ignored confirm for %dms wall at battle speed 1x (time_scale 0.25)" % wall)
	assert_gt(wall, 1000, "the fade and the brief pause before confirm are still there (%dms)" % wall)


func test_confirm_leaves_the_defeat_screen_on_the_wall_clock() -> void:
	await _settle()
	var screen := GameOverScreen.new()
	add_child_autofree(screen)
	screen._active = true
	screen._selected_index = 0
	var got := [false]
	screen.retry_selected.connect(func() -> void: got[0] = true)
	screen._confirm_selection()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1200 and not got[0]:
		await get_tree().process_frame
	var wall := Time.get_ticks_msec() - t0
	assert_true(got[0],
		"Retry stayed on the fade-out for %dms wall at battle speed 1x (time_scale 0.25)" % wall)
