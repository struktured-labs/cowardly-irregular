extends GutTest

## 2026-11-26 (cowir-story): world6_before_she_left step 2 is "a 3-beat recall dialogue chain (the vowels / the light /
## the weather-word)" per its _wiring_notes, and none of the three beats had a line. They are authored on the objective's
## `beats` for the emitter to come. Data only: this proves the words exist, not that a player hears them yet.

const QUEST := "res://data/quests/world6_before_she_left.json"
const BEATS := ["vowels", "light", "weather"]


func test_each_fragment_has_words() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(QUEST))
	assert_true(parsed is Dictionary, "CONTROL: the quest parses")
	if not (parsed is Dictionary):
		return
	var step: Dictionary = {}
	for o in (parsed as Dictionary).get("objectives", []):
		if int((o as Dictionary).get("step", 0)) == 2:
			step = o
	assert_eq(str(step.get("flag_on_complete", "")), "quest_world6_before_she_left_fragments_gathered", "CONTROL: step 2 is the recall")
	var seen := {}
	for b in step.get("beats", []):
		var lines: Array = (b as Dictionary).get("lines", [])
		var spoken := lines.filter(func(l): return str((l as Dictionary).get("text", "")).strip_edges() != "" and str(l.get("speaker", "")) == "Traveler")
		assert_false(str(b.get("label", "")).strip_edges().is_empty(), "%s has a prompt to pick" % b.get("id", "?"))
		assert_gt(spoken.size(), 0, "%s has the Traveler's words" % b.get("id", "?"))
		seen[str(b.get("id", ""))] = true
	assert_eq(seen.keys().size(), BEATS.size(), "exactly the three fragments the notes name")
	for id in BEATS:
		assert_true(seen.has(id), "the %s beat is authored" % id)
