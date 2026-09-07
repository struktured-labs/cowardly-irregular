extends GutTest

## Encounter feel regression — player must dead-stop the instant a random
## battle triggers. Source-pin tests because driving the real signal chain
## through Bash + scene-tree is overkill for these single-call invariants.

const GAME_LOOP_PATH := "res://src/GameLoop.gd"
const PLAYER_PATH := "res://src/exploration/OverworldPlayer.gd"
const TRANSITION_PATH := "res://src/transitions/BattleTransition.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


func test_battle_triggered_handler_pushes_input_lock() -> void:
	var text := _read(GAME_LOOP_PATH)
	var idx := text.find("func _on_exploration_battle_triggered")
	assert_gt(idx, -1, "_on_exploration_battle_triggered must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("InputLockManager.push_lock(\"encounter_transition\")"),
		"_on_exploration_battle_triggered must push an InputLockManager lock so the player dead-stops during the transition")


func test_player_physics_process_snaps_to_idle_when_locked() -> void:
	var text := _read(PLAYER_PATH)
	var idx := text.find("func _physics_process")
	assert_gt(idx, -1, "_physics_process must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("if not _can_move()"),
		"_physics_process must early-return when _can_move() is false")
	assert_true(body.contains("_anim_frame = 0"),
		"_physics_process must snap _anim_frame to 0 on lock so the encounter halt shows a still pose, not mid-stride")


func test_encounter_sound_fires_before_capture_and_flash() -> void:
	var text := _read(TRANSITION_PATH)
	var idx := text.find("func play_battle_transition")
	assert_gt(idx, -1, "play_battle_transition must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	var sound_idx := body.find("_play_encounter_sound(")
	var capture_idx := body.find("_capture_screen(")
	var flash_idx := body.find("_play_encounter_flash(")
	assert_gt(sound_idx, -1, "play_battle_transition must call _play_encounter_sound")
	assert_gt(capture_idx, -1, "play_battle_transition must call _capture_screen")
	assert_gt(flash_idx, -1, "play_battle_transition must call _play_encounter_flash")
	assert_lt(sound_idx, capture_idx,
		"_play_encounter_sound must run BEFORE _capture_screen so audio lands at the visual hit, not after the screenshot delay")
	assert_lt(sound_idx, flash_idx,
		"_play_encounter_sound must run BEFORE _play_encounter_flash so the encounter hits as one punch, not flash-then-late-sound")
