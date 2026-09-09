extends GutTest

## struktured asked for the BD2 field elite and the monster moods by name on 2026-09-06. Both
## SHIPPED in v3.33.225 and neither has ever worked in play, for two separate reasons — so this
## file asserts the VALUES the feature produces, not that its code exists. A source-text test
## would have passed throughout (cowir-overworld's own words after finding the first cause).
##
##   cause 1, fixed v3.33.242: BestiarySystem is a class_name with STATIC functions and is NOT an
##           autoload, so get_node_or_null returned null forever. _is_field_elite read false for
##           EVERY monster and _monster_level read 1 for every monster.
##   cause 2, OPEN — deliberately not fixed here: only dark_knight carries the `field_elite` flag
##           the solo guard reads, so five of six worlds' elites still spawn with duplicates. The
##           obvious patch (flag the other five) is WRONG: those five are also each world's apex
##           ORDINARY monster, and _apply_field_elite_scaling fires on the species flag for EVERY
##           encounter — so it would turn common suburban/steampunk/industrial/futuristic/abstract
##           encounters into party-average+5, x3 HP, x8 EXP fights. Measured against enemy_pools.json:
##           dark_knight is the only one absent from the ordinary pools, which is exactly why it is
##           the only one flagged. The real fix carries elite-ness through the SPAWN (RoamingMonster
##           already has an `elite` bool the spawner sets); the species flag cannot express it.
##           cowir-overworld owns that; this file pins the gap so it cannot be quietly forgotten.

const ROSTER := "res://data/field_elites.json"
const RM_SRC := "res://src/exploration/RoamingMonster.gd"


func _roster() -> Dictionary:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROSTER))
	return cfg.get("per_world", {})


# ── the flag the solo guard actually reads ────────────────────────────────

func test_the_elite_flag_only_covers_species_that_are_ALWAYS_elite() -> void:
	## The conflation, pinned in BOTH directions so neither half can be "fixed" in isolation.
	## A rostered species may carry the flag ONLY if it never appears in an ordinary pool —
	## otherwise the flag makes its common encounters elite fights.
	var roster := _roster()
	assert_gt(roster.size(), 1, "CONTROL: the roster is populated, or this test checks nothing")
	var pools := FileAccess.get_file_as_string("res://data/enemy_pools.json")
	var wrongly_flagged: Array[String] = []
	var unprotected: Array[String] = []
	for world in roster:
		var id: String = str(roster[world])
		var flagged: bool = bool(BestiarySystem.get_monster_data(id).get("field_elite", false))
		var ordinary: bool = pools.contains('"%s"' % id)
		if flagged and ordinary:
			wrongly_flagged.append("%s (%s)" % [id, world])
		elif not flagged and not ordinary:
			unprotected.append("%s (%s)" % [id, world])
	assert_eq(wrongly_flagged, [] as Array[String],
		"flagged AND in an ordinary pool — every common encounter with these becomes an elite fight (x3 HP, x8 EXP): %s" % str(wrongly_flagged))
	assert_eq(unprotected, [] as Array[String],
		"elite-only species missing the flag — it would never fight alone: %s" % str(unprotected))


func test_the_open_gap_is_measured_not_assumed() -> void:
	## The five that CANNOT take the flag are exactly the five that still spawn with duplicates.
	## When cowir-overworld carries elite-ness through the spawn, this count goes to 0 and the
	## assertion below fails loudly — a stale debt line is how a known gap becomes a forgotten one.
	var roster := _roster()
	var pools := FileAccess.get_file_as_string("res://data/enemy_pools.json")
	var still_gregarious: Array[String] = []
	for world in roster:
		var id: String = str(roster[world])
		if not bool(BestiarySystem.get_monster_data(id).get("field_elite", false)):
			still_gregarious.append(id)
	assert_eq(still_gregarious.size(), 5,
		"the solo-elite gap is 5 of 6 worlds. If this is now 0 the spawn-side fix landed — delete this test. If it grew, a roster entry lost its protection: %s" % str(still_gregarious))
	assert_true(pools.contains('"unassuming_dog"'),
		"CONTROL: the pool reader works, so 'is in an ordinary pool' is a reading and not an empty string search")


func test_an_ordinary_monster_is_not_an_elite() -> void:
	# CONTROL. Without this, flagging the whole bestiary would pass the assertion above.
	for id in ["goblin", "slime", "bat"]:
		assert_false(bool(BestiarySystem.get_monster_data(id).get("field_elite", false)),
			"%s must NOT be a field elite — the flag has to discriminate" % id)


# ── the lookup that was null for a week ───────────────────────────────────

func test_the_bestiary_lookup_returns_real_values_not_a_fallback() -> void:
	## The whole defect class: a null lookup returned a PLAUSIBLE value (false / level 1) and was
	## indistinguishable from a working one. Pin the values, not the call.
	assert_eq(int(BestiarySystem.get_monster_data("dark_knight").get("level", 1)), 12,
		"dark_knight's authored level must survive the lookup — 1 means the lookup is dead again")
	assert_eq(int(BestiarySystem.get_monster_data("goblin").get("level", 1)), 3)
	assert_eq(int(BestiarySystem.get_monster_data("zzz_no_such_monster").get("level", 1)), 1,
		"CONTROL: an unknown id still falls back to 1, so the assertions above are real readings")


func test_moods_read_the_level_through_that_same_lookup() -> void:
	# _monster_level is what AFRAID compares the party average against. When it returned 1 for
	# everything, "afraid of things much weaker than you" became "afraid of everything past level 5".
	var src := FileAccess.get_file_as_string(RM_SRC)
	var i: int = src.find("func _monster_level")
	assert_gt(i, -1, "CONTROL: RoamingMonster still resolves a monster level")
	var body := src.substr(i, 500)
	assert_true(body.contains("BestiarySystem.get_monster_data"),
		"the level must come from the static call, not a node lookup that resolves to null")
	assert_false(body.contains('get_node_or_null("BestiarySystem")'),
		"BestiarySystem is not an autoload — a node lookup here is the dead-lookup defect returning")


func test_an_elite_outranks_the_party_enough_to_never_read_as_afraid() -> void:
	## Behavioural consequence, and the reason the two bugs compounded: an elite is meant to be
	## unfairly strong. With level 1 it was BELOW every mid-game party, so the one monster designed
	## to menace you was eligible to flee from you.
	var gap: int = int(load(RM_SRC).AFRAID_LEVEL_GAP)
	var elite_lv: int = int(BestiarySystem.get_monster_data("dark_knight").get("level", 1))
	assert_gt(elite_lv, gap,
		"an elite at level %d with an afraid-gap of %d would flee from an ordinary party" % [elite_lv, gap])
