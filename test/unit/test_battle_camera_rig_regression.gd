extends GutTest

## Phase A: the camera rig is the single writer of camera offset/zoom during battle.
## Pins the properties that keep it safe without a CanvasLayer: zoom floor 1.0 (zoom-out
## reveals canvas edges), the Phase-A ceiling (UI shares the sprite canvas — >4% zoom
## visibly scales panels), rotation held at 0 until A2, gates, and teardown restore.

const RigScript = preload("res://src/battle/BattleCameraRig.gd")


func _rig_with_cam() -> Array:
	var cam := Camera2D.new()
	add_child_autofree(cam)
	var rig: Node = RigScript.new()
	add_child_autofree(rig)
	rig.setup(cam)
	return [rig, cam]


func test_zoom_pivot_identity_at_rest() -> void:
	# offset = P * (1 - 1/z) must be ZERO at z=1 for any pivot — the rig at rest is an identity transform
	var pair := _rig_with_cam()
	var rig: Node = pair[0]
	var cam: Camera2D = pair[1]
	rig._apply_zoom(1.0, Vector2(640, 360))
	assert_eq(cam.offset, Vector2.ZERO, "z=1 must produce zero offset at any pivot")
	assert_eq(cam.zoom, Vector2.ONE, "z=1 leaves zoom at identity")


func test_zoom_pivot_math() -> void:
	var pair := _rig_with_cam()
	var rig: Node = pair[0]
	var cam: Camera2D = pair[1]
	var pivot := Vector2(640, 360)
	rig._apply_zoom(1.04, pivot)
	var expected := pivot * (1.0 - 1.0 / 1.04)
	assert_almost_eq(cam.offset.x, expected.x, 0.01, "FIXED_TOP_LEFT pivot math: offset = P*(1-1/z)")
	assert_almost_eq(cam.offset.y, expected.y, 0.01, "FIXED_TOP_LEFT pivot math: offset = P*(1-1/z)")


func test_zoom_floor_and_ceiling_pinned() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleCameraRig.gd")
	assert_gt(src.length(), 500, "CONTROL: read a real file")
	assert_true("clampf(1.0 + strength, 1.0, ZOOM_CEILING)" in src, "zoom clamped: floor 1.0 (never zoom out), ceiling const")
	assert_true("ZOOM_CEILING := 1.04" in src, "Phase-A ceiling 1.04 — raise only after A2 CanvasLayer migration")
	assert_true("ROTATION_MAX := 0.0" in src, "rotation stays 0 pre-A2 (would rotate UI text on the shared canvas)")


func test_trauma_respects_shake_setting_and_decays() -> void:
	var pair := _rig_with_cam()
	var rig: Node = pair[0]
	var prev: bool = GameState.screen_shake_enabled
	GameState.screen_shake_enabled = false
	rig.add_trauma(1.0)
	assert_eq(rig._trauma, 0.0, "shake setting OFF blocks trauma entirely")
	GameState.screen_shake_enabled = true
	rig.add_trauma(0.5)
	assert_eq(rig._trauma, 0.5, "trauma accumulates when enabled")
	rig._process(0.1)
	assert_lt(rig._trauma, 0.5, "trauma decays over time")
	GameState.screen_shake_enabled = prev


func test_reset_restores_camera() -> void:
	var pair := _rig_with_cam()
	var rig: Node = pair[0]
	var cam: Camera2D = pair[1]
	rig.add_trauma(1.0)
	rig._apply_zoom(1.04, Vector2(100, 100))
	rig.reset()
	assert_eq(cam.zoom, Vector2.ONE, "reset restores identity zoom")
	assert_eq(cam.offset, Vector2.ZERO, "reset restores zero offset")
	assert_eq(rig._trauma, 0.0, "reset clears trauma")
