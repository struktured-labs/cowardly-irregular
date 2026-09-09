extends GutTest

## Terrain and weather damage modifiers key on ELEMENT, not on ability type — but both had
## exactly ONE call site, inside _execute_magic_ability. A lightning DASH got no storm bonus
## while a lightning SPELL did, purely because of which function it runs through.

const BM := "res://src/battle/BattleManager.gd"

func _src() -> String:
	var s := FileAccess.get_file_as_string(BM)
	assert_gt(s.length(), 1000, "CONTROL: read BattleManager")
	return s

func _abilities() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	assert_not_null(parsed, "CONTROL: abilities.json parses")
	return parsed.get("abilities", parsed)

func _elemental_physicals() -> Array:
	var out: Array = []
	var ab := _abilities()
	for id in ab:
		var a: Dictionary = ab[id]
		if str(a.get("type", "")) == "physical" and str(a.get("element", "")) != "":
			out.append(str(id))
	out.sort()
	return out

func test_the_population_this_defends_exists() -> void:
	## If this ever hits 0 the fix below is untested, not unnecessary.
	var e := _elemental_physicals()
	assert_gt(e.size(), 3,
		"CONTROL: physical abilities DO carry elements (%d): %s" % [e.size(), str(e)])
	assert_true("lightning_dash" in e, "CONTROL: the storm-bonus case is in the corpus")

func test_both_modifiers_reach_the_physical_ability_path() -> void:
	var s := _src()
	var i := s.find("func _execute_physical_ability(")
	assert_gt(i, -1, "CONTROL: located the physical ability path")
	var j := s.find("\nfunc ", i + 10)
	var body := s.substr(i, j - i)
	assert_true(body.contains("get_weather_damage_modifier("),
		"an elemental physical ability must take the weather modifier")
	assert_true(body.contains("get_terrain_damage_modifier("),
		"and the terrain modifier — they were applied together in the magic path and belong together here")

func test_the_modifiers_are_gated_on_the_ability_having_an_element() -> void:
	## Strictly additive: an elementless physical ability must resolve exactly as before, or all
	## 68 of them change damage at once.
	var s := _src()
	var i := s.find("var phys_element: String = str(ability.get(\"element\", \"\"))")
	assert_gt(i, -1, "the element must be read from the ability")
	var body := s.substr(i, 320)
	assert_true(body.contains("if phys_element != \"\":"),
		"elementless physical abilities must skip the modifiers entirely")

func test_the_magic_path_still_has_them() -> void:
	## Guards the pair: this fix adds a second call site, it must not have MOVED the first.
	var s := _src()
	var i := s.find("func _execute_magic_ability(")
	assert_gt(i, -1, "CONTROL: located the magic path")
	var j := s.find("\nfunc ", i + 10)
	var body := s.substr(i, j - i)
	assert_true(body.contains("get_weather_damage_modifier("), "the magic path keeps its weather modifier")
	assert_true(body.contains("get_terrain_damage_modifier("), "and its terrain modifier")

func test_the_basic_attack_path_correctly_has_neither() -> void:
	## A basic attack is elementless by definition, so it must NOT gain these — the negative
	## control that proves the fix was scoped by element rather than sprayed across every path.
	var s := _src()
	var i := s.find("func _execute_attack(")
	var j := s.find("\nfunc ", i + 10)
	var body := s.substr(i, j - i)
	assert_false(body.contains("get_weather_damage_modifier("),
		"basic attacks carry no element — an elemental modifier there would be wrong")
