extends GutTest

## struktured OK'd 2026-11-16 (grokbot 26157): the .807 smoke still had the EXP cards over "ONE-SHOT!" and the Rogue card over "Rank:".
## The banner fires BEFORE the overlay exists (it waits for the downbeat), so it had no cards to dodge. Real order here, real scene.

const SCENE := preload("res://src/battle/BattleScene.tscn")
const OverlayScript := preload("res://src/battle/VictoryOverlay.gd")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")

var _guard
var _orig_scale := 1.0
var _orig_time := 1.0


func before_each() -> void:
	AutobattleSystem._test_disable_persistence = true
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	_orig_scale = float(GameState.text_size_scale)
	_orig_time = Engine.time_scale


func after_each() -> void:
	GameState.text_size_scale = _orig_scale
	Engine.time_scale = _orig_time
	_guard.restore()


func after_all() -> void:
	SoundState.restore()


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 2, "FLOOR: the Text Size presets were read (%s)" % [p])
	return p


func test_the_floor_names_every_member_this_file_drives() -> void:
	var m: Array = (OverlayScript as GDScript).get_script_method_list().map(func(x): return str(x["name"]))
	for f in ["build", "complete_now", "occupied_rects", "banner_text_hits", "_clear_stale_banners"]:
		assert_has(m, f, "VictoryOverlay.%s must exist" % f)
	var s: Array = (load("res://src/battle/BattleScene.gd") as GDScript).get_script_method_list().map(func(x): return str(x["name"]))
	for f in ["_on_one_shot_achieved", "_on_autobattle_victory"]:
		assert_has(s, f, "BattleScene.%s must exist" % f)
	var h: Array = (load("res://src/ui/TutorialHint.gd") as GDScript).get_script_method_list().map(func(x): return str(x["name"]))
	for f in ["show_hint", "step_aside", "panel_rect"]:
		assert_has(h, f, "TutorialHint.%s must exist" % f)


func _results() -> Dictionary:
	var cr: Array = []
	for n in ["Fighter", "Cleric", "Rogue", "Mage"]:
		cr.append({"name": n, "job_name": n.to_lower(), "is_alive": true, "exp_gained": 35, "job_exp_before": 40,
			"exp_to_next": 200, "leveled_up": false, "job_level": 4, "job_exp": 75, "stat_gains": {}})
	return {"char_results": cr, "total_gold": 40, "item_drops": [], "bonuses": [{"type": "one_shot", "rank": "S"}], "injuries": [], "one_shot_rank": "S"}


## The banners fire first (as in battle), THEN the overlay builds: returns [scene, overlay].
func _victory(scale: float, time_scale: float) -> Array:
	GameState.text_size_scale = scale
	Engine.time_scale = time_scale
	var scene = SCENE.instantiate()
	scene.encounter_enemies = ["goblin"]
	add_child_autofree(scene)
	await wait_frames(6)
	scene._on_one_shot_achieved("S", 0)
	await wait_frames(2)
	scene._on_autobattle_victory(2.5, 10)
	await wait_frames(2)
	var o: Control = OverlayScript.new()
	o.name = "VictoryResults"
	scene.add_child(o)
	o.build(_results(), scene)
	o.complete_now()
	await wait_frames(3)
	return [scene, o]


