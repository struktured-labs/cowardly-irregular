extends GutTest

## A Repel ran out in silence; the step that spends its last charge now plays repel_wears_off, on both step paths, once.

const SfxState := preload("res://test/unit/helpers/sfx_state.gd")
const KEY := "repel_wears_off"

var _saved_steps: int = 0
var _saved_enabled: bool = true


func before_each() -> void:
	_saved_steps = EncounterSystem.repel_steps_remaining
	_saved_enabled = EncounterSystem.encounters_enabled
	EncounterSystem.repel_steps_remaining = 0
	EncounterSystem.encounters_enabled = true
	SoundManager._sfx_cooldowns.erase(KEY)
	SoundManager._ui_player.stream = null


func after_each() -> void:
	EncounterSystem.repel_steps_remaining = _saved_steps
	EncounterSystem.encounters_enabled = _saved_enabled
	SoundManager._sfx_cooldowns.erase(KEY)
	SoundManager._sfx_suppressed_by_cooldown = false
	SfxState.release_streams()
	SoundManager._ui_player.stream = null


func _file() -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}
	return str((sfx.get(KEY, {}) as Dictionary).get("file", ""))


## True when the UI voice holds the fizzle; the voice and the manifest cooldown are cleared so the next read is fresh.
func _heard() -> bool:
	var s: AudioStream = SoundManager._ui_player.stream
	SoundManager._ui_player.stream = null
	SoundManager._sfx_cooldowns.erase(KEY)
	return s != null and s.resource_path.ends_with(_file())


func test_the_cue_is_authored_and_loads_as_its_own_file() -> void:
	var f := _file()
	assert_ne(f, "", "repel_wears_off is not registered in sfx_manifest.json")
	assert_true(FileAccess.file_exists("res://" + f), "repel_wears_off names %s, which is not on disk" % f)
	var stream = load("res://" + f)
	assert_true(stream is AudioStream and (stream as AudioStream).get_length() > 0.3,
		"repel_wears_off does not load as a real stream (length %s)" % [
			(stream as AudioStream).get_length() if stream is AudioStream else -1.0])


func test_the_last_field_step_is_heard_and_only_the_last() -> void:
	EncounterSystem.use_repel(3)
	assert_eq(EncounterSystem.repel_steps_remaining, 3, "CONTROL: use_repel(3) did not arm three steps")
	var heard: Array = []
	for _i in range(3):
		assert_false(EncounterSystem.check_for_encounter(), "CONTROL: a repelled step started a fight")
		heard.append(_heard())
	assert_eq(EncounterSystem.repel_steps_remaining, 0, "CONTROL: three steps did not spend a three-step Repel")
	assert_eq(heard, [false, false, true], "the fizzle must play on the step that spends the last charge, and only that one")


func test_the_world_map_step_is_heard_when_it_spends_the_last_charge() -> void:
	EncounterSystem.use_repel(2)
	EncounterSystem.consume_repel_step()
	assert_false(_heard(), "a world-map step with a charge left played the fizzle early")
	EncounterSystem.consume_repel_step()
	assert_eq(EncounterSystem.repel_steps_remaining, 0, "CONTROL: two world-map steps did not spend a two-step Repel")
	assert_true(_heard(), "the world-map step that spent the last charge was silent")


func test_walking_with_no_repel_stays_quiet() -> void:
	for _i in range(5):
		EncounterSystem.consume_repel_step()
	assert_eq(EncounterSystem.repel_steps_remaining, 0, "CONTROL: stepping with no Repel moved the counter")
	assert_false(_heard(), "stepping with no Repel active played the fizzle")
