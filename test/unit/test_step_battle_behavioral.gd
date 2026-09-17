extends GutTest

## Behavioral coverage for CutsceneDirector._step_battle — the duel
## retry loop at the heart of the spotlight system. The silent-failure
## audit's CRITICAL finding (missing PC → infinite retry softlock) was
## source-pinned; this drives the real function through a stubbed
## GameLoop at /root (GameLoop is the main-scene root in game, NOT an
## autoload — so the path is free in headless GUT).

const STEP := {
	"type": "battle",
	"combatants": ["bard"],
	"enemies": ["bard_hostile_courtier"],
	"on_defeat": "retry",
}


class StubGameLoop extends Node:
	var results: Array = []
	var calls: int = 0

	func start_solo_battle(_job: String, _enemy: String, _opts: Dictionary = {}) -> String:
		calls += 1
		# process_frame await keeps this a real coroutine like production.
		await get_tree().process_frame
		if results.is_empty():
			return "defeat"
		return str(results.pop_front())


var _stub: StubGameLoop


func before_each() -> void:
	_stub = StubGameLoop.new()
	_stub.name = "GameLoop"
	get_tree().root.add_child(_stub)


func after_each() -> void:
	if is_instance_valid(_stub):
		get_tree().root.remove_child(_stub)
		_stub.free()


func _director() -> Node:
	# CutsceneDirector is instantiated by the game, not a project
	# autoload — build one directly; _step_battle only needs the tree
	# and the /root/GameLoop lookup (stubbed).
	var d: Node = load("res://src/cutscene/CutsceneDirector.gd").new()
	add_child_autofree(d)
	return d


func test_unavailable_skips_instead_of_retrying_forever() -> void:
	# THE softlock: pre-fix, "unavailable" was returned as "defeat" and
	# retried unboundedly. Now: exactly one attempt, loud skip, returns.
	_stub.results = ["unavailable"]
	await _director()._step_battle(STEP.duplicate(true))
	assert_eq(_stub.calls, 1,
		"an unrunnable duel must NOT retry — one attempt then skip")


func test_defeat_retries_until_victory() -> void:
	_stub.results = ["defeat", "defeat", "victory"]
	await _director()._step_battle(STEP.duplicate(true))
	assert_eq(_stub.calls, 3, "retry-on-defeat must relaunch until victory")


func test_fail_forward_stops_after_one_defeat() -> void:
	var step: Dictionary = STEP.duplicate(true)
	step["on_defeat"] = "fail_forward"
	_stub.results = ["defeat"]
	await _director()._step_battle(step)
	assert_eq(_stub.calls, 1, "fail_forward must not retry")


func test_victory_returns_immediately() -> void:
	_stub.results = ["victory"]
	await _director()._step_battle(STEP.duplicate(true))
	assert_eq(_stub.calls, 1)


func test_missing_data_never_calls_battle() -> void:
	await _director()._step_battle({"type": "battle", "combatants": [], "enemies": []})
	assert_eq(_stub.calls, 0, "empty step must warn and skip without battling")


func test_unrunnable_duel_aborts_the_whole_cutscene() -> void:
	# The quieter brick: a skipped duel used to still FINISH the
	# cutscene → completion flag set → spotlight never replays → PC
	# locked forever. Abort semantics: cutscene_finished still emits
	# (chains unblock) but reports aborted so the flag-writer skips
	# and remaining steps (incl. any set_flag) never run.
	_stub.results = ["unavailable"]
	var d: Node = _director()
	var finished: Array = [false]
	d.cutscene_finished.connect(func(_id): finished[0] = true)
	var data := {"steps": [
		{"type": "battle", "combatants": ["bard"], "enemies": ["bard_hostile_courtier"], "on_defeat": "retry"},
		{"type": "set_flag", "flag": "test_abort_should_not_set"},
	]}
	await d.play_cutscene_from_data("test_abort_cutscene", data)
	assert_true(finished[0], "aborted cutscene must STILL emit cutscene_finished (awaiters unblock)")
	assert_true(d.last_finished_was_aborted(), "the run must report itself aborted")
	assert_false(GameState.is_story_flag_set("test_abort_should_not_set"),
		"steps after the abort — including set_flag — must not run")
	GameState.story_flags.erase("test_abort_should_not_set")


func test_normal_run_reports_not_aborted() -> void:
	_stub.results = ["victory"]
	var d: Node = _director()
	var data := {"steps": [
		{"type": "battle", "combatants": ["bard"], "enemies": ["bard_hostile_courtier"], "on_defeat": "retry"},
	]}
	await d.play_cutscene_from_data("test_normal_cutscene", data)
	assert_false(d.last_finished_was_aborted())


## The duel hides the director's UI so the BattleScene (layer 0) is visible under
## it, then restores. Restoring the dialogue panel to a HARDCODED true re-opens a
## box the player already closed: every one of the five spotlight cutscenes runs a
## narration before its battle step, so at duel's end the panel came back holding
## the pre-fight line — over the victory screen, and over the retry sting that was
## added because that same gap "read as a glitch".
func _finished_narration_panel(d: Node) -> Node:
	var dlg: Node = d._get_or_create_dialogue()
	dlg.show_dialogue([{"speaker": "", "text": "The skeleton bowed.", "theme": "narrator", "portrait": "narrator"}])
	# Two accepts, exactly as the player gives them: finish the typewriter, then close.
	dlg._advance_dialogue()
	dlg._advance_dialogue()
	assert_false(dlg.visible, "precondition: a finished narration leaves the panel hidden")
	return dlg


func test_a_closed_dialogue_stays_closed_after_the_duel() -> void:
	_stub.results = ["victory"]
	var d: Node = _director()
	var dlg: Node = _finished_narration_panel(d)
	await d._step_battle(STEP.duplicate(true))
	assert_false(dlg.visible,
		"a dialogue the player already dismissed must not reappear when the duel ends")


func test_the_reappearing_panel_would_hold_the_pre_fight_line() -> void:
	# Why the above matters: _finish_dialogue clears the queue, not the label, so
	# the box that came back was showing the line from before the battle.
	var d: Node = _director()
	var dlg: Node = _finished_narration_panel(d)
	assert_eq(str(dlg._text_label.text), "The skeleton bowed.",
		"a finished panel retains its last line — making a spurious re-show a stale box, not a blank one")


func test_a_visible_dialogue_is_restored_after_the_duel() -> void:
	# The other half of the contract: the step restores what it found, so it must
	# still bring a genuinely-live panel back rather than hiding it for good.
	_stub.results = ["victory"]
	var d: Node = _director()
	var dlg: Node = d._get_or_create_dialogue()
	dlg.show_dialogue([{"speaker": "", "text": "Still talking.", "theme": "narrator", "portrait": "narrator"}])
	assert_true(dlg.visible, "precondition: an open panel is visible")
	await d._step_battle(STEP.duplicate(true))
	assert_true(dlg.visible,
		"a panel that was open when the duel started must be restored, not left hidden")


func test_the_panel_stays_closed_across_a_retry() -> void:
	# The defeat path restores, plays the sting, then hides again — so the second
	# lap must read the state it left, not the state the narration left.
	_stub.results = ["defeat", "victory"]
	var d: Node = _director()
	var dlg: Node = _finished_narration_panel(d)
	await d._step_battle(STEP.duplicate(true))
	assert_eq(_stub.calls, 2, "precondition: the duel was retried")
	assert_false(dlg.visible,
		"the retry sting must not play under a reopened dialogue box")
