extends GutTest

## `BattleTransition._await_tween_safe` exists for the 2026-09-06 spider wedge — a tween whose
## targets are freed mid-flight never emits `finished`. Its own comment says so. Its condition was
## `is_running()`, which is blind to exactly that death.
##
## Engine facts, measured rather than reasoned (2026-09-18):
##     freed target : is_running TRUE   is_valid FALSE   <- the wedge case
##     killed       : is_running FALSE  is_valid FALSE
##     live         : is_running TRUE   is_valid TRUE    <- control: the fix cannot shorten this
##     finished     : is_running FALSE  is_valid TRUE    <- control: already exited on is_running
##
## Not a wedge — the 6 s ceiling always terminated it — but six seconds of frozen transition on the
## one path the helper was written to protect.

const BT_SRC := "res://src/transitions/BattleTransition.gd"


func test_the_wait_condition_checks_validity_not_just_running() -> void:
	var src: String = FileAccess.get_file_as_string(BT_SRC)
	assert_ne(src, "", "CONTROL: BattleTransition.gd must be readable")
	var at: int = src.find("func _await_tween_safe")
	assert_gt(at, -1, "CONTROL: _await_tween_safe must exist to be pinned")
	var after: int = src.find("\nfunc ", at + 1)
	var body: String = src.substr(at, (after - at) if after != -1 else -1)
	assert_true(body.contains("is_valid()"),
		"_await_tween_safe waits on is_running(), which stays TRUE forever for a tween whose target "
		+ "was freed — the exact death its own comment cites. Without is_valid() the loop runs to the "
		+ "6s deadline and freezes the transition for six seconds. 14 call sites.")


func test_a_freed_target_tween_really_does_keep_reporting_running() -> void:
	# The premise. If the engine ever changes this, the guard above is defending nothing.
	var n := Node2D.new()
	add_child_autofree(n)
	var t: Tween = n.create_tween()
	t.tween_property(n, "position", Vector2(500, 0), 10.0)
	await get_tree().process_frame
	n.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(is_instance_valid(t), "the Tween object itself survives its target")
	assert_true(t.is_running(), "PREMISE: a freed-target tween still reports is_running() — if this "
		+ "fails the engine changed and _await_tween_safe's extra term is now dead weight")
	assert_false(t.is_valid(), "PREMISE: is_valid() is the only tell for a freed target")


func test_a_live_tween_is_still_waited_on() -> void:
	# Control for the fix: is_valid() must be TRUE mid-flight, or adding it would make every one of
	# the 14 call sites return instantly and break the transitions it is meant to protect.
	var n := Node2D.new()
	add_child_autofree(n)
	var t: Tween = n.create_tween()
	t.tween_property(n, "position", Vector2(500, 0), 5.0)
	await get_tree().process_frame
	assert_true(t.is_valid(), "a live tween must read valid, else the new term short-circuits the wait")
	assert_true(t.is_running(), "and running")
	t.kill()
