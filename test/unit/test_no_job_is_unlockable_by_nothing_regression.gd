extends GutTest

## THREE JOBS ARE LOCKED BY A CONDITION THAT DOES NOT EXIST.
##
## 2026-09-11. `JobSystem.is_job_unlocked()` returns FALSE when a non-starter job's
## `unlock_condition` is null or empty — before any match arm runs, with no warning:
##
##     var cond: Variant = job_data.get("unlock_condition", {})
##     if not (cond is Dictionary) or (cond as Dictionary).is_empty():
##         return false
##
## `scriptweaver`, `time_mage` and `necromancer` are all type 2 with
## `"unlock_condition": null`. There is no game state that unlocks them. They have
## full kits, portraits registered in CutsceneDialogue.PORTRAIT_SPRITES, and abilities
## authored to level 8 — and a player outside debug mode can never field one.
##
## ⚠️ WHY THE EXISTING GUARD IS GREEN ON THIS, because it is the evening's shape again.
## test_job_unlock_condition_regression pins the MECHANISM: the helper exists, starters
## are unconditional, debug bypasses, JobMenu consults it, guardian gates on chapter 2,
## bossbinder gates on ten bosses. Every arm is correct. Its data arm asserts that SOME
## job authors a condition (`found_with_cond`) — so three jobs authoring NONE is exactly
## what it cannot see. Plumbing, never membership.
##
## 🔑 THE MECHANISM THAT WOULD FIX TWO OF THEM IS AUTHORED AND UNREAD. jobs.json carries
## a complete `evolution` block on 14 jobs — six real paths with level gates — and no
## code reads "evolution", "evolves_from", "level_required" or "future_targets":
##     fighter@5 -> guardian     guardian@8 -> bossbinder    summoner@8  -> necromancer
##     rogue@5   -> ninja        ninja@8    -> skiptrotter   speculator@8 -> scriptweaver
## So necromancer and scriptweaver have an authored route nothing runs, and time_mage
## has `evolution.target: null` — no authored route at all, by either vocabulary.
## Same class as the one_shot block and the cutscene `trigger` field: data that states
## the answer, and no consumer.
##
## ⚠️ NOT THE SAME DEFECT AS THE NINJA, deliberately excluded from the list below. The
## Ninja's condition EXISTS and is well-formed (`achievement: speed_demon`); nothing in
## the game awards that flag. Satisfy it by hand and the Ninja unlocks — which is why
## the arm below passes for it and why test_the_ninja_cannot_be_unlocked owns that half.
## A job with no condition and a job with an unproducible one fail in different places
## and are one fix apart in different directions; merging them would hide both.

const JOBS_JSON := "res://data/jobs.json"

## Non-starter jobs that NO game state can unlock, with the reason each is stuck.
## This is DEBT, not an exemption — every one is a shipped class a player cannot reach.
##   grows   -> a new job shipped with no unlock_condition
##   shrinks -> someone gave one a route; delete the line
const UNREACHABLE_JOBS := {
	"scriptweaver": "unlock_condition null; evolution says speculator@L8 and nothing reads evolution",
	"time_mage": "unlock_condition null AND evolution.target null — no authored route in either vocabulary",
	"necromancer": "unlock_condition null; evolution says summoner@L8 and nothing reads evolution",
}

## The keys that would carry the missing route if anything read them. Bidirectional:
## when a consumer appears, the debt list above has to be re-examined rather than left
## claiming these classes are stranded.
const EVOLUTION_KEYS: Array[String] = ["evolution", "evolves_from", "level_required", "future_targets"]

const STARTER_TYPE := 0

var _cache: Dictionary = {}


func _jobs() -> Dictionary:
	if _cache.has("jobs"):
		return _cache["jobs"]
	var raw: String = FileAccess.get_file_as_string(JOBS_JSON)
	assert_ne(raw, "", "jobs.json must be readable")
	var parsed: Variant = JSON.parse_string(raw)
	var root: Dictionary = parsed as Dictionary if parsed is Dictionary else {}
	var inner: Variant = root.get("jobs", root)
	var out: Dictionary = inner as Dictionary if inner is Dictionary else {}
	_cache["jobs"] = out
	return out


## Non-starter jobs whose unlock_condition is absent — the shape is_job_unlocked
## refuses before any match arm runs.
func _conditionless_non_starters() -> Array[String]:
	var out: Array[String] = []
	for jid in _jobs().keys():
		var j: Variant = _jobs()[jid]
		if not (j is Dictionary):
			continue
		if int((j as Dictionary).get("type", STARTER_TYPE)) == STARTER_TYPE:
			continue
		var cond: Variant = (j as Dictionary).get("unlock_condition", null)
		if not (cond is Dictionary) or (cond as Dictionary).is_empty():
			out.append(str(jid))
	out.sort()
	return out


