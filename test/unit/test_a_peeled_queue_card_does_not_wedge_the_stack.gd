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
