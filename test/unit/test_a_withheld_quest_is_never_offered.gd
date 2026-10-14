extends GutTest

## ⛔ BEHAVIOURAL HALF OF `wiring_pending`. The TEXT question — "does every playable custom
## objective have an emitter?" — belongs to `test_custom_objectives_advance.gd`, which already
## models six emitter shapes, carries both a strict and a permissive predicate, and (since
## 2026-10-14) derives its scope from this same key. This file asks only the question that one
## cannot: **does QuestSystem actually refuse to offer a withheld quest?**
##
## ⚠️ MEASURED 2026-10-14: three quests were acceptable-and-permanently-unfinishable from a PLACED
## giver — world4_the_watercolors (Shift Foreman Grix, Rivet Row, no prereq),
## world5_termination_condition (the Firewall Attendant, Node Prime, no prereq) and
## world4_form_exception_alpha (Dorrit, after the W4 chapter-2 cutscene). A `type: "custom"`
## objective advances ONLY through `notify_flag`, and there is no abandon, so the quest sits in the
## log and on the HUD tracker for the rest of the save.
##
## 🔑 `markerless` was NOT enough: it suppresses the "!" in `giver_business_kind` and leaves the
## OFFER intact, so the quest is still acceptable by walking up and pressing the button. And
## `wiring_pending` is its own field rather than 2026-07's convention of overwriting `prereq_flag`
## with a never-set `quest_wiring_*_ready` gate, because five of the ten withheld quests have a
## REAL prereq the convention would have to clobber and later restore from memory. The composition
## is what `test_a_withheld_quest_is_not_offered` proves: prereq satisfied, still not offered.

const QUEST_DIR := "res://data/quests"
## The control. Same SHAPE as world4_form_exception_alpha — unstarted, prereq-gated, giver placed —
## but wired, so it must still be offered. Without it, an arm that refuses EVERYTHING passes.
const WIRED_CONTROL := "w1_ironhaven_flame_speaks_wrong"

var _quests: Dictionary = {}
var _skips: Array = []
var _qs: Node
var _saved_flags: Dictionary = {}
var _saved_quests: Dictionary = {}
## Quest ids whose LIVE `wiring_pending` key this test temporarily removed. Restored in
## `after_each`, never inline: an abort below the removal would strand the autoload's loaded data
## with the key off, and every later test in the process would then see a withheld quest as open.
var _unkeyed: Array = []


func before_all() -> void:
	_qs = get_tree().root.get_node_or_null("QuestSystem")
	var d := DirAccess.open(QUEST_DIR)
	if d == null:
		_skips.append("%s is not listable" % QUEST_DIR)
		return
	for f in d.get_files():
		if not f.ends_with(".json"):
			continue                  ## not a quest file; not a skip of the population
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [QUEST_DIR, f]))
		if not (parsed is Dictionary):
			_skips.append("%s did not parse as a Dictionary" % f)
			continue
		var qid: String = str((parsed as Dictionary).get("id", ""))
		if qid == "":
			_skips.append("%s has no id" % f)
			continue
		_quests[qid] = parsed


func before_each() -> void:
	_saved_flags = GameState.story_flags.duplicate(true)
	_saved_quests = GameState.quests.duplicate(true)
	GameState.quests.clear()


func after_each() -> void:
	for qid in _unkeyed:
		var live: Dictionary = _qs.get_quest(str(qid)) if _qs != null else {}
		if not live.is_empty():
			live["wiring_pending"] = true
	_unkeyed.clear()
	GameState.story_flags = _saved_flags
	GameState.quests = _saved_quests


func _withheld_ids() -> Array:
	var out: Array = []
	for qid in _quests:
		if bool((_quests[qid] as Dictionary).get("wiring_pending", false)):
			out.append(qid)
	out.sort()
	return out


## The corpus control, with a DERIVED denominator — a round number is a guess that the population
## will not shrink. Every skip is recorded WITH ITS REASON and asserted empty, because a count
## cannot tell you a file dropped out of it.
func test_the_quest_corpus_is_whole() -> void:
	assert_eq(_skips, [], "quest files were dropped silently: %s" % [_skips])
	assert_gt(_quests.size(), 25, "VOID: the quest corpus did not load, so nothing below holds")
	var withheld: Array = _withheld_ids()
	assert_gt(withheld.size(), 0, "VOID: no quest carries wiring_pending, so every arm below examines nobody")
	gut.p("  %d quests · %d withheld: %s" % [_quests.size(), withheld.size(), withheld])


