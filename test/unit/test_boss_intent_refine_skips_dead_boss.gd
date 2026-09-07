extends GutTest

## tick 123 regression: _refine_boss_intent_async must check
## combatant.is_alive AFTER the LLM await. Symmetric with tick 121's
## party-line fix. Pre-fix, a boss killed during the multi-hundred-ms
## LLM call would still emit a refined taunt — the boss talks while
## dying. The is_instance_valid guard only catches the freed-node
## case (battle scene tore down), not the alive-but-just-died case.

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _refine_async_body() -> String:
	var src := _read(BATTLE_MANAGER)
	var idx: int = src.find("func _refine_boss_intent_async")
	assert_gt(idx, -1, "_refine_boss_intent_async must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_refine_async_post_await_alive_guard_present() -> void:
	var body := _refine_async_body()
	assert_true(body.contains("if not combatant.is_alive:"),
		"_refine_boss_intent_async must check combatant.is_alive AFTER the LLM await — boss dying mid-await still talked otherwise")


func test_alive_guard_follows_is_instance_valid_guard() -> void:
	# Same ordering rule as tick 121: instance_valid first (memory
	# safety), then is_alive (game-state validity). Property access
	# on a freed instance would crash before the alive check ran.
	var body := _refine_async_body()
	var iv_idx: int = body.find("if not is_instance_valid(combatant):")
	# We need the alive check that comes AFTER the await. There's
	# also an entry-point is_instance_valid at the top. Anchor on
	# the comment to disambiguate to the post-await one.
	var post_await_iv: int = body.find("if not is_instance_valid(combatant):\n\t\treturn  # Boss died")
	var alive_idx: int = body.find("if not combatant.is_alive:")
	assert_gt(iv_idx, -1, "is_instance_valid guard must exist")
	assert_gt(post_await_iv, -1, "post-await is_instance_valid guard must exist (with the 'Boss died' comment)")
	assert_gt(alive_idx, -1, "is_alive guard must exist")
	assert_lt(post_await_iv, alive_idx,
		"post-await is_instance_valid must precede is_alive — property access on freed node would crash")


func test_alive_guard_follows_the_llm_await() -> void:
	var body := _refine_async_body()
	var await_idx: int = body.find("var refined: Dictionary = await boss_dlg.pick_intent_async(ctx)")
	var alive_idx: int = body.find("if not combatant.is_alive:")
	assert_gt(await_idx, -1, "LLM await must exist")
	assert_gt(alive_idx, -1, "is_alive guard must exist")
	assert_lt(await_idx, alive_idx,
		"is_alive guard must follow the LLM await — pre-await check wouldn't catch deaths during the await")


func test_alive_guard_precedes_taunt_emit() -> void:
	var body := _refine_async_body()
	var alive_idx: int = body.find("if not combatant.is_alive:")
	var emit_idx: int = body.find("boss_taunt.emit(combatant, refined_taunt)")
	assert_gt(alive_idx, -1, "is_alive guard must exist")
	assert_gt(emit_idx, -1, "boss_taunt emit must exist")
	assert_lt(alive_idx, emit_idx,
		"is_alive guard must precede the taunt emit — otherwise dead boss still talks")


func test_alive_guard_precedes_stale_phase_check() -> void:
	# Pin ordering: alive check comes BEFORE the stale-phase check.
	# If alive came after, we'd waste cycles on stale-phase math
	# only to discard the result anyway. Trivial perf + intent
	# clarity.
	var body := _refine_async_body()
	var alive_idx: int = body.find("if not combatant.is_alive:")
	var phase_idx: int = body.find("if current_phase > phase:")
	assert_gt(alive_idx, -1, "is_alive guard must exist")
	assert_gt(phase_idx, -1, "stale-phase guard must exist")
	assert_lt(alive_idx, phase_idx,
		"is_alive guard must precede stale-phase guard — discard dead-boss results before doing phase math")


func test_tick_121_party_line_guard_still_present() -> void:
	# Don't regress tick 121's party-line is_alive guard while
	# adding the boss-side one — both should coexist.
	var src := _read(BATTLE_MANAGER)
	var run_async_idx: int = src.find("func _run_party_line_async")
	assert_gt(run_async_idx, -1, "_run_party_line_async must exist")
	var next_fn: int = src.find("\nfunc ", run_async_idx + 1)
	var run_body: String = src.substr(run_async_idx, next_fn - run_async_idx) if next_fn > -1 else src.substr(run_async_idx)
	assert_true(run_body.contains("if not combatant.is_alive:"),
		"tick 121's _run_party_line_async is_alive guard must still be present — symmetric coverage")
