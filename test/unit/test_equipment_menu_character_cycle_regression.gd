extends GutTest

## struktured 2026-09-06: "should be able to switch who ur equipping in the menu with L/R or
## something (or L2/R2)". battle_defer / battle_advance carry both the shoulders AND the
## triggers (project.godot binds LB + axis 4, RB + axis 5), so one arm covers his "or".

const SRC := "res://src/ui/EquipmentMenu.gd"


class FakeGameLoop:
	extends Node
	var party: Array = []


func _combatant(n: String) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = n
	return c


func _rig() -> Dictionary:
	var gl := FakeGameLoop.new()
	gl.name = "GameLoop"
	var a := _combatant("Alpha")
	var b := _combatant("Beta")
	var c := _combatant("Gamma")
	gl.party = [a, b, c]
	get_tree().root.add_child(gl)
	var menu: Control = load(SRC).new()
	add_child_autofree(menu)
	menu.setup(b, [], [], [])
	return {"gl": gl, "menu": menu, "a": a, "b": b, "c": c}


func _teardown(r: Dictionary) -> void:
	r["gl"].free()
	for k in ["a", "b", "c"]:
		r[k].free()


func test_advance_moves_to_the_next_party_member() -> void:
	var r := _rig()
	r["menu"]._cycle_character(1)
	assert_eq(r["menu"].character, r["c"], "R / R2 must re-target the NEXT member")
	_teardown(r)


func test_defer_moves_to_the_previous_member_and_wraps() -> void:
	var r := _rig()
	r["menu"]._cycle_character(-1)
	assert_eq(r["menu"].character, r["a"], "L / L2 must re-target the PREVIOUS member")
	r["menu"]._cycle_character(-1)
	assert_eq(r["menu"].character, r["c"], "and wrap around the party")
	_teardown(r)


func test_cycle_returns_to_slot_mode() -> void:
	var r := _rig()
	r["menu"].mode = r["menu"].Mode.ITEM_SELECT
	r["menu"].selected_item_index = 3
	r["menu"]._cycle_character(1)
	assert_eq(r["menu"].mode, r["menu"].Mode.SLOT_SELECT, "a new character starts at slot selection")
	assert_eq(r["menu"].selected_item_index, 0, "and never inherits the previous item cursor")
	_teardown(r)


func test_solo_party_is_a_no_op() -> void:
	var gl := FakeGameLoop.new()
	gl.name = "GameLoop"
	var solo := _combatant("Solo")
	gl.party = [solo]
	get_tree().root.add_child(gl)
	var menu: Control = load(SRC).new()
	add_child_autofree(menu)
	menu.setup(solo, [], [], [])
	menu._cycle_character(1)
	assert_eq(menu.character, solo, "nothing to cycle to")
	gl.free()
	solo.free()


func test_input_arms_are_wired_to_both_shoulder_actions() -> void:
	var src := FileAccess.get_file_as_string(SRC)
	var i: int = src.find("func _handle_slot_input(")
	var body: String = src.substr(i, 1600)
	assert_true(body.contains('is_action_pressed("battle_defer")') and body.contains("_cycle_character(-1)"),
		"L must cycle backward from slot mode")
	assert_true(body.contains('is_action_pressed("battle_advance")') and body.contains("_cycle_character(1)"),
		"R must cycle forward from slot mode")
