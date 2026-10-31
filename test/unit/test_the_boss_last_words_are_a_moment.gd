extends GutTest

## struktured 2026-10-30, on the Prismatic Construct's concession: "that's amazing, we need to make that more
## present, I barely saw it." The gloat went to the battle log ONLY, and it arrived up to GLOAT_WAIT_SEC after
## end_battle, so it printed AFTER the rewards had already opened.
##
## Now it is a beat: the boss's line in a dialogue box between the killing blow and the victory screen, held for
## the async line (bounded), dismissed on a press, auto-dismissed under automation, suppressed at turbo / 4x+.
##
## TWO TRAPS LIVE IN GameLoop, which is why it waits on BattleScene rather than BattleScene deciding alone:
##   _wait_for_confirm_victory returned at 0.5s if VictoryResults did not exist yet, so a held overlay would have
##   SKIPPED a duel's victory screen; and it POLLS Input, so the press that dismissed the beat would also have
##   confirmed the rewards. Input here goes through Input.parse_input_event, the real path, for that reason.

const SceneScript := preload("res://src/battle/BattleScene.gd")
const DialogueScript := preload("res://src/ui/BattleDialogue.gd")
const GameLoopScript := preload("res://src/GameLoop.gd")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const LINE := "Pass — though you let a script sit the exam."


class ProbeScene extends "res://src/battle/BattleScene.gd":
	var results_at: int = -1
	var quip_at: int = -1
	func _show_victory_results() -> void:
		results_at = Time.get_ticks_msec()
	func _show_victory_quip() -> void:
		quip_at = Time.get_ticks_msec()


class HoldStub extends Node:
	var holding: bool = false
	func is_holding_for_boss_beat() -> bool:
		return holding


class ResultsStub extends Node:
	func is_complete() -> bool:
		return true
	func complete_now() -> void:
		pass


var _saved_speed: int = 0
var _saved_pending: bool = false
var _scene: Node = null
var _dialogue: Node = null
var _shown: int = 0
var _bm_guard = BattleStateGuard.new()


func before_each() -> void:
	_bm_guard.snapshot()
	_saved_speed = SceneScript._battle_speed_index
	_saved_pending = BattleManager.boss_gloat_pending
	SceneScript._battle_speed_index = 0
	BattleManager.boss_gloat_pending = false
	_shown = 0


func after_each() -> void:
	SceneScript._battle_speed_index = _saved_speed
	BattleManager.boss_gloat_pending = _saved_pending
	Input.action_release("ui_accept")
	AutobattleSystem.autobattle_enabled.erase("beat_probe_bot")
	InputLockManager.pop_all()
	_bm_guard.restore()


## A bare scene (its _ready stops before any battle) with a real BattleDialogue attached.
func _make_scene() -> Node:
	_scene = ProbeScene.new()
	add_child_autofree(_scene)
	_dialogue = DialogueScript.new()
	_scene.add_child(_dialogue)
	_scene._battle_dialogue = _dialogue
	_dialogue.dialogue_finished.connect(func() -> void: _shown += 1)
	return _scene


func _press_accept() -> void:
	var down := InputEventAction.new()
	down.action = "ui_accept"
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventAction.new()
	up.action = "ui_accept"
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _wait_until(cond: Callable, cap_ms: int) -> bool:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < cap_ms:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


# ── BattleScene: the beat comes before the rewards ───────────────────────────

func test_control_no_boss_no_beat_and_no_delay() -> void:
	## CONTROL: an ordinary win must show its results in the SAME call, exactly as before this change.
	var s: Node = _make_scene()
	s._finish_victory_after_boss_beat()
	assert_gt(s.results_at, -1, "a fight with no boss line must show its results immediately, not wait on a beat")
	assert_false(s.is_holding_for_boss_beat(), "and must never report a hold")
	assert_false(_dialogue.visible, "and must show no dialogue")


