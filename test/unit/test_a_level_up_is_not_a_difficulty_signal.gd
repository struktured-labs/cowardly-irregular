extends GutTest

## The rebalance daemon (opt-in, on in struktured's settings) sent the model a bare trigger NAME under a header calling
## it "a high-signal event", so the model invented what each event implied. His saves hold the result: XP x1.05
## APPLIED for entering Eldertree Hollow (save_00/02/98/99) and Sandrift (save_50), and for the Fighter reaching level 5
## (save_01: "After a string of level-ups ... a slight boost to XP gain"), each at exactly the 0.7 auto-apply threshold.
## A curator was making the game more generous because he walked into a village, or got stronger.
##
## MEASURED against live llama3 (12 replies per cell, his own contexts, 2026-10-31):
##   level_up      old 12/12 nudge_easier (7 would auto-apply)   new 12/12 no_change
##   area_entered  old 12/12 nudge_easier (9 would auto-apply)   new 12/12 no_change
##   party_wipe    old 12/12 nudge_easier                        new 12/12 nudge_easier   <- the real signal still lands
## The prompt now states what each trigger MEANS. These arms pin that the meaning reaches the model, for every trigger.

const DAEMON_PATH := "res://src/llm/RebalanceDaemon.gd"


func _daemon():
	return load(DAEMON_PATH).new()


## Every TRIGGER_* constant, derived, so a trigger added later reds here until it is given a meaning.
func _triggers() -> Array:
	var out: Array = []
	var cmap: Dictionary = load(DAEMON_PATH).get_script_constant_map()
	for key in cmap.keys():
		if str(key).begins_with("TRIGGER_") and str(key) != "TRIGGER_MEANINGS" and cmap[key] is String:
			out.append(str(cmap[key]))
	out.sort()
	return out


func test_every_trigger_has_a_meaning() -> void:
	var triggers: Array = _triggers()
	assert_gt(triggers.size(), 4, "FLOOR: derived only %s, so the derivation broke and every arm here is vacuous" % [triggers])
	var meanings: Dictionary = load(DAEMON_PATH).TRIGGER_MEANINGS
	for t in triggers:
		assert_true(str(meanings.get(t, "")).length() > 20,
			"trigger '%s' has no meaning, so the model will invent one, as it did for level_up" % t)


func test_the_meaning_reaches_the_prompt_for_every_trigger() -> void:
	var meanings: Dictionary = load(DAEMON_PATH).TRIGGER_MEANINGS
	for t in _triggers():
		var p: String = _daemon().build_prompt(t, {"map_id": "whispering_cave"}, [])
		assert_true(p.contains("WHAT THIS EVENT MEANS: " + str(meanings[t])), "the meaning of '%s' never reached the prompt" % t)


func test_progress_events_point_at_no_change() -> void:
	## THE DEFECT: a level-up or a new area is progress, and the model read it as a reason to be generous.
	var meanings: Dictionary = load(DAEMON_PATH).TRIGGER_MEANINGS
	for t in ["level_up", "area_entered"]:
		assert_string_contains(str(meanings[t]), "no_change", "'%s' must steer the model to no_change" % t)
	assert_string_contains(str(meanings["boss_defeat"]).to_lower(), "never", "a boss win must never read as a reason to make it easier")


func test_the_header_no_longer_primes_the_model_to_act() -> void:
	var p: String = _daemon().build_prompt("level_up", {"member": "Fighter", "new_level": 5}, [])
	assert_false(p.contains("high-signal event"), "the old header told the model every event was a signal to act on")
	assert_string_contains(p, "Most events need no change", "the header now sets the default the measurement showed it needs")


func test_control_a_wipe_still_reads_as_too_hard() -> void:
	## CONTROL: without it, the arms above pass on a prompt that talks the model out of EVERY nudge.
	var meanings: Dictionary = load(DAEMON_PATH).TRIGGER_MEANINGS
	assert_string_contains(str(meanings["party_wipe"]), "TOO HARD", "a wipe is the real signal and must still say so")
	assert_false(str(meanings["party_wipe"]).contains("no_change"), "and must not steer the model away from acting on it")


func test_an_unknown_trigger_degrades_without_a_meaning_line() -> void:
	var p: String = _daemon().build_prompt("not_a_real_trigger", {}, [])
	assert_false(p.contains("WHAT THIS EVENT MEANS"), "an unknown trigger must not print an empty meaning line")
	assert_string_contains(p, "EVENT: not_a_real_trigger", "but the event itself is still named")
