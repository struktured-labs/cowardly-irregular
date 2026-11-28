extends GutTest

## The operator button on a condition no evaluator compares (Has Status, Weather, Member Dead, Member Has Status…) wrote an op nothing reads and clicked menu_select; the autobattle editor's Always refusal said nothing.
## Each such press now plays menu_error, leaves the condition untouched and says why; a real operator still cycles and clicks. Read through cooldown stamps, whose CONTROL is the first arm.

const AB_EDITOR := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const AG_EDITOR := "res://src/ui/autogrind/AutogrindGridEditor.gd"
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const SfxState := preload("res://test/unit/helpers/sfx_state.gd")

## [editor, a condition whose op is compared, conditions whose op is not]
const CASES := [
	[AB_EDITOR, {"type": "hp_percent", "op": "<", "value": 50},
		[{"type": "always"}, {"type": "has_status", "status": "poison"}, {"type": "weather", "weather": "rain"}]],
	[AG_EDITOR, {"type": "party_hp_avg", "op": "<", "value": 50},
		[{"type": "always"}, {"type": "member_dead", "member": ""}, {"type": "member_status", "member": "", "value": "poison"}]],
]

var _abs
var _profiles_backup: Dictionary = {}
var _ag: Dictionary


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_abs = get_tree().root.get_node_or_null("AutobattleSystem")
	_profiles_backup = (_abs.character_profiles as Dictionary).duplicate(true)
	SoundManager._sfx_cooldowns.clear()


func after_each() -> void:
	var live: Dictionary = _abs.character_profiles
	live.clear()
	for k in _profiles_backup:
		live[k] = _profiles_backup[k]
	AutogrindState.restore(_ag)
	SoundManager._sfx_cooldowns.clear()
	SoundManager._sfx_suppressed_by_cooldown = false
	SfxState.release_streams()


func _stamped(key: String) -> bool:
	return SoundManager._sfx_cooldowns.has(key)


func _editor(path: String, cond: Dictionary) -> Node:
	var ed: Node = load(path).new()
	ed.size = Vector2(1280, 720)
	add_child_autofree(ed)
	await get_tree().process_frame
	var rules: Array = ed.get("rules") as Array
	rules.clear()
	rules.append({"conditions": [cond.duplicate(true)], "actions": [{"type": "attack"}], "enabled": true})
	ed.set("cursor_row", 0)
	ed.set("cursor_col", 0)
	ed._refresh_grid()
	assert_true(ed._is_on_condition_cell(), "CONTROL: the cursor is on the condition")
	SoundManager._sfx_cooldowns.clear()
	return ed


func _cond(ed: Node) -> Dictionary:
	return (((ed.get("rules") as Array)[0] as Dictionary)["conditions"] as Array)[0] as Dictionary


func _shown(ed: Node) -> String:
	var label: Label = ed.get("_flash_label") if ed.get("_flash_label") != null else ed.get("_status_label")
	return str(label.text) if label != null else ""


func _name(path: String) -> String:
	return path.get_file().get_basename()


func test_the_cue_oracle_can_see_a_cue() -> void:
	assert_false(_stamped("menu_error"), "FLOOR: the stamp table starts clean")
	SoundManager.play_ui("menu_error")
	assert_true(_stamped("menu_error"), "CONTROL: play_ui leaves a stamp, or every arm here measures nothing")


func test_an_operator_that_is_compared_still_cycles() -> void:
	for c in CASES:
		var ed: Node = await _editor(c[0], c[1])
		ed._cycle_condition_operator()
		assert_ne(str(_cond(ed).get("op", "")), "<", "CONTROL %s: the op moved on from <" % _name(c[0]))
		assert_true(_stamped("menu_select"), "%s: a real operator change must still click" % _name(c[0]))
		assert_false(_stamped("menu_error"), "%s: a real operator change must not play the refusal" % _name(c[0]))


func test_an_operator_no_evaluator_reads_is_refused_out_loud() -> void:
	var judged := 0
	for c in CASES:
		for cond in c[2]:
			var ed: Node = await _editor(c[0], cond)
			var before: Dictionary = _cond(ed).duplicate(true)
			ed._cycle_condition_operator()
			judged += 1
			assert_eq(_cond(ed), before, "%s: %s gained an operator nothing reads" % [_name(c[0]), cond["type"]])
			assert_true(_stamped("menu_error"), "%s: the operator press on %s was not refused" % [_name(c[0]), cond["type"]])
			assert_false(_stamped("menu_select"), "%s: the operator press on %s still clicked as a change" % [_name(c[0]), cond["type"]])
			assert_string_contains(_shown(ed), "no operator", "%s: the refusal on %s must say why" % [_name(c[0]), cond["type"]])
			SoundManager._sfx_cooldowns.clear()
	assert_eq(judged, 6, "FLOOR: every opless condition was driven")


## The evaluator itself is the oracle: a has_status condition answers the same whatever op it carries.
func test_the_refused_conditions_really_ignore_their_operator() -> void:
	var with_op := {"type": "has_status", "status": "poison", "op": ">", "value": 999}
	var bare := {"type": "has_status", "status": "poison"}
	var c := Combatant.new()
	autofree(c)
	c.status_effects.append("poison")
	assert_true(AutobattleSystem._evaluate_condition(c, bare), "CONTROL: a poisoned combatant matches Has Status poison")
	assert_eq(AutobattleSystem._evaluate_condition(c, with_op), AutobattleSystem._evaluate_condition(c, bare),
		"Has Status compares its op after all, so refusing the operator would hide a real setting")


## The grind twin (cowir-autogrind 28745): Member Has Status answers the same whatever op it carries.
func test_the_grind_status_condition_really_ignores_its_operator() -> void:
	var bare := {"type": "member_status", "member": "", "value": "poison"}
	var with_op := {"type": "member_status", "member": "", "value": "poison", "op": ">"}
	var c := Combatant.new()
	autofree(c)
	c.status_effects.append("poison")
	assert_true(AutogrindSystem._evaluate_party_condition([c], bare), "CONTROL: a poisoned member matches Member Has Status poison")
	assert_eq(AutogrindSystem._evaluate_party_condition([c], with_op), AutogrindSystem._evaluate_party_condition([c], bare),
		"Member Has Status compares its op after all, so refusing the operator would hide a real setting")
