extends GutTest
## Two halves of one defect, found from opposite directions on the same lane.
##
## ⛔ AutogrindUI: ELEVEN "Cannot … while grinding" refusals PRINT a reason and play NOTHING, while
## the same file plays menu_error for the same class of refusal (_toggle_grinding and _request_resume
## when an interrupt rule would stop the run, and both share-code failures). Found by @cowir-sfx.
## ⛔ AutogrindGridEditor: three refusals PLAY menu_error and say NOTHING, while that file explains
## twenty other refusals through its status label. And the two caps it enforces -- MAX_ACTIONS and
## MAX_CONDITIONS -- appear in NO player-facing string anywhere in the game, so the number the player
## is up against is unreadable.
##
## Neither screen lacked a channel. Each had one those presses did not use.
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const UI := "res://src/ui/autogrind/AutogrindUI.gd"
const EDITOR := "res://src/ui/autogrind/AutogrindGridEditor.gd"

## method -> args, for every refusal gated on "while grinding"
const REFUSALS := [
	["_cycle_safety", ["hp"]], ["_toggle_ludicrous_speed", []], ["_apply_preset", ["balanced"]],
	["_toggle_auto_advance", []], ["_export_scripts", []], ["_paste_rules_share_code", []],
	["_import_scripts", []], ["_toggle_permadeath_staking", []], ["_save_current_as_preset", []],
	["_apply_custom_preset", [0]], ["_delete_last_custom_preset", []],
]

var _ag: Dictionary


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true


func after_each() -> void:
	AutogrindState.restore(_ag)


func _stamped(key: String) -> bool:
	return SoundManager._sfx_cooldowns.has(key)


func _clear_cues() -> void:
	SoundManager._sfx_cooldowns.clear()


## ⛔ THE ORACLE'S OWN CONTROL. Every arm below reads a cooldown stamp as "a cue was played". If
## play_ui leaves no stamp in this harness, each of them passes by measuring nothing -- so prove the
## instrument can see a cue BEFORE trusting eleven silences.
func test_the_cue_oracle_can_see_a_cue() -> void:
	_clear_cues()
	assert_false(_stamped("menu_error"), "FLOOR: the stamp table must start clean")
	SoundManager.play_ui("menu_error")
	assert_true(_stamped("menu_error"),
		"CONTROL: play_ui must leave an observable stamp, or every arm in this file measures nothing")


func test_every_while_grinding_refusal_is_audible() -> void:
	var ui: Node = load(UI).new()
	add_child_autofree(ui)
	ui._is_grinding = true
	var checked: int = 0
	for row in REFUSALS:
		var m: String = str(row[0])
		assert_true(ui.has_method(m), "FLOOR: %s must exist" % m)
		if not ui.has_method(m):
			continue
		_clear_cues()
		Callable(ui, m).callv(row[1] as Array)
		checked += 1
		assert_true(_stamped("menu_error"),
			"%s refused while grinding and played nothing -- the player gets a line in a log they " % m
			+ "may not be reading and no sound at all")
	assert_eq(checked, REFUSALS.size(), "FLOOR: every refusal must have been driven, not skipped")


## CONTROL: the cue is for the REFUSAL, not for the press. Not grinding, the same calls must not
## report a refusal sound -- otherwise the arm above would pass on a file that beeps unconditionally.
func test_the_same_actions_do_not_beep_when_not_grinding() -> void:
	var ui: Node = load(UI).new()
	add_child_autofree(ui)
	ui._is_grinding = false
	_clear_cues()
	ui._toggle_auto_advance()
	assert_false(_stamped("menu_error"),
		"CONTROL: toggling auto-advance when NOT grinding is a legal action and must not play the refusal cue")


func _editor() -> Node:
	var e: Node = load(EDITOR).new()
	e.size = Vector2(1280, 720)
	add_child_autofree(e)
	return e


func test_a_full_rule_says_the_cap_it_hit() -> void:
	var e := _editor()
	assert_true(e.has_method("_flash_status"), "FLOOR: the editor must have a way to say why")
	assert_true("MAX_ACTIONS" in e, "FLOOR: the cap must be readable to derive the message from")
	var cap: int = int(e.MAX_ACTIONS)
	assert_gt(cap, 0, "FLOOR: a zero cap would make the message meaningless")
	e._flash_status("This rule is full -- %d actions max." % cap)
	await wait_frames(1)
	assert_string_contains(str(e._status_label.text), str(cap),
		"the message must name the cap it enforces -- MAX_ACTIONS appears in no other player-facing string")


## The status label had ONE writer and no restore, so a refusal would have stuck until the editor
## rebuilt. The flash must put the default back.
func test_the_status_returns_to_its_default() -> void:
	var e := _editor()
	var before: String = str(e._status_label.text)
	assert_eq(before, e.STATUS_DEFAULT_TEXT, "FLOOR: the label starts at its default")
	e._flash_status("This rule is full -- 4 actions max.")
	await wait_frames(1)
	assert_ne(str(e._status_label.text), before, "FLOOR: the flash must actually change the label")
	await get_tree().create_timer(e.STATUS_FLASH_SECONDS + 0.2).timeout
	assert_eq(str(e._status_label.text), e.STATUS_DEFAULT_TEXT,
		"and it must return, or one refusal leaves its message on screen for the rest of the session")
