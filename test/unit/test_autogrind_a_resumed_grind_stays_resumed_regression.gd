extends GutTest

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const ControllerScript := preload("res://src/autogrind/AutogrindController.gd")

## `_state_before_pause` carries TWO meanings and nothing separates them:
##   :559  pause_grind() while BATTLE_RUNNING  -> a deferred-pause REQUEST flag
##   :563  pause_grind() otherwise             -> a MEMORY of the pre-pause state
## and resume_grind() never clears it. So pausing while BETWEEN_BATTLES — an ordinary press
## during the inter-battle delay — leaves the field holding exactly the value on_battle_ended
## reads as "a pause was requested mid-battle". The player resumes, one more battle runs, and
## the grind pauses itself again with nothing asking it to.

var _ag_state: Dictionary
var _c: Node


func before_each() -> void:
	_ag_state = AutogrindState.snapshot_and_isolate()
	_c = ControllerScript.new()
	_c.headless_mode = true
	add_child_autofree(_c)


func after_each() -> void:
	AutogrindState.restore(_ag_state)


## Drive one ordinary victory through the real handler.
func _one_battle_ends() -> void:
	_c._state = _c.State.BATTLE_RUNNING
	_c.on_battle_ended(true, 0, {})


func test_a_pause_between_battles_then_resume_stays_resumed() -> void:
	_c._state = _c.State.BETWEEN_BATTLES
	_c.pause_grind()
	assert_eq(_c._state, _c.State.PAUSED, "CONTROL: pausing between battles must actually pause")

	_c.resume_grind()
	assert_false(_c.is_paused(), "CONTROL: resume must leave the grind running")

	_one_battle_ends()
	gut.p("    after one post-resume battle: state=%s" % _c.State.keys()[_c._state])
	assert_false(_c.is_paused(),
		"the grind paused itself one battle after the player resumed — nothing requested it. " +
		"pause_grind() between battles stores BETWEEN_BATTLES in _state_before_pause, resume " +
		"does not clear it, and on_battle_ended reads that value as a deferred pause request")


## The mechanism this must not break: a pause pressed MID-BATTLE is deliberately deferred.
func test_a_pause_requested_mid_battle_still_activates_after_it() -> void:
	_c._state = _c.State.BATTLE_RUNNING
	_c.pause_grind()
	assert_false(_c.is_paused(), "CONTROL: a mid-battle pause must not take effect immediately")

	_c.on_battle_ended(true, 0, {})
	assert_true(_c.is_paused(),
		"a pause requested during a battle must activate when that battle ends — this is the "
		+ "feature the bug above is a side effect of, and it must survive the fix")


## Without any pause at all, an ordinary battle must never pause the grind.
func test_an_untouched_grind_never_pauses_itself() -> void:
	_one_battle_ends()
	assert_false(_c.is_paused(), "CONTROL: a grind nobody paused must keep running")
	_one_battle_ends()
	assert_false(_c.is_paused(), "CONTROL: and still after a second battle")


## The meta-boss branch returns before the old check, so a request made during one sat until the
## NEXT ordinary battle — the pause landed a whole battle after the player pressed it.
func test_a_pause_requested_during_a_meta_boss_activates_when_that_battle_ends() -> void:
	_c._state = _c.State.BATTLE_RUNNING
	_c._current_battle_is_meta_boss = true
	_c._current_meta_boss_data = {"exp_reward": 0}
	_c.pause_grind()
	assert_false(_c.is_paused(), "CONTROL: still deferred while the boss fight runs")

	_c.on_battle_ended(true, 0, {})
	assert_true(_c.is_paused(),
		"a pause pressed during a meta-boss fight did not take effect when that fight ended — " +
		"the meta-boss branch returns early, so it waited for the next ordinary battle")


## A queued request must not outlive the session that received it.
func test_stopping_discards_a_queued_pause() -> void:
	_c._state = _c.State.BATTLE_RUNNING
	_c.pause_grind()
	assert_true(_c._pause_requested, "CONTROL: the request is queued")

	_c.stop_grind("test")
	assert_false(_c._pause_requested,
		"a queued pause survived stop_grind — the next session would pause itself after its first battle")
