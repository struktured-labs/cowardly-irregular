extends GutTest

## L on an Always rule, or on a rule already holding its cap of conditions, did nothing and said nothing.
## Both editors now play menu_error and flash why, from one shared rule (AutobattleGridEditor.and_condition_refusal).

const AB_EDITOR := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const AG_EDITOR := "res://src/ui/autogrind/AutogrindGridEditor.gd"
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const SfxState := preload("res://test/unit/helpers/sfx_state.gd")
const CUES := ["menu_error", "menu_select", "menu_expand"]

var _abs
var _profiles_backup: Dictionary = {}
var _ag: Dictionary
var _saved_scale = null


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_abs = get_tree().root.get_node_or_null("AutobattleSystem")
	_profiles_backup = (_abs.character_profiles as Dictionary).duplicate(true)
	_clear()


func after_each() -> void:
	var live: Dictionary = _abs.character_profiles
	live.clear()
	for k in _profiles_backup:
		live[k] = _profiles_backup[k]
	AutogrindState.restore(_ag)
	if _saved_scale != null:
		GameState.text_size_scale = _saved_scale
	_clear()
	SoundManager._sfx_suppressed_by_cooldown = false
	SfxState.release_streams()


func _clear() -> void:
	SoundManager._ui_player.stream = null
	for k in CUES:
		SoundManager._sfx_cooldowns.erase(k)


func _file(key: String) -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}
	return str((sfx.get(key, {}) as Dictionary).get("file", ""))


func _heard() -> String:
	var s: AudioStream = SoundManager._ui_player.stream
	return s.resource_path.trim_prefix("res://") if s != null else ""


func _editor(path: String, conditions: Array) -> Node:
	var ed: Node = load(path).new()
	ed.size = Vector2(1280, 720)
	add_child_autofree(ed)
	await get_tree().process_frame
	var rules: Array = ed.get("rules") as Array
	rules.clear()
	rules.append({"conditions": conditions.duplicate(true), "actions": [{"type": "attack"}], "enabled": true})
	ed.set("cursor_row", 0)
	ed.set("cursor_col", 0)
	ed._refresh_grid()
	_clear()
	return ed


func _count(ed: Node) -> int:
	return (((ed.get("rules") as Array)[0] as Dictionary)["conditions"] as Array).size()


func _shown(ed: Node) -> String:
	var label: Label = ed.get("_flash_label") if ed.get("_flash_label") != null else ed.get("_status_label")
	return str(label.text) if label != null else ""


const ALWAYS := [{"type": "always"}]
const ONE := [{"type": "hp_percent", "op": "<", "value": 50}]


