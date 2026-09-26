extends GutTest

## An ambush plate sets EncounterSystem.forced_encounter_next_step and marks
## itself used in GameState. The fight is the next step, and that step has
## not happened yet when the player stops, opens the menu, or quits to title.
## Quit to Title leaves the autoload armed. Continue, Load from the title,
## game-over Continue, in-game Load, and quick-load all go through
## SaveSystem.load_game → _apply_save_data, which writes Repel and the step
## counter back from encounter_state and used to leave the armed plate alone.
## The first step of the loaded save was then a fight.
##
## Saving in that gap is possible (menu Save, F2, a dungeon crystal). The
## file still has no field for the plate — a real restart already walks away
## from a spent plate with no fight. Load matches the file: the used bit
## stays in GameState, and the one-step latch is cleared. Repel is unchanged.

var _repel: int = 0
var _steps: int = 0
var _forced: bool = false
var _enabled: bool = true


func before_each() -> void:
	if EncounterSystem == null:
		return
	_repel = int(EncounterSystem.repel_steps_remaining)
	_steps = int(EncounterSystem.steps_since_last_encounter)
	_forced = bool(EncounterSystem.forced_encounter_next_step)
	_enabled = bool(EncounterSystem.encounters_enabled)


func after_each() -> void:
	if EncounterSystem == null:
		return
	EncounterSystem.repel_steps_remaining = _repel
	EncounterSystem.steps_since_last_encounter = _steps
	EncounterSystem.forced_encounter_next_step = _forced
	EncounterSystem.encounters_enabled = _enabled


func test_the_latch_and_the_save_block_are_still_there() -> void:
	assert_not_null(EncounterSystem, "EncounterSystem autoload")
	assert_not_null(SaveSystem, "SaveSystem autoload")
	for name in ["check_for_encounter", "reset_for_new_game"]:
		assert_true(EncounterSystem.has_method(name), "EncounterSystem.%s()" % name)
	assert_true("forced_encounter_next_step" in EncounterSystem)
	assert_true(SaveSystem.has_method("_apply_save_data"))
	assert_true(SaveSystem.has_method("_create_save_data"))


func test_loading_another_save_does_not_fight_on_the_first_step() -> void:
	if not _have_autoloads():
		return
	EncounterSystem.encounters_enabled = true
	EncounterSystem.repel_steps_remaining = 0
	EncounterSystem.steps_since_last_encounter = 0
	EncounterSystem.forced_encounter_next_step = true
	assert_true(EncounterSystem.check_for_encounter(),
		"CONTROL: a sprung plate must force the next step, or this file is not holding the latch")
	assert_false(bool(EncounterSystem.forced_encounter_next_step),
		"CONTROL: the fight spends the latch")
	# Quit to Title, plate still armed, then a different save with no pending fight.
	EncounterSystem.forced_encounter_next_step = true
	EncounterSystem.repel_steps_remaining = 0
	EncounterSystem.steps_since_last_encounter = 40
	var grace: int = int(EncounterSystem.minimum_steps_between_encounters)
	assert_gt(grace, 0, "the post-load step needs a grace window so a pass is not a lucky roll")
	SaveSystem._apply_save_data({
		"encounter_state": {
			"repel_steps_remaining": 0,
			"steps_since_last_encounter": 0,
		},
	})
	assert_false(bool(EncounterSystem.forced_encounter_next_step),
		"loading another save kept a sprung plate from the visit you just left")
	assert_eq(int(EncounterSystem.repel_steps_remaining), 0)
	assert_eq(int(EncounterSystem.steps_since_last_encounter), 0)
	assert_false(EncounterSystem.check_for_encounter(),
		"the first step of the loaded save was a forced fight")


func test_a_save_taken_while_the_plate_is_armed_does_not_store_the_fight() -> void:
	if not _have_autoloads():
		return
	EncounterSystem.forced_encounter_next_step = true
	EncounterSystem.repel_steps_remaining = 18
	EncounterSystem.steps_since_last_encounter = 3
	var created: Dictionary = SaveSystem._create_save_data()
	assert_true(created.has("encounter_state") and created["encounter_state"] is Dictionary,
		"a save must still carry encounter_state")
	var block: Dictionary = created["encounter_state"]
	assert_false(block.has("forced_encounter_next_step"),
		"the pending fight is not a save field — storing it would change the format")
	assert_eq(int(block["repel_steps_remaining"]), 18)
	assert_eq(int(block["steps_since_last_encounter"]), 3)
	assert_true(bool(EncounterSystem.forced_encounter_next_step),
		"writing the save must leave the live latch armed — the next step of THIS visit is still the fight")
	SaveSystem._apply_save_data({"encounter_state": block})
	assert_false(bool(EncounterSystem.forced_encounter_next_step),
		"reloading the save taken on the sprung plate brought the fight back, but the file never had it")
	assert_eq(int(EncounterSystem.repel_steps_remaining), 18,
		"that reload must still restore the Repel that was saved")
	assert_eq(int(EncounterSystem.steps_since_last_encounter), 3,
		"that reload must still restore the step counter that was saved")


func test_a_save_with_no_encounter_block_still_drops_the_plate() -> void:
	if not _have_autoloads():
		return
	EncounterSystem.forced_encounter_next_step = true
	EncounterSystem.repel_steps_remaining = 9
	EncounterSystem.steps_since_last_encounter = 4
	SaveSystem._apply_save_data({})
	assert_false(bool(EncounterSystem.forced_encounter_next_step),
		"an older save with no encounter_state kept the sprung plate")
	assert_eq(int(EncounterSystem.repel_steps_remaining), 9,
		"a missing encounter_state must not wipe a Repel the file does not mention")
	assert_eq(int(EncounterSystem.steps_since_last_encounter), 4,
		"a missing encounter_state must not wipe the step counter")


func _have_autoloads() -> bool:
	if EncounterSystem == null or SaveSystem == null:
		pending("EncounterSystem and SaveSystem autoloads required")
		return false
	return true
