extends GutTest

## Staged-kit `shake` step — a CT-style shudder (fear, cold, laughter) on a puppet. Jitters the
## SPRITE's offset, never the actor's position, so a walk in flight is not fought; self-clears;
## instant no-op off-tree (spine-walker safety). The Director holds through _sleep like every
## other timed beat, so a skip cuts it the same frame and a held confirm runs it faster, and the
## sprite is put back the moment the hold releases — not at the tween's own time.

const DirectorScript = preload("res://src/cutscene/CutsceneDirector.gd")

var _d: Node


func before_each() -> void:
	Input.action_release("ui_accept")
	_d = DirectorScript.new()
	add_child_autofree(_d)
	_d._skipping = false


func after_each() -> void:
	Input.action_release("ui_accept")
	if _d and is_instance_valid(_d):
		_d._active = false


func _puppet(id: String) -> CutsceneActor:
	var a := CutsceneActor.build(id, {"kind": "npc", "archetype": "old_man"})
	add_child_autofree(a)
	_d._actors[id] = a
	return a


func _start(step: Dictionary) -> Array:
	var done := [false]
	var runner := func() -> void:
		await _d._execute_step(step)
		done[0] = true
	runner.call()
	return done


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _until(done: Array, budget: int) -> void:
	var n := 0
	while not done[0] and n < budget:
		await get_tree().process_frame
		n += 1


func test_shake_off_tree_is_an_instant_noop() -> void:
	var a := CutsceneActor.build("x", {"kind": "npc", "archetype": "old_man"})
	a.shake(1.0, 3.0)
	assert_false(a.is_shaking(), "off-tree (headless spine walk) a shake starts nothing")
	a.free()


func test_shake_jitters_the_sprite_and_puts_it_back() -> void:
	var a := _puppet("m")
	var pos := a.position
	a.shake(0.3, 4.0)
	await _frames(2)
	assert_true(a.is_shaking(), "control: the shudder is in flight")
	assert_eq(a.position, pos, "the actor's position is never touched — only the sprite jitters")
	var n := 0
	while a.is_shaking() and n < 60:
		await get_tree().process_frame
		n += 1
	assert_false(a.is_shaking(), "it self-clears")
	assert_eq(a._sprite.offset, Vector2.ZERO, "and the sprite lands back exactly where it was")
	assert_eq(a.position, pos)


func test_the_step_holds_then_releases_with_the_sprite_restored() -> void:
	var a := _puppet("m")
	var done := _start({"type": "shake", "id": "m", "duration": 0.3})
	await _frames(2)
	assert_false(done[0], "control: the step holds for the shudder")
	assert_true(a.is_shaking())
	await _until(done, 60)
	assert_true(done[0], "the step releases after its duration")
	assert_eq(a._sprite.offset, Vector2.ZERO)


func test_a_skip_cuts_the_shake_the_same_frame() -> void:
	var a := _puppet("m")
	var done := _start({"type": "shake", "id": "m", "duration": 30.0})
	await _frames(2)
	assert_false(done[0], "control: a 30s shudder is in flight")
	_d._skipping = true
	await _frames(4)
	assert_true(done[0], "a skip releases the step within a few frames, not after 30s")
	assert_false(a.is_shaking(), "and ends the shudder")
	assert_eq(a._sprite.offset, Vector2.ZERO, "with the sprite put back")


func test_wait_false_returns_while_the_shudder_continues() -> void:
	var a := _puppet("m")
	var done := _start({"type": "shake", "id": "m", "duration": 1.0, "wait": false})
	await _frames(1)
	assert_true(done[0], "wait:false lets the scene move on under the shudder")
	assert_true(a.is_shaking(), "which is still running")
	a.stop_shake()


func test_an_unknown_actor_resolves_instantly() -> void:
	var done := _start({"type": "shake", "id": "nobody", "duration": 5.0})
	await _frames(1)
	assert_true(done[0], "headless contract: a missing target never holds the scene")


func test_dispatch_has_the_shake_arm() -> void:
	var src := FileAccess.get_file_as_string("res://src/cutscene/CutsceneDirector.gd")
	assert_true(src.contains("\"shake\":\n\t\t\tawait _step_shake(step)"), "the step must be dispatched, or every authored shake hits the Unknown-step warning")