func test_a_fast_line_shows_once_before_the_results() -> void:
	## The scripted path: the line lands BEFORE battle_ended, so it is already buffered.
	var s: Node = _make_scene()
	BattleManager._emit_boss_gloat(LINE, true)
	s._finish_victory_after_boss_beat()
	assert_true(s.is_holding_for_boss_beat(), "the hold must be set synchronously, before GameLoop's first poll")
	assert_true(await _wait_until(func() -> bool: return _dialogue.visible, 1000), "the boss's line must appear as a beat")
	assert_string_contains(_dialogue._current_text, "script sit the exam", "the beat must carry the boss's own line")
	assert_eq(s.results_at, -1, "the rewards must NOT open while the boss is still speaking")
	await _press_accept()
	await _press_accept()
	assert_true(await _wait_until(func() -> bool: return s.results_at > -1, 2000), "a press must dismiss the beat and let the rewards open")
	assert_false(s.is_holding_for_boss_beat(), "the hold must clear once the beat is dismissed")
	await get_tree().process_frame
	assert_eq(_shown, 1, "the beat must show EXACTLY once")


func test_a_slow_line_still_comes_before_the_results() -> void:
	## The model path: the line arrives AFTER battle_ended. The results must wait for it, not race past it.
	var s: Node = _make_scene()
	BattleManager.boss_gloat_pending = true
	s._finish_victory_after_boss_beat()
	await get_tree().create_timer(0.4, true, false, true).timeout
	assert_eq(s.results_at, -1, "the rewards opened before a pending boss line had a chance to arrive")
	BattleManager._emit_boss_gloat(LINE, true)
	assert_true(await _wait_until(func() -> bool: return _dialogue.visible, 1000), "a late line must still get its beat")
	assert_eq(s.results_at, -1, "and still before the rewards")
	await _press_accept()
	await _press_accept()
	assert_true(await _wait_until(func() -> bool: return s.results_at > -1, 2000), "the rewards must follow the dismissed beat")
	assert_eq(_shown, 1, "exactly once")


func test_a_line_that_never_comes_does_not_hold_the_results() -> void:
	## BOUNDED: a pending flag with no line must release at GLOAT_WAIT_SEC + slack, never wedge the victory.
	var s: Node = _make_scene()
	BattleManager.boss_gloat_pending = true
	var t0: int = Time.get_ticks_msec()
	s._finish_victory_after_boss_beat()
	var bound_ms: int = int((BattleManager.GLOAT_WAIT_SEC + SceneScript.BOSS_BEAT_ARRIVAL_SLACK_SEC) * 1000.0)
	assert_true(await _wait_until(func() -> bool: return s.results_at > -1, bound_ms + 1500), "a line that never arrives must not hold the rewards forever")
	assert_gte(s.results_at - t0, bound_ms - 100, "and must have waited out the arrival window first")
	assert_false(_dialogue.visible, "with no line, no empty beat")


func test_the_beat_is_suppressed_at_4x_and_at_turbo() -> void:
	for mode in ["4x", "turbo"]:
		var s: Node = _make_scene()
		if mode == "4x":
			SceneScript._battle_speed_index = SceneScript.BATTLE_SPEED_LABELS.find("4x")
			assert_gt(SceneScript._battle_speed_index, -1, "the 4x rung must exist to be tested")
		else:
			s.turbo_mode = true
		BattleManager._emit_boss_gloat(LINE, true)
		s._finish_victory_after_boss_beat()
		assert_gt(s.results_at, -1, "%s: the rewards must open at once, as party quips are suppressed at this pace" % mode)
		assert_false(_dialogue.visible, "%s: no beat" % mode)
		SceneScript._battle_speed_index = 0


