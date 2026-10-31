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
	assert_true(text.find("_lead_job_id()") > -1,
		"lead_job branch must read the live leader via _lead_job_id(), not the save snapshot")
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
	# get_party_leader() still returns the save snapshot. The lead_job branch
	# does not read it (that snapshot lags a job change). Other callers do.
	# If the return type stops being a Dictionary, those callers break.
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
	# A bare contains("push_warning") passes as soon as ANY warning exists in this
	# function — including one added to the flag path — so it would stop guarding
	# the fallthrough without reddening. Pin the arm and the message it owes.
	assert_true(body.contains("\n\telse:"),
		"_step_branch must keep an else arm — without it an unknown condition runs nothing silently")
	assert_true(body.contains("has no handler"),
		"the fallthrough must NAME the unhandled condition; a silent else is the same bug with extra lines")


## COVERAGE, which is the half neither ratchet asks. The arm above pins that every authored
## lead_job KEY resolves to a real job; the playstyle sibling pins the same for its own keys.
## Neither asks whether the keys COVER the leads the game can hand the branch, and with no
## `default` the dispatcher runs NOTHING: `cases.get(lead_job, cases.get("default", []))`
## returns `[]`, the sub-step loop iterates zero times, and nothing warns — the else arm pinned
## above only fires for an unknown CONDITION, never for an unmatched case.
##
## Measured on eb41c9954: 10 lead_job branches, 8 carry a default, and the two that do not are
## both in world1_prologue. One of them is the SOLE writer of `spotlight_lead_<job>` — the key
## GameLoop._reconcile_spotlight_locks reads to leave the PC you led with playable without
## winning their spotlight duel. A lead with no arm there keeps the lock, silently.
##
## The startable set is DERIVED from jobs.json `type == 0`, not listed: advanced (1) and meta (2)
## jobs are debug-gated, so a lead outside the starters is not normal play and must not red this,
## while authoring a sixth starter must.
const STARTER_JOB_TYPE := 0


func _starter_job_ids() -> Array:
	var json := JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(JOBS_PATH)), OK, "jobs.json must parse")
	var rows: Dictionary = json.data
	var out: Array = []
	for id in rows.keys():
		var row: Variant = rows[id]
		if row is Dictionary and int((row as Dictionary).get("type", -1)) == STARTER_JOB_TYPE:
			out.append(str(id))
	out.sort()
	return out


## Whole branches, not just their keys — the default and the arms' side effects are the subject.
func _lead_job_branches() -> Array:
	var found: Array = []
	var dir := DirAccess.open(CUTSCENE_DIR)
	assert_not_null(dir, "cutscene dir must be readable")
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			var json := JSON.new()
			if json.parse(FileAccess.get_file_as_string(CUTSCENE_DIR.path_join(fname))) == OK:
				_collect_lead_job_branches(json.data, fname, found)
		fname = dir.get_next()
	dir.list_dir_end()
	return found


func _collect_lead_job_branches(node: Variant, fname: String, out: Array) -> void:
	if node is Dictionary:
		var d: Dictionary = node
		if str(d.get("condition", "")) == "lead_job" and d.get("cases") is Dictionary:
			var cases: Dictionary = d["cases"]
			var keys: Array = []
			var flags: Array = []
			for k in cases.keys():
				keys.append(str(k))
				_collect_set_flags(cases[k], flags)
			keys.sort()
			flags.sort()
			out.append({"file": fname, "keys": keys, "has_default": cases.has("default"), "flags": flags})
		for v in d.values():
			_collect_lead_job_branches(v, fname, out)
	elif node is Array:
		for v in node:
			_collect_lead_job_branches(v, fname, out)


## Flags an arm writes at ANY depth — a set_flag nested in a choice or an inner branch still
## travels with the arm, and a shallow read would call a deep write uncovered.
func _collect_set_flags(node: Variant, out: Array) -> void:
	if node is Dictionary:
		var d: Dictionary = node
		if str(d.get("type", "")) == "set_flag" and str(d.get("flag", "")) != "":
			var f: String = str(d["flag"])
			if not out.has(f):
				out.append(f)
		for v in d.values():
			_collect_set_flags(v, out)
	elif node is Array:
		for v in node:
			_collect_set_flags(v, out)


