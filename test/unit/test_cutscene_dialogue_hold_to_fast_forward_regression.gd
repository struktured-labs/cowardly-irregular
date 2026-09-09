extends GutTest

## Hold-confirm fast-forward on the dialogue box (every JRPG's "hold A to blow through text").
## CutsceneDirector declared a `_fast_forward` flag that nothing ever set or read, so the
## intent existed with no outcome: a tap advanced one line, and the only way past a long
## exchange was hold-B skip, which throws the whole scene away. Now: after HOLD_SEC the
## typewriter finishes and lines advance every LINE_SEC while confirm stays held. A tap
## still advances exactly one line; the LLM thinking guard and a fresh box reset the hold.

const DialogueScript = preload("res://src/cutscene/CutsceneDialogue.gd")

var _box: Node


func before_each() -> void:
	Input.action_release("ui_accept")
	_box = DialogueScript.new()
	add_child_autofree(_box)


func after_each() -> void:
	Input.action_release("ui_accept")  # the Input singleton leaks across tests


func _lines(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({"speaker": "", "text": "line %d of a long exchange" % i, "theme": "narrator", "portrait": "narrator"})
	return out


func _tick(times: int, dt: float = 0.1) -> void:
	for i in times:
		_box._process(dt)


func test_holding_confirm_fast_forwards_through_the_exchange() -> void:
	_box.show_dialogue(_lines(5))
	Input.action_press("ui_accept")
	_tick(5)  # 0.5s: the hold threshold
	_tick(1)  # first held tick past the threshold finishes any typewriter
	assert_false(_box._is_typing, "past the hold threshold the typewriter must be finished")
	assert_eq(_box._current_index, 0, "finishing the typewriter is not yet an advance")
	_tick(3)  # 0.3s held: one LINE_SEC elapsed
	assert_gte(_box._current_index, 1, "held confirm must advance a line every LINE_SEC")
	_tick(40)  # plenty to run out the remaining lines
	assert_false(_box.visible, "held confirm must run the exchange to its end and close the box")


func test_a_tap_still_advances_one_line_only() -> void:
	# ARM+: a fast-forward that ignored the hold threshold would blow through on a tap.
	_box.show_dialogue(_lines(5))
	Input.action_press("ui_accept")
	_tick(4)  # 0.4s < HOLD_SEC
	assert_eq(_box._current_index, 0, "below the hold threshold _process must not advance anything")
	Input.action_release("ui_accept")
	_tick(10)
	assert_eq(_box._current_index, 0, "released confirm must never advance")
	assert_true(_box.visible)


func test_thinking_guard_blocks_fast_forward() -> void:
	_box.show_dialogue(_lines(5))
	_box.set_thinking(true)
	Input.action_press("ui_accept")
	_tick(20)
	assert_eq(_box._current_index, 0, "while the LLM thinking indicator is up, a held confirm must not advance")
	_box.set_thinking(false)


func test_a_new_box_resets_the_hold() -> void:
	_box.show_dialogue(_lines(5))
	Input.action_press("ui_accept")
	_tick(9)  # fast-forward engaged
	assert_gte(_box._current_index, 1, "control: fast-forward engaged on the first box")
	_box.show_dialogue(_lines(5))  # next NPC opens while the button is still down
	_tick(4)  # 0.4s < HOLD_SEC again
	assert_eq(_box._current_index, 0, "a button still held from the last box must not blow through the next one")
