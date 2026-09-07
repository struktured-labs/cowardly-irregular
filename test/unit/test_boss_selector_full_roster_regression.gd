extends GutTest

## Regression test for the 2026-07-25 playtest ask:
## "should be able to fight mordaine in the fight boss debug menu thingy
##  (and any boss for that matter)".
##
## BossSelectorMenu.BOSSES was a hardcoded list of exactly the 20 Masterites.
## monsters.json carries 37 boss:true entries plus 9 miniboss-only ones, so
## Chancellor Mordaine, all four elemental dragons, the Cave Rat King and every
## spotlight duelist were unreachable from the debug launcher — with nothing
## flagging the drift, because a hardcoded list can't know what it's missing.
##
## The roster is now DERIVED from monsters.json. These assertions are
## relationship-form: they compare the menu's roster against the data file at
## test time rather than against a copied list, so a boss added to the data is
## either fightable or this test fails.

const SelectorScript := preload("res://src/ui/BossSelectorMenu.gd")


func _data_boss_ids() -> Dictionary:
	var src := FileAccess.get_file_as_string("res://data/monsters.json")
	var parsed = JSON.parse_string(src)
	assert_true(parsed is Dictionary, "monsters.json must parse")
	var monsters = parsed.get("monsters", parsed)
	var out := {}
	for mid in monsters:
		var m = monsters[mid]
		if m is Dictionary and (m.get("boss", false) or m.get("miniboss", false)):
			out[str(mid)] = true
	return out


func test_roster_covers_every_boss_in_the_data() -> void:
	var roster: Array = SelectorScript.load_boss_roster()
	var listed := {}
	for r in roster:
		listed[str(r["id"])] = true

	var missing: Array = []
	for mid in _data_boss_ids():
		if not listed.has(mid):
			missing.append(mid)

	assert_eq(
		missing, [],
		"every boss/miniboss in monsters.json must be fightable from the debug menu — "
		+ "a hardcoded list silently omitted 17 of them, including the W1 final boss"
	)


func test_the_specific_bosses_struktured_named_are_present() -> void:
	var roster: Array = SelectorScript.load_boss_roster()
	var ids := {}
	for r in roster:
		ids[str(r["id"])] = true
	# Mordaine by name, plus the set that was missing alongside her.
	for required in [
		"chancellor_mordaine",      # "should be able to fight mordaine"
		"cave_rat_king",            # W1 tutorial boss
		"fire_dragon", "ice_dragon", "lightning_dragon", "shadow_dragon",
		"fighter_skeleton_knight",  # spotlight duelists
		"bard_hostile_courtier",
	]:
		assert_true(ids.has(required), "'%s' must appear in the boss selector" % required)


func test_roster_is_not_empty_and_beats_the_old_hardcoded_count() -> void:
	var roster: Array = SelectorScript.load_boss_roster()
	assert_gt(roster.size(), 20, "the derived roster must exceed the old 20-Masterite hardcoded list")


func test_every_entry_has_the_fields_the_menu_renders() -> void:
	for r in SelectorScript.load_boss_roster():
		assert_true(r.has("id") and r.has("name") and r.has("world"),
			"each roster row needs id/name/world — _build_display_list groups on 'world'")
		assert_ne(str(r["name"]), "", "a blank name would render an empty row")


func test_story_bosses_sort_before_the_twenty_masterites() -> void:
	# Ordering is the usability half of the fix: 20 Masterites ahead of Mordaine
	# would leave her just as hard to reach as when she was absent.
	var roster: Array = SelectorScript.load_boss_roster()
	var first_masterite := -1
	var mordaine := -1
	for i in range(roster.size()):
		var rid := str(roster[i]["id"])
		if first_masterite < 0 and rid.begins_with("masterite_"):
			first_masterite = i
		if rid == "chancellor_mordaine":
			mordaine = i
	assert_gt(mordaine, -1, "Mordaine must be in the roster")
	assert_gt(first_masterite, -1, "Masterites must still be in the roster")
	assert_lt(mordaine, first_masterite, "story bosses must sort ahead of the 20 Masterites")


func test_group_assignment_is_stable_for_each_family() -> void:
	assert_eq(SelectorScript._group_for("masterite_warden_medieval", true, false), "Medieval")
	assert_eq(SelectorScript._group_for("masterite_curator_abstract", true, false), "Abstract")
	assert_eq(SelectorScript._group_for("fighter_skeleton_knight", true, false), "Spotlight Duels")
	assert_eq(SelectorScript._group_for("cave_troll", false, true), "Minibosses")
	assert_eq(SelectorScript._group_for("chancellor_mordaine", true, false), "Story")
