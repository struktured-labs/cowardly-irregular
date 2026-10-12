extends GutTest
## A paused grind hands the player back to the overworld on purpose, and its ONLY paused signal was a
## toast that fades after ~2.8s. After that the screen is an ordinary overworld with a suspended
## session behind it, so a pause was indistinguishable from a lost grind -- and the persistent label
## that was meant to say so lives on _create_autogrind_overlay(), which has had ZERO callers since
## f3f808a90 (2026-03-09). The badge is that toast with no fade-out.
## Keyed to NODE NAMES, not to _autogrind_paused_layer: that field does not exist on the unfixed tree,
## and reading a missing property aborts the enclosing function, which scores arms green vacuously.
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const BADGE := "PausedBadgeLabel"
const BADGE_PANEL := "PausedBadgePanel"

var _ag: Dictionary
var _gl: Node


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	Engine.time_scale = 1.0
	_gl = load("res://src/GameLoop.gd").new()
	add_child_autofree(_gl)
	var explore := Node.new()
	add_child_autofree(explore)
	_gl._exploration_scene = explore
	_gl._current_map_id = "overworld"
	_gl.current_state = _gl.LoopState.EXPLORATION


func after_each() -> void:
	AutogrindState.restore(_ag)
	Engine.time_scale = 1.0
	SoundManager.stop_music()


func _badge() -> Node:
	return _gl.find_child(BADGE, true, false)


func _pause() -> Node:
	_gl._on_autogrind_paused()
	await wait_frames(3)
	var b: Node = _badge()
	assert_not_null(b, "pausing a grind must leave a paused indicator on screen")
	return b


func test_a_pause_leaves_an_indicator_on_screen() -> void:
	var b: Node = await _pause()
	if b == null:
		return
	assert_true(b is Label, "the indicator must be a Label the player can read")
	assert_string_contains((b as Label).text, "resume", "it must say how to get the grind back")


## THE POINT OF THE FIX: the old toast was gone by ~2.8s, which is what made a pause look like a loss.
func test_the_indicator_outlives_the_toast_that_replaced_it() -> void:
	var b: Node = await _pause()
	if b == null:
		return
	await wait_seconds(3.4)
	assert_not_null(_badge(), "the indicator must still be there after the toast's 2.8s lifetime")
	assert_true(is_instance_valid(b), "and must be the same node, not a re-created one")
	## The pulse modulates the PANEL, so the panel's alpha is the one that says "still visible".
	var panel: Node = _gl.find_child(BADGE_PANEL, true, false)
	assert_not_null(panel, "the badge panel must still be there too")
	if panel != null:
		assert_gt((panel as Control).modulate.a, 0.4, "it must still be visible -- the pulse may dim it, never hide it")


func test_resuming_takes_the_indicator_down() -> void:
	var b: Node = await _pause()
	if b == null:
		return
	_gl._on_autogrind_resumed()
	await wait_frames(3)
	assert_null(_badge(), "resuming must take the paused indicator down")


## Stopping while PAUSED is the stranding case: every teardown path funnels through this one call.
func test_stopping_while_paused_does_not_strand_the_indicator() -> void:
	var b: Node = await _pause()
	if b == null:
		return
	_gl._destroy_autogrind_overlay()
	await wait_frames(3)
	assert_null(_badge(), "a grind torn down while paused must not leave its indicator behind")


func test_pausing_twice_does_not_stack_indicators() -> void:
	var b: Node = await _pause()
	if b == null:
		return
	_gl._on_autogrind_paused()
	await wait_frames(3)
	var found: Array = _gl.find_children(BADGE, "", true, false)
	assert_eq(found.size(), 1, "a second pause must replace the indicator, not stack another on top")


func test_an_unpaused_grind_shows_no_indicator() -> void:
	assert_null(_badge(), "CONTROL: nothing paused, so there must be no indicator to begin with")


## It carries its own background on purpose: two placements in a row landed under a transient panel
## (the battle hint at y 8..110, the toast lane at y=80), and a permanent badge cannot win a fight
## for space against surfaces it does not know about.
func test_the_indicator_is_readable_wherever_it_lands() -> void:
	var b: Node = await _pause()
	if b == null:
		return
	var panel: Node = _gl.find_child(BADGE_PANEL, true, false)
	assert_not_null(panel, "the indicator must bring its own background, not rely on what is behind it")
	if panel == null:
		return
	var style: StyleBox = (panel as PanelContainer).get_theme_stylebox("panel")
	assert_true(style is StyleBoxFlat, "that background must be a real styled box")
	if style is StyleBoxFlat:
		assert_gt((style as StyleBoxFlat).bg_color.a, 0.8, "and opaque enough to read text over anything beneath it")
	assert_gt((panel as Control).size.x, 0.0, "the panel must have been sized to its text")
