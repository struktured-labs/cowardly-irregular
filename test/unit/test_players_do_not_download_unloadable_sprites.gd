extends GutTest

## `assets/sprites/jobs/` holds seven directories no job id can ever name — LoRA experiments
## (`*_sdxl`), separate artist drops (`*_artist`) and the aseprite sources. Nothing in `src/`
## references them and `HybridSpriteLoader` resolves a sheet by JOB ID, so no lookup can reach
## them. They were shipping in every build: 1.92 MB of art a player downloads and cannot see.
##
## That is small against a 321 MB desktop download and NOT small against the web build, whose
## pipeline hard-fails at a 190 MB pck — headroom spent on art nothing loads.
##
## ⛔ THE DANGEROUS DIRECTION IS THE OTHER ONE. An over-broad filter ships a game with no party
## sprites, which is far worse than shipping spare ones, so the first arm below exists to fail
## loudly if a LIVE job's art is ever caught by these patterns.
const MANIFEST := "res://data/sprite_manifest.json"
const JOBS := "res://data/jobs.json"
const PRESETS := "res://export_presets.cfg"
const JOB_DIR := "res://assets/sprites/jobs"


func _job_ids() -> Array[String]:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(JOBS))
	var out: Array[String] = []
	if parsed is Dictionary:
		for k in parsed:
			out.append(str(k))
	elif parsed is Array:
		for e in parsed:
			if e is Dictionary and e.has("id"):
				out.append(str(e["id"]))
	return out


## Every preset's exclude_filter, as a list of {preset, patterns}. Read from the real file:
## a guard that models the filter it is checking proves nothing about the shipped one.
func _exclude_filters() -> Array:
	var out: Array = []
	var text := FileAccess.get_file_as_string(PRESETS)
	var preset := "?"
	for line in text.split("\n"):
		var l := str(line).strip_edges()
		if l.begins_with("name="):
			preset = l.substr(5).replace("\"", "")
		elif l.begins_with("exclude_filter="):
			var inner := l.substr("exclude_filter=".length()).strip_edges().trim_prefix("\"").trim_suffix("\"")
			var pats: Array[String] = []
			for p in inner.split(","):
				var s := str(p).strip_edges()
				if s != "":
					pats.append(s)
			out.append({"preset": preset, "patterns": pats})
	return out


func _excluded_by(patterns: Array, path: String) -> bool:
	for p in patterns:
		if path.matchn(str(p)):
			return true
	return false


func _dirs_under_jobs() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(JOB_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if d.current_is_dir() and not n.begins_with("."):
			out.append(n)
		n = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


## ⛔ THE SAFETY ARM. If this reds, a build ships without a party member's sprites.
func test_no_live_jobs_art_is_excluded_from_any_export() -> void:
	var filters := _exclude_filters()
	assert_gt(filters.size(), 0, "ANTI-VACUITY: no exclude_filter was parsed out of export_presets.cfg")
	var lost: Array = []
	var checked := 0
	for job in _job_ids():
		var probe := "assets/sprites/jobs/%s/idle.png" % job
		if not FileAccess.file_exists("res://" + probe):
			continue
		checked += 1
		for f in filters:
			if _excluded_by(f["patterns"], probe):
				lost.append("%s would be excluded from the %s export by one of its filters" % [probe, f["preset"]])
	assert_gt(checked, 4, "ANTI-VACUITY: only %d job sheets were probed — the arm must see the real roster" % checked)
	assert_eq(lost, [], "an export filter catches a LIVE job's sprites — that build ships a party with no art: %s" % [lost])


## Every directory under jobs/ that no job id names must be excluded from EVERY preset. One
## preset missing it is how the web build (the one with a hard pck cap) keeps the payload.
func test_no_unloadable_sprite_dir_ships_in_any_export() -> void:
	var jobs := _job_ids()
	var filters := _exclude_filters()
	var shipped: Array = []
	var dead_dirs := 0
	for dir_name in _dirs_under_jobs():
		if jobs.has(dir_name):
			continue
		dead_dirs += 1
		var probe := "assets/sprites/jobs/%s/idle.png" % dir_name
		for f in filters:
			if not _excluded_by(f["patterns"], probe):
				shipped.append("%s/ is not excluded from the %s export — no job id can load it" % [dir_name, f["preset"]])
	assert_gt(dead_dirs, 0,
		"ANTI-VACUITY: no unloadable sprite dir exists any more, so this guard is defending nothing — check whether the filters are still earning their place")
	assert_eq(shipped, [], "a sprite dir no job can load is still in a player's download: %s" % [shipped])


## The manifest registers four of these dirs as `sheets` entries. That is provenance, not a
## route — but it is also how a reader concludes they are live, so the claim is pinned here.
func test_the_registered_experiment_sheets_are_not_job_ids() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(parsed is Dictionary, "sprite_manifest.json must parse")
	var sheets: Dictionary = parsed.get("sheets", {}) if parsed is Dictionary else {}
	assert_gt(sheets.size(), 0, "ANTI-VACUITY: no sheets registered")
	var jobs := _job_ids()
	var non_job := 0
	for k in sheets:
		if not jobs.has(str(k)):
			non_job += 1
	assert_gt(non_job, 0,
		"every sheets entry is now a job id — the experiment registrations are gone, so the export filters for them may be stale")
	assert_gt(sheets.size() - non_job, 4,
		"only %d sheets entries are real job ids — the roster cannot have shrunk that far, so this arm is measuring the wrong thing" % (sheets.size() - non_job))
