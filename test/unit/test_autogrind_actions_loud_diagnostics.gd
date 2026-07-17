extends GutTest

## Cadence #18 — apply_autogrind_actions diagnostic quality:
## 1. flee_battle fallback path is tagged "shouldn't happen" (controller
##    filters it out at AutogrindController:166 before apply is called).
##    Reaching this branch = real code-path regression, must push_warning.
## 2. heal_party / restore_mp merged two distinct 0-count states into one
##    misleading log ("no potions available") — even when nobody needed
##    healing. Split so a player debugging their rules can tell
##    rule-design-mismatch from empty-inventory.


func _get_action_body() -> String:
	# Load apply_autogrind_actions body for source ratchets.
	var src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code
	var start: int = src.find("func apply_autogrind_actions")
	assert_true(start >= 0, "setup: apply_autogrind_actions must exist")
	var end: int = src.find("\nfunc ", start + 20)
	if end < 0:
		end = src.length()
	return src.substr(start, end - start)


func _isolate_case(body: String, case_key: String) -> String:
	# Pull a match-case block by its "case_key": marker up to the next "\t\t\t\"" at
	# the same indent. Good enough for our source-ratchet purpose — we don't need
	# perfect grammar, just the branch's text.
	var marker: String = "\"%s\":" % case_key
	var start: int = body.find(marker)
	if start < 0:
		return ""
	# The next case starts at the same indent as this one.
	var next_case: int = body.find("\n\t\t\t\"", start + marker.length())
	if next_case < 0:
		next_case = body.length()
	return body.substr(start, next_case - start)


func test_flee_battle_fallback_pushes_warning() -> void:
	# The fallback path used to `print` — cadence #18 promoted it to push_warning
	# because reaching this branch means AutogrindController's line-166 filter was
	# bypassed (a real regression). Source ratchet: the case body must contain
	# push_warning, not silent print alone.
	var body: String = _get_action_body()
	var flee_case: String = _isolate_case(body, "flee_battle")
	assert_true(flee_case.length() > 0, "setup: flee_battle case must exist")
	assert_true(flee_case.contains("push_warning"),
		"flee_battle fallback must push_warning — reaching this branch means the AutogrindController pre-filter regressed; silent print would hide the bug (cadence #18)")


func test_flee_battle_fallback_still_calls_stop() -> void:
	# The fallback also stops the grind so the action isn't silently ignored.
	# Cadence #18 hardened the diagnostic but must preserve the stop.
	var body: String = _get_action_body()
	var flee_case: String = _isolate_case(body, "flee_battle")
	assert_true(flee_case.contains("stop_autogrind"),
		"flee_battle fallback must still call stop_autogrind after warning — else a regression means the grind loops forever with a warning but no action")


func test_heal_party_distinguishes_eligibility_from_consumable() -> void:
	# Pre-fix, the 0-count branch merged "no members below 80% HP" (no-op by
	# design) with "no potions in inventory" (rule-design mismatch) into a
	# single misleading "no potions available" log. Source ratchet: the case
	# must reference eligible_count (or equivalent) to prove the branches
	# were separated.
	var body: String = _get_action_body()
	var heal_case: String = _isolate_case(body, "heal_party")
	assert_true(heal_case.length() > 0, "setup: heal_party case must exist")
	assert_true(heal_case.contains("eligible_count"),
		"heal_party must track how many members were eligible for healing so the 0-count log can distinguish 'no-one-needed' from 'no-potions' (cadence #18)")
	assert_true(heal_case.contains("no members needed healing") or heal_case.contains("no-op"),
		"heal_party must have a distinct log for the 'nobody needed healing' case — currently 'no members needed healing (all ≥80%% HP) — no-op'")
	assert_true(heal_case.contains("no potions in party inventory") or heal_case.contains("no potions in"),
		"heal_party must retain the 'no potions in inventory' log for the rule-design-mismatch case, distinct from the no-eligibility case")


func test_restore_mp_distinguishes_eligibility_from_consumable() -> void:
	# Same shape as heal_party — MP variant must also split the two states.
	var body: String = _get_action_body()
	var mp_case: String = _isolate_case(body, "restore_mp")
	assert_true(mp_case.length() > 0, "setup: restore_mp case must exist")
	assert_true(mp_case.contains("eligible_count"),
		"restore_mp must track eligibility count for the two-state distinction (cadence #18)")
	assert_true(mp_case.contains("no members needed MP") or mp_case.contains("no-op"),
		"restore_mp must have a distinct log for the 'no-one-needed' case")
	assert_true(mp_case.contains("no ethers in"),
		"restore_mp must retain the 'no ethers' log for the empty-inventory case")


func test_success_prints_unchanged_by_cadence_18() -> void:
	# Cadence #18 hardened only the FAILURE branches. The successful "used
	# potions on N members" / "used ethers on N members" prints must remain
	# so the grind log stays informative when things work.
	var body: String = _get_action_body()
	var heal_case: String = _isolate_case(body, "heal_party")
	var mp_case: String = _isolate_case(body, "restore_mp")
	assert_true(heal_case.contains("used potions on"),
		"heal_party success print must remain unchanged")
	assert_true(mp_case.contains("used ethers on"),
		"restore_mp success print must remain unchanged")


func test_runtime_flee_battle_fallback_stops_grind() -> void:
	# End-to-end: calling apply_autogrind_actions with a flee_battle action
	# (bypassing the controller filter as this branch expects) must stop
	# the grind, not silently no-op. Guards against a regression where
	# someone removes the stop call while keeping the warning.
	var system: Node = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(system)
	system._test_disable_persistence = true
	system.is_grinding = true

	system.apply_autogrind_actions([{"type": "flee_battle"}])
	assert_false(system.is_grinding,
		"flee_battle fallback must stop the grind, not silently no-op (cadence #18 hardening must not lose the stop_autogrind call)")
