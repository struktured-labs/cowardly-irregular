extends GutTest

## A hold-B skip tore the scene down in ONE FRAME — backdrop, puppets, letterbox and dialogue
## vanished at once and the map was simply there. The Director now dips through black across
## that cut (FF6-style): fade out, tear down under the curtain, emit, fade in. A normal end
## and an abort do NOT dip. The emit happens while the curtain is fully black, so no listener
## can observe a map flash, and a listener that chains a new scene keeps the layer.

const DirectorScript = preload("res://src/cutscene/CutsceneDirector.gd")

var _d: Node


func before_each() -> void:
	_d = DirectorScript.new()
	add_child_autofree(_d)


func _long_scene() -> Dictionary:
	return {"id": "dip_probe", "steps": [{"type": "wait", "duration": 30.0}]}


## Runs a scene, triggers a skip after one frame, and samples the curtain alpha until finished.
func _run_skipped(record_alpha_at_emit: Array) -> Dictionary:
	_d.cutscene_finished.connect(func(_id): record_alpha_at_emit.append(_d._effects_rect.color.a), CONNECT_ONE_SHOT)
	_d.play_cutscene_from_data("dip_probe", _long_scene())
	await get_tree().process_frame
	await get_tree().process_frame
	_d._trigger_skip()
	var max_alpha := 0.0
	var elapsed := 0.0
	var seen_visible_after_emit := false
	while elapsed < 2.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		max_alpha = maxf(max_alpha, _d._effects_rect.color.a)
		if not record_alpha_at_emit.is_empty() and _d.visible:
			seen_visible_after_emit = true
		if not record_alpha_at_emit.is_empty() and not _d.visible:
			break
	return {"max_alpha": max_alpha, "layer_visible_after_emit": seen_visible_after_emit}


func test_skip_dips_through_black_and_emits_under_the_curtain() -> void:
	var at_emit: Array = []
	var r := await _run_skipped(at_emit)
	assert_gte(r["max_alpha"], 0.99, "the curtain must reach full black during a skip")
	assert_eq(at_emit.size(), 1, "cutscene_finished must emit exactly once")
	assert_gte(float(at_emit[0]), 0.99, "the emit must happen while the curtain is fully black — no map flash")
	assert_true(r["layer_visible_after_emit"], "the layer must stay visible through the fade-in after the emit")
	assert_false(_d.visible, "after the fade-in the layer must hide")
	assert_false(_d._effects_rect.visible, "the curtain must be cleared after the fade-in")
	assert_false(_d._active)


func test_a_normal_end_does_not_dip() -> void:
	var max_alpha := [0.0]
	var done := [false]
	_d.cutscene_finished.connect(func(_id): done[0] = true, CONNECT_ONE_SHOT)
	_d.play_cutscene_from_data("short", {"id": "short", "steps": [{"type": "wait", "duration": 0.05}]})
	var elapsed := 0.0
	while not done[0] and elapsed < 2.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		max_alpha[0] = maxf(max_alpha[0], _d._effects_rect.color.a)
	assert_true(done[0], "control: the short scene must finish")
	assert_lt(max_alpha[0], 0.01, "a scene ending normally must not dip to black")
	assert_false(_d.visible)


func test_an_abort_does_not_dip() -> void:
	var max_alpha := [0.0]
	var done := [false]
	_d.cutscene_finished.connect(func(_id): done[0] = true, CONNECT_ONE_SHOT)
	_d.play_cutscene_from_data("dip_probe", _long_scene())
	await get_tree().process_frame
	_d._aborted = true
	_d._skipping = true
	var elapsed := 0.0
	while not done[0] and elapsed < 2.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		max_alpha[0] = maxf(max_alpha[0], _d._effects_rect.color.a)
	assert_true(done[0], "control: the aborted scene must finish")
	assert_lt(max_alpha[0], 0.01, "an abort is not a player skip and must not dip")
