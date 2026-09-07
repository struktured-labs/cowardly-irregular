extends GutTest

## Regression test for the Mode 7 battle floor spike.
##
## Spike scope (per cowir-main review msg 1739):
## - BattleMode7Floor.gd is a procedural-draw Control with @export tunables
## - BattleScene.gd preloads it as Mode7FloorClass and gates instantiation
##   behind _mode7_floor_enabled
## - The floor is added at child index 1 so sprites (added later) render above it
## - Easy rollback: flip the toggle, no other code changes
##
## These tests guard the structural contract so the spike can't silently
## regress (e.g. someone removes the toggle, the file gets renamed, the
## class drops the 'spike' export knobs that exist for live iteration).

const BattleScenePath := "res://src/battle/BattleScene.gd"
const Mode7FloorPath := "res://src/battle/BattleMode7Floor.gd"


func test_mode7_floor_class_loads() -> void:
	var script = load(Mode7FloorPath)
	assert_not_null(script,
		"BattleMode7Floor.gd must load (regression: spike file removed/renamed)")


func test_mode7_floor_extends_control() -> void:
	# Must be a Control so it can be added as a UI overlay below sprites.
	# AnimatedSprite2D / Node would not lay out / draw correctly.
	var script = load(Mode7FloorPath) as GDScript
	assert_not_null(script)
	var instance = script.new()
	assert_true(instance is Control,
		"BattleMode7Floor must extend Control (regression: base class change breaks layout)")
	instance.free()


func test_mode7_floor_has_iteration_knobs() -> void:
	# These exports exist precisely so we can iterate on the look without
	# code edits. If any disappear, the spike's "easy to tune" property breaks.
	var script = load(Mode7FloorPath) as GDScript
	var instance = script.new()
	var required_props = [
		"horizon_ratio",
		"floor_color",
		"grid_color",
		"vertical_line_count",
		"depth_line_count",
		"depth_curve",
		"vertical_overshoot",
		"tilt_amplitude",
	]
	for prop_name in required_props:
		assert_true(prop_name in instance,
			"BattleMode7Floor must export '%s' for live iteration (regression: knob removed)" % prop_name)
	instance.free()


func test_battle_scene_preloads_mode7_floor() -> void:
	# BattleScene.gd must reference the floor class via preload so the
	# instantiation path stays wired. This is a structural check via source
	# read because Mode7FloorClass is a const inside BattleScene and we
	# don't want to instantiate the whole BattleScene tree just to verify it.
	var file = FileAccess.open(BattleScenePath, FileAccess.READ)
	assert_not_null(file, "BattleScene.gd must exist")
	var text = file.get_as_text()
	file.close()
	assert_true(text.contains("Mode7FloorClass"),
		"BattleScene.gd must reference Mode7FloorClass (regression: preload removed, floor will never spawn)")
	assert_true(text.contains("BattleMode7Floor.gd"),
		"BattleScene.gd preload must point at BattleMode7Floor.gd (regression: path drift)")


func test_battle_scene_has_enable_toggle() -> void:
	# The kill-switch is the spike's "easy rollback" — must remain so
	# user can flip a single bool to disable. Verifies the var exists in
	# BattleScene source.
	var file = FileAccess.open(BattleScenePath, FileAccess.READ)
	var text = file.get_as_text()
	file.close()
	assert_true(text.contains("_mode7_floor_enabled"),
		"BattleScene must keep _mode7_floor_enabled toggle (regression: kill-switch removed)")


func test_mode7_floor_static_state_is_zero_cpu() -> void:
	# The spike's only-redraw-when-tilting contract: tilt_amplitude default
	# must stay 0 so the static look has zero per-frame CPU. If a future
	# tweak sets it >0 by default, every battle pays for redraws.
	var script = load(Mode7FloorPath) as GDScript
	var instance = script.new()
	assert_eq(instance.tilt_amplitude, 0.0,
		"tilt_amplitude default must be 0.0 (zero-CPU static contract — regression: default changed)")
	instance.free()
