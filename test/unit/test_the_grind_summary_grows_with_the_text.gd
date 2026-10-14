extends GutTest
## The end-of-grind Summary carried 8 hardcoded font sizes and ZERO TextScale, so the screen that
## always runs -- the one a player reads when a grind stops -- ignored Text Size entirely.
##
## ⛔ AND THIS FILE HAS A HAZARD THE CONSOLE DID NOT: the stat VALUES are `clip_text`. A clipped
## Label's rect does NOT move with its text (measured: clip_text frees the WIDTH minimum), so a value
## that outgrows its box is CUT rather than overflowing. Every containment arm passes that, because
## the rect stays inside its box -- the player simply loses characters. A fit arm cannot see a cut,
## so this file carries an arm that measures the text's own width against the box it is given.
##
## ⛔ THE FIXTURE DRIVES THE REAL FORMATTERS, not strings I invented. Five lanes were corrected today
## for arms driven by a hand-picked sample the game never produces (@cowir-battle's 32-char turn line
## against a real 57; @cowir-controller's 3 of 74 candidates). Every value below comes out of
## _build_ui's own stats_data via plausible session numbers.
const SummaryScript := preload("res://src/ui/autogrind/AutogrindSummary.gd")
const SettingsMenuScript = preload("res://src/ui/SettingsMenu.gd")
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

var _ag: Dictionary
var _scale_was: float = 1.0


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	_scale_was = float(GameState.text_size_scale) if "text_size_scale" in GameState else 1.0


func after_each() -> void:
	if "text_size_scale" in GameState:
		GameState.text_size_scale = _scale_was
	AutogrindState.restore(_ag)


## A long but ordinary session: every row the builder can emit, with values at the widths a real
## grind produces (five-figure EXP, a full party's per-character breakdown, meta-bosses, collapses).
func _fixture_stats() -> Dictionary:
	return {
		"battles_won": 148, "total_exp": 184320, "total_gold": 97450,
		"elapsed_seconds": 7382.0, "consecutive_wins": 41, "efficiency": 3.75,
		"corruption": 4.5, "corruption_threshold": 5.0, "adaptation": 2.75,
		"collapse_count": 3, "meta_bosses_defeated": 12, "meta_bosses_spawned": 15,
		## The two widest forms the real formatters can emit, reached rather than assumed:
		## _format_save_corruption -> "%.3f (+%.3f this session)" needs a positive delta;
		## _rules_summary -> "%d of %d fired (%d checks)" needs authored AND checks above zero.
		"save_corruption": 12.75, "save_corruption_delta": 3.25,
		"rules_authored": 14, "rules_that_fired": 12, "rule_checks": 9999,
		"per_character_exp": {"Bram": 41230, "Marta": 38110, "Phil": 36500, "Theron": 35980, "Milo": 32500},
		"achievements_earned_this_session": [],
	}


func _screen(scale: float, rule: String = "hp_threshold") -> Node:
	if "text_size_scale" in GameState:
		GameState.text_size_scale = scale
	if "last_interrupt_rule" in AutogrindSystem:
		AutogrindSystem.last_interrupt_rule = rule
	var s: Node = SummaryScript.new()
	add_child_autofree(s)
	s.setup(_fixture_stats(), "Party HP dropped below your 30% stop")
	await wait_frames(3)
	return s


func _labels(n: Node, acc: Array) -> Array:
	if n is Label and n.visible and str(n.text).strip_edges() != "":
		acc.append(n)
	for c in n.get_children():
		_labels(c, acc)
	return acc


## The DRAWN rect: a wrapping Label's size is a minimum, so height comes from the lines it draws.
func _rect(l: Label) -> Rect2:
	return Rect2(l.global_position, Vector2(l.size.x, float(l.get_line_count() * l.get_line_height())))


func _short(l: Label) -> String:
	return str(l.text).replace("\n", " ").substr(0, 30)


