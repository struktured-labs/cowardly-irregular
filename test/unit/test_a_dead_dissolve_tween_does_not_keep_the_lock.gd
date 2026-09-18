extends GutTest

## `Mode7Overlay.play_dissolve_out/in` awaited `tween.finished` on a tween bound to `_player_ref`.
## Godot KILLS a tween whose bound node is freed, and a killed tween never emits `finished` — the
## awaiting coroutine then sleeps forever.
##
## ⛔ NOT HYPOTHETICAL. `InputLockManager.gd:24` records it happening, verbatim: the
## `has_lock("world_transition")` guard in `_start_battle_async` "was added for the mid-dissolve
## tween death that skips the pop — i.e. the one leak it could not recover from on its own."
## v3.33.431 fixed the CONSEQUENCE (the suppressed duel's hung coroutine); this is the cause.
##
## 🔑 WHY IT MATTERS AT THE CALL SITE: all six `_on_transition_triggered` copies do
##   push_lock("world_transition") -> await play_dissolve_out() -> pop_lock -> area_transition.emit
## with NO re-entrancy guard. A hang there strands the input lock AND leaves the player standing in
## a fully dissolved world, because the emit that changes the scene is below the await.
##
## ⚠️ THE RE-ENTRANCY SHAPE IS NOT FIXED HERE — 0 of 6 copies have a guard, and that is recorded as
## open. Bounding the await defangs it: both dissolves now terminate, so the pop and the emit run.

const MODE7 := "res://src/exploration/Mode7Overlay.gd"


func _overlay() -> Node:
	var script = load(MODE7)
	assert_not_null(script, "could not load Mode7Overlay.gd")
	return script.new() if script else null


func test_a_killed_tween_does_not_hang_the_dissolve_wait() -> void:
	## The defect's exact condition, staged: the engine kills a tween whose bound node dies, so a
	## killed tween is what the caller is left awaiting. Before the fix this never returned.
	var ov := _overlay()
	assert_not_null(ov, "Mode7Overlay instance")
	if ov == null:
		return
	add_child_autofree(ov)

	var tween := create_tween()
	tween.tween_interval(10.0)
	assert_true(tween.is_running(), "CONTROL: the tween must be running before we kill it")
	tween.kill()

	## ⚠️ NO WALL-CLOCK BOUND. Headless runs uncapped, so tween time advances about 3x faster than
	## the clock (measured: a 0.3s tween completes in 15 frames but 92 ms). A wall-clock assertion
	## here is the engine-time-vs-wall-clock trap and flakes with frame pacing, not with the bug.
	var frames := 0
	var done := [false]
	var co := func() -> void:
		await ov._await_dissolve(tween, 1.2)
		done[0] = true
	co.call()
	while not done[0] and frames < 400:
		await get_tree().process_frame
		frames += 1
	assert_true(done[0],
		"the wait never returned on a KILLED tween after %d frames — it is waiting for a `finished` that can never arrive, and the caller's input lock is never popped" % frames)


func test_control_the_wait_still_waits_for_a_live_tween() -> void:
	## Without this, "returns immediately always" would pass the arm above — the fix must still
	## let a real dissolve play, or the transition cuts to black instantly.
	var ov := _overlay()
	assert_not_null(ov, "Mode7Overlay instance")
	if ov == null:
		return
	add_child_autofree(ov)

	var tween := create_tween()
	tween.tween_interval(0.3)
	assert_true(tween.is_running(), "CONTROL: the tween must be live before the wait")
	await ov._await_dissolve(tween, 0.3)
	## STATE, not duration: the claim is "it waited until the tween stopped", which is true
	## whatever the frame pacing. A wall-clock floor would measure the harness, not the subject.
	assert_false(tween.is_running(),
		"the wait returned while the tween was STILL RUNNING — it is not waiting for the dissolve, so the transition would cut to black instantly")


func test_the_dissolves_do_not_await_a_signal_that_can_be_revoked() -> void:
	## Source ratchet on CODE only. ⚠️ The file's own docstring names `await tween.finished` to
	## explain what it replaced, so a naive text scan matches the cure and reports the disease —
	## the same inversion that made three throwaway classifiers flag correct code today.
	var f := FileAccess.open(MODE7, FileAccess.READ)
	assert_not_null(f, "could not read Mode7Overlay.gd")
	if f == null:
		return
	var src := f.get_as_text()
	f.close()

	var offenders: Array = []
	for line in src.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("#"):
			continue
		if t.contains("await ") and t.contains(".finished"):
			offenders.append(t)
	assert_eq(offenders, [],
		"a dissolve awaits a tween signal directly: %s — a tween bound to the player is killed when the player is freed, and a killed tween never emits it" % str(offenders))

	assert_true(src.contains("func _await_dissolve"),
		"CONTROL: the bounded wait must still exist, or this arm is asserting the absence of something nothing replaced")


## ⛔ THE END-TO-END ARM, ADDED AFTER A MUTATION EXPOSED THE GAP. Restoring `await tween.finished`
## at the CALL SITES left both behaviour arms above GREEN — they drive `_await_dissolve` directly,
## so they prove the helper is bounded and say nothing about whether `play_dissolve_out` uses it.
## The source ratchet caught that mutation, but a ratchet is a text claim; this drives the subject.
func test_play_dissolve_out_returns_when_the_player_dies_mid_dissolve() -> void:
	var ov := _overlay()
	assert_not_null(ov, "Mode7Overlay instance")
	if ov == null:
		return
	add_child_autofree(ov)

	## The two fields play_dissolve_out early-returns on. Without both, the function returns
	## immediately and this arm passes having driven nothing.
	ov._shader_mat = ShaderMaterial.new()
	var player := Node2D.new()
	add_child(player)
	ov._player_ref = player
	assert_not_null(ov._player_ref, "CONTROL: the player ref must be set or the function early-returns")

	var done := [false]
	var co := func() -> void:
		await ov.play_dissolve_out(1.2)
		done[0] = true
	co.call()

	## Let the dissolve start, then kill the node the tween is bound to — the exact event
	## InputLockManager.gd:24 records ("the mid-dissolve tween death that skips the pop").
	for i in range(3):
		await get_tree().process_frame
	assert_false(done[0], "CONTROL: the dissolve must still be in flight when the player dies, or this arm proves nothing")
	player.free()

	var frames := 0
	while not done[0] and frames < 600:
		await get_tree().process_frame
		frames += 1
	assert_true(done[0],
		"play_dissolve_out never returned after the player was freed (%d frames) — its caller holds push_lock(\"world_transition\") across this await and emits area_transition below it, so the lock strands and the player is left in a fully dissolved world" % frames)
