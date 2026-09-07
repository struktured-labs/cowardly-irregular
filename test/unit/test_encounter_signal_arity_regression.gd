extends GutTest

## Regression: struktured's live session, 2026-07-31 — every random encounter logged
##
##   ERROR: Error calling from signal 'encounter_triggered' to callable:
##   'CanvasLayer(SceneTransition.gd)::_on_encounter_triggered':
##   Method expected 1 arguments, but called with 2.
##
## EncounterSystem declares `encounter_triggered(enemy_data: Array, terrain_type: String)`
## but SceneTransition's handler took one argument and connected with no .unbind(). Godot
## rejects the call, so the handler NEVER RAN — its only effect was an error per encounter.
##
## ⚠️ The fix was to DELETE the connection, not to correct the arity. transition_to_battle's
## sole caller was that handler, and BattleTransition's SHAKE_FLASH already owns encounter
## transitions (confirmed in the same log: "Playing SHAKE_FLASH transition for enemies").
## Repairing the signature would have played a SECOND transition on top of it — a silent
## defect traded for a visible one.
##
## Guards the CLASS, not the deleted line: any current or future connection to this signal
## must accept the arguments it is emitted with.


func _signal_arg_count(obj: Object, sig: String) -> int:
	for s in obj.get_signal_list():
		if str(s.get("name", "")) == sig:
			return (s.get("args", []) as Array).size()
	return -1


func test_control_signal_still_carries_two_arguments() -> void:
	# CONTROL: everything below is about a 2-arg signal. If it is ever reduced to one, the
	# arity check would pass trivially and this file would guard nothing.
	assert_eq(_signal_arg_count(EncounterSystem, "encounter_triggered"), 2,
		"encounter_triggered must still be (enemy_data, terrain_type)")


func test_every_connection_accepts_the_emitted_arguments() -> void:
	var emitted: int = _signal_arg_count(EncounterSystem, "encounter_triggered")
	var offenders: Array = []
	for c in EncounterSystem.get_signal_connection_list("encounter_triggered"):
		var cb: Callable = c.get("callable")
		if cb == null or not cb.is_valid():
			continue
		# A callable's own arity plus anything .bind() supplied must cover the emit.
		var accepts: int = cb.get_argument_count() - cb.get_bound_arguments_count()
		if accepts != emitted:
			offenders.append("%s accepts %d, signal emits %d" % [str(cb), accepts, emitted])
	assert_eq(offenders, [],
		"a handler that cannot accept the emitted arguments is NEVER CALLED — it only logs an error per encounter: %s" % str(offenders))


func test_harness_would_catch_a_mismatch() -> void:
	# CONTROL for the check above: with zero live connections the loop is vacuous, so connect
	# a deliberately WRONG handler and prove the same predicate flags it.
	var probe := func(_only_one_arg): pass
	EncounterSystem.encounter_triggered.connect(probe)
	var emitted: int = _signal_arg_count(EncounterSystem, "encounter_triggered")
	var flagged := false
	for c in EncounterSystem.get_signal_connection_list("encounter_triggered"):
		var cb: Callable = c.get("callable")
		if cb.is_valid() and (cb.get_argument_count() - cb.get_bound_arguments_count()) != emitted:
			flagged = true
	EncounterSystem.encounter_triggered.disconnect(probe)
	assert_true(flagged,
		"CONTROL: the arity predicate must flag a 1-arg handler on a 2-arg signal — otherwise the test above cannot fail")


func test_scene_transition_does_not_reconnect_it() -> void:
	# The specific removal, pinned so a well-meaning "fix the signature" does not reintroduce
	# a second transition on top of SHAKE_FLASH.
	var src := FileAccess.get_file_as_string("res://src/transitions/SceneTransition.gd")
	assert_ne(src, "", "SceneTransition.gd must be readable")
	assert_false(src.contains("encounter_triggered.connect("),
		"SceneTransition must not reconnect encounter_triggered — BattleTransition owns encounter transitions")
