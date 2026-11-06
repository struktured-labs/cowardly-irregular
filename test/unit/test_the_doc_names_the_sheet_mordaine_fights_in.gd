extends GutTest

## CLAUDE.md's W1 boss notes said Mordaine's sprite was "`shadow_knight` placeholder (tier T1) pending artist sheet" until
## 2026-11-06, three and a half months after her artist sheet shipped (caf43710f, 2026-07-25). A lane reading it would
## have regenerated art the artist had already drawn. The line now names the manifest entry and states no tier.
##
## ⛔ PINS THE POINTER, NOT THE TIER. Asserting "T2" here would red on a correct T3 promotion; asserting that the line
## names the entry battle loads, and claims no placeholder while that entry is artist art, is what stays true.

const CLAUDE_MD := "res://CLAUDE.md"
const BOSS_ID := "chancellor_mordaine"


func _sprite_line() -> String:
	var doc := FileAccess.get_file_as_string(CLAUDE_MD)
	assert_gt(doc.length(), 1000, "PRECONDITION: CLAUDE.md must be readable")
	var in_roster := false
	for line in doc.split("\n"):
		if line.begins_with("### W1 Boss Roster"):
			in_roster = true
		elif in_roster and line.begins_with("#"):
			break
		elif in_roster and (line.contains("Sprite is") or line.contains("Battle sprite")):
			return line
	return ""


func _sheet() -> Dictionary:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	return (manifest["monster_sheets"] as Dictionary).get(BOSS_ID, {})


func test_the_roster_names_the_sheet_the_boss_fight_loads() -> void:
	var castle := FileAccess.get_file_as_string("res://src/maps/dungeons/CastleHarmonia.gd")
	assert_true(castle.contains('boss_id = "%s"' % BOSS_ID), "CONTROL: Castle Harmonia's boss fight is %s" % BOSS_ID)
	assert_false(_sheet().is_empty(), "CONTROL: monster_sheets registers %s" % BOSS_ID)
	var line := _sprite_line()
	assert_ne(line, "", "the W1 Boss Roster notes must carry a sprite line for Mordaine")
	assert_string_contains(line, BOSS_ID, "the sprite line must name the manifest entry battle loads")


func test_the_roster_calls_no_artist_sheet_a_placeholder() -> void:
	var tier := str(_sheet().get("tier", ""))
	assert_true(tier in ["T2", "T3"], "CONTROL: %s is artist art (tier %s)" % [BOSS_ID, tier])
	var line := _sprite_line()
	for claim in ["Sprite is `shadow_knight`", "pending artist sheet", "(tier T1)"]:
		assert_false(line.begins_with("- Sprite is") and line.contains(claim),
			"the line must not claim an artist-drawn boss is a placeholder: found %s" % claim)
