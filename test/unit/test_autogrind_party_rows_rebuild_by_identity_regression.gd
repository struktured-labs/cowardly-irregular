extends GutTest

## After every grind battle the console rebuilt its party rows by deleting whatever sat in a y band (28..120 px). At 100%
## a 5th member's row sits at y=124, so it was never removed and a new one stacked on it each battle (its HP bar kept the
## old fill under the new); larger Text Sizes left more rows behind. With a small party the band instead held the SAVED
## PRESETS / RECENT SESSIONS lines, which were deleted and never rebuilt. Rows are now removed by identity.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const UI := "res://src/ui/autogrind/AutogrindUI.gd"

var _ag: Dictionary
var _scale_was: float = 1.0
var _history_was: Array = []


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_scale_was = float(GameState.text_size_scale)
	_history_was = AutogrindSystem.session_history.duplicate(true)


func after_each() -> void:
	GameState.text_size_scale = _scale_was
	AutogrindSystem.session_history = _history_was
	AutogrindState.restore(_ag)


func _presets() -> Array:
	var p: Array = load("res://src/ui/SettingsMenu.gd").get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	return p


func _party(names: Array) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for nm in names:
		var c := Combatant.new()
		autofree(c)
		c.initialize({"name": nm, "max_hp": 100, "max_mp": 50})
		out.append(c)
	return out


func _console(scale: float, party: Array[Combatant]) -> Control:
	GameState.text_size_scale = scale
	var ui: Control = load(UI).new()
	ui.size = Vector2(1280, 720)
	add_child_autofree(ui)
	ui.setup(party)
	await wait_frames(3)
	return ui


## How many Labels under the status panel read exactly `text`.
func _count(ui: Control, text: String) -> int:
	var panel: Node = ui.get("_status_panel")
	var n := 0
	var stack: Array = [panel] if panel != null else []
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Label and (node as Label).text == text:
			n += 1
		stack.append_array(node.get_children())
	return n


func test_the_floor_names_every_member_this_file_drives() -> void:
	assert_gte(_presets().size(), 2, "SettingsMenu.TEXT_SIZE_PRESETS must exist and offer a choice (%s)" % [_presets()])
	var ui: Array = (load(UI) as GDScript).get_script_method_list().map(func(m): return str(m["name"]))
	for f in ["setup", "update_party_status"]:
		assert_has(ui, f, "AutogrindUI.%s must exist" % f)
	var props: Array = (load(UI) as GDScript).get_script_property_list().map(func(p): return str(p["name"]))
	assert_has(props, "_status_panel", "AutogrindUI._status_panel must exist (rows are counted under it)")
	assert_true("session_history" in AutogrindSystem, "AutogrindSystem.session_history must exist (the fixture writes it)")


func test_a_rebuild_leaves_one_row_per_member_at_every_text_size() -> void:
	var names := ["Fighter", "Cleric", "Mage", "Rogue", "Bard"]
	for s in _presets():
		var ui := await _console(float(s), _party(names))
		for nm in names:
			assert_eq(_count(ui, nm), 1, "CONTROL: one %s row as built at %s" % [nm, s])
		ui.update_party_status()
		ui.update_party_status()
		await wait_frames(2)
		for nm in names:
			assert_eq(_count(ui, nm), 1, "after two battles %s has ONE row at %sx, not a stack of stale ones" % [nm, s])
		ui.queue_free()
		await get_tree().process_frame


func test_a_rebuild_keeps_the_session_lines_of_a_small_party() -> void:
	AutogrindSystem.session_history = [{"battles": 3, "total_exp": 120, "duration_sec": 75, "reason": "manual"}]
	for s in _presets():
		var ui := await _console(float(s), _party(["Fighter", "Cleric"]))
		assert_eq(_count(ui, "RECENT SESSIONS"), 1, "CONTROL: the session heading is built at %s" % s)
		ui.update_party_status()
		await wait_frames(2)
		assert_eq(_count(ui, "RECENT SESSIONS"), 1, "a party rebuild at %sx keeps the session heading it does not own" % s)
		assert_eq(_count(ui, "Fighter"), 1, "and rebuilds the Fighter row it does own at %sx" % s)
		ui.queue_free()
		await get_tree().process_frame