func _full(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({"type": "hp_percent", "op": "<", "value": 50 + i})
	return out


func test_the_shared_rule_names_each_refusal_and_lets_a_plain_rule_through() -> void:
	assert_eq(AutobattleGridEditor.and_condition_refusal(ONE, 3), "", "CONTROL: a one-condition rule can take another")
	assert_string_contains(AutobattleGridEditor.and_condition_refusal(ALWAYS, 3), "Always", "an Always rule must say why")
	assert_string_contains(AutobattleGridEditor.and_condition_refusal(_full(3), 3), "3", "a full rule must name its cap")


func test_l_on_a_plain_rule_still_adds_a_condition_in_both_editors() -> void:
	for path in [AB_EDITOR, AG_EDITOR]:
		var ed: Node = await _editor(path, ONE)
		assert_true(ed._add_and_condition(), "CONTROL %s: the add reports success" % path.get_file())
		assert_eq(_count(ed), 2, "CONTROL %s: a plain rule took the condition" % path.get_file())
		assert_eq(_heard(), _file("menu_expand"), "CONTROL %s: an add is still heard as menu_expand" % path.get_file())
		_clear()


func test_l_on_an_always_rule_is_refused_out_loud_in_both_editors() -> void:
	for path in [AB_EDITOR, AG_EDITOR]:
		var ed: Node = await _editor(path, ALWAYS)
		assert_false(ed._add_and_condition(), "%s: an Always rule must refuse" % path.get_file())
		assert_eq(_count(ed), 1, "%s: the Always rule must be unchanged" % path.get_file())
		assert_eq(_heard(), _file("menu_error"), "%s: L on an Always rule was silent" % path.get_file())
		assert_string_contains(_shown(ed), "Always", "%s: the refusal must say why" % path.get_file())
		_clear()


func test_l_on_a_full_rule_is_refused_out_loud_in_both_editors() -> void:
	for path in [AB_EDITOR, AG_EDITOR]:
		var cap: int = int(load(path).get_script_constant_map().get("MAX_CONDITIONS", 0))
		assert_gt(cap, 0, "CONTROL %s: MAX_CONDITIONS is read from the editor" % path.get_file())
		var ed: Node = await _editor(path, _full(cap))
		assert_false(ed._add_and_condition(), "%s: a full rule must refuse" % path.get_file())
		assert_eq(_count(ed), cap, "%s: the full rule must be unchanged" % path.get_file())
		assert_eq(_heard(), _file("menu_error"), "%s: L on a full rule was silent" % path.get_file())
		assert_string_contains(_shown(ed), str(cap), "%s: the refusal must name the cap" % path.get_file())
		_clear()



# ── the two sentences, measured in each editor's slot at every Text Size ──────



func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must resolve, got %s" % [p])
	return p


## A 1280x720 editor at this Text Size, set up the way the game opens it, holding one rule of these conditions.
func _on_screen(path: String, scale: float, conditions: Array) -> Control:
	GameState.text_size_scale = scale
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	var ed: Control = load(path).new()
	ed.size = Vector2(1280, 720)
	vp.add_child(ed)
	await get_tree().process_frame
	if path == AB_EDITOR:
		ed.setup("hero", "Hero")
	else:
		ed.setup([])
	await get_tree().process_frame
	var rules: Array = ed.get("rules") as Array
	rules.clear()
	rules.append({"conditions": conditions.duplicate(true), "actions": [{"type": "attack"}], "enabled": true})
	ed.set("cursor_row", 0)
	ed.set("cursor_col", 0)
	ed._refresh_grid()
	return ed


func _refusals(path: String) -> Array:
	var cap: int = int(load(path).get_script_constant_map().get("MAX_CONDITIONS", 0))
	return [["always", ALWAYS], ["full", _full(cap)]]


func test_the_autobattle_flash_holds_each_refusal_at_every_text_size() -> void:
	_saved_scale = GameState.text_size_scale
	for s in _presets():
		for r in _refusals(AB_EDITOR):
			var ed: Control = await _on_screen(AB_EDITOR, float(s), r[1])
			var why: String = AutobattleGridEditor.and_condition_refusal(r[1], int(ed.MAX_CONDITIONS))
			assert_false(ed._add_and_condition(), "CONTROL @%s %s: refused" % [s, r[0]])
			await get_tree().process_frame
			var l: Label = ed._flash_label
			var tag := "@%sx %s" % [s, r[0]]
			assert_eq(str(l.text), why, "CONTROL %s: the flash shows the refusal" % tag)
			var lines: int = l.get_line_count()
			assert_gt(lines, 0, "CONTROL %s: the label laid its text out" % tag)
			assert_lte(lines * l.get_line_height(), l.size.y + 0.5, "%s: %d line(s) fit the flash's %.0f px height" % [tag, lines, l.size.y])
			assert_gte(l.position.x, 0.0, "%s: starts on screen" % tag)
			assert_lte(l.position.x + l.size.x, ed.size.x, "%s: ends on screen" % tag)
			assert_lte(l.position.y + l.size.y, ed.size.y - float(ed._legend_h), "%s: ends above the legend strip" % tag)
			ed.queue_free()
	GameState.text_size_scale = _saved_scale


func test_the_grind_status_holds_each_refusal_on_one_line_at_every_text_size() -> void:
	_saved_scale = GameState.text_size_scale
	for s in _presets():
		for r in _refusals(AG_EDITOR):
			var ed: Control = await _on_screen(AG_EDITOR, float(s), r[1])
			var why: String = AutobattleGridEditor.and_condition_refusal(r[1], int(ed.MAX_CONDITIONS))
			assert_false(ed._add_and_condition(), "CONTROL @%s %s: refused" % [s, r[0]])
			await get_tree().process_frame
			var l: Label = ed._status_label
			var tag := "@%sx %s" % [s, r[0]]
			assert_eq(str(l.text), why, "CONTROL %s: the status shows the refusal" % tag)
			var px: int = l.get_theme_font_size("font_size")
			var w: float = l.get_theme_font("font").get_string_size(why, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			assert_lte(w, l.size.x + 0.5, "%s: '%s' (%.0f px) fits the %.0f px status box" % [tag, why, w, l.size.x])
			assert_lte(l.position.x + l.size.x, 1280.0, "%s: the status box stays on screen" % tag)
			ed.queue_free()
	GameState.text_size_scale = _saved_scale
