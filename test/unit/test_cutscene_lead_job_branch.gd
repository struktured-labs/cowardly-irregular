extends GutTest

## Regression test for the lead_job branch step type in CutsceneDirector.
##
## Added 2026-05-25 to support W1 spotlight cutscenes (cowir-story
## feature/world1-spotlight-cutscenes). Each spotlight cutscene needs
## to play different beats based on who the player picked as lead PC.
##
## Structural test — runs cheap, catches the case where someone refactors
## _step_branch and accidentally drops the lead_job condition.


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_step_branch_handles_lead_job_condition() -> void:
	var text = _read("res://src/cutscene/CutsceneDirector.gd")
	assert_true(text.find("condition\", \"\") == \"lead_job\"") > -1,
		"_step_branch must have a 'lead_job' condition case")
	assert_true(text.find("GameState.get_party_leader()") > -1,
		"lead_job branch must read the leader from GameState.get_party_leader()")
	assert_true(text.find("job_id") > -1,
		"lead_job branch must extract job_id from the leader dict")


func test_step_branch_lead_job_falls_back_to_default() -> void:
	# When the leader's job has no explicit case in `cases`, the branch
	# must fall back to `cases.default` (matching the playstyle pattern).
	# Without this, lead-variant authoring would have to enumerate all
	# 14 jobs for every spotlight cutscene.
	var text = _read("res://src/cutscene/CutsceneDirector.gd")
	var idx = text.find("\"lead_job\"")
	assert_gt(idx, -1, "lead_job case must exist")
	var next_elif = text.find("\n\telif ", idx)
	if next_elif == -1:
		next_elif = text.find("\n\nfunc ", idx)
	var block = text.substr(idx, next_elif - idx) if next_elif > -1 else text.substr(idx)
	assert_true(block.find("cases.get(lead_job, cases.get(\"default\", []))") > -1,
		"lead_job branch must use cases.get(lead_job, cases.get(\"default\", []))")


func test_get_party_leader_returns_dict_with_job_id() -> void:
	# GameState.get_party_leader() is the source of truth for lead_job.
	# If it ever changes shape (e.g. returns a Combatant instead of a
	# Dictionary), the lead_job branch silently breaks and all spotlight
	# scenes fall through to default.
	var text = _read("res://src/meta/GameState.gd")
	var idx = text.find("func get_party_leader()")
	assert_gt(idx, -1, "GameState must expose get_party_leader()")
	# Confirm signature returns Dictionary (used by the lead_job branch).
	var sig_end = text.find("\n", idx)
	var signature = text.substr(idx, sig_end - idx)
	assert_true(signature.find("-> Dictionary") > -1,
		"get_party_leader() must return Dictionary so lead_job branch can read job_id")


## The playstyle sibling ratchets its case keys hard — every authored key reachable,
## every classifier output authored — but `_collect` filters on condition=="playstyle",
## so the TEN lead_job branches (against six playstyle ones) sit outside its corpus.
## A typo'd job id here is not an error: `cases.get(lead_job, cases.get("default", []))`
## quietly serves the default beat, so the authored lines for that job never play and
## the scene looks fine. Same silent-fallback class, the majority of the branches.
const CUTSCENE_DIR := "res://data/cutscenes"
const JOBS_PATH := "res://data/jobs.json"


func _lead_job_case_keys() -> Array:
	var found: Array = []
	var dir := DirAccess.open(CUTSCENE_DIR)
	assert_not_null(dir, "cutscene dir must be readable")
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			var json := JSON.new()
			if json.parse(FileAccess.get_file_as_string(CUTSCENE_DIR.path_join(fname))) == OK:
				_collect_lead_job(json.data, fname, found)
		fname = dir.get_next()
	dir.list_dir_end()
	return found


func _collect_lead_job(node: Variant, fname: String, out: Array) -> void:
	if node is Dictionary:
		var d: Dictionary = node
		if str(d.get("condition", "")) == "lead_job" and d.get("cases") is Dictionary:
			for k in (d["cases"] as Dictionary).keys():
				out.append({"file": fname, "key": str(k)})
		for v in d.values():
			_collect_lead_job(v, fname, out)
	elif node is Array:
		for v in node:
			_collect_lead_job(v, fname, out)


func test_every_authored_lead_job_case_is_a_real_job() -> void:
	var jobs_json := JSON.new()
	assert_eq(jobs_json.parse(FileAccess.get_file_as_string(JOBS_PATH)), OK, "jobs.json must parse")
	var job_ids: Dictionary = jobs_json.data
	# Corpus floors: an empty scan and a clean scan are the same assertion below.
	assert_gt(job_ids.size(), 10, "jobs.json should hold 14 ids — read %d" % job_ids.size())
	var authored := _lead_job_case_keys()
	assert_gt(authored.size(), 10, "the scan must find the authored lead_job cases — found %d" % authored.size())

	var unreachable: Array = []
	for entry in authored:
		var key: String = entry["key"]
		if key != "default" and not job_ids.has(key):
			unreachable.append("%s: %s" % [entry["file"], key])
	assert_eq(unreachable.size(), 0,
		"these lead_job case keys match no job id, so the branch silently serves 'default' and the authored beat never plays: %s" % str(unreachable))


func test_an_unhandled_branch_condition_is_not_silent() -> void:
	# Source pin: push_warning is not observable from GUT, so the arm checks the
	# fallthrough exists. _execute_step warns on an unknown step TYPE; this chain
	# had no else at all, so an unknown condition ran nothing and said nothing.
	var text := _read("res://src/cutscene/CutsceneDirector.gd")
	var idx := text.find("func _step_branch")
	assert_gt(idx, -1, "_step_branch must exist")
	var next_fn := text.find("\nfunc ", idx + 1)
	var body := text.substr(idx, next_fn - idx) if next_fn > 0 else text.substr(idx)
	assert_true(body.contains("push_warning"),
		"_step_branch must warn when a branch condition matches no handler, or authored sub-steps vanish silently")
