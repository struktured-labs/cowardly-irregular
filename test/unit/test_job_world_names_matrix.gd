extends GutTest

## Guards data/job_world_names.json: a missing cell must never be indistinguishable from a deliberate fallback.

const NAMES_PATH := "res://data/job_world_names.json"
const JOBS_PATH := "res://data/jobs.json"
const REGIONS_PATH := "res://src/autogrind/AutogrindSystem.gd"

var _data: Dictionary = {}
var _worlds: Dictionary = {}
var _jobs: Dictionary = {}


func before_each() -> void:
	var raw: String = FileAccess.get_file_as_string(NAMES_PATH)
	var parsed: Variant = JSON.parse_string(raw)
	_data = (parsed as Dictionary) if parsed is Dictionary else {}
	_worlds = _data.get("worlds", {}) as Dictionary
	_jobs = _data.get("jobs", {}) as Dictionary


## FLOOR. Every assertion below is vacuous if the file did not parse.
func test_control_the_file_parses_and_names_a_known_member() -> void:
	assert_false(_data.is_empty(), "job_world_names.json must parse as a Dictionary")
	assert_false(_jobs.is_empty(), "the jobs map must be non-empty")
	assert_true(_jobs.has("fighter"),
		"NAMED-member control, not a count: a count passes on an empty parse. got keys: %s" % [_jobs.keys()])
	assert_eq(str((_jobs.get("fighter", {}) as Dictionary).get("suburban", "")), "Mall Cop",
		"struktured's own example is the anchor — if this moves, the register moved with it")


## The world key space must EQUAL 1-6, not merely contain it.
func test_world_keys_are_exactly_one_through_six() -> void:
	var keys: Array = _worlds.keys()
	keys.sort()
	assert_eq(keys, ["1", "2", "3", "4", "5", "6"],
		"set equality, not 'contains': a per-key loop passes a file missing World 5 entirely. got: %s" % [keys])
	assert_true(_worlds.has("5"),
		"NAMED control on the world four vocabularies disagree about — W5 is the one that goes silent")


## Every job carries every world. A sparse matrix makes MISSING and FALLS-BACK the same observation.
func test_every_job_has_a_name_for_every_world() -> void:
	var labels: Array = _worlds.values()
	var holes: Array = []
	for job_id in _jobs:
		for label in labels:
			if not (_jobs[job_id] as Dictionary).has(label):
				holes.append("%s/%s" % [job_id, label])
	assert_eq(holes, [],
		"a hole is silently indistinguishable from 'use the base name' at runtime — fill it or "
		+ "make the fallback an explicit branch. missing: %s" % [holes])


## A label no world maps to is dead content the resolver can never reach.
func test_no_job_carries_an_unknown_world_label() -> void:
	var labels: Array = _worlds.values()
	var strays: Array = []
	for job_id in _jobs:
		for label in (_jobs[job_id] as Dictionary):
			if not labels.has(label):
				strays.append("%s/%s" % [job_id, label])
	assert_eq(strays, [], "labels not present in `worlds` are unreachable. got: %s" % [strays])


## Six identical name-sets is exactly what a resolver stuck on its default produces.
func test_each_world_name_set_is_distinct() -> void:
	var labels: Array = _worlds.values()
	var sets: Dictionary = {}
	for label in labels:
		var names: Array = []
		for job_id in _jobs:
			names.append(str((_jobs[job_id] as Dictionary).get(label, "")))
		names.sort()
		sets[label] = "|".join(names)
	var collisions: Array = []
	for i in range(labels.size()):
		for j in range(i + 1, labels.size()):
			if sets[labels[i]] == sets[labels[j]]:
				collisions.append("%s==%s" % [labels[i], labels[j]])
	assert_eq(collisions, [],
		"distinctness is the property a fallback cannot fake — a stuck resolver yields identical "
		+ "sets and every other check still passes. collisions: %s" % [collisions])


## A renamed job silently orphans its whole row; jobs.json is the registry that decides.
func test_every_named_job_exists_in_jobs_json() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(JOBS_PATH))
	assert_true(parsed is Dictionary, "jobs.json is a flat Dictionary keyed by job id")
	var known: Array = (parsed as Dictionary).keys() if parsed is Dictionary else []
	assert_true(known.has("fighter"),
		"CONTROL: the jobs.json parse must find a known id, else every check below is vacuous. got %d ids" % [known.size()])
	var orphans: Array = []
	for job_id in _jobs:
		if not known.has(job_id):
			orphans.append(job_id)
	assert_eq(orphans, [], "job ids must exist in jobs.json. orphaned rows: %s" % [orphans])


## Cross-check the int->label order against a second, independently maintained source.
func test_world_numbering_agrees_with_autogrind_region_table() -> void:
	var src: String = FileAccess.get_file_as_string(REGIONS_PATH)
	assert_false(src.is_empty(), "CONTROL: AutogrindSystem.gd must be readable")
	var rx := RegEx.create_from_string('"world"\\s*:\\s*(\\d+)\\s*,\\s*"region"\\s*:\\s*"([a-z_]+)"')
	var found: Dictionary = {}
	for m in rx.search_all(src):
		found[m.get_string(1)] = m.get_string(2)
	assert_true(found.has("5"),
		"CONTROL: the region table must yield a known member, else a zero here reads as agreement. got %s" % [found])
	var disagreements: Array = []
	for world_num in _worlds:
		if world_num == "1":
			continue
		var label: String = str(_worlds[world_num])
		var region: String = str(found.get(world_num, ""))
		if region != "" and not region.contains(label):
			disagreements.append("world %s: names say '%s', region is '%s'" % [world_num, label, region])
	assert_eq(disagreements, [],
		"world 1's region id is the bare 'overworld' and is skipped; 2-6 must contain their label. %s" % [disagreements])
