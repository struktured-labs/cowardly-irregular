extends GutTest

## Advance escalation ladder (struktured-approved via cowir-sfx, 2026-07-11/12).
## Each Advance press plays advance_<job>_<depth 1..3> when the manifest has
## it; every other job falls back to the arcade credit. Depth = queue size
## AFTER the press. Fighter STEEL + Cleric Faith + Rogue inverted tiers
## shipped v3.33.133-134; the fighter STEEL set replaced the drum-v1 pilot.

const LADDERED_JOBS := ["fighter", "cleric", "rogue"]


func test_laddered_jobs_have_all_three_tiers() -> void:
	for job in LADDERED_JOBS:
		for i in [1, 2, 3]:
			var key := "advance_%s_%d" % [job, i]
			assert_true(SoundManager._sfx_manifest.has(key),
				"%s must be authored now that the ladder shipped" % key)
			var entry: Dictionary = SoundManager._sfx_manifest.get(key, {})
			assert_eq(str(entry.get("fallback_to", "")), "advance_queue",
				"%s must fall back to the arcade credit if its asset ever goes missing" % key)


func test_ladder_ogg_assets_are_real_audio_on_disk() -> void:
	# Silent-failure guard: a manifest key pointing at a missing or LFS-pointer
	# ogg falls through to advance_queue with no error. Confirm real bytes.
	for job in LADDERED_JOBS:
		for i in [1, 2, 3]:
			var path := "res://assets/audio/sfx/advance_%s_%d.ogg" % [job, i]
			assert_true(FileAccess.file_exists(path), "%s must exist on disk" % path)
			var f := FileAccess.open(path, FileAccess.READ)
			assert_not_null(f, "%s must open" % path)
			if f:
				assert_gt(f.get_length(), 1024,
					"%s must be real audio, not a ~130-byte LFS pointer" % path)
				f.close()


func test_laddered_job_ids_match_manifest_keys() -> void:
	# The menu keys the ladder on combatant.job["id"] (BattleCommandMenu ->
	# Win98Menu._character_class). If a laddered job's id drifts from its
	# manifest suffix the ladder SILENTLY reverts to the arcade credit —
	# pin the id == suffix contract at the data layer.
	var jobs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/jobs.json"))
	assert_not_null(jobs, "jobs.json must parse")
	for job in LADDERED_JOBS:
		assert_true(jobs.has(job), "jobs.json must have a '%s' entry" % job)
		assert_eq(str(jobs.get(job, {}).get("id", "")), job,
			"job '%s' id must equal its ladder manifest suffix" % job)
	# The submenu advance path resolves the class via CHARACTER_STYLES, so the
	# laddered jobs must be named there too (not only fed through setup()).
	var win98 := FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")
	for job in LADDERED_JOBS:
		assert_true(win98.find("\"%s\":" % job) > -1,
			"Win98Menu CHARACTER_STYLES must name '%s' so submenu advances resolve the ladder" % job)


func test_win98_menu_wires_depth_and_fallback() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")
	assert_true("func _play_advance_sound(depth: int = 1)" in src, "depth param")
	assert_true("advance_%s_%d" in src, "per-job key format")
	assert_true("clampi(depth, 1, 3)" in src, "depth clamped to authored tiers")
	var fn := src.substr(src.find("func _play_advance_sound"))
	assert_true("play_battle(\"advance_queue\")" in fn.substr(0, 600),
		"unknown job/tier must fall back to the arcade credit")
	assert_true("_play_advance_sound(root._queued_actions.size())" in src,
		"queue caller passes post-press depth")
	assert_true("_play_advance_sound(root._queued_actions.size() + 1)" in src,
		"auto-submit caller passes post-press depth (append happens later on that path)")
