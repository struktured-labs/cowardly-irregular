extends GutTest

## The staged kit's `say` step: a CT-style line in a bubble over a puppet's head, for
## asides while the scene keeps moving. Pins: the bubble carries the text and sits ABOVE
## the head (not on the body, not below), clears itself after `duration`, `wait: false`
## returns without blocking, and a skipping director never spawns one (skip-snap parity
## with emote/hop). Registered in the schema audit and the actor-id ratchet alongside.

const ActorScript = preload("res://src/cutscene/CutsceneActor.gd")
const DirectorScript = preload("res://src/cutscene/CutsceneDirector.gd")


func _actor() -> Node2D:
	var a: Node2D = ActorScript.new()
	add_child_autofree(a)
	return a


func test_say_builds_a_bubble_with_the_text_above_the_head() -> void:
	var a := _actor()
	a.say("Not laziness. Enlightenment.", 0.0)
	assert_not_null(a._bubble, "say must create a bubble")
	var label: Label = a._bubble.get_child(0) as Label
	assert_not_null(label)
	assert_eq(label.text, "Not laziness. Enlightenment.")
	assert_true(a._bubble.position.y + a._bubble.size.y < 0.0,
		"the bubble's bottom edge must sit above the actor origin (head), got y=%s h=%s" % [a._bubble.position.y, a._bubble.size.y])
	assert_true(a._bubble.size.x <= ActorScript.BUBBLE_MAX_WIDTH + 16.0,
		"long lines must wrap inside BUBBLE_MAX_WIDTH, got width %s" % a._bubble.size.x)


func test_say_replaces_a_previous_bubble_and_clears_after_duration() -> void:
	var a := _actor()
	a.say("first", 0.0)
	var first = a._bubble
	a.say("second", 0.2)
	assert_ne(a._bubble, first, "a new line replaces the old bubble instead of stacking")
	await get_tree().create_timer(0.45).timeout
	assert_null(a._bubble, "the bubble must clear itself after `duration`")


func test_director_say_step_honours_wait_false_and_skip() -> void:
	var d: Node = DirectorScript.new()
	add_child_autofree(d)
	var a := _actor()
	d._actors["milo"] = a
	# wait:false — returns without blocking, bubble is up
	d._skipping = false
	d._step_say({"type": "say", "id": "milo", "text": "quick aside", "duration": 5.0, "wait": false})
	assert_not_null(a._bubble, "wait:false must still show the bubble")
	a.clear_bubble()
	# skipping — no bubble at all (parity with emote/hop)
	d._skipping = true
	d._step_say({"type": "say", "id": "milo", "text": "never shown", "duration": 1.0})
	assert_null(a._bubble, "a skipping director must not spawn bubbles")
	# unknown actor — no crash, no bubble
	d._skipping = false
	d._step_say({"type": "say", "id": "nobody", "text": "x"})
	assert_null(a._bubble)


func test_say_is_dispatched_by_execute_step() -> void:
	var src := FileAccess.get_file_as_string("res://src/cutscene/CutsceneDirector.gd")
	var fn := src.find("func _execute_step")
	var body := src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_true(body.contains("\"say\":"), "the match must carry a \"say\" arm — otherwise authored steps hit the unknown-type warning")
	assert_true(body.contains("_step_say("), "the arm must call _step_say")
