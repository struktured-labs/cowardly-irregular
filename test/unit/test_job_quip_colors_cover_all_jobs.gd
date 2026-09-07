extends GutTest

## tick 124 regression: JOB_QUIP_COLORS must have an entry for every
## playable job (5 starter + 4 advanced + 5 meta = 14 total). Pre-fix,
## the 5 meta jobs (scriptweaver / time_mage / necromancer / bossbinder
## / skiptrotter) fell through to the default gray Color(0.8, 0.8, 0.8)
## in _get_job_quip_color — breaking the per-job visual story for
## anyone unlocking them via debug mode.

const BATTLE_SCENE := "res://src/battle/BattleScene.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


## All 14 playable job ids from data/jobs.json.
const ALL_JOB_IDS: Array[String] = [
	# Starter (type 0)
	"fighter", "cleric", "mage", "rogue", "bard",
	# Advanced (type 1)
	"guardian", "ninja", "summoner", "speculator",
	# Meta (type 2) — added in tick 124
	"scriptweaver", "time_mage", "necromancer", "bossbinder", "skiptrotter",
]


func _job_quip_colors_body() -> String:
	var src := _read(BATTLE_SCENE)
	var idx: int = src.find("const JOB_QUIP_COLORS")
	assert_gt(idx, -1, "JOB_QUIP_COLORS const must exist")
	# Const body ends with `}` on its own line.
	var end_idx: int = src.find("\n}", idx)
	assert_gt(end_idx, -1, "JOB_QUIP_COLORS const must have a closing brace")
	return src.substr(idx, end_idx - idx + 2)


func test_every_playable_job_has_a_quip_color() -> void:
	var body := _job_quip_colors_body()
	for job_id in ALL_JOB_IDS:
		var quoted: String = "\"" + job_id + "\":"
		assert_true(body.contains(quoted),
			"JOB_QUIP_COLORS must contain key for %s — otherwise quip bubbles fall back to default gray" % job_id)


func test_no_two_jobs_share_a_color() -> void:
	# Pin uniqueness: each job's color must be visually distinct.
	# Two jobs sharing a color defeats the per-job visual story.
	# Skip this if the dict still has duplicates from a future
	# intentional decision — but for now every entry is unique.
	var script_class = load(BATTLE_SCENE)
	var colors: Dictionary = script_class.JOB_QUIP_COLORS
	var seen: Dictionary = {}
	for job_id in colors:
		var c: Color = colors[job_id]
		var key: String = "%.3f,%.3f,%.3f" % [c.r, c.g, c.b]
		assert_false(seen.has(key),
			"%s shares color (%s) with %s — every job must have a unique quip color" % [job_id, key, seen.get(key, "")])
		seen[key] = job_id


func test_meta_job_colors_are_distinct_from_starters() -> void:
	# Defensive: meta jobs shouldn't accidentally land on a starter
	# color. Specifically check that scriptweaver/time_mage/etc aren't
	# clashing with their thematic neighbors.
	var script_class = load(BATTLE_SCENE)
	var colors: Dictionary = script_class.JOB_QUIP_COLORS
	# scriptweaver (neon green) shouldn't match rogue (sneak green).
	assert_ne(colors["scriptweaver"], colors["rogue"],
		"scriptweaver and rogue must have distinct colors — both lean green, easy to confuse")
	# time_mage (pale blue) shouldn't match mage (purple).
	assert_ne(colors["time_mage"], colors["mage"],
		"time_mage and mage must have distinct colors")
	# bossbinder (boss-red) — pin the specific value so a future
	# refactor doesn't accidentally soften it (the point IS that it
	# reads as boss-red). Float-precision tolerant.
	assert_almost_eq(colors["bossbinder"].r, 0.95, 0.001,
		"bossbinder must keep its boss-red R component near 0.95 — diegetic 'they BECOME the boss' tell")


func test_default_fallback_unchanged() -> void:
	# Sanity: don't accidentally break the fallback path for unknown
	# job ids. _get_job_quip_color should still default to gray.
	var src := _read(BATTLE_SCENE)
	var idx: int = src.find("func _get_job_quip_color")
	assert_gt(idx, -1, "_get_job_quip_color must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("Color(0.8, 0.8, 0.8)"),
		"_get_job_quip_color must still default to gray Color(0.8, 0.8, 0.8) — catch-all for unknown ids")


func test_jobs_json_only_contains_known_ids() -> void:
	# Sanity: every job ID in data/jobs.json must be in
	# JOB_QUIP_COLORS or we have an inverse gap. (If a NEW job is
	# added to jobs.json without updating this const, this test
	# fails — prompts a sibling color decision.)
	var f := FileAccess.open("res://data/jobs.json", FileAccess.READ)
	assert_not_null(f, "jobs.json must be readable")
	var text: String = f.get_as_text()
	f.close()
	var json := JSON.new()
	assert_eq(json.parse(text), OK, "jobs.json must parse")
	var data = json.data
	assert_true(data is Dictionary, "jobs.json must be a dict")
	var known: Array[String] = ALL_JOB_IDS
	for job_id in data.keys():
		# Skip evolutions/forks marked with `evolves_from` — those
		# aren't directly playable. Detect by looking for the field.
		var entry = data[job_id]
		if entry is Dictionary and entry.has("evolves_from"):
			continue
		assert_true(job_id in known,
			"data/jobs.json has job '%s' but JOB_QUIP_COLORS doesn't — add an entry" % job_id)
