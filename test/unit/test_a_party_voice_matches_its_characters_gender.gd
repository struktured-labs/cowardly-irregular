extends GutTest

## The Bard shipped voiced by "Charlie", a male ElevenLabs voice, while the Bard is canonically a
## woman (struktured's locked per-job gender, 2026-03-21; restated 2026-09-24 as "obv wrong").
## Nothing caught it because the casting was never recorded: each clip carried its text's sha and
## nothing about who spoke it. So every spoken clip now declares `voice` and `voice_gender` (from
## the voice API's own gender label), and this checks the declaration against the canon.
##
## It guards the RECORD, not the waveform — a clip re-cut with a mislabelled voice would pass. The
## re-voice itself was verified by pitch (median F0 ~207 Hz, against ~115 Hz for the male voice).

const MANIFEST := "res://data/sfx_manifest.json"
const PERSONAS := "res://data/job_personas.json"

## struktured's locked canon: Fighter he · Cleric she · Mage he · Bard she.
const CANON := {"fighter": "male", "cleric": "female", "mage": "male", "bard": "female"}
## The Rogue is "unknown for the whole game", and struktured put the voice in scope on 2026-09-24:
## "doesnt really sound androgenous, might need to revisit". Callum (male) is still cast, so the Rogue
## must declare its casting but is unconstrained here until a re-voice defines an ambiguous target.
const UNRULED := ["rogue"]


func _sfx() -> Dictionary:
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(p is Dictionary and p.has("sfx"), "manifest parses to {sfx:{...}}")
	return p["sfx"] if p is Dictionary else {}


func _voiced_jobs() -> Array:
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(PERSONAS))
	assert_true(p is Dictionary, "job_personas parses")
	var jobs: Dictionary = p.get("jobs", p) if p is Dictionary else {}
	var out: Array = []
	for job_id in jobs:
		if (jobs[job_id] as Dictionary).get("trigger_voices", {}).size() > 0:
			out.append(str(job_id))
	return out


func test_every_voiced_job_has_a_gender_ruling() -> void:
	## A new voiced job with no entry in either list would otherwise go unchecked forever.
	var jobs := _voiced_jobs()
	assert_gt(jobs.size(), 0, "VOID: no job carries trigger_voices, so nothing here is checked")
	var unruled: Array = []
	for job_id in jobs:
		if not CANON.has(job_id) and not UNRULED.has(job_id):
			unruled.append(job_id)
	assert_eq(unruled, [], "voiced jobs with no gender canon and no explicit UNRULED entry: %s" % [unruled])


func test_every_spoken_clip_declares_who_voiced_it() -> void:
	var sfx := _sfx()
	var clips := 0
	var undeclared: Array = []
	for key in sfx:
		var k := str(key)
		if not k.begins_with("voice_") or k.begins_with("voice_blip_"):
			continue
		clips += 1
		var e: Dictionary = sfx[key]
		if str(e.get("voice", "")) == "" or str(e.get("voice_gender", "")) == "":
			undeclared.append(k)
	assert_gt(clips, 0, "VOID: no voice_<job>_* clip found, so this arm checked nothing")
	assert_eq(undeclared, [], "spoken clips with no recorded voice/voice_gender (%d): %s" % [undeclared.size(), undeclared])


func test_each_clip_is_voiced_in_its_characters_canon_gender() -> void:
	var sfx := _sfx()
	var seen := {}
	var wrong: Array = []
	for job_id in CANON:
		for key in sfx:
			var k := str(key)
			if not k.begins_with("voice_%s_" % job_id):
				continue
			seen[job_id] = int(seen.get(job_id, 0)) + 1
			var got := str((sfx[key] as Dictionary).get("voice_gender", ""))
			if got != CANON[job_id]:
				wrong.append("%s is voiced %s by %s, canon is %s" % [k, got, str(sfx[key].get("voice", "?")), CANON[job_id]])
	## Without this a job whose clips all vanished would pass by checking nothing.
	for job_id in CANON:
		assert_gt(int(seen.get(job_id, 0)), 0, "CONTROL: no clip found for %s, so its canon was never checked" % job_id)
	assert_eq(wrong, [], "clips voiced against the character's canon gender (%d): %s" % [wrong.size(), wrong])
