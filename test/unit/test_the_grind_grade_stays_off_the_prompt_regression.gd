extends GutTest

## Regression: at Text Size 2.0 a full Summary drew its SESSION GRADE onto "Press X or Z to continue" (52% covered).
## Under pressure the stats rows shrank to their 18 px floor while the badge rows kept their whole reservation, though the
## badges drawn are only those that fit and the rest are counted in the ACHIEVEMENTS header. Badge rows now give way first.

const SummaryScript := preload("res://src/ui/autogrind/AutogrindSummary.gd")
const SettingsMenuScript = preload("res://src/ui/SettingsMenu.gd")
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

var _ag: Dictionary
var _flags: Dictionary
var _scale_was: float = 1.0


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	## The Summary awards badges into GameState.story_flags, which AutogrindState does not snapshot.
	_flags = GameState.story_flags.duplicate(true)
	_scale_was = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.story_flags = _flags
	GameState.text_size_scale = _scale_was
	AutogrindState.restore(_ag)


## A long session that earns every badge in the catalog, so the badge rows are as tall as they get.
func _stats() -> Dictionary:
	var noops := {}
	for i in SummaryScript.RULE_NOOP_ROWS_MAX:
		noops["Heal Party: out of potions %d" % i] = 9 - i
	return {
		"battles_won": 1480, "total_exp": 184320, "total_gold": 97450, "battles_without_heal": 60,
		"elapsed_seconds": 7382.0, "consecutive_wins": 41, "efficiency": 3.75,
		"corruption": 4.5, "corruption_threshold": 5.0, "adaptation": 2.75,
		"collapse_count": 3, "meta_bosses_defeated": 12, "meta_bosses_spawned": 15,
		"save_corruption": 12.75, "save_corruption_delta": 3.25,
		"rules_authored": 14, "rules_that_fired": 12, "rule_checks": 9999,
		"per_character_exp": {"Bram": 41230, "Marta": 38110, "Phil": 36500, "Theron": 35980, "Milo": 32500},
		"achievements_earned_this_session": [],
		"rule_noops": noops,
	}


func _screen(scale: float) -> Node:
	GameState.text_size_scale = scale
	var s: Node = SummaryScript.new()
	add_child_autofree(s)
	s.setup(_stats(), "Party HP dropped below your 30% stop")
	await wait_frames(3)
	return s


func _labels(n: Node, acc: Array) -> Array:
	if n is Label and n.visible and str(n.text).strip_edges() != "":
		acc.append(n)
	for c in n.get_children():
		_labels(c, acc)
	return acc


func _rect(l: Label) -> Rect2:
	return Rect2(l.global_position, Vector2(l.size.x, float(l.get_line_count() * l.get_line_height())))


func test_nothing_lands_on_the_continue_prompt_at_any_text_size() -> void:
	var pressured := 0
	for scale in SettingsMenuScript.TEXT_SIZE_PRESETS:
		var s: Node = await _screen(float(scale))
		var labels := _labels(s, [])
		var prompt: Label = null
		for l in labels:
			if str((l as Label).text).ends_with("to continue"):
				prompt = l
		assert_not_null(prompt, "CONTROL: the continue prompt is drawn at %sx" % scale)
		if prompt == null:
			continue
		var panel: Control = prompt.get_parent()
		if panel.size.y >= s.get_viewport().get_visible_rect().size.y - 40.0 - 0.5:
			pressured += 1
		var on_it: Array = []
		for l in labels:
			if l != prompt and _rect(l).intersects(_rect(prompt)):
				on_it.append(str((l as Label).text).left(30))
		assert_eq(on_it, [], "at %sx these are drawn on 'Press … to continue': %s" % [scale, on_it])
	assert_gt(pressured, 0, "CONTROL: at no Text Size did the panel reach the screen cap, so nothing was under pressure")
