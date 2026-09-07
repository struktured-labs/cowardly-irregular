extends GutTest

## Cadence #19 — HeadlessBattleResolver.resolve_battle used to exhaust
## MAX_ROUNDS=50 silently, returning _build_results(false) with no log
## entry and no diagnostic. A rule against an unkillable enemy (healing
## boss, resistant to the party's only damage type, party under-leveled)
## would grind to a halt reporting defeats forever with no clue why.
##
## Now: the stalemate exit path logs, push_warns, and marks the result
## dict with termination_reason="stalemate" so callers can distinguish
## "party died fair and square" from "battle timed out".


func _get_resolve_body() -> String:
	var src: String = load("res://src/autogrind/HeadlessBattleResolver.gd").source_code
	var start: int = src.find("func resolve_battle")
	assert_true(start >= 0, "setup: resolve_battle must exist")
	var end: int = src.find("\nfunc ", start + 20)
	if end < 0:
		end = src.length()
	return src.substr(start, end - start)


func test_stalemate_exit_logs_reason() -> void:
	# The MAX_ROUNDS exit branch must call _log with a stalemate message.
	# Grep it out of the function body — the log call is the player-facing
	# breadcrumb in the returned "log" array.
	var body: String = _get_resolve_body()
	# The stalemate exit is the last few lines of resolve_battle.
	# Assertions on substring presence.
	assert_true(body.contains("Battle exhausted MAX_ROUNDS"),
		"MAX_ROUNDS exit path must call _log with an explanation — pre-cadence-#19 it exited silently, appearing indistinguishable from an actual party defeat in battle results")


func test_stalemate_exit_push_warns() -> void:
	# The stalemate exit must also push_warning so the editor warnings
	# panel + CI runs surface a grind productivity collapse.
	var body: String = _get_resolve_body()
	assert_true(body.contains("push_warning"),
		"MAX_ROUNDS exit path must push_warning so a stalemate registers in the editor warnings panel and CI logs — silent was the pre-cadence-#19 bug")
	assert_true(body.contains("undertuned") or body.contains("heal/regen loop") or body.contains("stalemated"),
		"the push_warning must name concrete failure modes (undertuned party / healing enemy) so the player can debug their rule set, not a generic 'battle failed'")


func test_stalemate_marker_in_results_dict() -> void:
	# Callers of resolve_battle read the returned dict — the termination_reason
	# field lets them distinguish stalemate from actual defeat. Source ratchet:
	# the stalemate exit passes "stalemate" through _build_results.
	var body: String = _get_resolve_body()
	assert_true(body.contains("_build_results(false, \"stalemate\")"),
		"MAX_ROUNDS exit must pass 'stalemate' as termination_reason to _build_results — else callers can't distinguish stalemate from party death (both return victory=false)")


func test_build_results_signature_added_termination_reason() -> void:
	# _build_results gained an optional termination_reason param. Existing
	# callers (immediate-defeat, real-defeat, victory) pass no arg → default
	# "" → normal termination. Only the stalemate exit passes "stalemate".
	var src: String = load("res://src/autogrind/HeadlessBattleResolver.gd").source_code
	assert_true(src.contains("func _build_results(victory: bool, termination_reason: String = \"\")"),
		"_build_results must gain an optional termination_reason param (cadence #19) so the stalemate exit can distinguish itself in the results dict")
	assert_true(src.contains("\"termination_reason\": termination_reason"),
		"_build_results must include termination_reason in the returned dict — else the param is inert")


func test_runtime_immediate_defeat_reports_empty_reason() -> void:
	# Sanity: the immediate-defeat exits (empty party, all-dead party) should
	# report termination_reason="" — cadence #19 only changed the MAX_ROUNDS
	# path. Constructing an empty-party defeat exercises the fastest early-return.
	var resolver = HeadlessBattleResolver.new()
	var results: Dictionary = resolver.resolve_battle([], [])
	assert_false(results.get("victory", true),
		"empty player party → immediate defeat (baseline contract preserved)")
	assert_eq(results.get("termination_reason", "missing"), "",
		"immediate defeat carries empty termination_reason — only stalemate exit sets it (cadence #19)")


func test_runtime_immediate_victory_reports_empty_reason() -> void:
	# Same for the "no enemies" immediate victory path.
	# We need a live-but-not-a-real-battle player so is_alive returns true.
	var member = Combatant.new()
	member.initialize({"name": "T", "max_hp": 100, "max_mp": 10, "attack": 10, "defense": 5, "magic": 5, "speed": 10})
	add_child_autofree(member)
	var resolver = HeadlessBattleResolver.new()
	var results: Dictionary = resolver.resolve_battle([member], [])
	assert_true(results.get("victory", false),
		"no-enemies → immediate victory (baseline contract preserved)")
	assert_eq(results.get("termination_reason", "missing"), "",
		"immediate victory carries empty termination_reason — only stalemate exit sets it (cadence #19)")
