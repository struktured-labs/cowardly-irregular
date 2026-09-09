extends GutTest

## An INVERTED assert: it pins a KNOWN GAP and is designed to FAIL when the gap closes.
##
## w2_ability_heal and w3_ability_heal have never been generated. Both `file` fields point at
## assets/audio/sfx/ability_heal.ogg — the W1 angelic choir — while their prompts describe a
## suburban garden hose and a steampunk clockwork apparatus. 34 of 36 world-variant keys have their
## own asset; these two are the exceptions, so it is unfinished work, not a deliberate alias.
##
## ⛔ WHY THIS IS AN ASSERT AND NOT A COMMENT. I recorded the debt in the manifest prompt on
## 2026-09-09 ("NOT YET GENERATED: this entry still points at ability_heal.ogg"). Nothing would have
## failed when that stopped being true, so the note could only ever rot into a false claim inside the
## file a regenerate READS — the EXPIRED shape, self-inflicted, in the fix for it.
## An exemption justified by an ABSENCE has to name what ENDS it. This is that: generate either cue
## and this test reds, naming the key, and the debt gets closed properly instead of silently.
##
## ✅ WHEN THIS GOES RED: that is SUCCESS. Remove the key from OWED below, strip "NOT YET GENERATED"
## from its prompt, and pin the new asset in tools/audit_whoop.py's PINNED list. When OWED is empty,
## DELETE THIS FILE.
##
## ⚠️ NOT generating them unilaterally: it spends ElevenLabs credit and picks a sonic register for
## two worlds, in the family struktured has rejected twice by ear. His call.

const MANIFEST := "res://data/sfx_manifest.json"
const BASE_ASSET := "assets/audio/sfx/ability_heal.ogg"
const OWED: Array[String] = ["w2_ability_heal", "w3_ability_heal"]


func _sfx() -> Dictionary:
	var raw := FileAccess.get_file_as_string(MANIFEST)
	assert_ne(raw, "", "manifest unreadable — this guard would pass vacuously")
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "manifest did not parse as a Dictionary")
	return (parsed as Dictionary).get("sfx", {})


func test_the_owed_keys_still_exist() -> void:
	## PREMISE: a deleted key would make the inverted assert below pass by absence.
	var sfx := _sfx()
	assert_gt(sfx.size(), 50, "manifest holds %d entries — not the file we think" % sfx.size())
	for k in OWED:
		assert_true(sfx.has(k), "%s is gone from the manifest — if the world variant was deliberately dropped, remove it from OWED here too" % k)


func test_they_are_still_borrowing_the_W1_asset() -> void:
	## THE INVERTED ASSERT. Red here means somebody generated one — close the debt, do not "fix" this.
	var sfx := _sfx()
	var freed: Array[String] = []
	for k in OWED:
		if not sfx.has(k):
			continue
		if str((sfx[k] as Dictionary).get("file", "")) != BASE_ASSET:
			freed.append(k)
	if not freed.is_empty():
		fail_test("%s now has its own asset — the debt is PAID. Remove it from OWED, strip 'NOT YET GENERATED' from its prompt, add it to PINNED in tools/audit_whoop.py, and delete this file once OWED is empty." % [freed])


func test_the_prompt_still_records_the_debt() -> void:
	## The prompt is what a regenerate reads. If the note goes while the file is still borrowed, the
	## next person to run elevenlabs_sfx.py has no way to know these two are the unfinished pair.
	var sfx := _sfx()
	for k in OWED:
		if not sfx.has(k):
			continue
		var prompt := str((sfx[k] as Dictionary).get("prompt", ""))
		assert_true(prompt.contains("NOT YET GENERATED"),
			"%s still borrows the W1 asset but its prompt no longer says so — the debt would be invisible to whoever regenerates next" % k)


func test_the_control_world_variants_are_NOT_borrowing() -> void:
	## CONTROL. If every world variant pointed at the base, the assert above would be trivially true
	## and would say nothing about these two in particular.
	var sfx := _sfx()
	var own := 0
	for k in ["w4_ability_heal", "w5_ability_heal", "w6_ability_heal"]:
		assert_true(sfx.has(k), "control: %s must exist" % k)
		if sfx.has(k) and str((sfx[k] as Dictionary).get("file", "")) != BASE_ASSET:
			own += 1
	assert_eq(own, 3,
		"control: only %d of 3 later-world heals have their own asset — if they are all borrowing, this is a family-wide gap and OWED is the wrong shape for it" % own)