## PREMISE. The walk needs a real population with both kinds in it, or the ratchet
## compares an empty set to an empty set.
func test_premise_the_job_corpus_has_starters_and_advanced() -> void:
	var jobs := _jobs()
	assert_gt(jobs.size(), 10, "only %d jobs parsed from jobs.json — the walk is not reading the file" % jobs.size())
	var starters: int = 0
	var advanced: int = 0
	for jid in jobs.keys():
		var j: Variant = jobs[jid]
		if not (j is Dictionary):
			continue
		if int((j as Dictionary).get("type", STARTER_TYPE)) == STARTER_TYPE:
			starters += 1
		else:
			advanced += 1
	assert_gt(starters, 3, "expected several starter jobs, found %d" % starters)
	assert_gt(advanced, 5, "expected several non-starter jobs, found %d" % advanced)
	# NAMED MEMBERS. A floor is blind to partial loss: drop half the jobs and both
	# counts above still clear. These four must be here by name, one per side.
	for jid in ["fighter", "rogue", "guardian", "time_mage"]:
		assert_true(jobs.has(jid),
			"%s is missing from the parsed jobs — the walk is covering less than it did, which a count floor cannot see" % jid)


## POSITIVE CONTROL, harvested: guardian authors a well-formed condition. If the
## detector cannot tell a job WITH a condition from one without, a clean list is
## meaningless.
func test_the_detector_distinguishes_a_job_that_has_a_condition() -> void:
	var conditionless := _conditionless_non_starters()
	assert_false(conditionless.has("guardian"),
		"guardian authors {type: story, chapter: 2} — flagging it as conditionless means this file's reader is broken, not the data")
	assert_false(conditionless.has("ninja"),
		"ninja authors {type: achievement, id: speed_demon} — its condition EXISTS and has no producer, which is a different defect and a different file")


## THE RATCHET, bidirectional.
func test_every_non_starter_job_has_some_route_or_is_named_as_stranded() -> void:
	var conditionless := _conditionless_non_starters()

	var newly_stranded: Array[String] = []
	for jid in conditionless:
		if not UNREACHABLE_JOBS.has(jid):
			newly_stranded.append(jid)
	assert_eq(newly_stranded.size(), 0,
		"a non-starter job shipped with no unlock_condition, so is_job_unlocked returns false for it in every game state: %s — give it a condition, or add it to UNREACHABLE_JOBS with the reason" % ", ".join(newly_stranded))

	# STALE-BY-DELETION, same cell. `conditionless` is built from jobs that EXIST, so a
	# deleted job simply stops appearing and its UNREACHABLE_JOBS line survives as a
	# standing claim about a class the game no longer has.
	var jobs := _jobs()
	var vanished: Array[String] = []
	for jid in UNREACHABLE_JOBS.keys():
		if not jobs.has(str(jid)):
			vanished.append(str(jid))
	vanished.sort()
	assert_eq(vanished.size(), 0,
		"UNREACHABLE_JOBS names a job that is no longer in jobs.json: %s — if the class was retired, delete the line with it; the entry currently claims a stranded class that does not exist." % ", ".join(vanished))

	var freed: Array[String] = []
	for jid in UNREACHABLE_JOBS.keys():
		if not conditionless.has(str(jid)):
			freed.append(str(jid))
	freed.sort()
	assert_eq(freed.size(), 0,
		"GOOD NEWS, STALE LIST: %s now authors an unlock_condition. Delete the key(s) from UNREACHABLE_JOBS at the top of this file so it stops claiming the class is unreachable." % ", ".join(freed))


