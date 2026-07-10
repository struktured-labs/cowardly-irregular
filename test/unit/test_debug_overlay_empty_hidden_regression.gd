extends GutTest

## Web-smoke finding #2 (2026-07-10): the debug overlay painted its empty
## gray panel over every player's screen — visibility tracked _enabled only,
## ignoring whether any lines existed. Now: visible = enabled AND non-empty,
## re-evaluated on add and on expiry.

func test_empty_overlay_hides_its_panel() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/DebugLogOverlay.gd")
	var i := src.find("func _update_visibility")
	var body := src.substr(i, 500)
	assert_true("_logs.size() > 0" in body,
		"visibility must require lines — the empty gray box class")
	# expiry AND add paths both re-evaluate
	assert_gt(src.count("_update_visibility()"), 3,
		"visibility re-evaluated on add + expiry, not just toggle")