func test_no_visible_banner_lands_on_the_title_strip_or_a_card() -> void:
	var bad: Array = []
	var would: Array = []
	var judged := 0
	for ts in [1.0, 4.0]:
		for s in _presets():
			var v: Array = await _victory(float(s), ts)
			var scene: Node = v[0]
			var o: Control = v[1]
			var vp: Vector2 = o.get_viewport_rect().size
			var occ: Array = o.occupied_rects()
			assert_gt(occ.size(), 4, "CONTROL @%s x%s: the overlay occupies a title, a strip and cards (%d)" % [s, ts, occ.size()])
			for bname in OverlayScript.STALE_BANNERS:
				var flash := scene.get_node_or_null(bname) as Control
				if flash == null:
					continue
				judged += 1
				var hits: Array = OverlayScript.banner_text_hits(flash, occ, vp)
				would.append_array(hits)
				if flash.is_visible_in_tree() and not hits.is_empty():
					bad.append("@%s%% x%s %s: %s" % [int(roundf(float(s) * 100.0)), ts, bname, hits])
			scene.queue_free()
			await wait_frames(2)
	assert_gt(judged, _presets().size(), "CONTROL: banners were built to judge (%d)" % judged)
	## CONTROL: the defect is real in this fixture — the banners WOULD land on the overlay, so a clean result is not vacuous.
	assert_gt(would.size(), 0, "CONTROL: some banner text lands on the overlay's ground before it steps aside")
	assert_eq(bad, [], "a visible victory banner lands on the overlay:\n%s" % "\n".join(PackedStringArray(bad.map(func(x): return str(x)))))


## CONTROL against "hide them all": a banner whose text lands on nothing the overlay occupies keeps showing.
func test_a_banner_clear_of_the_overlay_keeps_showing() -> void:
	GameState.text_size_scale = 1.0
	var scene = SCENE.instantiate()
	scene.encounter_enemies = ["goblin"]
	add_child_autofree(scene)
	await wait_frames(6)
	scene._on_one_shot_achieved("S", 0)
	await wait_frames(2)
	var flash := scene.get_node_or_null("OneShotFlash") as Control
	assert_not_null(flash, "CONTROL: the one-shot banner was built")
	if flash == null:
		return
	var vp: Vector2 = scene.get_viewport_rect().size
	for c in flash.get_children():
		if c is Label:
			var l := c as Label
			l.offset_left = vp.x / 2.0 - 230.0
			l.offset_right = vp.x / 2.0 - 20.0
			l.offset_top = -20.0
			l.offset_bottom = 20.0
	var o: Control = OverlayScript.new()
	o.name = "VictoryResults"
	scene.add_child(o)
	o.build(_results(), scene)
	o.complete_now()
	await wait_frames(2)
	assert_eq(OverlayScript.banner_text_hits(flash, o.occupied_rects(), vp), [], "CONTROL: moved to the right edge at mid-height, it lands on nothing")
	assert_true(flash.visible, "a banner clear of the overlay is not hidden")


## The faint VICTORY! under the Group Attacks hint (grokbot 26157): an open hint over the docked title steps aside and re-arms.
func test_a_tutorial_hint_over_the_title_steps_aside_and_shows_again_later() -> void:
	const ID := "zz_victory_title_probe"
	GameState.game_constants.erase("tutorial_" + ID)
	GameState.text_size_scale = 1.0
	var scene = SCENE.instantiate()
	scene.encounter_enemies = ["goblin"]
	add_child_autofree(scene)
	await wait_frames(6)
	var hint: TutorialHint = TutorialHint.new()
	add_child_autofree(hint)
	await wait_frames(1)
	hint.show_hint(ID, "Group Attacks", "Pool every member's AP into one strike.")
	await wait_frames(2)
	var before: Rect2 = hint.panel_rect()
	assert_true(before.has_area(), "CONTROL: the hint is open (%s)" % before)
	var o: Control = OverlayScript.new()
	o.name = "VictoryResults"
	scene.add_child(o)
	o.build(_results(), scene)
	o.complete_now()
	await wait_frames(2)
	assert_true(o.occupied_rects().any(func(r): return (r as Rect2).intersects(before)), "CONTROL: the hint sat on the overlay's ground (%s vs %s)" % [before, o.occupied_rects()])
	assert_false(hint.visible, "a hint over the victory title steps aside")
	assert_false(TutorialHint.is_any_active(), "stepping aside releases the input gate")
	assert_false(bool(GameState.game_constants.get("tutorial_" + ID, false)), "a hint that stepped aside is re-armed, so it still teaches")
	GameState.game_constants.erase("tutorial_" + ID)
