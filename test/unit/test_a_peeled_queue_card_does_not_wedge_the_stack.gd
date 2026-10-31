extends GutTest

## Regression (struktured's 2026-10-05 play log): 20 "Invalid type in function '_peel'/'_pop' ... (previously freed)" plus
## freed 'modulate'/'find_child' errors from AdvanceQueueCards. run_step freed each fired card but kept it in _cards, so
## run_end handed a freed card to the typed _peel(card: Control), which aborted before clearing the stack; every later
## show_queue/run_step/_light then hit the dead cards. A freed card is now skipped and the stack always clears.


func _cards_node() -> AdvanceQueueCards:
	var c := AdvanceQueueCards.new()
	add_child_autofree(c)
	return c


func _actions(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({"type": "attack"})
	return out


func test_a_run_whose_fired_cards_are_gone_still_ends_clean() -> void:
	var c := _cards_node()
	var acts := _actions(3)
	c.run_begin(acts, Rect2(400, 300, 100, 100), false)
	assert_eq(c.card_count(), 3, "SCOPE: the run laid out one card per queued action")
	c.run_step([], false)
	await get_tree().process_frame
	c.run_end(false)
	assert_eq(c.card_count(), 0, "run_end must clear the stack even when a fired card is already freed")


func test_the_next_queue_builds_after_a_run_with_freed_cards() -> void:
	var c := _cards_node()
	c.run_begin(_actions(2), Rect2(400, 300, 100, 100), false)
	c.run_step([], false)
	await get_tree().process_frame
	c.show_queue([{"id": "attack", "data": {}}], Rect2(400, 300, 100, 100), null, false)
	assert_eq(c.card_count(), 1, "a fresh queue must build after a run whose fired cards were freed")
	assert_ne(c.card_text(0), "", "the new card is live and readable")


func test_a_step_after_a_freed_card_lights_the_next_live_one() -> void:
	var c := _cards_node()
	c.run_begin(_actions(3), Rect2(400, 300, 100, 100), false)
	c.run_step([], false)
	await get_tree().process_frame
	c.run_step([], false)
	await get_tree().process_frame
	assert_true(c.is_running(), "SCOPE: one step is still to fire")
	c.run_end(false)
	assert_eq(c.card_count(), 0, "the run still ends clean after two freed steps")

## ⛔ THE THREE ARMS ABOVE PASS `animate: false` IN ALL SIX CALLS, AND THAT IS WHY THE SAME 20
## ABORTS CAME BACK IN HIS 2026-10-12 SESSION A WEEK AFTER THIS FILE DECLARED THEM FIXED.
## `_peel`'s two paths free the card at different TIMES: `not animate` calls `queue_free()`
## synchronously, while the animated path defers it through a tween 0.43 s out (0.25 interval +
## 0.18 fade). The arms above drive the synchronous one. `BattleScene._queue_cards_animate()`
## returns `Engine.time_scale < 4.0 and not turbo_mode`, so the DEFERRED path is what every
## player gets at normal speed and the synchronous one only happens at 4x or in turbo.
## A guard named for a defect, green on its rare branch while the shipped branch kept failing.
##
## These arms assert the MECHANISM rather than the abort: with the free deferred the card is still
## valid for 0.43 s, so no short test can observe the crash. What makes the crash impossible is
## that a peeled slot is vacated at peel time, and that is what is pinned here.
func test_an_animated_peel_vacates_its_slot() -> void:
	var c := _cards_node()
	c.run_begin(_actions(3), Rect2(400, 300, 100, 100), true)
	assert_eq(c.card_count(), 3, "SCOPE: three cards laid out on the animated path")
	c.run_step([], true)
	assert_eq(c._cards.size(), 3, "CONTROL: the slot is vacated, not removed — _run_index indexes this array")
	assert_null(c._cards[0], "the peeled slot must be null: its free is 0.43s out and run_end would hand it back to _peel")
	assert_true(is_instance_valid(c._cards[1]), "CONTROL: an unpeeled slot still holds a live card")


func test_run_end_on_the_animated_path_clears_the_stack() -> void:
	var c := _cards_node()
	c.run_begin(_actions(3), Rect2(400, 300, 100, 100), true)
	c.run_step([], true)
	c.run_end(true)
	assert_eq(c.card_count(), 0, "run_end must clear the stack on the path players actually get")


func test_the_synchronous_path_vacates_its_slot_too() -> void:
	## The fix must not be animated-only: the 4x/turbo path lands in the same consumers.
	var c := _cards_node()
	c.run_begin(_actions(2), Rect2(400, 300, 100, 100), false)
	c.run_step([], false)
	assert_null(c._cards[0], "the synchronous peel must vacate its slot as well")
