extends GutTest

## With LLM dialogue on, the LLM chose to WRITE a line that had no clip, so party lines went silent; now it picks a voiced one.

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _run_async_body() -> String:
	var src: String = FileAccess.get_file_as_string(BATTLE_MANAGER)
	var idx: int = src.find("func _run_party_line_async")
	assert_gt(idx, -1, "_run_party_line_async must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx)


func test_labels_are_numbers_from_one() -> void:
	assert_eq(VoiceLines.choice_labels(3), ["1", "2", "3"] as Array[String])


func test_a_label_maps_back_to_its_entry_and_clip() -> void:
	var entries: Array = [{"index": 0, "line": "a", "tags": []}, {"index": 4, "line": "e", "tags": []}]
	assert_eq(VoiceLines.entry_for_choice(entries, "2")["index"], 4, "label 2 is the second ELIGIBLE entry, index 4")
	assert_true(VoiceLines.entry_for_choice(entries, "3").is_empty(), "an out-of-range label maps to nothing")
	assert_true(VoiceLines.entry_for_choice(entries, "x").is_empty())


func test_the_prompt_numbers_every_line_and_asks_for_a_number() -> void:
	var ctx := {"event_kind": "low_hp", "speaker_name": "Vex", "speaker_job_id": "rogue",
		"speaker_hp_pct": 20.0, "party": [], "enemies": []}
	var p: String = DialoguePrompts.build_party_line_choice("A wry thief.", [], ctx, ["First line.", "Second line."])
	assert_true(p.contains("1. First line."))
	assert_true(p.contains("2. Second line."))
	assert_true(p.contains("Reply with only the number"), "the reply must be a number, which choose() can read exactly")


func test_the_context_is_built_before_the_line_is_picked() -> void:
	var body := _run_async_body()
	var ctx_at: int = body.find("_build_party_line_context(")
	var pick_at: int = body.find("pick_trigger_voice(")
	assert_gt(ctx_at, -1)
	assert_gt(pick_at, -1)
	assert_lt(ctx_at, pick_at, "eligibility needs the context on EVERY branch, including LLM off, so it is built first")
	assert_true(body.contains("pick_trigger_voice(job_id, event_kind, ctx)"), "the pick must be given the context")


func test_a_pc_who_dies_during_the_choose_await_says_nothing() -> void:
	## test_party_line_skipped_when_pc_dies_during_await pins "if not combatant.is_alive:" ANYWHERE in
	## the body, so the older await's guard satisfies it; this pins the guard on the choose await itself.
	var body := _run_async_body()
	var await_at: int = body.find("await llm.choose(")
	assert_gt(await_at, -1, "the choose branch must await the LLM")
	var emit_at: int = body.find("_emit_party_line(", await_at)
	assert_gt(emit_at, -1)
	var between: String = body.substr(await_at, emit_at - await_at)
	assert_true(between.contains("not combatant.is_alive"),
		"a PC killed while the LLM was choosing must not speak afterwards")
	assert_lt(between.find("is_instance_valid(combatant)"), between.find("combatant.is_alive"),
		"validity must be checked before is_alive, or a freed combatant crashes the property read")


func test_the_llm_branch_chooses_among_eligible_lines_and_voices_the_choice() -> void:
	var body := _run_async_body()
	assert_true(body.contains("eligible_trigger_entries(job_id, event_kind, ctx)"))
	assert_true(body.contains("llm.choose("), "the LLM must choose among authored lines")
	assert_true(body.contains("VoiceLines.variant_key(event_kind, int(chosen[\"index\"]))"),
		"the chosen line must be emitted WITH its clip key")
