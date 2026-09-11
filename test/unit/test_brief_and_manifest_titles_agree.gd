extends GutTest

## A track's shipped title and its authoring brief must not disagree.
##
## tools/music_prompts.json carries a `title_template` per track; the manifest
## carries the `title` the Jukebox actually shows. They are two authored records
## of one name, and nothing kept them in step.
##
## Found 1 of 133: victory_suburban's brief said "One More Boot Up" while the
## shipped track is "Nailed It". The brief was the stale side, and visibly so —
## "boot up" is DIGITAL-world register, while "Nailed It" sits with its actual
## siblings (HOA President · Neighborhood Watch · After The Barbecue · 911).
##
## 🔑 WHY IT MATTERS DESPITE THE TRACK ALREADY EXISTING: the brief is what a
## REGENERATION reads. Nine to fifteen tracks are staged behind the Suno ToS
## block, and any re-roll of victory_suburban would have come back titled "One
## More Boot Up" — silently reverting a name somebody had improved. A stale
## brief is not a dead record, it is a loaded one.
##
## ⚠️ THIS IS THE WEAKER HALF OF A PAIR, and saying so matters because it looks
## like the same check. It would NOT have caught boss_medieval carrying
## Mordaine's epithet — there the brief and the manifest AGREED, both stale,
## because the bed was authored as her theme and only the ROUTING moved. Two
## records agreeing is not evidence they are right; it is evidence they have the
## same parent. test_generic_beds_are_not_named_after_a_boss covers that half by
## checking the title against a THIRD source (boss_dialogue.json) that moved
## independently. Agreement between siblings proves nothing about either.

const MANIFEST := "res://data/music_manifest.json"
const PROMPTS := "res://tools/music_prompts.json"


func _tracks() -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	assert_gt(raw.length(), 1000, "SCOPE control: manifest read back %d chars" % raw.length())
	return (JSON.parse_string(raw) as Dictionary).get("tracks", {})


func _briefs() -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(PROMPTS)
	assert_gt(raw.length(), 1000, "SCOPE control: music_prompts.json read back %d chars" % raw.length())
	return (JSON.parse_string(raw) as Dictionary).get("shared_tracks", {})


func test_control_both_records_load_and_overlap() -> void:
	## Every arm is vacuous if the two sets do not intersect — a green would then
	## mean "nothing was compared", not "nothing disagrees".
	var tracks: Dictionary = _tracks()
	var briefs: Dictionary = _briefs()
	assert_gt(briefs.size(), 100,
		"SCOPE control: only %d briefs parsed" % briefs.size())
	var overlap: int = 0
	for k in briefs.keys():
		if tracks.has(k):
			overlap += 1
	assert_gt(overlap, 100,
		"SCOPE control: only %d tracks carry BOTH a brief and a manifest entry — the comparison below has almost nothing to compare" % overlap)


func test_no_shipped_title_disagrees_with_its_brief() -> void:
	var tracks: Dictionary = _tracks()
	var briefs: Dictionary = _briefs()
	var compared: int = 0
	var drift: Array[String] = []
	for key in briefs.keys():
		var k: String = str(key)
		var entry: Variant = tracks.get(k, null)
		if not (entry is Dictionary):
			continue
		## Unrendered tracks are the STAGED set (blocked on Suno). They have a
		## brief and no audio, so there is no shipped title to disagree with.
		if str((entry as Dictionary).get("file", "")) == "":
			continue
		var shipped: String = str((entry as Dictionary).get("title", "")).strip_edges()
		var brief: String = str((briefs[k] as Dictionary).get("title_template", "")).strip_edges()
		if shipped == "" or brief == "":
			continue
		compared += 1
		if shipped.to_lower() != brief.to_lower():
			drift.append("%s: brief %s vs shipped %s" % [k, brief, shipped])
	assert_gt(compared, 100,
		"SCOPE control: only %d titles compared" % compared)
	assert_eq(drift.size(), 0,
		"brief and shipped title disagree (%d of %d): %s — the brief is what a REGENERATION reads, so a stale one silently reverts a name that was improved. Update whichever is wrong; they must not both stand." % [drift.size(), compared, drift])


func test_the_staged_set_is_exempt_for_a_stated_reason() -> void:
	## Tracks with a brief and no audio are not drift — they are the queue. This
	## arm exists so the skip above cannot quietly grow into a general exemption:
	## if the staged count ever reaches zero the skip is inert and should go, and
	## if it balloons someone has stopped rendering.
	var tracks: Dictionary = _tracks()
	var briefs: Dictionary = _briefs()
	var staged: Array[String] = []
	for key in briefs.keys():
		var entry: Variant = tracks.get(key, null)
		if not (entry is Dictionary) or str((entry as Dictionary).get("file", "")) == "":
			staged.append(str(key))
	staged.sort()
	## 15 today: 5 W1 villages, 4 dragons, castle warden, calibrant, 2 steampunk
	## Masterites, wolf alpha, shop. All blocked on one ToS login.
	assert_gt(staged.size(), 0,
		"no briefs are unrendered — the staged-set skip above now covers nothing and should be deleted rather than left as a standing exemption")
	assert_lt(staged.size(), 40,
		"%d briefs have no audio (%s) — that is not a queue any more, it is a backlog; the skip above is hiding a corpus that stopped being rendered" % [staged.size(), staged])
