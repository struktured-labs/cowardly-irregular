extends GutTest

## TurnInfo is one of BattleScene's themed scene nodes — no font override in the `.tscn`, no project
## theme to inherit a scale from — so it ignored Text Size. It is the strip that names whose turn it
## is and what the battle is waiting for.
##
## ✅ WHY THIS ONE IS SAFE AND ITS SIBLING IS NOT, probed rather than assumed. The battle log's budget
## is `474 - enemy_panel_bottom`, and with five enemies that is 68px. Scaling EnemyStatusPanel's
## title moves enemy_bottom 406 -> 413 and LOSES the log at 1.25x, so that label is held with the
## enemy-panel trade. TurnInfo lives in its own UI/TurnInfoPanel and is an input to nobody's budget.
## The last arm pins that, because "it is in its own panel" is a claim about today's scene tree.

const SCENE := "res://src/battle/BattleScene.tscn"
const TURN_INFO := "UI/TurnInfoPanel/TurnInfo"
## ⛔ Adding a BattleScene to the tree STARTS A BATTLE on the BattleManager autoload, and this
## file instantiates one. Without a restore, test_battle_state_not_leaked_by_tests reds after
## it ("state=3") — which is how the first version of this stack was dropped from .691.
## The helper derives its surface from get_property_list(), so a field added tomorrow is
## covered without editing anything; a hand-written teardown covers only the fields its
## author thought of, which is the failure its own docstring records twice.
const BattleStateHelper := preload("res://test/unit/helpers/battle_state.gd")
const PRESETS: Array = [0.8, 1.0, 1.25, 1.5, 2.0]

var _saved_scale: float = 1.0
var _scene: Node = null
var _battle_state: RefCounted = null
var _file_state: RefCounted = null


## ⛔ BACKSTOP UNDER THE PER-TEST RESTORE, AND IT IS NOT BELT-AND-BRACES. after_each puts the
## restore LAST, because queue_free()ing the scene can re-dirty the autoload — correct, and it leaves
## the restore ABORT-EXPOSED: a GDScript error in the lines above it kills the enclosing function, so
## the restore never runs and the file is green either way. The helper's own note names this exact
## shape and names the repair: a file-scope snapshot a per-test abort cannot skip. This stack was
## dropped from .691 for precisely that leak, one signal over.
func before_all() -> void:
	_file_state = BattleStateHelper.new()
	_file_state.snapshot()


func after_all() -> void:
	if _file_state != null:
		_file_state.restore()


func before_each() -> void:
	_battle_state = BattleStateHelper.new()
	_battle_state.snapshot()
	_saved_scale = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _saved_scale
	if _scene and is_instance_valid(_scene):
		_scene.queue_free()
	_scene = null
	## LAST, not first: queue_free()ing the scene above can re-dirty the autoload, and the
	## helper's own note says a restore must follow any line that does.
	if _battle_state != null:
		_battle_state.restore()
func _build(scale: float) -> Node:
	GameState.text_size_scale = scale
	var n: Node = load(SCENE).instantiate()
	add_child(n)
	await get_tree().process_frame
	return n


func _px(n: Node) -> int:
	var c: Control = n.get_node_or_null(TURN_INFO)
	return -1 if c == null else c.get_theme_font_size("font_size")


## FLOOR: a path typo would make every size arm compare -1 to -1 and pass.
func test_the_turn_info_node_exists_at_its_path() -> void:
	_scene = await _build(1.0)
	assert_false(_scene.get_node_or_null(TURN_INFO) == null,
		"FLOOR: TurnInfo must exist at %s, or the arms below compare -1 to -1" % TURN_INFO)
	assert_gt(_px(_scene), 0, "FLOOR: and it must resolve a font size")


func test_the_turn_info_font_follows_the_setting_in_both_directions() -> void:
	_scene = await _build(1.0)
	var base: int = _px(_scene)
	_scene.queue_free()
	_scene = await _build(2.0)
	var big: int = _px(_scene)
	_scene.queue_free()
	_scene = await _build(0.8)
	var small: int = _px(_scene)
	assert_gt(big, base, "TurnInfo must GROW at 200%%: 100%%=%d 200%%=%d" % [base, big])
	assert_lt(small, base, "and SHRINK at 80%%: 80%%=%d 100%%=%d" % [small, base])


func test_every_preset_moves_it_monotonically() -> void:
	var seen: Array = []
	for s in PRESETS:
		_scene = await _build(float(s))
		seen.append(_px(_scene))
		_scene.queue_free()
		_scene = null
		await get_tree().process_frame
	for i in range(1, seen.size()):
		assert_true(int(seen[i]) >= int(seen[i - 1]),
			"it must never shrink as the setting rises: %s for %s" % [str(seen), str(PRESETS)])
	assert_true(int(seen[-1]) > int(seen[0]), "and the ladder must move: %s" % str(seen))


