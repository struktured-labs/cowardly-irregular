extends GutTest

## Regression: playtest scout 2026-07-16 — `portrait: "villager"` (36 uses
## across 3 W4-W5 cutscene files) fell through _create_portrait's match
## statement to the narrator procedural (a grey blur), because PR #146
## registered the villager THEME but never added a portrait arm. Same
## silent-fallback failure mode as the theme-registration bug.
##
## Ratchet: every portrait value referenced in data/cutscenes/*.json must
## resolve — either via PORTRAIT_SPRITES artist assets, via the auto-crop
## bust from a job's idle sheet, or via a specific match arm in
## _create_portrait's procedural switch. No silent narrator fallbacks.

const CUTSCENE_DIALOGUE := "res://src/cutscene/CutsceneDialogue.gd"

## Emotion suffixes stripped by _create_portrait before resolution.
const EMOTIONS := ["angry", "sad", "happy", "surprised", "worried", "determined", "mysterious"]


func _strip_emotion(p: String) -> String:
	for e in EMOTIONS:
		if p.ends_with("_" + e):
			return p.substr(0, p.length() - e.length() - 1)
	return p


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


## Everything _create_portrait can resolve to something intentional:
##   (a) PORTRAIT_SPRITES artist bust asset (direct sprite path)
##   (b) auto-crop bust from res://assets/sprites/jobs/<id>/idle.png (any job)
##   (c) an explicit case in the procedural match statement
## Anything NOT in this union hits `_:` and draws the narrator procedural.
func _resolvable_bases() -> Dictionary:
	var src := _read(CUTSCENE_DIALOGUE)
	var resolvable: Dictionary = {}

	# (a) PORTRAIT_SPRITES keys
	var script: GDScript = load(CUTSCENE_DIALOGUE)
	assert_not_null(script, "CutsceneDialogue script must load")
	var sprites: Dictionary = script.PORTRAIT_SPRITES
	for k in sprites:
		resolvable[str(k)] = true

	# (b) job idle sheets on disk (auto-crop bust)
	var jobs_dir = DirAccess.open("res://assets/sprites/jobs")
	if jobs_dir:
		for sub in jobs_dir.get_directories():
			if ResourceLoader.exists("res://assets/sprites/jobs/%s/idle.png" % sub):
				resolvable[sub] = true

	# (c) procedural match arms — extract from source between _create_portrait
	# and _create_bust_from_job_sheet.
	var start := src.find("func _create_portrait(")
	var end := src.find("func _create_bust_from_job_sheet", start)
	assert_gt(start, -1, "_create_portrait must exist")
	assert_gt(end, start, "match block must precede _create_bust_from_job_sheet")
	var block := src.substr(start, end - start)
	# Match arms look like:   "id":  or  "id_a", "id_b":
	# Grab everything inside quotes before a colon.
	var regex := RegEx.new()
	regex.compile('"([a-z_]+)"')
	for m in regex.search_all(block):
		var name := m.get_string(1)
		# Skip _draw_* method-name-fragment false positives.
		if name.begins_with("draw"):
			continue
		resolvable[name] = true
	# Underscore catch-all is NOT resolvable in this audit — it IS the fallback.

	return resolvable


func test_villager_portrait_resolves() -> void:
	# Direct pin for the fix: villager portrait must resolve to something
	# intentional (not the narrator blur fallback).
	var resolvable := _resolvable_bases()
	assert_true(resolvable.has("villager"),
		"'villager' portrait must resolve intentionally in _create_portrait — 36 uses across data/cutscenes were silently drawing the narrator procedural (PR #146 registered the theme colors, not the portrait art)")


func test_every_cutscene_portrait_resolves() -> void:
	var resolvable := _resolvable_bases()
	var offenders: Dictionary = {}  # portrait -> [example files]
	var dir = DirAccess.open("res://data/cutscenes")
	assert_not_null(dir, "cutscenes dir must open")
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var path = "res://data/cutscenes/%s" % f
		var file = FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed = JSON.parse_string(file.get_as_text())
		file.close()
		if not (parsed is Dictionary):
			continue
		for step in parsed.get("steps", []):
			if not (step is Dictionary) or step.get("type") != "dialogue":
				continue
			for line in step.get("lines", []):
				if not (line is Dictionary):
					continue
				var p := str(line.get("portrait", ""))
				if p == "":
					continue
				var base := _strip_emotion(p)
				if resolvable.has(base):
					continue
				if not offenders.has(p):
					offenders[p] = []
				if offenders[p].size() < 3:
					offenders[p].append(f)
	if offenders.is_empty():
		assert_true(true)
		return
	var reports: Array = []
	for p in offenders:
		reports.append("'%s' (e.g. in %s)" % [p, ", ".join(offenders[p])])
	assert_true(false,
		"cutscene JSON references portraits that fall through to the narrator procedural (silent grey blur):\n  %s" % "\n  ".join(reports))
