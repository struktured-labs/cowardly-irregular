extends "res://addons/gut/test.gd"

## TestBattleBDFFHDHudStrip - Verifies HUD state binding, UI updates and elements.
## Ensure safety & reliable execution headless.

const HudStripClass = preload("res://src/ui/autogrind/BattleBDFFHDHudStrip.gd")
const CombatantClass = preload("res://src/battle/Combatant.gd")

var _hud: BattleBDFFHDHudStrip
var _combatant_1: Combatant
var _combatant_2: Combatant

func before_each() -> void:
	_hud = HudStripClass.new()
	add_child_autoqfree(_hud)
	
	_combatant_1 = CombatantClass.new()
	_combatant_1.combatant_name = "Alice"
	_combatant_1.max_hp = 100
	_combatant_1.current_hp = 100
	_combatant_1.is_alive = true
	_combatant_1.current_ap = 2
	_combatant_1.autobattle_locked = false
	
	_combatant_2 = CombatantClass.new()
	_combatant_2.combatant_name = "Bob"
	_combatant_2.max_hp = 150
	_combatant_2.current_hp = 30
	_combatant_2.is_alive = true
	_combatant_2.current_ap = -1
	_combatant_2.autobattle_locked = true

func test_hud_generation() -> void:
	_hud._build_hud_strip()
	assert_eq(_hud._party_columns.size(), 5, "Should generate exactly 5 columns for a 5-PC party.")
	
	for i in range(5):
		var col = _hud._party_columns[i]
		assert_not_null(col.get_node("HeaderRow/NameLabel"), "Name label must exist.")
		assert_not_null(col.get_node("HeaderRow/TrustLabel"), "Trust/AI label must exist.")
		assert_not_null(col.get_node("HPBar"), "HP progress bar must exist.")
		assert_not_null(col.get_node("HPBar/HPLabel"), "HP text label overlay must exist.")
		assert_not_null(col.get_node("APLabel"), "AP rich label indicator must exist.")

func test_hud_update_state_bindings() -> void:
	_hud._build_hud_strip()
	var party = [_combatant_1, _combatant_2]
	_hud.update_hud(party)
	
	# Verify Column 1 (Alice - Manual)
	var col1 = _hud._party_columns[0]
	assert_true(col1.visible, "Column 1 should be visible.")
	assert_eq(col1.get_node("HeaderRow/NameLabel").text, "Alice")
	assert_eq(col1.get_node("HeaderRow/TrustLabel").text, "Manual")
	assert_eq(col1.get_node("HPBar").value, 100.0)
	assert_eq(col1.get_node("HPBar/HPLabel").text, "HP: 100/100")
	assert_string_contains(col1.get_node("APLabel").text, "AP: +2")

	# Verify Column 2 (Bob - Trust / AI)
	var col2 = _hud._party_columns[1]
	assert_true(col2.visible, "Column 2 should be visible.")
	assert_eq(col2.get_node("HeaderRow/NameLabel").text, "Bob")
	assert_eq(col2.get_node("HeaderRow/TrustLabel").text, "Trust / AI")
	assert_eq(col2.get_node("HPBar").value, 30.0)
	assert_eq(col2.get_node("HPBar/HPLabel").text, "HP: 30/150")
	assert_string_contains(col2.get_node("APLabel").text, "AP: -1")

	# Columns 3, 4, 5 should be hidden since party size is 2
	assert_false(_hud._party_columns[2].visible, "Column 3 should be hidden.")
	assert_false(_hud._party_columns[3].visible, "Column 4 should be hidden.")
	assert_false(_hud._party_columns[4].visible, "Column 5 should be hidden.")

func test_hud_ko_state_binding() -> void:
	_hud._build_hud_strip()
	_combatant_1.is_alive = false
	_combatant_1.current_hp = 0
	
	_hud.update_hud([_combatant_1])
	var col = _hud._party_columns[0]
	assert_eq(col.get_node("HPBar/HPLabel").text, "KO")
