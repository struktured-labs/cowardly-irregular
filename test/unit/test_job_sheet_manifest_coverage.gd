extends GutTest

## Regression: a job with art on disk must be REGISTERED, or the art is dead weight.
##
## This exists because a commit of mine was wrong in exactly this way. `97ad5a9c` shipped
## idle.png for the five meta jobs and its message said the last T0 surface was closed.
## The art landed; the registration did not. HybridSpriteLoader.load_sprite_frames gates on
## `_manifest.has(job_id)` and falls straight to procedural, so all five still rendered as
## proc-gen in battle — while the DIALOGUE portrait looked correct, because
## _create_bust_from_job_sheet reads assets/sprites/jobs/<id>/idle.png by path and never
## consults the manifest.
##
## That split is what made it invisible: the cheap way to check ("is there a portrait?")
## passes, and only the battle path is broken. Presence of a PNG proves nothing about
## whether anything loads it — this joins the two.

const Loader := preload("res://src/battle/sprites/HybridSpriteLoader.gd")
const JOBS_DIR := "res://assets/sprites/jobs"

## Which directories are REAL jobs is derived from data/jobs.json, never hand-listed.
## The first draft of this file did hand-list the exemptions and was wrong in both
## directions at once: it named mage_artist/rogue_artist, which have no idle.png, and it
## missed cleric_artist/cleric_sdxl, which do. A hand-written exemption list is a place
## for real gaps to hide, and it drifts the moment someone adds a reference dir.
func _real_job_ids() -> Array:
	var raw := FileAccess.get_file_as_string("res://data/jobs.json")
	if raw == "":
		return []
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return []
	var src: Variant = parsed.get("jobs", parsed)
	var out: Array = (src.keys() if src is Dictionary else [])
	out.sort()
	return out


func _job_dirs_with_idle() -> Array:
	var out: Array = []
	var d := DirAccess.open(JOBS_DIR)
	if d == null:
		return out
	for sub in d.get_directories():
		if ResourceLoader.exists("%s/%s/idle.png" % [JOBS_DIR, sub]):
			out.append(sub)
	out.sort()
	return out


## Real jobs that actually have art — the only set manifest coverage is owed to.
func _covered_jobs() -> Array:
	var real := _real_job_ids()
	var out: Array = []
	for job in _job_dirs_with_idle():
		if job in real:
			out.append(job)
	return out


func test_every_job_with_idle_art_is_registered_in_the_manifest() -> void:
	var real := _real_job_ids()
	# NAMED controls on BOTH inputs — either one silently empty makes this vacuous.
	assert_eq(real.size(), 14,
		"jobs.json must yield 14 job ids, got %d — the id scan drifted" % [real.size()])
	assert_true("fighter" in _job_dirs_with_idle(),
		"the disk scan must find 'fighter' — it is the artist's anchor sheet")

	var unregistered: Array = []
	for job in _covered_jobs():
		if not Loader.has_artist_sheet(job):
			unregistered.append(job)
	unregistered.sort()
	assert_eq(unregistered, [],
		("job(s) with idle.png on disk and NO manifest entry — load_sprite_frames gates on " +
		"the manifest, so these render PROCEDURALLY in battle while their dialogue portrait " +
		"looks correct (portraits read the PNG by path). The art is generated and unreachable: %s") % [unregistered])


func test_the_meta_jobs_specifically_reach_battle() -> void:
	# Named because these are the five that were broken, and because they are the jobs
	# a player only sees late — a silent regression here would go unreported for weeks.
	var missing: Array = []
	for job in ["scriptweaver", "time_mage", "necromancer", "bossbinder", "skiptrotter"]:
		if not Loader.has_artist_sheet(job):
			missing.append(job)
	missing.sort()
	assert_eq(missing, [],
		"meta job(s) unregistered — they fall back to procedural sprites in battle: %s" % [missing])


func test_registered_jobs_actually_load_frames() -> void:
	# Registration is necessary but not sufficient: an entry whose path or frame size is
	# wrong yields null and falls back just as silently as no entry at all.
	#
	# This MUST feed the manifest's own entry to the loader. The first version synthesized
	# `{"path": JOBS_DIR + "/" + job}` itself and passed 4/4 against a mutation that pointed
	# cleric's real path at a directory with no art — it was validating a path this test had
	# just built, which is true by construction and says nothing about the manifest.
	var sheets := _manifest_sheets()
	assert_true(sheets.has("fighter"),
		"the manifest read must yield 'fighter' — otherwise every result below is vacuous")

	var broken: Array = []
	for job in _covered_jobs():
		if not sheets.has(job):
			continue
		var entry: Dictionary = sheets[job]
		var frames = Loader._load_external_sheet(entry, job)
		if frames == null or frames.get_animation_names().is_empty():
			broken.append("%s (path '%s')" % [job, entry.get("path", "<none>")])
	broken.sort()
	assert_eq(broken, [],
		("registered job(s) whose manifest entry yields no frames — the entry exists so " +
		"nothing warns, and the job renders procedurally anyway: %s") % [broken])


func _manifest_sheets() -> Dictionary:
	var raw := FileAccess.get_file_as_string("res://data/sprite_manifest.json")
	if raw == "":
		return {}
	var parsed = JSON.parse_string(raw)
	return parsed.get("sheets", {}) if parsed is Dictionary else {}


## The derivation must stay honest: every real job needs art, or the coverage set above
## silently shrinks and reports clean while jobs go unregistered.
func test_every_real_job_has_art_on_disk() -> void:
	var real := _real_job_ids()
	var dirs := _job_dirs_with_idle()
	var artless: Array = []
	for job in real:
		if not (job in dirs):
			artless.append(job)
	artless.sort()
	assert_eq(artless, [],
		("real job(s) from jobs.json with no idle.png — they render procedurally, and they " +
		"also drop OUT of the manifest-coverage set above, so that test stops watching them: %s") % [artless])
