extends GutTest

## Settings → Text Speed is labeled "Dialogue text display speed" and CutsceneDialogue
## honors slow/normal/fast/instant. BattleDialogue (boss intro, low-HP taunt, defeat
## line) kept a hardcoded 0.03s tick, so Instant still typed the Rat King's intro
## one character at a time and Slow was no slower than Normal.

var _saved_speed: String = "normal"


func before_each() -> void:
	if GameState and "text_speed" in GameState:
		_saved_speed = str(GameState.text_speed)


func after_each() -> void:
	if GameState and "text_speed" in GameState:
		GameState.text_speed = _saved_speed


func _box() -> BattleDialogue:
	var box := BattleDialogue.new()
	add_child_autofree(box)
	return box


func test_slow_and_fast_change_how_fast_a_boss_line_types() -> void:
	var box := _box()
	GameState.text_speed = "slow"
	box.show_boss_intro("Cave Rat King", ["Cave Rat King: Kneel, irregular."])
	assert_almost_eq(box._typing_speed, CutsceneDialogue.TYPING_SPEED_PRESETS["slow"], 0.001,
		"Slow must type a boss line at the same cadence as a cutscene line")
	assert_eq(box._text_label.text, "",
		"a Slow line starts empty and types; it must not already be the whole sentence")
	assert_true(box._is_typing, "a Slow boss line is still typing when it appears")

	GameState.text_speed = "fast"
	box.show_boss_intro("Cave Rat King", ["Cave Rat King: Kneel, irregular."])
	assert_almost_eq(box._typing_speed, CutsceneDialogue.TYPING_SPEED_PRESETS["fast"], 0.001,
		"Fast must type a boss line at the same cadence as a cutscene line")
	assert_eq(box._text_label.text, "")
	assert_true(box._is_typing)


func test_instant_text_speed_shows_the_whole_boss_line() -> void:
	var box := _box()
	GameState.text_speed = "instant"
	box.show_boss_intro("Cave Rat King", ["Cave Rat King: Kneel, irregular."])
	assert_eq(box._text_label.text, "Kneel, irregular.",
		"Instant must reveal the boss line immediately, the same bypass cutscenes use")
	assert_false(box._is_typing, "an Instant line is finished, not mid-typewriter")
	assert_true(box._typing_timer.is_stopped(),
		"Instant must not leave the typewriter timer running")
