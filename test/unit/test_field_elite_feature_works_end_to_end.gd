extends GutTest

## struktured asked for the BD2 field elite and the monster moods by name on 2026-09-06. Both
## SHIPPED in v3.33.225 and neither has ever worked in play, for two separate reasons — so this
## file asserts the VALUES the feature produces, not that its code exists. A source-text test
## would have passed throughout (cowir-overworld's own words after finding the first cause).
##
##   cause 1, fixed v3.33.242: BestiarySystem is a class_name with STATIC functions and is NOT an
##           autoload, so get_node_or_null returned null forever. _is_field_elite read false for
##           EVERY monster and _monster_level read 1 for every monster.
##   cause 2, fixed here:      only dark_knight carried the `field_elite` flag the solo guard
##           reads. The roster in field_elites.json names six species, one per world, so five of
##           six worlds' elites would STILL have spawned with duplicates after cause 1 was fixed.

const ROSTER := "res://data/field_elites.json"
const RM_SRC := "res://src/exploration/RoamingMonster.gd"


func _roster() -> Dictionary:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROSTER))
	return cfg.get("per_world", {})


# ── the flag the solo guard actually reads ────────────────────────────────

func test_every_rostered_elite_carries_the_flag_the_solo_guard_reads() -> void:
	var roster := _roster()
	assert_gt(roster.size(), 1, "CONTROL: the roster is populated, or this test checks nothing")
	var unflagged: Array[String] = []
	for world in roster:
		var id: String = str(roster[world])
		if not bool(BestiarySystem.get_monster_data(id).get("field_elite", false)):
			unflagged.append("%s (%s)" % [id, world])
	assert_eq(unflagged, [] as Array[String],
		"rostered elites with no field_elite flag — these spawn with random duplicates and are not rare: %s" % str(unflagged))


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
