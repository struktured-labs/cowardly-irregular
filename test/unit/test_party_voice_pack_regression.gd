extends GutTest

## The party voice pack: 25 clips, voice_<job>_<trigger>, one per scripted trigger_voices
## line. struktured heard the five casting samples 2026-08-22 and the pack shipped on that.
##
## THE COUPLING IS THE FRAGILE PART, not the assets. BattleScene builds the key at runtime
## as "voice_%s_%s" % [job_id, voice_trigger] and SoundManager is manifest-gated, so a
## mismatch is SILENT — a new trigger in job_personas.json, or a job id rename, produces a
## key nothing authored and the line just plays without voice. Nothing fails.
##
## So this pins the JOIN in both directions rather than counting files.

const MANIFEST := "res://data/sfx_manifest.json"
const PERSONAS := "res://data/job_personas.json"

## Lines authored ahead of their clip, named one by one with the reason — NOT a suppression flag.
## @cowir-story added 30 moment lines on 2026-10-12 and 24 were cut on the free engine the same day.
## These six are the Fighter's, and they are his call, not a lane's: struktured ruled the Fighter
## stays on ElevenLabs Harry ("I is the best but elevenlabs is just SOO much better... I'm not saying
## forever, I'm saying its the bar we need to meet"), so recasting them free contradicts the ruling
## and cutting them on ElevenLabs spends credits nobody authorised. Until he says which, the line
## plays with its text and no audio — exactly as all 30 did before the other 24 landed.
##
## The set is EXACT in BOTH directions, which is what makes it an explanation rather than a mute
## button: a SEVENTH unvoiced line reds, and the day these six are cut the stale entries red too and
## this block must go with them. You cannot silence this guard green, only explain it green.
const AWAITING_HIS_CALL: Array[String] = [
	"voice_fighter_turn_start_10",
	"voice_fighter_turn_start_11",
	"voice_fighter_turn_start_12",
	"voice_fighter_turn_start_13",
	"voice_fighter_turn_start_14",
	"voice_fighter_turn_start_15",
]


func _sfx() -> Dictionary:
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(p is Dictionary and p.has("sfx"), "manifest parses to {sfx:{...}}")
	return p["sfx"]


func _jobs() -> Dictionary:
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(PERSONAS))
	assert_true(p is Dictionary, "job_personas parses")
	return p.get("jobs", p)


## Every clip a trigger can speak: [key, line] per variant. A trigger's entry is one string or a list;
## variant 0 keeps the unsuffixed key, variant n>=1 is voice_<job>_<trigger>_<n> (PartyPersonas.pick_trigger_voice).
func _variants(job_id: String, trig: String, entry: Variant) -> Array:
	var lines: Array = entry if entry is Array else [entry]
	var out: Array = []
	for n in lines.size():
		var key := "voice_%s_%s" % [job_id, trig] if n == 0 else "voice_%s_%s_%d" % [job_id, trig, n]
		out.append([key, VoiceLines.text_of(lines[n])])
	return out


func test_every_scripted_trigger_line_has_a_voice_clip() -> void:
	## FORWARD: a trigger the game can fire must have audio. Adding a line to
	## job_personas.json without a clip is the silent-miss direction.
	var sfx := _sfx()
	var jobs := _jobs()
	var checked := 0
	var missing: Array[String] = []
	for job_id in jobs:
		var tv: Dictionary = jobs[job_id].get("trigger_voices", {})
		for trig in tv:
			for v in _variants(job_id, trig, tv[trig]):
				checked += 1
				if not sfx.has(v[0]):
					missing.append(v[0])
	assert_gt(checked, 0, "the scan found trigger lines at all — a zero here is a dead scan, not a clean result")
	var unexplained: Array[String] = []
	for k in missing:
		if not AWAITING_HIS_CALL.has(k):
			unexplained.append(k)
	assert_eq(unexplained.size(), 0, "scripted trigger lines with no voice clip and no reason: %s" % [unexplained])
	## THE OTHER DIRECTION, which is what stops the list above becoming muscle memory: every entry
	## must STILL be missing. The day someone cuts these six, this reds and names them, and the
	## exemption has to be deleted rather than quietly outliving the decision it records.
	var landed: Array[String] = []
	for k in AWAITING_HIS_CALL:
		if sfx.has(k):
			landed.append(k)
	assert_eq(landed.size(), 0,
		"these clips now EXIST, so the exemption naming them is stale — delete them from AWAITING_HIS_CALL: %s" % [landed])


