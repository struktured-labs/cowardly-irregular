extends GutTest

## Only the 5 starters had a per-press ladder; the other 9 jobs repeated ONE flat arcade credit at every press, full bank included.
## struktured 2026-09-09 asked for a new sound at the 4th press. Driven through the REAL Win98Menu walk-down, never a copy of it.

const JOBS_PATH := "res://data/jobs.json"
const BASELINE := "res://test/fixtures/sfx_whoop_baseline.json"
const MANIFEST := "res://data/sfx_manifest.json"
const LADDERLESS := "ninja"


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _job_ids() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(JOBS_PATH))
	return (parsed as Dictionary).keys() if parsed is Dictionary else []


## The cue the real menu actually reaches for this job at this press depth.
func _key_for(job_id: String, depth: int) -> String:
	var sm: Node = _sm()
	var menu := Win98Menu.new()
	menu._character_class = job_id
	sm._sfx_cooldowns.clear()
	sm._battle_player.stream = null
	menu._play_advance_sound(depth)
	var out := "" if sm._battle_player.stream == null else str(sm._battle_player.stream.resource_path).get_file()
	menu.free()
	return out


func test_every_job_escalates_across_its_five_presses() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	var ids := _job_ids()
	assert_gt(ids.size(), 5, "CONTROL: jobs.json gave %d jobs — this arm would check almost nothing" % ids.size())
	var flat: Array[String] = []
	var thin: Array[String] = []
	for job_id in ids:
		var keys := {}
		var first := ""
		var last := ""
		for depth in range(1, 6):
			var k := _key_for(str(job_id), depth)
			keys[k] = true
			if depth == 1:
				first = k
			last = k
		if keys.size() <= 1:
			flat.append("%s (one cue at every press: %s)" % [job_id, first])
		elif keys.size() < 4 or first == last:
			thin.append("%s (%d distinct across 5 presses)" % [job_id, keys.size()])
	assert_eq(flat, ([] as Array[String]), "jobs whose Advance press sounds identical every time: %s" % [flat])
	assert_eq(thin, ([] as Array[String]), "jobs whose press ladder barely moves: %s" % [thin])


func test_a_job_without_its_own_ladder_walks_the_generic_one() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	assert_false(sm._sfx_manifest.has("advance_%s_1" % LADDERLESS),
		"CONTROL: %s must have NO per-job ladder, or this arm proves nothing" % LADDERLESS)
	for depth in range(1, 6):
		var k := _key_for(LADDERLESS, depth)
		assert_true(k.begins_with("advance_generic_%d" % depth),
			"%s press %d played %s — it should walk the generic ladder, not repeat the flat credit" % [LADDERLESS, depth, k])


func test_the_starters_keep_their_own_voice() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	for job_id in ["fighter", "cleric", "mage", "rogue", "bard"]:
		if not sm._sfx_manifest.has("advance_%s_5" % job_id):
			continue
		var k := _key_for(job_id, 5)
		assert_true(k.begins_with("advance_%s_5" % job_id),
			"%s press 5 played %s — the generic ladder must never displace a job that has its own" % [job_id, k])


func test_the_generic_ladder_reads_as_escalation() -> void:
	# GUT cannot do an FFT, so loudness comes from what audit_whoop recorded; duration is the manifest's own.
	var base: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASELINE))
	var man: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(base is Dictionary and man is Dictionary, "baseline or manifest did not parse")
	if not (base is Dictionary and man is Dictionary):
		return
	var cues: Dictionary = (base as Dictionary).get("cues", {})
	var sfx: Dictionary = (man as Dictionary).get("sfx", {})
	var prev_rms := -999.0
	var prev_dur := 0.0
	var checked := 0
	for n in range(1, 6):
		var key := "advance_generic_%d" % n
		assert_true(cues.has(key), "%s is not whoop-pinned — a re-roll could change it silently" % key)
		assert_true(sfx.has(key), "%s missing from the manifest" % key)
		if not (cues.has(key) and sfx.has(key)):
			continue
		var rms: float = float((cues[key] as Dictionary).get("rms_db", -999.0))
		var dur: float = float((sfx[key] as Dictionary).get("duration_seconds", 0.0))
		if n > 1:
			assert_gt(rms - prev_rms, 1.0,
				"%s is only %.1f dB over rung %d — under ~1 dB the step does not read" % [key, rms - prev_rms, n - 1])
			assert_gt(dur - prev_dur, 0.04, "%s is not audibly longer than rung %d (one more note per press)" % [key, n - 1])
		prev_rms = rms
		prev_dur = dur
		checked += 1
	assert_eq(checked, 5, "CONTROL: only %d of 5 generic rungs were compared" % checked)


func test_the_flat_credit_is_no_longer_what_a_ladderless_job_hears() -> void:
	# The defect itself: press 4 used to be the same arcade credit as press 1.
	var sm: Node = _sm()
	if sm == null:
		return
	var fourth := _key_for(LADDERLESS, 4)
	assert_false(fourth.begins_with("advance_queue"),
		"press 4 is still the flat credit (%s) — the fourth press struktured asked about sounds like the first" % fourth)
	assert_ne(fourth, _key_for(LADDERLESS, 1), "press 4 and press 1 play the same cue")
