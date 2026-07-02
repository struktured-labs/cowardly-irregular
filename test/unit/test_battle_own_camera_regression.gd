extends GutTest

## Live playtest 2026-07-02: cave battle rendered offset RIGHT — the
## backdrop + party + enemies + menu all shifted so the party column
## clipped off the right edge of the window. Root cause: BattleScene
## has no Camera2D in .tscn, so the viewport kept using whatever was
## current before — the OverworldPlayer's Camera2D at the player's
## cave-world coordinates. Fix: BattleScene installs its own camera
## at (0,0) and calls make_current() so no foreign camera can win.


func test_battle_scene_installs_its_own_camera() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_true(src.contains("Camera2D.new()"),
		"BattleScene must instantiate its own camera")
	assert_true(src.contains("_battle_cam.make_current()"),
		"the camera must call make_current() so a stale foreign camera can't win the viewport")
	assert_true(src.contains("_battle_cam.position = Vector2.ZERO"),
		"battle content is authored around origin — camera must sit at (0,0)")
	assert_true(src.contains("ANCHOR_MODE_FIXED_TOP_LEFT"),
		"camera must anchor top-left: DRAG_CENTER at (0,0) shifted the WHOLE battle (UI incl.) by half the viewport — 19:39 cap")
