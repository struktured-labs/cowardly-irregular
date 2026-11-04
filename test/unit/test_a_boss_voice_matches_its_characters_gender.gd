extends GutTest

## Mordaine shipped voiced by two male VCTK speakers (p273/p258) while the game's own text calls her a
## "Sorceress-usurper" and uses she/her for her 12 times of 12 (2026-11-04). Same defect as the Bard on the
## party side (test_a_party_voice_matches_its_characters_gender), one layer over: every boss_line_* clip
## already declared voice_gender, and nothing compared it with the character. It guards the RECORD.

const MANIFEST := "res://data/sfx_manifest.json"

## Mordaine she/her (text 12 of 12, "Sorceress"); the Rat King he/him/his; the dragons are their shipped voices (struktured via cowir-main 21627).
const CANON := {"Mordaine": "female", "Cave Rat King": "male", "Pyrroth": "male", "Glacius": "female", "Voltharion": "male", "Umbraxis": "male"}
## Voiced with no ruling yet; nothing is checked for a speaker listed here.
const UNRULED := []
## A masked speaker is the character its key belongs to (world1_mordaine_secondary_unlock speaks as "???").
const MASKED := {"boss_line_mordaine_unlock_": "Mordaine"}


func _boss_lines() -> Dictionary:
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(p is Dictionary and p.has("sfx"), "manifest parses to {sfx:{...}}")
	var out := {}
	if not p is Dictionary:
		return out
	for key in p["sfx"]:
		if str(key).begins_with("boss_line_"):
			out[str(key)] = p["sfx"][key]
	return out


func _speaker_of(key: String, e: Dictionary) -> String:
	var s: String = str(e.get("speaker", ""))
	if s != "???":
		return s
	for prefix in MASKED:
		if key.begins_with(prefix):
			return str(MASKED[prefix])
	return "???"


func test_every_voiced_boss_has_a_gender_ruling() -> void:
	var lines := _boss_lines()
	assert_gt(lines.size(), 100, "VOID: the boss_line_ clips moved and nothing here is checked")
	var unruled: Array = []
	for key in lines:
		var who := _speaker_of(key, lines[key])
		if not CANON.has(who) and not UNRULED.has(who) and not unruled.has(who):
			unruled.append("%s (%s)" % [who, key])
	assert_eq(unruled, [], "voiced boss speakers with no canon and no UNRULED entry (a masked line needs a MASKED prefix): %s" % [unruled])


func test_each_boss_clip_is_voiced_in_its_characters_gender() -> void:
	var lines := _boss_lines()
	var seen := {}
	var wrong: Array = []
	for key in lines:
		var e: Dictionary = lines[key]
		var who := _speaker_of(key, e)
		if not CANON.has(who):
			continue
		seen[who] = int(seen.get(who, 0)) + 1
		var got := str(e.get("voice_gender", ""))
		if got != CANON[who]:
			wrong.append("%s is voiced %s by %s" % [key, got, str(e.get("voice", "?")).substr(0, 40)])
	for who in CANON:
		assert_gt(int(seen.get(who, 0)), 0, "CONTROL: no clip found for %s, so its canon was never checked" % who)
	assert_eq(wrong, [], "boss clips voiced against the character's gender (%d): %s" % [wrong.size(), wrong.slice(0, 6)])
