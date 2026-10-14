extends GutTest

## The battle log carried every refusal, damage and bark line and was pinned at font 12 whatever the
## player set — `RetroFont.configure_battle_log` wrote two raw 12s. The one surface a player who
## raised Text Size most needs to read.
##
## ⚠️ IT IS NOT A THEMED SURFACE. An explicit `add_theme_font_size_override` BEATS a theme default,
## so a project-theme fix could never have reached it. The override lives in a HELPER that takes the
## node as a parameter, which is why a receiver-keyed grep on BattleScene.gd finds nothing.
##
## ⛔ AND SCALING THE FONT ALONE CAN MAKE THE LOG VANISH. `_reposition_battle_log_panel_now` has two
## `log_panel.visible = false` branches, and it budgeted the panel with two hand-measured literals:
## NON_TEXT_OVERHEAD 64 (the LogHeader row + margins) and MIN_TEXT_HEIGHT 16 (under ONE scaled line).
## LogTitle and LogExpandButton are themed nodes in that header, so their own Text Size fix would
## have made 64 wrong and pushed the panel into the hide branch. Both are derived now.
##
## So the fourth arm is specific to this surface: AN INVISIBLE PANEL SATISFIES EVERY FIT ASSERTION.

const SCENE := "res://src/battle/BattleScene.tscn"
const RetroFontClass := preload("res://src/ui/RetroFont.gd")
const PRESETS: Array = [0.8, 1.0, 1.25, 1.5, 2.0]

var _saved_scale: float = 1.0
var _scene: Node = null


func before_each() -> void:
	_saved_scale = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _saved_scale
	if _scene and is_instance_valid(_scene):
		_scene.queue_free()
	_scene = null


func _log_font_at(scale: float) -> int:
	GameState.text_size_scale = scale
	var rtl := RichTextLabel.new()
	autofree(rtl)
	RetroFontClass.configure_battle_log(rtl)
	return rtl.get_theme_font_size("normal_font_size")


## FLOOR: the symbols these arms reach, so a rename reds with the name rather than aborting an arm
## mid-frame and scoring as a pass.
func test_the_subjects_this_file_drives_exist() -> void:
	## configure_battle_log is a STATIC reached through a preload, so a missing one is a PARSE
	## error and run_tests.sh exits 3 — louder than any floor. Not floored here on purpose.
	assert_true("text_size_scale" in GameState,
		"FLOOR: TextScale reads GameState.text_size_scale; without it every preset is the same run")
	var probe := RichTextLabel.new()
	autofree(probe)
	assert_true(probe.has_method("get_theme_font_size"), "FLOOR: the arms read the font back")


## ARM 1 — the font GREW at 200% and SHRANK at 80%. A fit-only arm is blind to the raw-font defect,
## because small text fits by construction (cowir-story's measurement, cowir-main's rule).
func test_the_log_font_follows_the_setting_in_both_directions() -> void:
	var base: int = _log_font_at(1.0)
	assert_gt(base, 0, "CONTROL: the log must get a font size at all")
	var big: int = _log_font_at(2.0)
	var small: int = _log_font_at(0.8)
	assert_gt(big, base,
		"the log font must GROW at 200%: it was pinned at a raw 12, so this is the whole defect. "
		+ "100%%=%d 200%%=%d" % [base, big])
	assert_lt(small, base,
		"and SHRINK at 80%%, or the setting is only honoured upward. 80%%=%d 100%%=%d"
		% [small, base])


## Every preset, not just the endpoints — cowir-adhoc measured a defect that started at 125%.
func test_every_preset_moves_the_log_font_monotonically() -> void:
	var seen: Array = []
	for s in PRESETS:
		seen.append(_log_font_at(float(s)))
	for i in range(1, seen.size()):
		assert_true(int(seen[i]) >= int(seen[i - 1]),
			"the log font must never shrink as the setting rises (a 0.8x regression is how this "
			+ "class goes wrong): %s for %s" % [str(seen), str(PRESETS)])
	assert_true(int(seen[-1]) > int(seen[0]),
		"and the ladder must actually move across the range: %s" % str(seen))


