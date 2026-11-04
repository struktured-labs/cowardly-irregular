extends GutTest
## The Debug log panel showed bottom-left in a --demo run (2026-11-03). Dev runs keep it.
const O = preload("res://src/ui/DebugLogOverlay.gd")

func test_dev_run_shows() -> void:
	assert_true(O.dev_run(PackedStringArray([]), true))

func test_demo_hides() -> void:
	assert_false(O.dev_run(PackedStringArray(["--demo"]), true))

func test_release_build_hides() -> void:
	assert_false(O.dev_run(PackedStringArray([]), false))