## Pure over its argument so the controls below can drive it with a synthetic corpus — a
## predicate only reachable through the real corpus cannot be shown to fire on a real gap.
func _coverage_gaps(branches: Array, starters: Array) -> Array:
	var gaps: Array = []
	for entry in branches:
		var b: Dictionary = entry
		if bool(b.get("has_default", false)):
			continue
		var keys: Array = b.get("keys", [])
		var missing: Array = []
		for job in starters:
			if not keys.has(job):
				missing.append(job)
		if not missing.is_empty():
			gaps.append("%s: no default and no arm for %s (authored: %s)" % [str(b.get("file", "?")), str(missing), str(keys)])
	return gaps


# ── Positive controls — a green guard below must be impossible to get for free ───────────────

func test_the_coverage_predicate_reports_a_real_gap() -> void:
	var starters := _starter_job_ids()
	assert_gt(starters.size(), 3,
		"jobs.json yielded only %d starter(s) at type == %d — the derivation has broken, so an empty gap list proves nothing" % [starters.size(), STARTER_JOB_TYPE])
	var under_covered: Array = [{"file": "synthetic.json", "keys": [starters[0]], "has_default": false, "flags": []}]
	assert_eq(_coverage_gaps(under_covered, starters).size(), 1,
		"a branch authoring one starter with no default MUST be reported — this is the shape the guard exists to catch")


func test_the_coverage_predicate_clears_the_two_legal_shapes() -> void:
	var starters := _starter_job_ids()
	assert_gt(starters.size(), 3, "the starter derivation must be real — read %d" % starters.size())
	var defaulted: Array = [{"file": "synthetic.json", "keys": ["default", starters[0]], "has_default": true, "flags": []}]
	assert_eq(_coverage_gaps(defaulted, starters).size(), 0,
		"a default arm IS the authored fallback — one starter beside it is legal and must not red")
	var complete: Array = [{"file": "synthetic.json", "keys": starters.duplicate(), "has_default": false, "flags": []}]
	assert_eq(_coverage_gaps(complete, starters).size(), 0,
		"full starter coverage needs no default")


# ── The guard ────────────────────────────────────────────────────────────────────────────────

func test_every_lead_job_branch_covers_every_startable_lead() -> void:
	var starters := _starter_job_ids()
	assert_gt(starters.size(), 3, "the starter derivation must be real — read %d" % starters.size())
	var branches := _lead_job_branches()
	assert_gt(branches.size(), 5,
		"the branch walk found only %d lead_job branch(es) — the corpus held 10 when this was written, so a clean result here would be vacuous" % branches.size())
	var gaps := _coverage_gaps(branches, starters)
	assert_eq(gaps.size(), 0,
		("a lead_job branch with no `default` runs NOTHING for a lead it has no arm for: " +
		"cases.get(lead_job, cases.get(\"default\", [])) hands back [] and no warning is emitted.\n  %s")
		% "\n  ".join(gaps))


func test_a_flag_writing_lead_job_arm_cannot_lose_its_write() -> void:
	var starters := _starter_job_ids()
	assert_gt(starters.size(), 3, "the starter derivation must be real — read %d" % starters.size())
	var writers: Array = []
	for entry in _lead_job_branches():
		var b: Dictionary = entry
		if not (b.get("flags", []) as Array).is_empty():
			writers.append(b)
	assert_gt(writers.size(), 0,
		"no lead_job arm writes a flag anywhere in the corpus — if the prologue's spotlight_lead_<job> write moved, this arm is measuring nothing and must be re-aimed")
	var gaps := _coverage_gaps(writers, starters)
	assert_eq(gaps.size(), 0,
		("a lead_job arm that WRITES A FLAG and has no default loses that write for an uncovered lead. " +
		"spotlight_lead_<job> is read by GameLoop._reconcile_spotlight_locks, so a lost write leaves the " +
		"lead PC autobattle_locked until they win a duel they were meant to skip.\n  %s")
		% "\n  ".join(gaps))