func test_automation_never_stalls_on_the_beat() -> void:
	var s: Node = _make_scene()
	var bot := Combatant.new()
	bot.combatant_name = "Beat Probe Bot"
	autofree(bot)
	var typed: Array[Combatant] = [bot]
	s.party_members.assign(typed)
	## Direct dict write: the setter fires a story-flag toast this test must not trip.
	AutobattleSystem.autobattle_enabled["beat_probe_bot"] = true
	BattleManager._emit_boss_gloat(LINE, true)
	var t0: int = Time.get_ticks_msec()
	s._finish_victory_after_boss_beat()
	assert_true(await _wait_until(func() -> bool: return _dialogue.visible, 1000), "automation still shows the beat")
	var cap_ms: int = int(SceneScript.BOSS_BEAT_AUTO_DISMISS_SEC * 1000.0)
	assert_true(await _wait_until(func() -> bool: return s.results_at > -1, cap_ms + 1500), "with nobody pressing, the beat must auto-dismiss")
	assert_lt(s.results_at - t0, cap_ms + 1500, "within the automation cap, not the 30s read cap")


func test_a_defeat_line_gets_its_beat_and_a_victory_line_does_not_leak_into_it() -> void:
	var s: Node = _make_scene()
	BattleManager._emit_boss_gloat(LINE, false)
	s._play_boss_beat(false)
	assert_true(await _wait_until(func() -> bool: return _dialogue.visible, 1000), "the wipe gloat gets the same beat")
	await _press_accept()
	await _press_accept()
	assert_true(await _wait_until(func() -> bool: return not s.is_holding_for_boss_beat(), 2000), "and releases on a press")
	var t: Node = _make_scene()
	BattleManager._emit_boss_gloat(LINE, true)
	t._play_boss_beat(false)
	assert_false(t.is_holding_for_boss_beat(), "a VICTORY line must never be staged as a defeat beat")


const AUTHORED_DEFEAT := ["Probe Boss: THEORY... REVISED.", "*It shatters into a small pile of dust.*"]


func _entry_is_beat() -> bool:
	## The last-words entry is the only one carrying a "blip" key; an authored scene's entries never do.
	if not _dialogue.visible or _dialogue._dialogue_queue.is_empty():
		return false
	var i: int = mini(_dialogue._current_index, _dialogue._dialogue_queue.size() - 1)
	return str(_dialogue._dialogue_queue[i].get("blip", "")) != ""


func test_last_words_come_before_the_authored_scene() -> void:
	## struktured 2026-10-31, after the capture showed the Construct "shatter into dust" and THEN speak: last words first.
	var s: Node = _make_scene()
	s._boss_dialogue_data = {"defeat": AUTHORED_DEFEAT.duplicate()}
	BattleManager._emit_boss_gloat(LINE, true)
	s._stage_defeat_scene(true)
	assert_false(_dialogue.visible, "with last words on the way, the authored scene must WAIT, not show at battle end")
	s._finish_victory_after_boss_beat()
	assert_true(await _wait_until(func() -> bool: return _dialogue.visible, 1000), "something must show")
	assert_true(_entry_is_beat(), "the FIRST box must be the boss's last words, not the authored scene")
	await _press_accept()
	await _press_accept()
	assert_true(await _wait_until(func() -> bool: return _dialogue.visible and not _entry_is_beat(), 2000),
		"the authored scene must follow the last words")
	assert_string_contains(_dialogue._current_text, "THEORY", "and it must be the authored defeat scene")
	assert_eq(s.results_at, -1, "the rewards must still wait while the authored scene plays")
	assert_true(s.is_holding_for_boss_beat(), "GameLoop must stay held across the authored scene too")
	for i in 6:
		if s.results_at > -1:
			break
		await _press_accept()
	assert_true(await _wait_until(func() -> bool: return s.results_at > -1, 2000), "the rewards come last")
	assert_false(s.is_holding_for_boss_beat(), "and the hold releases")


