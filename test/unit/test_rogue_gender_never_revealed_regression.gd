extends GutTest

## Regression: world1_chapter9 steps[24] said "her shoulders" of the Rogue — 2026-03-21 directive, the text must never reveal the Rogue's gender.

## Cutscenes only: novella paragraphs are multi-character, so this rule yields 18-28 false positives there (measured).
const DIR := "res://data/cutscenes"

## Deliberately NOT "pronouns" — a gendered noun reveals gender just as completely.
const PRONOUN := "(?i)\\b(she|her|hers|he|him|his)\\b"
const GENDER_NOUN := "(?i)\\b(man|woman|girl|boy|lady|sir|madam|miss|mister|sister|brother|daughter|son|king|queen|prince|princess|lord|mistress|maiden|lass|lad|wife|husband)\\b"
## A second named referent between the Rogue and the word means the word is not about the Rogue.
const OTHER := "\\b(Fighter|Cleric|Mage|Bard|Mordaine|Coordinator|Warden|Lockward|Aldric|Marcus|Enforcer|Steampriest|Nurse|Officer|Calibrant|Arbiter|Curator|Tempo)\\b"

var _blocks: Array = []


func before_all() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for fname in dir.get_files():
		if not fname.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/" + fname))
		if not (parsed is Dictionary):
			continue
		var steps: Variant = (parsed as Dictionary).get("steps", [])
		if not (steps is Array):
			continue
		for idx in (steps as Array).size():
			var step: Variant = (steps as Array)[idx]
			if not (step is Dictionary):
				continue
			var text: Variant = (step as Dictionary).get("text", "")
			if text is String and str(text) != "":
				_blocks.append({"file": fname, "index": idx, "text": str(text)})


## Scans `text` only — a `speaker` of "Rogue" with narration about someone else is not a reveal.
func _offenders(word_pattern: String) -> Array:
	var subject := RegEx.create_from_string("\\bRogue\\b")
	var word := RegEx.create_from_string(word_pattern)
	var other := RegEx.create_from_string(OTHER)
	var out: Array = []
	for block in _blocks:
		var text: String = str((block as Dictionary)["text"])
		var sm := subject.search(text)
		if sm == null:
			continue
		var wm := word.search(text, sm.get_end())
		if wm == null:
			continue
		if other.search(text.substr(sm.get_end(), wm.get_start() - sm.get_end())) != null:
			continue
		out.append("%s steps[%s]: '%s' in \"%s\"" % [
			str((block as Dictionary)["file"]), str((block as Dictionary)["index"]),
			wm.get_string(0), text.substr(0, 90)])
	return out


## FLOOR. Every assertion below is vacuous if the corpus did not load.
func test_control_corpus_loaded_and_names_a_known_member() -> void:
	assert_gt(_blocks.size(), 100,
		"NAMED-corpus control: cutscene text blocks must load, else every check below passes on nothing")
	var found_rogue := false
	for block in _blocks:
		if str((block as Dictionary)["text"]).contains("Rogue"):
			found_rogue = true
			break
	assert_true(found_rogue,
		"the SUBJECT must be present in the corpus — a zero is meaningless if the Rogue is never named")


## The corpus MUST be able to express gender, or the Rogue's zero proves nothing about the rule.
func test_control_the_scan_can_detect_a_reveal_when_one_exists() -> void:
	var probe := RegEx.create_from_string(PRONOUN)
	var hits := 0
	for block in _blocks:
		if probe.search(str((block as Dictionary)["text"])) != null:
			hits += 1
	assert_gt(hits, 20,
		"gendered pronouns must be plentiful in the corpus at large (%d found) — if this is 0 the "
		% [hits] + "detector is broken and the Rogue result is a FALSE ZERO, not compliance")


func test_no_pronoun_is_attributable_to_the_rogue() -> void:
	var offenders := _offenders(PRONOUN)
	assert_eq(offenders, [],
		"a gendered pronoun follows 'Rogue' with no other named referent between them. "
		+ "Recast without the pronoun — the Rogue is the one party member the text never gets inside. %s"
		% [offenders])


func test_no_gendered_noun_is_attributable_to_the_rogue() -> void:
	var offenders := _offenders(GENDER_NOUN)
	assert_eq(offenders, [],
		"the directive is 'never reveal the gender', not 'avoid pronouns' — a gendered NOUN "
		+ "reveals it identically. %s" % [offenders])
