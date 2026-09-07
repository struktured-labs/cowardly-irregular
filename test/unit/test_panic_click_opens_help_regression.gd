extends GutTest

## struktured 2026-08-25: "what about 'panicky mouse' buttons auto popping it up too".
##
## Context: he wedged on the victory screen and reported "r mouse click sorta worked but
## enetered the settinsg menu instead and I couldnt escape". He was clicking because nothing
## was responding — the game had the evidence and did nothing with it.
##
## The discriminator is free and needs no heuristic: _unhandled_input receives ONLY events no
## other node consumed, so a click arriving there is BY DEFINITION a click that did nothing.
## Fast clicking through dialogue, a shop, or the grid editor is handled and never counts.

const GL := "res://src/GameLoop.gd"


func _fn_body(src: String, fn: String) -> String:
	var i := src.find("func " + fn)
	assert_gt(i, -1, fn + " present")
	var next := src.find("\nfunc ", i + 1)
	return src.substr(i, (next - i) if next > -1 else -1)


## The mechanism must live in _unhandled_input specifically. In _input it would see EVERY
## click — including handled ones — and fire while the player is happily clicking through a
## menu, which is the false positive the whole design avoids.
func test_it_counts_only_clicks_nothing_answered() -> void:
	var src := FileAccess.get_file_as_string(GL)
	assert_gt(src.find("func _unhandled_input"), -1,
		"the counter must live in _unhandled_input — in _input it cannot tell a stuck player from a fast one")
	var body := _fn_body(src, "_unhandled_input")
	assert_true(body.contains("InputEventMouseButton"), "it watches mouse clicks")
	assert_true(body.contains("_toggle_help_overlay"), "and opens the reference")


## Sliding window, not a running total: 4 clicks spread over a minute is ordinary play.
func test_the_window_slides_so_slow_clicking_never_triggers() -> void:
	var body := _fn_body(FileAccess.get_file_as_string(GL), "_unhandled_input")
	assert_true(body.contains("PANIC_CLICK_WINDOW_S"), "old clicks must age out of the window")
	assert_true(body.contains("remove_at(0)"), "the window slides from the front")
	var src := FileAccess.get_file_as_string(GL)
	var n := int(src.substr(src.find("PANIC_CLICK_COUNT: int = ") + 25, 3).strip_edges())
	assert_gt(n, 1, "one stray unanswered click must not pop a full-screen overlay, got %d" % n)
	assert_lt(n, 10, "and the threshold must be reachable by a real frustrated person, got %d" % n)


## If the reference is already up, clicks on it must not re-enter the toggle — that would
## CLOSE the thing the player just asked for, which is worse than doing nothing.
func test_it_does_not_fire_while_the_reference_is_already_open() -> void:
	var body := _fn_body(FileAccess.get_file_as_string(GL), "_unhandled_input")
	var guard := body.find("_help_overlay and is_instance_valid(_help_overlay)")
	var toggle := body.find("_toggle_help_overlay")
	assert_gt(guard, -1, "an already-open reference must short-circuit")
	assert_lt(guard, toggle, "and the check precedes the toggle, or the overlay closes itself")


## The counter resets on fire. Without this the next single click re-opens it, because the
## window would still hold the four that triggered.
func test_the_counter_clears_after_firing() -> void:
	var body := _fn_body(FileAccess.get_file_as_string(GL), "_unhandled_input")
	var clear := body.find("_panic_clicks.clear()")
	var toggle := body.find("_toggle_help_overlay")
	assert_gt(clear, -1, "the window clears when it fires")
	assert_lt(clear, toggle, "before opening, so a re-entrant toggle cannot see a full window")
