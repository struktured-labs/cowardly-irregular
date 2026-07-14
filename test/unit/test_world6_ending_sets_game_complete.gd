extends GutTest

## tick 108 regression: world6_ending must set a durable
## `game_complete` flag + surface a celebratory toast on completion.
## Pre-fix, finishing the game's narrative closer dumped the player
## back into vertex_village with no acknowledgment that they'd just
## won. The completion flag also gives NG+ / replay UI a stable hook
## to branch on without re-deriving from cutscene-state soup.

const GAME_LOOP := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _play_story_cutscene_body() -> String:
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _play_story_cutscene")
	assert_gt(idx, -1, "_play_story_cutscene must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_world6_ending_branch_present_in_handler() -> void:
	# The cutscene_finished handler must have an explicit world6_ending
	# branch — without it, completion is anonymous and the player has
	# no acknowledgment.
	var body := _play_story_cutscene_body()
	assert_true(body.contains("if cutscene_id == \"world6_ending\":"),
		"world6_ending handler branch must exist in cutscene_finished lambda")


func test_game_complete_set_in_game_constants() -> void:
	# Durable flag in game_constants — survives save/load.
	var body := _play_story_cutscene_body()
	assert_true(body.contains("GameState.game_constants[\"game_complete\"] = true"),
		"world6_ending must set GameState.game_constants['game_complete'] = true")


func test_game_complete_mirrored_to_story_flags() -> void:
	# QuestLog + LLMContext read via get_story_flag, not raw
	# game_constants. The mirror keeps the two surfaces in sync —
	# same pattern as the chapter completion mirror higher up in the
	# same handler.
	var body := _play_story_cutscene_body()
	assert_true(body.contains("GameState.set_story_flag(\"game_complete\")"),
		"world6_ending must mirror game_complete into story_flags so QuestLog + LLMContext see it")


func test_completion_toast_present() -> void:
	var body := _play_story_cutscene_body()
	assert_true(body.contains("Toast.show_success"),
		"world6_ending must surface a Toast on completion")
	assert_true(body.contains("Calibration complete"),
		"world6_ending toast must mention 'Calibration complete' — matches the cutscene's title")
	assert_true(body.contains("thank you for playing"),
		"world6_ending toast must thank the player — acknowledgment, not just a flag flip")


func test_branch_guarded_after_existing_flag_machinery() -> void:
	# Ordering: world6_ending branch must come AFTER the standard
	# completion_flag machinery (game_constants set, story_flags
	# mirror, EventLog record). If it came before, the standard
	# machinery would still fire and the special branch is redundant
	# — but the ordering matters for the spotlight reconcile path
	# above, which is generic.
	# Tick 220: standard completion_flag set is now the helper call.
	var body := _play_story_cutscene_body()
	var standard_flag_set: int = body.find("_set_cutscene_flag_and_mirror(completion_flag)")
	var ending_branch: int = body.find("if cutscene_id == \"world6_ending\":")
	assert_gt(standard_flag_set, -1, "standard completion_flag helper call must exist")
	assert_gt(ending_branch, -1, "world6_ending branch must exist")
	assert_lt(standard_flag_set, ending_branch,
		"world6_ending branch must come AFTER the standard completion_flag helper call — keeps the special-case scoped to extras (game_complete + toast)")


func test_other_cutscenes_dont_trigger_game_complete() -> void:
	# Negative pin: the game_complete write must be inside the
	# world6_ending branch, not elsewhere. Any other path setting
	# game_complete would corrupt the completion semantics (e.g. a
	# stray earlier set during world1_prologue).
	var src := _read(GAME_LOOP)
	var count: int = 0
	var pos: int = 0
	while true:
		var p: int = src.find("game_constants[\"game_complete\"] = true", pos)
		if p == -1:
			break
		count += 1
		pos = p + 1
	assert_eq(count, 1,
		"game_complete write must appear EXACTLY ONCE in GameLoop.gd — only inside the world6_ending branch")