func test_control_with_no_line_coming_the_authored_scene_shows_at_once() -> void:
	## CONTROL: a fight with no gloat keeps the old behaviour, so the deferral cannot strand the scene.
	var s: Node = _make_scene()
	s._boss_dialogue_data = {"defeat": AUTHORED_DEFEAT.duplicate()}
	s._stage_defeat_scene(true)
	assert_true(_dialogue.visible, "with no last words coming, the authored scene must show at battle end, as before")
	assert_string_contains(_dialogue._current_text, "THEORY", "and it is the authored scene")
	assert_true(s._deferred_defeat_scene.is_empty(), "and nothing is held back")


func test_one_press_dismisses_a_fully_typed_line() -> void:
	## A player who lets the line finish typing presses ONCE. The other arms press twice (skip the typing, then advance),
	## so none of them could see a single press failing, and one capture run showed exactly that.
	var s: Node = _make_scene()
	BattleManager._emit_boss_gloat(LINE, true)
	s._finish_victory_after_boss_beat()
	assert_true(await _wait_until(func() -> bool: return _dialogue.visible, 1000), "the beat shows")
	assert_true(await _wait_until(func() -> bool: return not _dialogue._is_typing, 8000), "the line finishes typing on its own")
	await get_tree().process_frame
	await _press_accept()
	assert_true(await _wait_until(func() -> bool: return s.results_at > -1, 1500),
		"ONE press on a fully typed line must dismiss it and let the rewards open")


# ── GameLoop: the confirm flow waits for the beat, and one press does one job ─

func _game_loop_with(stub: Node) -> Node:
	var gl: Node = GameLoopScript.new()
	add_child_autofree(gl)
	add_child_autofree(stub)
	gl.current_scene = stub
	return gl


func test_the_hold_cap_outlasts_the_scenes_own_worst_case() -> void:
	## A RELATIONSHIP, not a number: the cap must exceed arrive + wait behind an authored line + read.
	var gl: Node = autofree(GameLoopScript.new())
	var worst: float = BattleManager.GLOAT_WAIT_SEC + SceneScript.BOSS_BEAT_ARRIVAL_SLACK_SEC + 2.0 * SceneScript.BOSS_BEAT_READ_CAP_SEC
	assert_gt(gl.boss_beat_hold_cap_sec(), worst, "GameLoop would give up on a beat the scene is still legitimately showing")


func test_a_stuck_hold_still_returns_at_the_bound() -> void:
	## cowir-main's condition 1: a beat that never clears must not wedge the victory flow.
	var stub := HoldStub.new()
	stub.holding = true
	var gl: Node = _game_loop_with(stub)
	var t0: int = Time.get_ticks_msec()
	await gl._await_boss_beat(0.4)
	var took: int = Time.get_ticks_msec() - t0
	assert_gte(took, 350, "the hold was not honoured at all")
	assert_lt(took, 2000, "a stuck hold did not return at its bound")


func test_a_win_reaches_its_screen_after_the_beat_and_one_press_does_one_job() -> void:
	## cowir-main's conditions 2 and 3 at the choke point both victory paths share (duel and ordinary).
	var stub := HoldStub.new()
	stub.holding = true
	var gl: Node = _game_loop_with(stub)
	var done := {"v": false}
	var waiter := func() -> void:
		await gl._wait_for_confirm_victory()
		done["v"] = true
	waiter.call()
	await get_tree().create_timer(0.9, true, false, true).timeout
	assert_false(done["v"], "SKIP: the confirm returned during the beat because VictoryResults did not exist yet")
	await _press_accept()   # the press that dismisses the beat
	stub.holding = false
	var results := ResultsStub.new()
	results.name = "VictoryResults"
	stub.add_child(results)
	await get_tree().create_timer(1.2, true, false, true).timeout
	assert_false(done["v"], "BLEED: the press that dismissed the beat also confirmed the rewards")
	await _press_accept()   # a second, deliberate press
	assert_true(await _wait_until(func() -> bool: return done["v"], 2000), "a fresh press must confirm the victory screen")
