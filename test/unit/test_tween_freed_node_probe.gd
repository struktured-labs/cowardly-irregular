extends GutTest

## THE LOAD-BEARING EXPERIMENT for the mode-7 dissolve candidate (cowir-controller,
## 2026-08-08): Mode7Overlay.play_dissolve_out awaits a tween created on _player_ref.
## If a tween bound to a freed node never emits `finished`, the awaiting coroutine in
## _on_transition_triggered never resumes and `area_transition.emit` never runs —
## "I teleported and got stuck." This probe answers whether the engine behaves that way.


func test_tween_on_freed_node_never_emits_finished() -> void:
	var n := Node.new()
	add_child(n)
	var fired := [false]
	var t := n.create_tween()
	t.tween_interval(0.3)
	t.finished.connect(func(): fired[0] = true)
	await get_tree().create_timer(0.1).timeout
	n.free()
	await get_tree().create_timer(0.5).timeout
	# Whichever way this asserts, the RESULT is the deliverable — it promotes or kills
	# the candidate. If finished fires on kill, the dissolve chain cannot hang this way.
	assert_false(fired[0],
		"a tween bound to a freed node must NOT emit finished — if this FAILS, the dissolve-hang candidate collapses")


func test_control_tween_on_live_node_finishes() -> void:
	# CONTROL: same shape, node stays alive — finished MUST fire, else the probe is vacuous.
	var n := Node.new()
	add_child(n)
	var fired := [false]
	var t := n.create_tween()
	t.tween_interval(0.2)
	t.finished.connect(func(): fired[0] = true)
	await get_tree().create_timer(0.5).timeout
	assert_true(fired[0], "CONTROL: a live node's tween must emit finished — probe can see the signal")
	n.queue_free()
