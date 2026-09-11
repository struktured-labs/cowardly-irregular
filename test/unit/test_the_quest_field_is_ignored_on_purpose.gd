extends GutTest

## Two errors cancel here, and a future REPAIR removes the cancellation.
##
## jobs.json gates guardian/speculator/summoner on {"type":"story","chapter":N,"quest":"<name>"}.
## None of the three named quests exists — each string occurs exactly once in the repo, in the gate
## requiring it, the identical fingerprint `speed_demon` had before the Ninja became obtainable.
## The three jobs are reachable anyway because the evaluator resolves "story" to the CHAPTER flag
## and throws the quest id away.
##
## So: making the reader honest — obviously correct work, which someone will eventually do — makes
## three jobs unreachable in that commit. cowir-adhoc's term for this shape is REDUNDANT BY DISCARD,
## as against redundant by design: the field is not merely unused, it is unused in a way that is
## holding up the data's own mistake. This file exists so that repair reds here first and arrives
## with the quests authored, rather than arriving alone.

const JOBS := "res://data/jobs.json"
const EVALUATOR := "res://src/jobs/JobSystem.gd"

func _jobs() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(JOBS))
	assert_not_null(parsed, "CONTROL: jobs.json parses")
	return parsed.get("jobs", parsed)

func _quest_gated() -> Dictionary:
	var out: Dictionary = {}
	for jid in _jobs():
		var c: Dictionary = (_jobs()[jid] as Dictionary).get("unlock_condition", {}) if _jobs()[jid] is Dictionary else {}
		if str(c.get("type", "")) == "story" and str(c.get("quest", "")) != "":
			out[jid] = str(c["quest"])
	return out

func test_the_named_quests_still_do_not_exist() -> void:
	## If somebody authors one, this reds — and that is the GOOD outcome: it means the repair below
	## has become safe for that job. The list shrinking is the signal to revisit, not a failure.
	var missing: Array = []
	var dir := DirAccess.open("res://data/quests")
	assert_not_null(dir, "CONTROL: opened the quest directory")
	var defined: String = ""
	if dir != null:
		dir.list_dir_begin()
		var e: String = dir.get_next()
		while e != "":
			if e.ends_with(".json"):
				defined += FileAccess.get_file_as_string("res://data/quests/" + e)
			e = dir.get_next()
		dir.list_dir_end()
	assert_gt(defined.length(), 500, "CONTROL: the quest corpus is readable and non-empty")
	var gated := _quest_gated()
	assert_gt(gated.size(), 2, "CONTROL: jobs still gate on a quest field (%d)" % gated.size())
	for jid in gated:
		if not defined.contains(str(gated[jid])):
			missing.append("%s/%s" % [jid, gated[jid]])
	missing.sort()
	assert_eq(missing, ["guardian/protectors_oath", "speculator/market_crash", "summoner/pact_of_eidolons"],
		"the set of jobs gated on a NON-EXISTENT quest changed — if one was authored, the evaluator may now safely read it for that job: " + str(missing))

func test_the_evaluator_still_ignores_the_quest_field() -> void:
	## The other half of the cancellation. If this reds, someone made the reader honest — and the
	## arm above tells them which jobs they just stranded.
	var src := FileAccess.get_file_as_string(EVALUATOR)
	assert_gt(src.length(), 1000, "CONTROL: read the evaluator")
	var i: int = src.find('"story":')
	assert_gt(i, -1, "CONTROL: located the story arm")
	var j: int = src.find('"boss_defeat":', i)
	assert_gt(j, i, "CONTROL: the arm window closes")
	var arm: String = src.substr(i, j - i)
	assert_true(arm.contains("cutscene_flag_chapter"), "CONTROL: the arm really does gate on the chapter flag")
	assert_false(arm.contains('"quest"') or arm.contains("get(\"quest\""),
		"the story arm now reads its quest id — guardian, speculator and summoner are gated on quests that DO NOT EXIST, so author those first or they become unreachable")

func test_those_three_jobs_are_reachable_today() -> void:
	## The outcome the two arms above protect, stated as behaviour rather than as source text.
	var js: Node = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	if js == null or gs == null or not js.has_method("is_job_unlocked"):
		pending("JobSystem and GameState required")
		return
	var prior_debug: bool = bool(gs.debug_log_enabled)
	var prior: Dictionary = gs.game_constants.duplicate(true)
	gs.debug_log_enabled = false
	gs.game_constants["cutscene_flag_chapter2_complete"] = true
	gs.game_constants["cutscene_flag_chapter3_complete"] = true
	var unlocked: Array = []
	for jid in ["guardian", "speculator", "summoner"]:
		if js.is_job_unlocked(jid):
			unlocked.append(jid)
	gs.game_constants = prior
	gs.debug_log_enabled = prior_debug
	assert_eq(unlocked, ["guardian", "speculator", "summoner"],
		"completing the chapters must unlock all three, quest field or no quest field")
