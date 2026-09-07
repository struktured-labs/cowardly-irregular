extends GutTest

## Feature 2026-07-04: the battle ability tooltip now leads with the ability's
## element ("Fire · Deals fire damage...") so it pairs at a glance with the
## enemy panel's "Weak: Fire" intel. Non-elemental abilities (JSON element
## null) get no prefix — and must NEVER render the literal "None". Chokepoint:
## BattleCommandMenu._build_ability_menu_item builds one ability_tooltip that
## every target-type branch reuses.

const BCM := preload("res://src/battle/BattleCommandMenu.gd")


func _broke_combatant() -> Combatant:
	# 0 MP forces every special branch (all of which require can_afford) to skip,
	# landing on the default flat entry that never dereferences _scene — so the
	# menu can be built with a null scene.
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Caster"
	c.current_mp = 0
	c.max_mp = 0
	return c


func _item(ability_id: String) -> Dictionary:
	var menu := BCM.new(null)
	var empty: Array[Combatant] = []
	return menu._build_ability_menu_item(ability_id, _broke_combatant(), empty, Transform2D.IDENTITY)


func test_elemental_ability_tooltip_leads_with_element() -> void:
	var item := _item("fire")
	assert_false(item.is_empty(), "fire must resolve to a menu item")
	assert_true((item.get("tooltip", "") as String).begins_with("Fire ·"),
		"an elemental ability's tooltip must lead with its element (got: %s)" % item.get("tooltip", ""))


func test_nonelemental_ability_has_no_element_prefix() -> void:
	var item := _item("cure")
	assert_false(item.is_empty(), "cure must resolve to a menu item")
	var tip: String = item.get("tooltip", "")
	assert_false(tip.begins_with("None ·"),
		"a JSON-null element must never leak as the literal 'None' (got: %s)" % tip)
	assert_gt(tip.length(), 0, "cure still shows its description as the tooltip")


func test_source_pins_the_null_guard() -> void:
	# The null guard is the whole point — ability.get("element") returns null for
	# 216 of 286 abilities; str(null) would print "<null>" without it.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleCommandMenu.gd")
	assert_true(src.contains("element_val != null"),
		"the element prefix must guard against the JSON-null element value")
