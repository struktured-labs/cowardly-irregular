extends GutTest

## The ready pool's data: one line per speaker + trigger, persisted, dropped when its voice is recast, and never one that names anybody.

const PATH := "user://test_voice_pool_store/pool.json"


func after_each() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_put_take_empties_the_slot() -> void:
	var s := VoicePoolStore.new(PATH)
	s.put("bard", "turn_start", "Tempo up.", "bard.wav", 1)
	assert_true(s.has_line("bard", "turn_start"), "CONTROL: the line was stored")
	assert_eq(s.take("bard", "turn_start").get("line", ""), "Tempo up.")
	assert_false(s.has_line("bard", "turn_start"), "a taken line stayed in its slot, so it would play twice")
	assert_eq(s.take("bard", "turn_start"), {}, "an empty slot must answer {}")


func test_the_pool_survives_a_restart() -> void:
	var s := VoicePoolStore.new(PATH)
	s.put("mage", "victory", "As calculated.", "mage.wav", 2)
	assert_true(s.save(), "CONTROL: the pool saved")
	var again := VoicePoolStore.new(PATH)
	again.load_from_disk()
	assert_eq(again.peek("mage", "victory").get("line", ""), "As calculated.", "a new session started cold")
	assert_eq(int(again.peek("mage", "victory").get("rev", -1)), 2, "the reloaded slot lost the voice revision it was rendered in")


func test_a_recast_voice_drops_its_lines() -> void:
	var s := VoicePoolStore.new(PATH)
	s.put("bard", "turn_start", "Tempo up.", "bard.wav", 1)
	s.put("mage", "turn_start", "Hm.", "mage.wav", 1)
	var dropped := s.drop_stale({"bard": {"voice": "bard.wav", "rev": 2}, "mage": {"voice": "mage.wav", "rev": 1}})
	assert_eq(dropped, 1)
	assert_false(s.has_line("bard", "turn_start"), "a line rendered in the old bard voice survived the recast")
	assert_true(s.has_line("mage", "turn_start"), "CONTROL: an unchanged voice keeps its line")


func test_a_line_naming_anyone_is_caught() -> void:
	var names := ["cleric", "Mira", "Goblin King"]
	assert_true(VoicePoolStore.names_anyone("Cleric, heal me!", names), "a job id at the start was missed")
	assert_true(VoicePoolStore.names_anyone("Mira's got this.", names), "a member name before an apostrophe was missed")
	assert_true(VoicePoolStore.names_anyone("Not the goblin king again.", names), "a two-word enemy name was missed")
	assert_false(VoicePoolStore.names_anyone("Every image lies.", ["mage"]), "a name inside another word is not a name")
	assert_false(VoicePoolStore.names_anyone("Steady now.", names), "CONTROL: a line naming no one passes")