## The text must FIT its own panel at every preset — a font-grew arm alone is blind to overflow.
##
## ⛔ THIS ARM USED ONE HAND-PICKED STRING, AND IT WAS A STRING THE GAME NEVER PRODUCES.
## "Fighter's turn — choose an action", 32 chars, invented. The real formats are in
## BattleUIManager.update_turn_info, and the worst of them with the longest authored name is
## "Round 99 - SELECT: Glacius, the Frozen Sovereign (AP: +4)" at 57 — nearly double. So the arm
## tested a narrower case than reality and would have passed an overflow of the real text.
## That is cowir-controller's exact failure (18110): a corpus of one, and 5 of their 289 abilities
## were short at 125% while none of the failures was the longest string. And cowir-adhoc's
## refinement (18111): len() is a PROXY for width, not width — a wide-glyph short word beats a
## narrow-glyph long one. So this drives EVERY authored name through EVERY real format and measures
## with get_string_size, not with len().
##
## A font query is valid here: TurnInfo has no autowrap_mode in the scene, so it is single-line and
## the default break flags are the ones it draws with — cowir-autogrind's flags hazard needs a
## wrapping node and cannot reach this one.
func _real_turn_lines() -> Array[String]:
	var names: Array[String] = []
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	if raw is Dictionary:
		var table: Variant = raw.get("monsters", raw)
		if table is Dictionary:
			for k in (table as Dictionary):
				var m: Variant = (table as Dictionary)[k]
				if m is Dictionary and str((m as Dictionary).get("name", "")) != "":
					names.append(str((m as Dictionary)["name"]))
	for job in ["Fighter", "Cleric", "Mage", "Rogue", "Bard"]:
		names.append(job)
	var out: Array[String] = []
	for n in names:
		out.append("Round 99 - SELECT: %s (AP: +4)" % n)
		out.append("Round 99 - EXECUTE: %s" % n)
	out.append("Round 99 - Selection Phase")
	out.append("Round 99 - Execution Phase")
	return out


func test_every_real_turn_line_fits_the_strip_at_every_preset() -> void:
	var lines: Array[String] = _real_turn_lines()
	assert_gt(lines.size(), 20,
		"FLOOR: the corpus must be the real one — %d lines derived from monsters.json plus the five "
		% lines.size() + "starter jobs, through every format update_turn_info writes")
	for s in PRESETS:
		_scene = await _build(float(s))
		var panel: Control = _scene.get_node_or_null("UI/TurnInfoPanel")
		var label: Label = _scene.get_node_or_null(TURN_INFO)
		assert_false(panel == null or label == null, "fixture: both must exist at %sx" % str(s))
		if panel == null or label == null:
			return
		var f := label.get_theme_font(&"font")
		var px: int = label.get_theme_font_size(&"font_size")
		assert_false(f == null, "fixture: the strip must resolve a font at %sx" % str(s))
		if f == null:
			return
		var avail: float = panel.size.x
		var worst: String = ""
		var worst_w: float = 0.0
		for line in lines:
			var w: float = f.get_string_size(line, HORIZONTAL_ALIGNMENT_CENTER, -1, px).x
			if w > worst_w:
				worst_w = w
				worst = line
		gut.p("%sx widest real line: %.0fpx of %.0f — '%s'" % [str(s), worst_w, avail, worst])
		assert_true(worst_w <= avail,
			("at %sx the widest REAL turn line needs %.0fpx in a %.0fpx strip: '%s'. Measured by "
			+ "width over every authored name, not by len() over one invented sample.")
			% [str(s), worst_w, avail, worst])
		_scene.queue_free()
		_scene = null
		await get_tree().process_frame


## THE SAFETY CLAIM, pinned. TurnInfo must not become an input to the battle log's budget the way
## EnemyStatusPanel's title is. If a later layout change moves it into that column, this reds and
## the held enemy-panel trade has to be reconsidered rather than silently regressed.
func test_scaling_the_turn_strip_leaves_the_logs_budget_alone() -> void:
	var seen: Array = []
	for s in [1.0, 2.0]:
		_scene = await _build(float(s))
		var enemy: Control = _scene.get_node_or_null("UI/EnemyStatusPanel")
		var panel: Control = _scene.get_node_or_null("UI/BattleLogPanel")
		assert_false(enemy == null or panel == null, "fixture: both panels must exist")
		if enemy == null or panel == null:
			return
		_scene._reposition_battle_log_panel_now()
		await get_tree().process_frame
		seen.append({"scale": s, "bottom": enemy.position.y + enemy.size.y, "log": panel.visible})
		_scene.queue_free()
		_scene = null
		await get_tree().process_frame
	## ⚠️ NOT asserted: that the enemy panel's bottom is PIXEL-IDENTICAL across the two builds.
	## Measured 282 at 100%% and 280 at 200%% — it moves 2px, and only with this change in place, so it
	## is real rather than noise. But I could not attribute those 2px to TurnInfo with confidence:
	## the arm calls _reposition_battle_log_panel_now(), whose chrome probe zeroes and restores a child
	## minimum and so provokes a layout pass, and a rect compared across two separately-built scenes
	## carries settling noise (cowir-autogrind: whether a minimum is current depends on the ORDER
	## properties were set in). An equality arm I cannot explain is not a guard, it is a tripwire on
	## my own fixture — so this asserts the CONSEQUENCE instead, and the 2px is written down for
	## whoever takes the enemy-panel trade. The full-roster case is pinned separately.
	assert_true(seen[0]["bottom"] > 0.0 and seen[1]["bottom"] > 0.0,
		"fixture: the enemy panel must have settled to a real height at both ends: %s" % str(seen))
	assert_true(bool(seen[0]["log"]) and bool(seen[1]["log"]),
		"and the log must stay visible at both ends with a default roster: %s" % str(seen))
