extends GutTest

## tick 121 regression: _run_party_line_async must check
## combatant.is_alive AFTER the LLM await. Pre-fix the post-await
## guard only checked is_instance_valid (memory safety), not is_alive
## (game-state validity). A PC that died during the multi-hundred-ms
## LLM call could still pipe up post-mortem with a chipper line —
## breaking immersion ("Mira: 'I'm fine!' [Mira is in dying pose]").

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _run_async_body() -> String:
	var src := _read(BATTLE_MANAGER)
	var idx: int = src.find("func _run_party_line_async")
	assert_gt(idx, -1, "_run_party_line_async must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_post_await_alive_guard_present() -> void:
	var body := _run_async_body()
	assert_true(body.contains("if not combatant.is_alive:"),
		"_run_party_line_async must check combatant.is_alive AFTER the LLM await — suppresses post-mortem lines")


func test_alive_guard_follows_is_instance_valid_guard() -> void:
	# Pin ordering: is_instance_valid first (memory safety — checks
	# the node hasn't been freed), THEN is_alive (game-state validity).
	# If is_alive ran first on a freed combatant, the property access
	# would crash with "Invalid call. Nonexistent function 'is_alive'
	# in base 'null instance'".
	var body := _run_async_body()
	var iv_idx: int = body.find("if not is_instance_valid(combatant):")
	var alive_idx: int = body.find("if not combatant.is_alive:")
	assert_gt(iv_idx, -1, "is_instance_valid guard must exist")
	assert_gt(alive_idx, -1, "is_alive guard must exist")
	assert_lt(iv_idx, alive_idx,
		"is_instance_valid guard must precede is_alive guard — alive on freed node would crash")


func test_alive_guard_follows_the_llm_await() -> void:
	# Pin: the is_alive check must come AFTER the `await llm.complete_json`.
	# If it ran before the await, a PC that was alive at request time
	# but died during the LLM call would still post the line —
	# defeating the purpose of the guard.
	var body := _run_async_body()
	var await_idx: int = body.find("var raw: Variant = await llm.complete_json(")
	var alive_idx: int = body.find("if not combatant.is_alive:")
	assert_gt(await_idx, -1, "LLM await must exist")
	assert_gt(alive_idx, -1, "is_alive guard must exist")
	assert_lt(await_idx, alive_idx,
		"is_alive guard must follow the LLM await — pre-await check wouldn't catch deaths during the await")


func test_alive_guard_precedes_emit() -> void:
	# Sanity: the guard must precede the _emit_party_line call so
	# the dead PC's line never reaches the battle log.
	var body := _run_async_body()
	var alive_idx: int = body.find("if not combatant.is_alive:")
	var emit_idx: int = body.find("_emit_party_line(combatant, line)")
	assert_gt(alive_idx, -1, "is_alive guard must exist")
	assert_gt(emit_idx, -1, "_emit_party_line call must exist")
	assert_lt(alive_idx, emit_idx,
		"is_alive guard must precede _emit_party_line — otherwise the dead-PC line still emits")


func test_scripted_fallback_path_not_guarded_for_off_branch() -> void:
	# Negative pin: the LLM-OFF fallback emit (from tick 120) must
	# NOT have the is_alive guard added there. _maybe_fire_party_line
	# already checked is_alive at the entry point, and the LLM-off
	# path doesn't await — so there's no chance for the PC to die
	# between entry-check and emit. Adding a redundant check there
	# would just be confusing.
	var body := _run_async_body()
	# Find the LLM-off branch (right after llm_dialogue_on check).
	var off_branch_idx: int = body.find("if not llm_dialogue_on:")
	var return_idx: int = body.find("return", off_branch_idx + 1)
	assert_gt(off_branch_idx, -1, "llm-off branch must exist")
	var off_block: String = body.substr(off_branch_idx, return_idx - off_branch_idx + 10)
	assert_false(off_block.contains("if not combatant.is_alive:"),
		"llm-off branch must NOT re-check is_alive — entry guard at maybe_fire already covered it, no await happens in between")
