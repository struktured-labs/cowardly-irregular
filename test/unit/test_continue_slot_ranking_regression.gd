extends GutTest

## get_most_recent_slot ranked purely on save_time with no validity check, so a 2.5KB partyless
## autosave outranked struktured's real 36KB save by 4.7 days and Continue loaded an empty game
## (2026-08-22). Asserts the RELATIONSHIP — resumable beats newer — never a slot number.

const SS = preload("res://src/save/SaveSystem.gd")


func _c(slot: int, save_time: float, resumable: bool) -> Dictionary:
	return {"slot": slot, "save_time": save_time, "resumable": resumable}


func test_a_newer_shell_does_not_outrank_an_older_real_save() -> void:
	var picked = SS.rank_resumable_slots([
		_c(7, 2000.0, false),
		_c(3, 1000.0, true),
	])
	assert_eq(picked, 3, "A partyless shell must not win on recency over a resumable save")


func test_among_resumable_slots_the_newest_still_wins() -> void:
	var picked = SS.rank_resumable_slots([
		_c(3, 1000.0, true),
		_c(7, 2000.0, true),
	])
	assert_eq(picked, 7, "ARM+: recency must still decide between two resumable saves")


func test_all_shells_resolve_to_no_slot() -> void:
	var picked = SS.rank_resumable_slots([
		_c(7, 2000.0, false),
		_c(3, 1000.0, false),
	])
	assert_eq(picked, -1, "With nothing resumable there is no Continue target")


func test_no_candidates_resolve_to_no_slot() -> void:
	assert_eq(SS.rank_resumable_slots([]), -1, "No saves means no Continue target")


func test_ordering_is_independent_of_candidate_order() -> void:
	var forward = SS.rank_resumable_slots([_c(1, 500.0, true), _c(2, 900.0, true), _c(9, 9999.0, false)])
	var reverse = SS.rank_resumable_slots([_c(9, 9999.0, false), _c(2, 900.0, true), _c(1, 500.0, true)])
	assert_eq(forward, reverse, "The winner must not depend on the order slots were collected")
	assert_eq(forward, 2, "The newest resumable slot wins from either direction")


func test_a_zero_save_time_resumable_slot_still_beats_nothing() -> void:
	## Regression guard: a >0.0 seed would silently discard a legitimate save stamped 0.
	assert_eq(SS.rank_resumable_slots([_c(4, 0.0, true)]), 4,
		"A resumable slot with save_time 0 is still a valid Continue target")
