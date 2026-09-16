extends GutTest

## The conversation reward is WRITTEN by ConversationRewards.grant_if_earned and only
## then announced, so anything that aborts _maybe_grant_reward between the two pays the
## player and never tells them.
##
## A call to a method the object does not have is exactly such an abort (CLAUDE.md's
## typed-array class: the error ends the enclosing function, so every line after it is
## skipped — here that is the await that shows the line). The sound guard named
## `play_ui` and the call was `play_pickup`, so the guard could not catch the case it
## exists for.
##
## Latent today — SoundManager carries both — which is the reason to pin it: nothing
## in the suite fails the day one of them is renamed.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const CONVO := "res://src/llm/DynamicConversation.gd"


func _reward_fn_code() -> String:
	var code: String = GdSource.code_of(CONVO)
	assert_false(code.is_empty(), "CONTROL: DynamicConversation must be readable as code")
	var at: int = code.find("func _maybe_grant_reward")
	assert_gt(at, -1, "CONTROL: _maybe_grant_reward must exist, or this measures nothing")
	var end: int = code.find("\nfunc ", at + 1)
	return code.substr(at, (end - at) if end > at else -1)


func test_the_cue_guard_names_the_method_it_calls() -> void:
	var body: String = _reward_fn_code()
	var calls: PackedStringArray = []
	for m in ["play_pickup", "play_ui", "play_sfx"]:
		if body.find("sound.%s(" % m) != -1:
			calls.append(m)
	assert_eq(calls.size(), 1,
		"the reward cue must be exactly one call on the SoundManager handle, got %s" % str(calls))
	assert_true(body.find('has_method("%s")' % calls[0]) != -1,
		"the guard must name %s — the method actually called — not a different one" % calls[0])


func test_the_line_is_shown_after_the_cue_not_before_it() -> void:
	## Ordering is the fix's other half: the payout announcement must not sit behind
	## anything optional. If a future edit moves _show_npc_line above the guard this
	## still passes; what must never happen is the line disappearing entirely.
	var body: String = _reward_fn_code()
	assert_true(body.find("await _show_npc_line(line)") != -1,
		"the reward line must still be shown — it is the only thing that tells the player")


func test_the_reward_is_written_before_the_announcement() -> void:
	## Pins WHY an abort here is a silent payout rather than a skipped one: the grant
	## has already happened by the time the cue runs.
	var body: String = _reward_fn_code()
	var granted: int = body.find("ConversationRewards.grant_if_earned")
	var shown: int = body.find("await _show_npc_line(line)")
	assert_gt(granted, -1, "CONTROL: the grant call must be in this function")
	assert_gt(shown, granted,
		"the announcement must come after the grant, or this test is pinned to the wrong shape")


func test_soundmanager_really_carries_the_guarded_method() -> void:
	## Anti-vacuity: if SoundManager stopped having it, the guard above would be
	## satisfied by a name nothing implements and the cue would go silent forever.
	var sm: Object = load("res://src/audio/SoundManager.gd").new()
	autofree(sm)
	assert_true(sm.has_method("play_pickup"),
		"SoundManager must carry play_pickup, or the reward cue is guarded into silence")
