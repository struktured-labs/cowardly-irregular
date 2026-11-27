extends GutTest

## .841 pre-gate: a meta-boss arm spent 3.6 s in one frame, and the next script's 1.2 s gloat timer expired on its first tick.
## The runner now yields two frames between scripts; each inner class below is a separate script in GUT's loop.

const LONG_FRAME_MSEC := 1500
const WINDOW_SEC := 1.0

const MARK := "cowir_long_test_frame_ended"


func test_the_runner_yields_between_scripts() -> void:
	var src := FileAccess.get_file_as_string("res://addons/gut/gut.gd")
	var at := src.find("\t\tend_script.emit()\n\t\t# cowir: spend a long last frame's delta here")
	assert_gt(at, -1, "gut.gd carries the cowir yield after end_script: re-apply it after a GUT upgrade")
	var after := src.substr(at, 400)
	assert_eq(after.count("\t\tawait get_tree().process_frame\n"), 2,
		"the yield after end_script awaits two frames: re-apply it after a GUT upgrade")


class TestAEndsOnALongFrame extends GutTest:
	func test_the_last_arm_blocks_one_frame() -> void:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < LONG_FRAME_MSEC:
			pass
		Engine.set_meta(MARK, Engine.get_process_frames())
		assert_true(true, "burned one long synchronous frame")


class TestBStartsATimerNext extends GutTest:
	func test_a_fresh_timer_outlives_its_first_tick() -> void:
		assert_true(Engine.has_meta(MARK), "CONTROL: the long-frame script ran before this one")
		Engine.remove_meta(MARK)
		var timer := get_tree().create_timer(WINDOW_SEC, true, false, true)
		await get_tree().process_frame
		await get_tree().process_frame
		assert_gt(timer.time_left, WINDOW_SEC * 0.5,
			"a %.1f s timer started right after a %d ms frame still has most of its window" % [WINDOW_SEC, LONG_FRAME_MSEC])
