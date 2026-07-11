extends GutTest

## Advance escalation ladder (struktured-approved via cowir-sfx/story,
## 2026-07-11; fighter pilot). Each Advance press plays
## advance_<job>_<depth 1..3> when the manifest has it; every other job
## falls back to the arcade credit. Depth = queue size AFTER the press.

func test_ladder_keys_exist_for_fighter() -> void:
	for i in [1, 2, 3]:
		assert_true(SoundManager._sfx_manifest.has("advance_fighter_%d" % i),
			"fighter tier %d must be in the manifest" % i)


func test_win98_menu_wires_depth_and_fallback() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")
	assert_true("func _play_advance_sound(depth: int = 1)" in src, "depth param")
	assert_true("advance_%s_%d" in src, "per-job key format")
	assert_true("clampi(depth, 1, 3)" in src, "depth clamped to authored tiers")
	var fn := src.substr(src.find("func _play_advance_sound"))
	assert_true("play_battle(\"advance_queue\")" in fn.substr(0, 600),
		"unknown job/tier must fall back to the arcade credit")
	assert_true("_play_advance_sound(root._queued_actions.size())" in src,
		"queue caller passes post-press depth")
	assert_true("_play_advance_sound(root._queued_actions.size() + 1)" in src,
		"auto-submit caller passes post-press depth (append happens later on that path)")
