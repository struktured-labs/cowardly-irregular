extends GutTest

## A gallery replay of world6_orrery put the four-way response menu up, uncancellable (B is
## swallowed by a story choice), and then threw the pick away — _set_choice_flag returns early
## under _replay. Every other world-changing step in that same scene guards _replay and drops
## itself (give_item, update_item, set_flag, battle); choice guarded only the WRITE, so the
## Theater stopped on a modal the replay could not use. The prompt is narration and still plays;
## the menu is the demand and no longer appears.
##
## Second half, latent: options with no text are dropped before the menu, but the deterministic
## answer (skip, dismiss, menu-script-unloadable) indexed the UNFILTERED array — so a skip could
## answer with an option the player was never shown. MEASURED 2026-09-16: one choice step existed
## across the cutscene corpus, 4 options, all texted — so that half defended a mechanism rather than
## a live scene AT THE TIME. ⚠️ That is a dated observation, not a current count: data/cutscenes is
## cowir-story's to add to, and the day an authored choice carries a blank option this half becomes
## live. No arm here depends on the number, and none should — a ratchet on "how many choices are
## authored" would red on content being written, which is the point of writing it
## (cowir-music's test: would a reader quote this as true TODAY?).
##
## HELD FOR STRUKTURED: whether a replay should ECHO the answer the player gave first time round
## (the four flags are persisted and read by nothing — separate finding). Only
## test_a_replayed_choice_does_not_park_the_scene assumes the step ends without more dialogue;
## an echo would red that one arm and no other.

const DirectorScript = preload("res://src/cutscene/CutsceneDirector.gd")
const FLAG_SHOWN := "test_replay_choice_shown"
const FLAG_UNSHOWN := "test_replay_choice_unshown"
const PROMPT := "Her voice doesn't expect an answer."

var _d: Node


func before_each() -> void:
	Input.action_release("ui_cancel")
	Input.action_release("ui_accept")
	_d = DirectorScript.new()
	add_child_autofree(_d)
	_d._skipping = false
	_d._replay = false
	_clear_flags()


func after_each() -> void:
	# Release any coroutine still parked on a menu so a freed Director never hosts a live await.
	if _d and is_instance_valid(_d) and _d._choice_menu != null:
		_d._trigger_skip()
		await _frames(4)
	if _d and is_instance_valid(_d):
		_d._active = false
	_clear_flags()


func _gs() -> Node:
	return get_tree().root.get_node_or_null("GameState")


func _clear_flags() -> void:
	var gs := _gs()
	if gs == null:
		return
	for f in [FLAG_SHOWN, FLAG_UNSHOWN]:
		gs.game_constants.erase("cutscene_flag_" + f)
		if gs.has_method("set_story_flag"):
			gs.set_story_flag(f, false)


func _flag_set(f: String) -> bool:
	var gs := _gs()
	return gs != null and gs.game_constants.get("cutscene_flag_" + f, false) == true


## Both options presentable — the shape every authored choice has today.
func _step(prompt: String = "") -> Dictionary:
	return {"type": "choice", "prompt": prompt, "options": [
		{"text": "I don't know.", "flag": FLAG_SHOWN},
		{"text": "...I'm sorry.", "flag": FLAG_UNSHOWN},
	]}


## First option has no text, so the menu can never offer it.
func _step_with_an_unshowable_first_option() -> Dictionary:
	return {"type": "choice", "prompt": "", "options": [
		{"text": "   ", "flag": FLAG_UNSHOWN},
		{"text": "I don't know.", "flag": FLAG_SHOWN},
	]}


## Starts the step unawaited; the one-slot array flips when it releases.
func _start(step: Dictionary) -> Array:
	var done := [false]
	var runner := func() -> void:
		await _d._execute_step(step)
		done[0] = true
	runner.call()
	return done


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## CanvasLayers the choice step parents its menu to (layer 96, above the Director's 95).
func _menu_layers() -> int:
	var n := 0
	for c in get_tree().root.get_children():
		if c is CanvasLayer and (c as CanvasLayer).layer == 96:
			n += 1
	return n