## ARM 2 + ARM 4 — the panel must still be VISIBLE and its text must FIT, at every preset, against a
## roster tall enough to squeeze the gap. Visibility first: an invisible panel trivially fits.
func test_the_log_panel_stays_visible_and_fits_at_every_preset() -> void:
	for s in PRESETS:
		GameState.text_size_scale = float(s)
		_scene = load(SCENE).instantiate()
		add_child(_scene)
		await get_tree().process_frame
		var panel: Control = _scene.get_node_or_null("UI/BattleLogPanel")
		var enemy: Control = _scene.get_node_or_null("UI/EnemyStatusPanel")
		assert_false(panel == null, "fixture: the log panel must exist at %sx" % str(s))
		assert_false(enemy == null, "fixture: the enemy panel must exist at %sx" % str(s))
		if panel == null or enemy == null:
			return
		## A tall pull: five enemies is the field ceiling MAX_FIELD_ENEMIES enforces.
		enemy.custom_minimum_size.y = 300.0
		await get_tree().process_frame
		_scene._reposition_battle_log_panel_now()
		await get_tree().process_frame
		assert_true(panel.visible,
			("at %sx the log panel HID itself. Scaling the font without the panel's reserve trades "
			+ "'too small to read' for 'no log at all', which is strictly worse — and an invisible "
			+ "panel passes every fit assertion.") % str(s))
		var log_label: Control = _scene.get_node_or_null(
			"UI/BattleLogPanel/MarginContainer/VBoxContainer/BattleLog")
		assert_false(log_label == null, "fixture: the log label must exist at %sx" % str(s))
		if log_label != null:
			assert_true(log_label.size.y <= panel.size.y + 1.0,
				("at %sx the log text box (%.1f) ran past its panel (%.1f) — the derived chrome "
				+ "under-reserved.") % [str(s), log_label.size.y, panel.size.y])
		_scene.queue_free()
		_scene = null
		await get_tree().process_frame


## ARM 3 — the shrink-the-container mutation, driven through the REAL reposition path. Testing
## _log_panel_chrome() directly only proves the helper works; the mutation that matters replaces its
## CALLER with the 64 literal, and a helper-only arm is green through that. Grow the header and the
## panel must still budget correctly.
func test_a_grown_header_does_not_break_the_panels_budget() -> void:
	GameState.text_size_scale = 2.0
	_scene = load(SCENE).instantiate()
	add_child(_scene)
	await get_tree().process_frame
	var panel: Control = _scene.get_node_or_null("UI/BattleLogPanel")
	var enemy: Control = _scene.get_node_or_null("UI/EnemyStatusPanel")
	var title: Control = _scene.get_node_or_null(
		"UI/BattleLogPanel/MarginContainer/VBoxContainer/LogHeader/LogTitle")
	var log_label: Control = _scene.get_node_or_null(
		"UI/BattleLogPanel/MarginContainer/VBoxContainer/BattleLog")
	assert_false(panel == null or enemy == null or title == null or log_label == null,
		"fixture: panel, enemy panel, LogTitle and the log label must all exist")
	if panel == null or enemy == null or title == null or log_label == null:
		return
	## LogTitle is a THEMED node in the chrome — exactly what its own Text Size fix will grow, and
	## what made the hand-measured 64 wrong.
	title.custom_minimum_size.y = title.size.y + 40.0
	enemy.custom_minimum_size.y = 240.0
	await get_tree().process_frame
	_scene._reposition_battle_log_panel_now()
	await get_tree().process_frame
	assert_true(panel.visible,
		"a grown header must not hide the log: with a literal reserve the text is over-budgeted, the "
		+ "panel's true minimum passes the cap and the whole log vanishes")
	assert_true(log_label.size.y <= panel.size.y + 1.0,
		("the log text box (%.1f) must stay inside its panel (%.1f) with the header grown — a reserve "
		+ "that does not track the chrome hands the label room the panel does not have.")
		% [log_label.size.y, panel.size.y])


## ⛔ A CHANGE I MADE AND WITHDREW, recorded here because the next person will reach for it.
## Raising LOG_PANEL_MIN_TEXT_HEIGHT to a whole SCALED line looks like the obvious companion to
## scaling the font. It is backwards:
##   squeeze at 200%, available 80, chrome 64
##     literal 16 -> budget max(16, 16) = 16 -> a CLIPPED 30px line, but the log is VISIBLE
##     scaled  30 -> 80 < 64+30          -> the panel HIDES, and shows nothing at all
## A clipped newest line beats no log. There is NO ARM for it: I wrote one, and the mutation that
## re-applies the withdrawn change passed it, because the binding squeeze is not reachable through
## this fixture. A guard green in both worlds advertises teeth it does not have, so the reasoning
## lives here and at the constant rather than as a test that proves nothing.