## BEHAVIOURAL. Runs the SHIPPED helper with debug off. A conditionless job must be
## locked no matter what the save looks like — this is what makes the list above a
## statement about the game rather than about the JSON.
##
## ⚠️ STATE IS RESTORED KEY BY KEY, NOT BY REASSIGNING THE DICT — and this is measured,
## not reasoned. The first cut did `GameState.game_constants = prior.duplicate(true)`,
## the pattern the neighbouring job-unlock test uses, and it CONTAMINATED
## test_dragon_intents_are_mechanical_too in the same process:
##     dragon file alone                         6/6 pass
##     after this file, dict REASSIGNED          fails on 'aggress', 0.61 vs < 0.05
##     after this file, restored IN PLACE       11/11 pass
##     after the NEIGHBOURING test (reassigns)  14/14 pass
## Same keys set in both of my versions, so the restore METHOD is the discriminator.
## Why reassignment is destructive here and not there, I did not establish — the
## neighbouring test touches fewer keys, so it is key-dependent and I am not going to
## state a mechanism I have not shown. What is demonstrated: touch only the keys you
## set, put back exactly what was there, and mutate arrays in place.
func test_a_stranded_job_is_locked_under_the_shipped_helper() -> void:
	if JobSystem == null or GameState == null:
		pending("JobSystem and GameState autoloads required")
		return
	var subject: String = ""
	for jid in UNREACHABLE_JOBS.keys():
		if JobSystem.jobs.has(str(jid)):
			subject = str(jid)
			break
	if subject == "":
		pending("none of the stranded jobs are loaded in this harness")
		return

	# The most permissive save this helper can read: every gate it knows how to check,
	# satisfied at once. A job still locked here is locked by the absence of a rule.
	var touched: Array[String] = ["game_complete"]
	for ch in range(1, 12):
		touched.append("cutscene_flag_chapter%d_complete" % ch)

	var prior_debug: bool = bool(GameState.debug_log_enabled)
	var had: Dictionary = {}
	var was: Dictionary = {}
	for key in touched:
		had[key] = GameState.game_constants.has(key)
		if bool(had[key]):
			was[key] = GameState.game_constants[key]
	var prior_bosses: Array = []
	for b in GameState.previously_fought_bosses:
		prior_bosses.append(b)

	GameState.debug_log_enabled = false
	for key in touched:
		GameState.game_constants[key] = true
	GameState.previously_fought_bosses.clear()
	for i in range(25):
		GameState.previously_fought_bosses.append("probe_boss_%d" % i)

	var locked_anyway: bool = not JobSystem.is_job_unlocked(subject)
	# Control in the same state: a job WITH a satisfiable condition must come back
	# unlocked, or "locked" below would just mean the probe state did not apply.
	var control_unlocked: bool = JobSystem.is_job_unlocked("guardian") if JobSystem.jobs.has("guardian") else true

	# Restore in place.
	GameState.debug_log_enabled = prior_debug
	for key in touched:
		if bool(had[key]):
			GameState.game_constants[key] = was[key]
		else:
			GameState.game_constants.erase(key)
	GameState.previously_fought_bosses.clear()
	for b in prior_bosses:
		GameState.previously_fought_bosses.append(b)

	assert_true(control_unlocked,
		"CONTROL FAILED: guardian stayed locked with every chapter flag set, so the probe state never applied and the result below says nothing")
	assert_true(locked_anyway,
		"%s reported UNLOCKED with no unlock_condition — if is_job_unlocked now has a default-allow path, this file's premise changed and the debt list must be re-derived" % subject)


## The repair pointer, same subject: the authored route nobody runs. When a consumer
## for the evolution vocabulary appears, two of the three stranded classes get a path
## and this list stops being true — so this fails rather than going quietly stale.
func test_the_evolution_vocabulary_is_still_unread() -> void:
	var job_system_src: String = FileAccess.get_file_as_string("res://src/jobs/JobSystem.gd")
	var job_menu_src: String = FileAccess.get_file_as_string("res://src/ui/JobMenu.gd")
	assert_ne(job_system_src, "", "JobSystem.gd must be readable")
	assert_ne(job_menu_src, "", "JobMenu.gd must be readable")

	# Confirm the data still carries the routes, or this arm is asking about nothing.
	var with_evolution: int = 0
	for jid in _jobs().keys():
		var j: Variant = _jobs()[jid]
		if j is Dictionary and (j as Dictionary).has("evolution"):
			with_evolution += 1
	assert_gt(with_evolution, 10,
		"only %d jobs carry an evolution block; there were 14 — if the data was removed, delete this arm with it" % with_evolution)

	var now_read: Array[String] = []
	for key in EVOLUTION_KEYS:
		var quoted: String = "\"%s\"" % key
		if job_system_src.contains(quoted) or job_menu_src.contains(quoted):
			now_read.append(key)
	assert_eq(now_read.size(), 0,
		"GOOD NEWS: the evolution vocabulary is now read (%s). Re-derive UNREACHABLE_JOBS — necromancer (summoner@L8) and scriptweaver (speculator@L8) may now have a route, and time_mage still will not." % ", ".join(now_read))
