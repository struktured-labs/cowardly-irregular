extends GutTest

## Seen in my own 200% victory frame (2026-11-12): "X: skip" was printed ON the hint bar's text. The prompt rested a
## fixed 58 px above the bottom while its font and the hint bar both grow with Text Size. It is now reserved before the
## cards are placed: at its resting line, lifted clear of the hint bar when the two would meet, and the card column's
## bottom limit follows it. Measured on a REAL BattleScene's built nodes with the overlay settled.

const SCENE := preload("res://src/battle/BattleScene.tscn")
const OverlayScript := preload("res://src/battle/VictoryOverlay.gd")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")

var _guard
var _orig_scale := 1.0


func before_each() -> void:
	AutobattleSystem._test_disable_persistence = true
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	_orig_scale = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _orig_scale
	_guard.restore()


func after_all() -> void:
	SoundState.restore()


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 2, "CONTROL: the Text Size presets were read")
	return p


func _settled(scale: float, members: int) -> Array:
	GameState.text_size_scale = scale
	var scene = SCENE.instantiate()
	scene.encounter_enemies = ["goblin", "goblin", "goblin"]
	add_child_autofree(scene)
	await wait_frames(6)
	var cr: Array = []
	for i in members:
		cr.append({"name": "Scriptweaver", "job_name": "fighter", "is_alive": true, "exp_gained": 99999,
			"job_exp_before": 40, "exp_to_next": 200, "leveled_up": true, "job_level": 11, "job_exp": 30, "stat_gains": {"HP": 46}})
	var o: Control = OverlayScript.new()
	scene.add_child(o)
	o.build({"char_results": cr, "total_gold": 40, "item_drops": [], "bonuses": [], "injuries": []}, scene)
	o.complete_now()
	await wait_frames(4)
	return [scene, o]


func _cards(o: Node, out: Array) -> void:
	for c in o.get_children():
		if c is Control and (c as Control).find_child("TopLine", true, false) != null:
			out.append(c)
		else:
			_cards(c, out)


func test_the_prompt_and_the_cards_stay_off_the_hint_bar_and_each_other() -> void:
	var lifted := 0
	for scale in _presets():
		var s: Array = await _settled(float(scale), 5)
		var o: Control = s[1]
		var hint := (s[0] as Node).get_node_or_null("UI/InputHintBar") as Control
		assert_true(hint != null and hint.is_visible_in_tree() and hint.get_global_rect().has_area(), "CONTROL: the hint bar is showing at %s" % scale)
		var prompt := o.get_node_or_null("ContinuePrompt") as Label
		assert_not_null(prompt, "CONTROL: the continue prompt was built at %s" % scale)
		if hint == null or prompt == null:
			continue
		var pr: Rect2 = prompt.get_global_rect()
		var hr: Rect2 = hint.get_global_rect()
		assert_gt(pr.size.y, 0.0, "CONTROL: the prompt has a height to judge (%s)" % scale)
		assert_false(pr.intersects(hr), "Text Size %s: the prompt %s is on the hint bar %s" % [scale, pr, hr])
		assert_gte(pr.position.y, 0.0, "and it is on the screen")
		var cards: Array = []
		_cards(o, cards)
		assert_eq(cards.size(), 5, "CONTROL: five cards at %s" % scale)
		for card in cards:
			var cr: Rect2 = (card as Control).get_global_rect()
			assert_false(cr.intersects(pr), "Text Size %s: a card %s is on the prompt %s" % [scale, cr, pr])
			assert_false(cr.intersects(hr), "Text Size %s: a card %s is on the hint bar %s" % [scale, cr, hr])
		if pr.position.y < o.get_viewport_rect().size.y - OverlayScript.PROMPT_REST - 0.5:
			lifted += 1
	assert_gt(lifted, 0, "CONTROL: at some Text Size the hint bar, not the resting line, is what places the prompt")


func test_at_100_percent_nothing_moves() -> void:
	var s: Array = await _settled(1.0, 5)
	var o: Control = s[1]
	var vp: Vector2 = o.get_viewport_rect().size
	var prompt := o.get_node_or_null("ContinuePrompt") as Label
	assert_not_null(prompt, "CONTROL: the prompt was built")
	if prompt == null:
		return
	assert_almost_eq(prompt.position.y, vp.y - OverlayScript.PROMPT_REST, 0.01, "the prompt rests where .792 put it")
	assert_almost_eq(o._bottom_margin(vp.y), OverlayScript.STRIP_BOTTOM_MARGIN, 0.01, "and the column keeps .792's bottom margin")


func test_with_no_hint_bar_the_prompt_rests() -> void:
	GameState.text_size_scale = 2.0
	var scene = SCENE.instantiate()
	scene.encounter_enemies = ["goblin"]
	add_child_autofree(scene)
	await wait_frames(6)
	var hint := scene.get_node_or_null("UI/InputHintBar") as Control
	assert_not_null(hint, "CONTROL: the hint bar exists to be hidden")
	if hint != null:
		hint.visible = false
	var o: Control = OverlayScript.new()
	scene.add_child(o)
	o.build({"char_results": [], "total_gold": 0, "item_drops": [], "bonuses": [], "injuries": []}, scene)
	o.complete_now()
	await wait_frames(2)
	var prompt := o.get_node_or_null("ContinuePrompt") as Label
	assert_not_null(prompt, "CONTROL: the prompt was built")
	if prompt != null:
		assert_almost_eq(prompt.position.y, o.get_viewport_rect().size.y - OverlayScript.PROMPT_REST, 0.01, "a hidden hint bar lifts nothing")
