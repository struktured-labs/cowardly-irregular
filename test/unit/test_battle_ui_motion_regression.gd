extends GutTest

## Phase D of the battle-feel plan: menus that MOVE make choosing feel good — most of a
## turn-based game's runtime is spent in the command menu, not watching hits land.
##
## The load-bearing constraint is the CLOSE path: msg-2503's two-menus identity bug means
## the logical close (active_win98_menu = null + signal emission) must stay SYNCHRONOUS.
## Only the open is animated; a deferred free would let a stale instance answer for the
## live one. This file pins that asymmetry so a future "let's animate the close too"
## can't silently reintroduce it.

func _menu_src() -> String:
	return FileAccess.get_file_as_string("res://src/battle/BattleCommandMenu.gd")


func test_open_is_animated_and_tier_gated() -> void:
	var src := _menu_src()
	assert_gt(src.length(), 1000, "CONTROL: read a real file")
	var i := src.find("func _animate_menu_open")
	assert_gt(i, -1, "open animation helper must exist")
	var fn_end := src.find("\nfunc ", i + 1)
	var body := src.substr(i, (fn_end - i) if fn_end > -1 else 1200)
	assert_true("battle_tier()" in body, "must gate on battle_tier() — presentation_tier() with no args asserts 'not turbo, not grinding' and animates through both")
	assert_true('flag("menu_motion")' in body, "respects the per-feature toggle")
	assert_true("is_instance_valid(menu)" in body, "validity-guarded — menus are freed aggressively")


func test_close_path_stays_synchronous() -> void:
	# The regression this guards: animating the close would defer the free, and a stale
	# instance could answer for the live one (msg-2503).
	var src := _menu_src()
	var i := src.find("func close_win98_menu")
	assert_gt(i, -1, "close_win98_menu must exist")
	var fn_end := src.find("\nfunc ", i + 1)
	var body := src.substr(i, (fn_end - i) if fn_end > -1 else 2000)
	assert_false("_animate_menu_open" in body, "close must NOT route through the open animation")
	assert_false("tween_property" in body, "close performs no tweening — it stays synchronous")


func test_ctb_queue_is_extracted_and_pure() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleUIManager.gd")
	var i := src.find("func _compute_ctb_queue")
	assert_gt(i, -1, "queue build extracted into its own function (testable without a scene)")
	var fn_end := src.find("\nfunc ", i + 1)
	var body := src.substr(i, (fn_end - i) if fn_end > -1 else 1600)
	assert_true("execution_order" in body, "EXECUTION phase shows pending speed-sorted actions")
	assert_true("selection_order" in body, "SELECTION phase shows who selects next")
	assert_false("add_child" in body, "pure: builds no nodes")
	assert_false("create_tween" in body, "pure: animates nothing")


func test_ctb_pulse_fires_on_head_change_only() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleUIManager.gd")
	var i := src.find("func _animate_ctb_rows")
	assert_gt(i, -1, "row animation helper must exist")
	var fn_end := src.find("\nfunc ", i + 1)
	var body := src.substr(i, (fn_end - i) if fn_end > -1 else 1600)
	assert_true("_ctb_last_head_id" in body, "tracks the head so the pulse fires on ARRIVAL, not every repaint")
	assert_true("battle_tier()" in body, "must gate on battle_tier() — the no-arg form is blind to turbo/autogrind")
	assert_true("row.create_tween()" in body, "tweens are owned by the Control — BattleUIManager is not a Node")


func test_target_highlight_pulse_is_single_and_killed_on_hide() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")
	var i := src.find("func _start_target_pulse")
	assert_gt(i, -1, "pulse helper must exist")
	var fn_end := src.find("\nfunc ", i + 1)
	var body := src.substr(i, (fn_end - i) if fn_end > -1 else 1200)
	assert_true("is_valid()" in body and "return" in body, "re-entry guard: one looping tween, not one per selection change")
	assert_true("set_loops()" in body, "breathing loop")
	var c := src.find("func _cleanup_target_highlight")
	var c_end := src.find("\nfunc ", c + 1)
	var cbody := src.substr(c, (c_end - c) if c_end > -1 else 900)
	assert_true("_target_pulse_tween" in cbody and "kill()" in cbody, "pulse killed on hide — a loop outliving its node leaks")


func test_new_flags_are_registered_in_the_toggle_menu() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/SettingsMenu.gd")
	for f in ["menu_motion", "ctb_motion", "target_pulse"]:
		assert_true('"%s"' % f in src, "%s is toggleable in the Battle FX menu" % f)
