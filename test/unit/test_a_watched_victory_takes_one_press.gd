extends GutTest

## Regression (cowir-main's .594 victory frames): VictoryOverlay only became complete through complete_now(), the
## skip-press. A cascade watched to its end stayed "incomplete", so GameLoop's first accept press "finished" nothing and
## continuing took a second press, while the prompt still offered "finish". Settling naturally now completes it.

const OverlayScript = preload("res://src/battle/VictoryOverlay.gd")


func _overlay() -> Control:
	var cr: Array = [{"name": "Cleric", "job_name": "cleric", "is_alive": true, "exp_gained": 10, "job_exp_before": 0,
		"exp_to_next": 100, "leveled_up": false, "job_level": 2, "job_exp": 0}]
	var o = OverlayScript.new()
	add_child_autofree(o)
	o.build({"char_results": cr, "total_gold": 5, "item_drops": [], "bonuses": [], "injuries": []}, null)
	return o


func _wait_settled(o: Control, max_s: float = 20.0) -> void:
	var t0 := Time.get_ticks_msec()
	while not o.is_complete() and Time.get_ticks_msec() - t0 < int(max_s * 1000.0):
		await get_tree().process_frame


func test_a_cascade_watched_to_its_end_is_complete() -> void:
	var o := _overlay()
	assert_false(o.is_complete(), "SCOPE: the cascade starts running")
	await _wait_settled(o)
	assert_true(o.is_complete(), "watching the cascade to its end must complete it, so ONE press continues")


func test_the_settled_prompt_offers_only_continue() -> void:
	var o := _overlay()
	await _wait_settled(o)
	var prompt: Label = null
	for c in o.get_children():
		if c is Label and str(c.text).contains("continue"):
			prompt = c
	assert_not_null(prompt, "SCOPE: the overlay shows its continue prompt")
	if prompt:
		assert_false(str(prompt.text).contains("finish"), "a settled overlay must not offer to finish: %s" % prompt.text)


func test_a_fresh_cascade_is_not_complete_yet() -> void:
	var o := _overlay()
	await get_tree().process_frame
	assert_false(o.is_complete(), "CONTROL: a cascade that just started still takes a skip press")
