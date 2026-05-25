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