func test_every_voice_clip_answers_a_real_trigger_line() -> void:
	## REVERSE: a clip whose trigger was renamed or deleted is dead weight the
	## dynamic-prefix exemption would hide from the orphan audit forever.
	var sfx := _sfx()
	var jobs := _jobs()
	var expected := {}
	for job_id in jobs:
		var tv: Dictionary = jobs[job_id].get("trigger_voices", {})
		for trig in tv:
			for v in _variants(job_id, trig, tv[trig]):
				expected[v[0]] = true
	var orphans: Array[String] = []
	for key in sfx:
		var k := str(key)
		if not k.begins_with("voice_") or k.begins_with("voice_blip_"):
			continue
		if not expected.has(k):
			orphans.append(k)
	assert_eq(orphans.size(), 0, "voice clips with no matching trigger line: %s" % [orphans])


func test_the_consumer_still_builds_the_key_this_pack_is_named_for() -> void:
	## If BattleScene's format string changes, both tests above stay green and every
	## clip goes silent. This is the only arm that watches the runtime key shape.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_ne(src, "", "BattleScene.gd readable")
	assert_true(src.contains('"voice_%s_%s" % [job_id, voice_trigger]'),
		"the runtime key shape must stay voice_<job>_<trigger> or the whole pack is unreachable")


func test_the_clips_exist_on_disk_and_are_not_empty() -> void:
	var sfx := _sfx()
	var checked := 0
	for key in sfx:
		var k := str(key)
		if not k.begins_with("voice_") or k.begins_with("voice_blip_"):
			continue
		checked += 1
		var f := str(sfx[k].get("file", ""))
		assert_ne(f, "", "%s carries a file key" % k)
		assert_true(FileAccess.file_exists("res://" + f), "%s -> %s exists" % [k, f])
	var lines := 0
	var jobs := _jobs()
	for job_id in jobs:
		var tv: Dictionary = jobs[job_id].get("trigger_voices", {})
		for trig in tv:
			lines += _variants(job_id, trig, tv[trig]).size()
	assert_gte(lines, 25, "the pack shipped as 5 jobs x 5 triggers; fewer lines means a trigger was lost")
	## Minus the clips he has not ruled on yet; AWAITING_HIS_CALL's own arm above proves each of those
	## is genuinely absent, so this subtraction cannot hide a clip that exists under a wrong key.
	var awaited := AWAITING_HIS_CALL.size()
	assert_eq(checked, lines - awaited,
		"one clip per scripted line (less the %d awaiting struktured's call), found %d clips for %d lines" % [awaited, checked, lines])

func test_each_clip_was_generated_from_the_line_that_ships_today() -> void:
	## THE DRIFT GUARD, and the reason it exists: on 2026-08-22 a spell-rename sweep changed
	## the Cleric's signature line from "Cure" to "Sanatio" on a different branch. The clip
	## still existed, the key was still right, the trigger still resolved -- every other arm
	## in this file stayed green while the bubble read "Sanatio" and the audio said "Cure".
	## No instrument compares an OGG's spoken words to a JSON string, so the manifest records
	## the sha of the text each clip was cut from and this compares it to the live line.
	## Redundant sources that are SUPPOSED to agree get an AGREEMENT assertion, not a
	## precedence rule (CLAUDE.md, "two data sources feeding one surface", form (a)).
	var sfx := _sfx()
	var jobs := _jobs()
	var checked := 0
	var stale: Array[String] = []
	for job_id in jobs:
		var tv: Dictionary = jobs[job_id].get("trigger_voices", {})
		for trig in tv:
			for v in _variants(job_id, trig, tv[trig]):
				var key: String = v[0]
				if not sfx.has(key):
					continue
				var recorded := str(sfx[key].get("source_sha", ""))
				assert_ne(recorded, "", "%s must record the text it was generated from" % key)
				checked += 1
				var live := str(v[1]).sha256_text().substr(0, 16)
				if recorded != live:
					stale.append("%s (clip cut from different text than ships today)" % key)
	assert_gt(checked, 0, "the scan compared something — a zero here is a dead scan")
	assert_eq(stale.size(), 0,
		"voice clips whose audio no longer matches the line the player reads: %s" % [stale])
