extends GutTest

## A stranded LLM NPC conversation used to be a FORCE-QUIT, and the file that documented the strand
## said the overworld menu was the way out. It is not: the menu's gate reads
## InputLockManager.is_locked(), and a thinking dialogue box heartbeats its field lock every frame in
## _process, so the stale reaper can never expire it. Driven before the fix: is_locked() stayed true
## past the reaper's timeout indefinitely while the box kept beating.
##
## Two exits now, because the player must not have to know the trick:
##   1. the box stops blocking the field once a thinking state outlives THINKING_BLOCK_MAX_MS
##   2. cancel on a thinking box emits thinking_cancelled, wired to DynamicConversation.abort()

const CD := preload("res://src/cutscene/CutsceneDialogue.gd")

var _box: Node = null
var _saved_locks: Dictionary = {}


func before_each() -> void:
	_saved_locks = InputLockManager._locks.duplicate()
	InputLockManager._locks.clear()


func after_each() -> void:
	if _box != null and is_instance_valid(_box):
		_box.queue_free()
	_box = null
	InputLockManager._locks.clear()
	InputLockManager._locks.merge(_saved_locks)


## A box mid-thought, exactly as DynamicConversation leaves it before every LLM await.
func _thinking_box() -> Node:
	var box = CD.new()
	add_child_autofree(box)
	await get_tree().process_frame
	box.show_dialogue([{"speaker": "Elder Theron", "text": "Dark days."}])
	await get_tree().process_frame
	box.set_thinking(true)
	await get_tree().process_frame
	return box


## Spin until the lowered bound has genuinely elapsed, so the arm tests the BOUND and not a race.
func _elapse(box: Node) -> void:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 <= box.thinking_block_max_ms + 5:
		await get_tree().process_frame


func test_a_thinking_box_blocks_the_field_while_it_is_thinking() -> void:
	## CONTROL: the whole point of the lock. If this stops holding, the fix broke normal dialogue.
	_box = await _thinking_box()
	assert_true(_box.is_thinking(), "CONTROL: the box must be thinking")
	assert_true(_box._conversation_blocks_field(),
		"a box mid-thought must block the field, or a player walks off during an LLM reply")


func test_a_thinking_state_that_outlives_its_bound_stops_blocking() -> void:
	_box = await _thinking_box()
	assert_true(_box._conversation_blocks_field(), "CONTROL: blocking before the bound elapses")
	## Lower the bound instead of back-dating the stamp: ticks start near zero in a fresh process,
	## so subtracting 15s yields a NEGATIVE stamp that the started-yet guard rejects — measured.
	_box.thinking_block_max_ms = 10
	await _elapse(_box)
	assert_false(_box._conversation_blocks_field(),
		"a thinking state older than THINKING_BLOCK_MAX_MS still blocks the field, so its heartbeat keeps the lock alive and the player cannot reach the menu")


func test_the_heartbeat_stops_so_the_reaper_can_free_the_lock() -> void:
	## The consequence that matters: with the heartbeat stopped, is_locked() goes false and the
	## overworld menu's gate opens. Driven through _process and the real reaper.
	_box = await _thinking_box()
	await get_tree().process_frame
	assert_true(InputLockManager.is_locked(), "CONTROL: the thinking box must hold a field lock")
	_box.thinking_block_max_ms = 10
	await _elapse(_box)
	await get_tree().process_frame
	for id in InputLockManager._locks.keys():
		InputLockManager._locks[id] = Time.get_ticks_msec() - (InputLockManager.STALE_TIMEOUT_MS + 500)
	await get_tree().process_frame
	assert_false(InputLockManager.is_locked(),
		"the lock survived its own reaper because _process kept beating it — this is the force-quit")


func test_cancel_on_a_thinking_box_asks_the_owner_to_abort() -> void:
	_box = await _thinking_box()
	var fired: Array = []
	_box.thinking_cancelled.connect(func(): fired.append(true))
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	_box._input(ev)
	assert_eq(fired.size(), 1, "cancel while thinking must ask the owner to abort, not be swallowed")
	assert_false(_box.is_thinking(), "cancel must drop the thinking state so the heartbeat stops")


func test_the_owner_wires_cancel_to_abort() -> void:
	## The wiring, read from source: without it the signal is a no-op and the player still cannot
	## escape. Driving a whole conversation needs a live LLM, so this pins the connection.
	var src: String = FileAccess.get_file_as_string("res://src/llm/DynamicConversation.gd")
	assert_ne(src, "", "CONTROL: the owner must be readable")
	assert_true(src.contains("thinking_cancelled.connect(abort)"),
		"DynamicConversation must abort when the box reports a cancel, or the escape goes nowhere")
	var wrapper: String = FileAccess.get_file_as_string("res://src/cutscene/NPCDialogue.gd")
	assert_true(wrapper.contains("thinking_cancelled"),
		"NPCDialogue must forward the box's cancel, or the owner never hears it")
