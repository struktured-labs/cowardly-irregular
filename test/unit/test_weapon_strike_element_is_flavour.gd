extends GutTest

## An element on a PHYSICAL ability is flavour, not a mechanic. Six abilities carry one
## (lightning_dash, dark_slash, cursed_strike, glitch_strike, permakill_strike, toxic_embrace) and
## the damage code consults it nowhere.
##
## This guard exists because the asymmetry LOOKS like a gap. I read it as one on 2026-09-09, added
## weather scaling to the physical path, shipped it in .242 and reverted it the same day: it made
## weather the ONLY mechanical consequence of an element on a weapon strike, so a storm boosted
## lightning_dash while the target's lightning IMMUNITY stayed ignored. An asymmetry is evidence of
## a decision at least as often as evidence of an omission, and nothing recorded which this was.

const BM := "res://src/battle/BattleManager.gd"
const HR := "res://src/autogrind/HeadlessBattleResolver.gd"

## CODE ONLY — comment lines stripped. The docstring under test names the very symbols it says are
## absent ("calculate_elemental_modifier 0"), so counting raw text scores 2 for a function that
## calls it 0 times. Caught by this file's first run: the guard failed on the prose explaining why
## it should pass. Every source-text assertion in this repo wants this, not just this one.
func _fn_body(path: String, header: String) -> String:
	var s := FileAccess.get_file_as_string(path)
	assert_gt(s.length(), 1000, "CONTROL: read %s" % path)
	var i := s.find(header)
	assert_gt(i, -1, "CONTROL: located %s" % header)
	var j := s.find("\nfunc ", i + 10)
	var code: PackedStringArray = []
	for line in s.substr(i, j - i).split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		code.append(line)
	return "\n".join(code)

func test_the_population_exists() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	assert_not_null(parsed, "CONTROL: abilities.json parses")
	var ab: Dictionary = parsed.get("abilities", parsed)
	var six: Array = []
	for id in ab:
		var a: Dictionary = ab[id]
		if str(a.get("type", "")) == "physical" and str(a.get("element", "")) != "":
			six.append(str(id))
	assert_gt(six.size(), 3,
		"CONTROL: physical abilities DO carry elements (%d) — if this hits 0 the guard is untested, not unnecessary" % six.size())

func test_the_live_physical_path_consults_no_element() -> void:
	var body := _fn_body(BM, "func _execute_physical_ability(")
	assert_eq(body.count("calculate_elemental_modifier"), 0, "no elemental resistance on a weapon strike")
	assert_eq(body.count("take_elemental_damage"), 0, "no elemental damage routing")
	assert_eq(body.count("get_weather_damage_modifier"), 0,
		"no weather scaling — this is the exact line I added and reverted")
	assert_eq(body.count("get_terrain_damage_modifier"), 0, "and no terrain scaling")

func test_the_magic_path_DOES_consult_it() -> void:
	## The half that makes the above a DECISION rather than a dead file. Without this, "no
	## elemental calls anywhere" would pass just as well and prove nothing.
	var body := _fn_body(BM, "func _execute_magic_ability(")
	assert_gt(body.count("calculate_elemental_modifier"), 0, "CONTROL: magic consults resistance")
	assert_gt(body.count("get_weather_damage_modifier"), 0, "CONTROL: magic takes the weather modifier")

func test_the_physical_path_treats_its_damage_as_elementless() -> void:
	## The sharpest single piece of evidence: the absorption helper is handed an EMPTY element.
	var body := _fn_body(BM, "func _execute_physical_ability(")
	assert_true(body.contains("_maybe_heal_from_damage(target, hit_damage, \"\")"),
		"physical damage is passed downstream with no element at all")

func test_headless_agrees_independently() -> void:
	## Corroboration that is NOT a re-badged premise: a second damage path, different author,
	## same position. cowir-autogrind measured this; asserted here so the two cannot drift.
	var s := FileAccess.get_file_as_string(HR)
	var i := s.find("match category:")
	assert_gt(i, -1, "CONTROL: located the headless dispatch")
	var tail := s.substr(i)
	var magic_at := tail.find("\"magic\":")
	var phys_at := tail.find("\"physical\":")
	assert_gt(magic_at, -1, "CONTROL: the magic arm exists")
	assert_gt(phys_at, -1, "CONTROL: the physical arm exists")
	var magic_arm := tail.substr(magic_at, phys_at - magic_at) if phys_at > magic_at else tail.substr(magic_at, 900)
	assert_gt(magic_arm.count("calculate_elemental_modifier"), 0,
		"headless magic applies the elemental modifier — so its physical arm omitting it is a stance, not an oversight")
