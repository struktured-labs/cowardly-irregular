extends GutTest

## `AutobattleSystem` holds TWO condition evaluators and only one runs.
##
##   _evaluate_grid_condition  :267   match on STRING ids   24 arms   LIVE — 1 src call site
##   _evaluate_condition       :2172  match on ConditionType enum  11 arms
##   _evaluate_rule            :2154  its only caller               ⛔ ZERO callers, any route
##
## The enum one is a stale half-migration, not pending work: thirteen condition types have been
## added to the live evaluator and never mirrored, and `ConditionType` appears in no other file.
##
## ⚠️ THE HAZARD IS LIVE AND IT ALREADY HAPPENED TO ME. My burn/alias fix (691388cb09) put
## `Combatant.resolve_status_alias` in BOTH — five times on the path that runs and once at :2191,
## which cannot. Nothing broke, because the dead copy is dead. The next edit may not be so lucky:
## a NEW condition type authored into the enum evaluator silently never fires, and the grid editor
## would offer a row that can never be true — the `slow`/`burn` shape one layer up.
##
## Reported by cowir-ai, who declined to delete it on cowir-main's reaper principle:
## dead-by-measurement is not the same as safe-to-remove. This guard makes the deadness LOUD
## instead of making the deletion call.

const SRC := "res://src/autobattle/AutobattleSystem.gd"


func _src() -> String:
	return FileAccess.get_file_as_string(SRC)


func _live_arms() -> Array:
	var s: String = _src()
	var i: int = s.find("func _evaluate_grid_condition")
	var j: int = s.find("\nfunc ", i + 10)
	var out: Dictionary = {}
	for m in RegEx.create_from_string("(?m)^\\t\\t\"([a-z_]+)\"").search_all(s.substr(i, j - i)):
		out[m.get_string(1)] = true
	var keys: Array = out.keys()
	keys.sort()
	return keys


func _dead_arms() -> Array:
	var s: String = _src()
	var i: int = s.find("func _evaluate_condition")
	var j: int = s.find("\nfunc ", i + 10)
	var out: Dictionary = {}
	for m in RegEx.create_from_string("ConditionType\\.([A-Z_]+)").search_all(s.substr(i, j - i)):
		out[m.get_string(1).to_lower()] = true
	var keys: Array = out.keys()
	keys.sort()
	return keys


func test_the_scan_sees_both_evaluators() -> void:
	## Without this every arm below passes whenever a regex breaks, which is how a guard about
	## dead code becomes dead itself.
	var live: Array = _live_arms()
	var dead: Array = _dead_arms()
	gut.p("    live=%d  dead=%d" % [live.size(), dead.size()])
	assert_gt(live.size(), 15, "CONTROL: the live evaluator's string arms must be findable")
	assert_gt(dead.size(), 5, "CONTROL: the enum evaluator's arms must be findable")
	assert_true(live.has("has_status"), "CONTROL: a known live arm is in the live set")


func test_the_enum_evaluator_has_no_callers() -> void:
	## Checked by every route it could be reached by, with the live evaluator as the control —
	## a pattern that finds nothing proves nothing until you have watched it find something.
	var s: String = _src()
	assert_eq(s.count("_evaluate_rule("), 1,
		"_evaluate_rule has gained a caller — it was its own only occurrence (the definition)")
	assert_eq(s.count("\"_evaluate_rule\""), 0, "nor a reflective one")
	assert_eq(s.count("callv(\"_evaluate_rule"), 0, "nor a callv")
	assert_gt(s.count("_evaluate_grid_condition("), 1,
		"CONTROL: the LIVE evaluator has a definition AND a caller, so this instrument can see one")


func test_no_condition_type_exists_only_in_the_dead_one() -> void:
	## THE RATCHET. An arm added to the enum evaluator and not the string one is a condition the
	## engine can never evaluate — and it would look completely correct in review.
	var live: Array = _live_arms()
	var orphans: Array[String] = []
	for arm in _dead_arms():
		if not live.has(arm):
			orphans.append(arm)
	for o in orphans:
		gut.p("    ORPHAN: %s is in the enum evaluator and not the live one" % o)
	assert_eq(orphans.size(), 0,
		"a condition type lives only in the UNREACHABLE evaluator, so it can never fire: " + str(orphans))


func test_the_live_evaluator_is_the_bigger_one() -> void:
	## The direction of the drift, pinned. Thirteen types exist only on the live path today; if that
	## ever inverts, somebody has been authoring into the dead one and this file's premise is stale.
	var live: Array = _live_arms()
	var dead: Array = _dead_arms()
	assert_gt(live.size(), dead.size(),
		"the UNREACHABLE evaluator now has more arms than the live one — the premise of this file has flipped")


func test_the_enum_serves_nothing_else() -> void:
	## If ConditionType gains a consumer outside this file, the enum evaluator may be being revived
	## and this guard should be re-scoped rather than trusted.
	var others: int = 0
	for f in ["res://src/autobattle/ScriptShareManager.gd", "res://src/llm/RuleComposer.gd",
			"res://src/ui/autobattle/AutobattleGridEditor.gd", "res://src/battle/BattleManager.gd"]:
		if FileAccess.get_file_as_string(f).contains("ConditionType"):
			others += 1
	assert_eq(others, 0,
		"ConditionType is referenced outside AutobattleSystem — the enum path may be reviving")