## ⛔ THE DEFECT ARM. Talk, accept, stuck — this is what must not be reachable.
func test_a_withheld_quest_is_not_offered() -> void:
	assert_not_null(_qs, "QuestSystem autoload must be present")
	if _qs == null:
		return
	## Only a giver who owns exactly ONE quest can prove anything about the "!" marker: with two,
	## `giver_business_kind` can honestly answer "offer" about the other one.
	var giver_counts: Dictionary = {}
	for qid in _quests:
		var g: String = str((_quests[qid] as Dictionary).get("giver", {}).get("npc_id", ""))
		if g != "":
			giver_counts[g] = int(giver_counts.get(g, 0)) + 1

	var checked: int = 0
	var sole_giver_checked: int = 0
	var offerable: Array = []
	var markered: Array = []
	var would_not_open: Array = []
	for qid in _withheld_ids():
		checked += 1
		var q: Dictionary = _quests[qid]
		## Satisfy the real prereq FIRST. Five of these are prereq-gated, and a quest that is
		## unofferable because its prereq is unmet proves nothing about `wiring_pending`.
		var prereq: String = str(q.get("prereq_flag", ""))
		if prereq != "":
			GameState.set_story_flag(prereq, true)
		assert_true(_qs.is_wiring_pending(qid), "%s must report as wiring_pending" % qid)
		if _qs.is_offerable(qid):
			offerable.append(qid)
		## ⛔ THE KEY MUST BE THE ONLY THING WITHHOLDING IT. Without this, a quest that is
		## unofferable for some OTHER reason — an unmet prereq, a state left by an earlier test —
		## passes the arm above and proves nothing. `get_quest` returns QuestSystem's own loaded
		## Dictionary by reference, so removing the key here asks the real gate the real question.
		var live: Dictionary = _qs.get_quest(qid)
		if not live.is_empty():
			live.erase("wiring_pending")
			_unkeyed.append(qid)
			if not _qs.is_offerable(qid):
				would_not_open.append(qid)
			live["wiring_pending"] = true
			_unkeyed.erase(qid)
		var giver: String = str(q.get("giver", {}).get("npc_id", ""))
		if giver != "" and int(giver_counts.get(giver, 0)) == 1:
			sole_giver_checked += 1
			if str(_qs.giver_business_kind(giver)) == "offer":
				markered.append("%s (%s)" % [qid, giver])

	assert_gt(checked, 0, "VOID: no withheld quest to check")
	assert_gt(sole_giver_checked, 0, "VOID: no withheld quest has a sole giver, so the marker half "
		+ "of this arm examined nobody and only the offerability half above is load-bearing")
	assert_eq(offerable, [], "a withheld quest was OFFERABLE even with its prereq satisfied — the "
		+ "player can accept it and it can never advance: %s" % [offerable])
	assert_eq(markered, [], "a withheld quest still paints a '!' over its giver, which is the "
		+ "invitation to accept it: %s" % [markered])
	assert_eq(would_not_open, [], "with the key removed these are STILL unofferable, so the arm "
		+ "above was passing for another reason and the key was never what withheld them — satisfy "
		+ "the real prereq or fix the fixture: %s" % [would_not_open])
	gut.p("  %d withheld · 0 offerable · all %d open with the key removed · %d sole-giver markers, 0 painted" % [
		checked, checked, sole_giver_checked])


## ⛔ THE CONTROL, and it is not optional: an `is_offerable` that returned false for everything
## would pass the arm above. This one also watches the prereq gate itself work in both directions,
## so a mutation that disables prereq checking cannot hide inside a one-way assertion.
func test_a_wired_prereq_gated_quest_is_still_offered() -> void:
	assert_not_null(_qs, "QuestSystem autoload must be present")
	if _qs == null:
		return
	var q: Dictionary = _quests.get(WIRED_CONTROL, {})
	assert_false(q.is_empty(), "%s must load — the control needs a real wired quest" % WIRED_CONTROL)
	if q.is_empty():
		return
	assert_false(_qs.is_wiring_pending(WIRED_CONTROL),
		"CONTROL: %s must NOT be withheld, or it tests the same thing as the arm above" % WIRED_CONTROL)
	var prereq: String = str(q.get("prereq_flag", ""))
	assert_ne(prereq, "", "CONTROL: %s must be prereq-gated, or it tests a different shape" % WIRED_CONTROL)

	GameState.set_story_flag(prereq, false)
	assert_false(_qs.is_offerable(WIRED_CONTROL), "CONTROL: an unmet prereq must withhold the offer")
	GameState.set_story_flag(prereq, true)
	assert_true(_qs.is_offerable(WIRED_CONTROL), "a wired quest must be offerable once its prereq is set")
	assert_eq(str(_qs.giver_business_kind(str(q.get("giver", {}).get("npc_id", "")))), "offer",
		"a wired, offerable quest must paint the '!' over its giver")


## A withheld giver must have NO business at all — not an in-voice refusal for a gate that does not
## exist in the data. `_giver_quest_for` returns a prereq-locked quest as a `locked_fallback` when
## it has authored `locked` dialogue, and that path would otherwise resurrect a withheld quest.
func test_a_withheld_quest_is_not_even_a_locked_refusal() -> void:
	assert_not_null(_qs, "QuestSystem autoload must be present")
	if _qs == null:
		return
	var checked: int = 0
	var resurrected: Array = []
	for qid in _withheld_ids():
		var q: Dictionary = _quests[qid]
		var giver: String = str(q.get("giver", {}).get("npc_id", ""))
		if giver == "" or not (q.get("dialogue", {}) as Dictionary).has("locked"):
			continue
		checked += 1
		if str(_qs._giver_quest_for(giver)) == qid:
			resurrected.append("%s (%s)" % [qid, giver])
	gut.p("  %d withheld quests carry authored 'locked' dialogue" % checked)
	assert_eq(resurrected, [], "a withheld quest came back through the locked-refusal fallback: %s" % [resurrected])