func test_the_summary_text_grows_with_the_setting() -> void:
	var ladder: Array = SettingsMenuScript.TEXT_SIZE_PRESETS
	var small: Node = await _screen(float(ladder[0]))
	var a: Array = _labels(small, [])
	assert_gt(a.size(), 8, "FLOOR: the summary must render its rows (%d)" % a.size())
	## ⛔ PAIRED BY TEXT, NOT BY INDEX. The two builds legitimately render DIFFERENT label counts --
	## at 2.0x the achievements that do not fit are counted in the header instead of drawn, so an
	## index pairing compares a chip against a prompt and reds on correct behaviour (49 vs 53,
	## measured). Keyed by text, every label present in both is compared and the rest are ignored.
	var was: Dictionary = {}
	for l in a:
		var k: String = str(l.text)
		var px: int = int(l.get_theme_font_size("font_size"))
		was[k] = mini(int(was.get(k, px)), px)
	var big: Node = await _screen(float(ladder[ladder.size() - 1]))
	var b: Array = _labels(big, [])
	var compared: int = 0
	for l in b:
		var k: String = str(l.text)
		if not was.has(k):
			continue
		compared += 1
		assert_gt(int(l.get_theme_font_size("font_size")), int(was[k]),
			"'%s' kept font %d at %sx and %sx" % [_short(l), int(was[k]), ladder[0], ladder[ladder.size() - 1]])
	assert_gt(compared, 8, "FLOOR: only %d labels appeared in both builds, so little was compared" % compared)


## ⛔ THE ARM A FIT CHECK CANNOT REPLACE. `clip_text` frees the width minimum, so the rect stays put
## while the glyphs grow: the box never overflows and the characters are simply gone. Measured
## against the font, because the node cannot report what it did not draw.
func test_no_clipped_value_loses_characters() -> void:
	for scale in SettingsMenuScript.TEXT_SIZE_PRESETS:
		var s: Node = await _screen(float(scale))
		var clipped: int = 0
		var cut: Array = []
		for l in _labels(s, []):
			if not l.clip_text:
				continue
			clipped += 1
			var f: Font = l.get_theme_font("font")
			if f == null:
				continue
			var w: float = f.get_string_size(str(l.text), l.horizontal_alignment, -1,
				int(l.get_theme_font_size("font_size"))).x
			if w > l.size.x + 0.5:
				cut.append("%s: %dpx of text in a %dpx clipped box" % [_short(l), int(w), int(l.size.x)])
		assert_gt(clipped, 0, "FLOOR: at %sx no clipped label was found, so nothing was judged" % scale)
		assert_eq(cut, [], "at %sx Text Size, %d value(s) are CUT, not overflowing: %s" % [scale, cut.size(), str(cut.slice(0, 4))])


func test_no_two_labels_collide_at_any_text_size() -> void:
	for scale in SettingsMenuScript.TEXT_SIZE_PRESETS:
		var s: Node = await _screen(float(scale))
		var by_parent: Dictionary = {}
		for l in _labels(s, []):
			var k: int = l.get_parent().get_instance_id()
			if not by_parent.has(k):
				by_parent[k] = []
			by_parent[k].append(l)
		var pairs: int = 0
		for k in by_parent:
			var g: Array = by_parent[k]
			for i in range(g.size()):
				for j in range(i + 1, g.size()):
					pairs += 1
					assert_false(_rect(g[i]).intersects(_rect(g[j])),
						"at %sx '%s' is drawn ON TOP of '%s'" % [scale, _short(g[i]), _short(g[j])])
		assert_gt(pairs, 0, "FLOOR: at %sx nothing was compared" % scale)


## The panel is the box every row lives in, and it is derived -- so this is the arm that catches a
## row count or a badge wrap outgrowing the panel the header reserved for it.
func test_nothing_is_drawn_outside_the_panel() -> void:
	for scale in SettingsMenuScript.TEXT_SIZE_PRESETS:
		var s: Node = await _screen(float(scale))
		var panel: Control = null
		for c in s.get_children():
			if c is Control and (c as Control).size.x > 0.0:
				panel = c as Control
				break
		assert_true(panel != null, "FLOOR: the summary must build a panel at %sx" % scale)
		if panel == null:
			return
		var box: Rect2 = Rect2(panel.global_position, panel.size)
		for l in _labels(s, []):
			assert_true(box.grow(0.5).encloses(_rect(l)),
				"at %sx '%s' %s is drawn outside the %s panel" % [scale, _short(l), str(_rect(l)), str(box)])
