extends GutTest

## tick 78 regression: opening the overworld menu (or party chat
## menu) during an area-transition fade-IN paused the OLD
## _exploration_scene — but _start_exploration then freed that
## scene mid-pause and rebuilt the NEW scene unpaused. The menu's
## close handler called resume() on the NEW scene, which was never
## paused, leaving an asymmetric pause/resume pair.
##
## The fade-OUT half is already covered by tick 77's
## 'area_transition_fade' InputLockManager lock — but that lock is
## only pushed AFTER _start_exploration. Fade-IN runs BEFORE
## _start_exploration and has no InputLockManager protection (the
## pop_all in _start_exploration is the reason).
##
## Tick 78 adds an explicit _transition_in_progress check to the
## menu-open input gates so the fade-IN window is also covered.

const GAME_LOOP := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_overworld_menu_input_checks_transition_in_progress() -> void:
	# Find the menu-open gate guarded by `x_pressed`. The
	# _transition_in_progress check must appear inside that block.
	var src := _read(GAME_LOOP)
	var idx: int = src.find("if x_pressed:")
	assert_gt(idx, -1, "x_pressed gate must exist (Esc/X menu open)")
	# Look forward enough chars to clear the comment block.
	var window: String = src.substr(idx, 1400)
	assert_true(window.contains("if _transition_in_progress:"),
		"x_pressed menu-open gate must check _transition_in_progress — otherwise menu can open during fade-in and pause the about-to-be-freed scene")


func test_party_chat_input_checks_transition_in_progress() -> void:
	# Same gate for the L-shoulder Party Chat menu.
	var src := _read(GAME_LOOP)
	var idx: int = src.find("if event.is_action_pressed(\"party_chat\"):")
	assert_gt(idx, -1, "party_chat input gate must exist")
	var window: String = src.substr(idx, 700)
	assert_true(window.contains("if _transition_in_progress:"),
		"party_chat menu-open gate must check _transition_in_progress — symmetric with x_pressed gate")


func test_transition_in_progress_flag_lifecycle_intact() -> void:
	# Pin the lifecycle: set true at start of _on_area_transition,
	# set false after the match block. A future refactor that drops
	# either would silently break the menu gate.
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _on_area_transition")
	assert_gt(idx, -1, "_on_area_transition must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	# Set true near top
	assert_true(body.contains("_transition_in_progress = true"),
		"_on_area_transition must set _transition_in_progress = true")
	assert_true(body.contains("_transition_in_progress = false"),
		"_on_area_transition must clear _transition_in_progress = false")
	# Ordering: true must precede false
	var true_pos: int = body.find("_transition_in_progress = true")
	var false_pos: int = body.rfind("_transition_in_progress = false")
	assert_lt(true_pos, false_pos,
		"set-true must precede set-false in _on_area_transition body — otherwise flag is cleared before the transition runs")


func test_input_lock_check_still_present() -> void:
	# Tick 78 ADDS to the gate; the existing InputLockManager.is_locked
	# check from tick 77 (and earlier encounter-transition guard) must
	# still be there. Otherwise other transient locks (encounter,
	# fade-out) stop blocking menu open.
	var src := _read(GAME_LOOP)
	var idx: int = src.find("if x_pressed:")
	var window: String = src.substr(idx, 1400)
	assert_true(window.contains("InputLockManager and InputLockManager.is_locked()"),
		"x_pressed gate must still check InputLockManager.is_locked — covers encounter-transition and fade-out locks")
