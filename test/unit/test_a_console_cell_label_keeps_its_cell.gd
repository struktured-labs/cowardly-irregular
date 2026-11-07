extends GutTest

## The grind console's small cells (+AND, [+A], [ON]/[OFF], [+ Add Rule]) give their Label a centred box before it enters the tree.
## A Label sized there takes its minimum at the DEFAULT 16 px (controller 23066), so where the text at 16 px is wider than the box
## ("[OFF]" ~50 px in 42, "[+ Add Rule]" ~100 px in 92) the box clamps wider than its cell and the centred text sits off-centre,
## spilling past the cell edge. The labels now clip, so their box is the cell's. Judged on the BUILT label at every Text Size.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const UI := "res://src/ui/autogrind/AutogrindUI.gd"
const SMALL := ["empty_condition", "empty_action", "toggle", "add_rule"]

var _ag: Dictionary
var _scale_was: float = 1.0


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_scale_was = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _scale_was
	AutogrindState.restore(_ag)


func _presets() -> Array:
	var consts: Dictionary = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map()
	var p: Array = consts.get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must resolve, got %s" % [p])
	return p


func _party() -> Array[Combatant]:
	var out: Array[Combatant] = []
	for nm in ["Fighter", "Cleric"]:
		var c := Combatant.new()
		autofree(c)
		c.initialize({"name": nm, "max_hp": 100, "max_mp": 50})
		out.append(c)
	return out


## One enabled and one disabled rule, so both [ON] and [OFF] are built, and short rules so +AND and [+A] slots exist.
func _console(scale: float) -> Node:
	GameState.text_size_scale = scale
	var ok: bool = AutogrindSystem.set_autogrind_rules([
		{"enabled": true, "conditions": [{"type": "party_hp_avg", "op": "<", "value": 50}], "actions": [{"type": "heal_party"}]},
		{"enabled": false, "conditions": [{"type": "corruption", "op": ">", "value": 3}], "actions": [{"type": "restore_mp"}]},
	])
	assert_true(ok, "FLOOR: the fixture's rules must be ACCEPTED, or the arm measures the default grid")
	var ui: Node = load(UI).new()
	ui.size = Vector2(1280, 720)
	add_child_autofree(ui)
	ui.setup(_party())
	await wait_frames(3)
	return ui


func test_a_small_cell_label_keeps_its_cell_at_every_preset() -> void:
	var bad: Array = []
	var seen := {}
	for scale in _presets():
		var ui: Node = await _console(float(scale))
		for c in ui.find_children("*", "Control", true, false):
			if not (c as Control).has_meta("cell_type") or not (str((c as Control).get_meta("cell_type")) in SMALL):
				continue
			var cell := c as Control
			var w: float = cell.custom_minimum_size.x if cell.custom_minimum_size.x > 0.0 else cell.size.x
			for k in cell.get_children():
				if not (k is Label):
					continue
				var l := k as Label
				seen[str(l.text)] = true
				if l.position.x + l.size.x > w + 0.5:
					bad.append("%sx: '%s' box ends at %.0f in a %.0f px cell" % [scale, l.text, l.position.x + l.size.x, w])
	for t in ["+AND", "[+A]", "[ON]", "[OFF]", "[+ Add Rule]"]:
		assert_true(seen.has(t), "CONTROL: the console built a '%s' cell (built: %s)" % [t, seen.keys()])
	assert_eq(bad, [], "a small console cell's label box runs past its cell: %s" % [bad])