func test_a_replayed_choice_never_puts_the_menu_up() -> void:
	_d._replay = true
	var before := _menu_layers()
	var done := _start(_step())
	await _frames(3)
	assert_null(_d._choice_menu, "a replay must not demand an answer it is going to discard")
	assert_eq(_menu_layers(), before, "and must not leave a layer-96 canvas over the Theater")
	assert_false(_flag_set(FLAG_SHOWN), "no answer is recorded either")
	assert_false(_flag_set(FLAG_UNSHOWN))


func test_a_real_play_of_the_same_step_does_put_the_menu_up() -> void:
	# ARM+: a Director that dropped every choice would pass the arm above.
	var before := _menu_layers()
	var done := _start(_step())
	await _frames(3)
	assert_not_null(_d._choice_menu, "control: a real play presents the menu")
	assert_eq(_menu_layers(), before + 1, "control: the instrument can see a layer-96 canvas")
	assert_false(done[0], "control: a real play parks on the player's answer")


func test_a_replay_still_speaks_the_prompt() -> void:
	# The prompt is narration, not a world change — dropping the whole step would lose a line.
	_d._replay = true
	var done := _start(_step(PROMPT))
	await _frames(3)
	assert_not_null(_d._dialogue, "a replayed choice still shows its prompt")
	if _d._dialogue:
		assert_true(str(_d._dialogue._current_text).contains("expect an answer"),
			"the prompt text reaches the box: %s" % [_d._dialogue._current_text])
	assert_null(_d._choice_menu, "and stops there — no menu behind the prompt")
	assert_false(done[0], "control: the step is parked on the prompt, not finished")
	# One press only ends the typing — read the line out the way a player does, bounded.
	for i in 12:
		if done[0]:
			break
		if _d._dialogue and is_instance_valid(_d._dialogue):
			_d._dialogue._advance_dialogue()
		await _frames(2)
	assert_true(done[0], "the prompt releases the step once it is read")
	assert_null(_d._choice_menu, "and no menu comes up behind it")


func test_a_replayed_choice_does_not_park_the_scene() -> void:
	# HELD-DECISION ARM: this is the only arm that requires the step to END after the prompt.
	_d._replay = true
	var done := _start(_step())
	await _frames(3)
	assert_true(done[0], "a replayed choice releases the scene instead of waiting on input")


func test_a_skipped_choice_answers_an_option_that_was_shown() -> void:
	_d._skipping = true
	var done := _start(_step_with_an_unshowable_first_option())
	await _frames(3)
	assert_true(done[0], "control: the skip path resolves without a menu")
	assert_true(_flag_set(FLAG_SHOWN), "a skip answers with the first option the player WOULD have seen")
	assert_false(_flag_set(FLAG_UNSHOWN), "never with one the menu filtered out")


func test_a_skipped_choice_still_answers_option_one_when_every_option_is_shown() -> void:
	# ARM+: the fix must not renumber the ordinary case — this is what the existing skip guard pins.
	_d._skipping = true
	var done := _start(_step())
	await _frames(3)
	assert_true(done[0], "control: resolved")
	assert_true(_flag_set(FLAG_SHOWN), "option 1 still answers a skip when option 1 is showable")
	assert_false(_flag_set(FLAG_UNSHOWN))


func test_a_dismissed_choice_answers_an_option_that_was_shown() -> void:
	# The live cancel path: B is swallowed, so the hold-skip dismiss is how a choice in flight ends.
	var done := _start(_step_with_an_unshowable_first_option())
	await _frames(3)
	var menu: Node = _d._choice_menu
	assert_not_null(menu, "control: the menu is up")
	if menu == null:
		return
	assert_eq((menu._choices as Array).size(), 1, "control: the blank option never reached the menu")
	_d._trigger_skip()
	await _frames(5)
	assert_true(done[0], "the dismiss releases the step")
	assert_true(_flag_set(FLAG_SHOWN), "a dismissed menu falls back to the first option it SHOWED")
	assert_false(_flag_set(FLAG_UNSHOWN), "not to a filtered-out option the player never saw")
