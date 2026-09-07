extends GutTest

## status_cannot_act.ogg has been on disk and in the manifest with ZERO consumers — a
## shipped, silent asset. A combatant losing its turn to stun/sleep/fear/charm/cannot_act
## produced a log line and no sound at all.
##
## The cue is wired at the SINGLE action_executing hook and keyed on the "_skip" SUFFIX
## rather than on a list of statuses, so a seventh skip path is covered the day it lands.
## That convention is the thing that can silently rot: if a future skip path emits a type
## that does not end in "_skip", it goes quiet and nothing fails. Both halves are pinned.
##
## ⚠️ BOUND, stated rather than implied: the firing test calls _cue_if_turn_skipped directly,
## so dead code INSIDE it is caught. A mutation at the CALL SITE — `if false: _cue_if...` —
## leaves every assertion here green. Closing that needs a harness that drives a real battle
## turn end-to-end, which this file does not do.

const MGR := "res://src/battle/BattleManager.gd"
const SCENE := "res://src/battle/BattleScene.gd"


func _handler_body() -> String:
	var src := FileAccess.get_file_as_string(SCENE)
	var i := src.find("func _on_action_executing")
	assert_gt(i, -1, "_on_action_executing present")
	var nxt := src.find("\nfunc ", i + 1)
	return src.substr(i, (nxt - i) if nxt > -1 else -1)


func test_every_turn_skip_emission_ends_in_the_suffix_the_cue_keys_on() -> void:
	## THE COUPLING. The handler matches `_skip`; if an emission stops matching, the cue
	## silently stops firing for that path and no other test notices.
	var src := FileAccess.get_file_as_string(MGR)
	assert_ne(src, "", "BattleManager.gd readable")
	var rx := RegEx.new()
	rx.compile('action_executing\\.emit\\(combatant, \\{"type": "([a-z_]+)"')
	var found: Array[String] = []
	for m in rx.search_all(src):
		found.append(m.get_string(1))
	assert_gt(found.size(), 0, "the emit pattern still matches — a zero here is a dead regex, not a clean result")
	for t in found:
		assert_true(t.ends_with("_skip"),
			"turn-skip emission '%s' must end in _skip or the cannot-act cue goes silent for it" % t)


func test_all_six_known_skip_paths_are_still_present() -> void:
	## Guards the test above from going vacuous by attrition: if the ladder is refactored
	## down to one path the suffix check still passes while coverage quietly shrinks.
	var src := FileAccess.get_file_as_string(MGR)
	for t in ["stun_skip", "cannot_act_skip", "sleep_skip", "confuse_skip", "fear_skip", "charm_skip"]:
		assert_true(src.contains('"type": "%s"' % t), "skip path %s still emits" % t)


func test_the_cue_fires_for_skip_types_and_stays_silent_otherwise() -> void:
	## BEHAVIOURAL, not a grep. A source pin cannot tell live code from dead code —
	## wrapping the call in `if false and ...` leaves every pinned string intact and the
	## sound never plays. Calling the real method is what closes that.
	var scene = load("res://src/battle/BattleScene.gd").new()
	autofree(scene)
	assert_true(scene._cue_if_turn_skipped({"type": "stun_skip"}),
		"a stun_skip must fire the cannot-act cue")
	assert_true(scene._cue_if_turn_skipped({"type": "charm_skip"}),
		"and so must charm_skip — the suffix is the key, not a hardcoded status list")
	assert_false(scene._cue_if_turn_skipped({"type": "attack"}),
		"an ordinary attack must NOT fire it")
	assert_false(scene._cue_if_turn_skipped({}),
		"and neither must a typeless action")


func test_the_call_site_is_reached_before_the_animator_early_return() -> void:
	## _on_action_executing returns early for any combatant without an animator. Below that
	## guard the cue would fire for some combatants and not others, which is worse than silent.
	## SOURCE-level by necessity: this is about ORDER inside a function the unit test above
	## cannot execute end-to-end. Bound stated in the header.
	var body := _handler_body()
	var call := body.find("_cue_if_turn_skipped(action)")
	var guard := body.find("if not animator")
	assert_gt(call, -1, "the handler still calls the cue helper")
	assert_gt(guard, -1, "the animator early-return is still there")
	assert_lt(call, guard, "the cue must fire BEFORE the animator guard, not after it")


func test_the_cue_is_authored_so_the_gated_call_is_not_a_permanent_noop() -> void:
	## play_status_if_authored stays silent when the key is unauthored — correct behaviour,
	## and it would also hide this whole feature being dead. Pin that the asset exists.
	var raw := FileAccess.get_file_as_string("res://data/sfx_manifest.json")
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "manifest parses")
	var sfx: Dictionary = parsed.get("sfx", {})
	assert_true(sfx.has("status_cannot_act"), "status_cannot_act is authored in the manifest")
	var f: String = str(sfx["status_cannot_act"].get("file", ""))
	assert_ne(f, "", "and carries a file key")
	assert_true(FileAccess.file_exists("res://" + f), "and that file exists on disk: %s" % f)
