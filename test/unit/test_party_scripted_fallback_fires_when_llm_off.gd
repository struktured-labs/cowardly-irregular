extends GutTest

## tick 120 regression: when party_llm_dialogue_enabled is FALSE
## (the default toggle), the scripted trigger_voices fallback must
## still fire. Pre-fix, _maybe_fire_party_line short-circuited on
## the flag, so party dialogue went completely silent in vanilla
## play. CLAUDE.md design says scripted lines play even without LLM.

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _maybe_fire_body() -> String:
	var src := _read(BATTLE_MANAGER)
	var idx: int = src.find("func _maybe_fire_party_line")
	assert_gt(idx, -1, "_maybe_fire_party_line must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func _run_async_body() -> String:
	var src := _read(BATTLE_MANAGER)
	var idx: int = src.find("func _run_party_line_async")
	assert_gt(idx, -1, "_run_party_line_async must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_maybe_fire_no_longer_early_returns_on_llm_toggle() -> void:
	# Negative pin: the pre-fix early return on
	# party_llm_dialogue_enabled inside _maybe_fire_party_line must
	# be gone. The flag-check responsibility moved into
	# _run_party_line_async where it can chain to the scripted
	# fallback path.
	var body := _maybe_fire_body()
	# This is the specific block that USED to early-return.
	assert_false(body.contains("not gs.party_llm_dialogue_enabled:\n\t\treturn"),
		"_maybe_fire_party_line must NOT early-return on party_llm_dialogue_enabled — blocks scripted fallback")


func test_run_async_now_checks_llm_toggle() -> void:
	# Positive pin: the flag check moved into _run_party_line_async,
	# where it can fall through to the scripted fallback when off.
	var body := _run_async_body()
	assert_true(body.contains("var llm_dialogue_on: bool = gs != null and (\"party_llm_dialogue_enabled\" in gs) and gs.party_llm_dialogue_enabled"),
		"_run_party_line_async must check party_llm_dialogue_enabled to decide LLM-vs-scripted")
	assert_true(body.contains("if not llm_dialogue_on:"),
		"_run_party_line_async must branch on the flag")


func test_off_branch_emits_scripted_fallback() -> void:
	# When LLM toggle is OFF, the scripted fallback path must run.
	# Specifically: emit the fallback if non-empty, then return.
	var body := _run_async_body()
	var idx: int = body.find("if not llm_dialogue_on:")
	assert_gt(idx, -1, "off branch must exist")
	# Look forward ~150 chars for the emit + return.
	var window: String = body.substr(idx, 200)
	assert_true(window.contains("if not fallback.is_empty():"),
		"off branch must guard on fallback non-empty before emitting")
	assert_true(window.contains("_emit_party_line(combatant, fallback, event_kind)"),
		"off branch must emit the scripted fallback line")


func test_llm_off_branch_precedes_llm_availability_check() -> void:
	# Ordering: the flag-off branch must come BEFORE the LLM
	# availability check. Otherwise checking LLMService (which may
	# fail to bind in tests / on web) blocks the scripted path
	# for flag-off players unnecessarily.
	var body := _run_async_body()
	var flag_idx: int = body.find("if not llm_dialogue_on:")
	var llm_idx: int = body.find("if llm == null or not llm.has_method(\"is_available\")")
	assert_gt(flag_idx, -1, "flag check must exist")
	assert_gt(llm_idx, -1, "LLM availability check must exist")
	assert_lt(flag_idx, llm_idx,
		"flag-off branch must precede LLM availability check — toggling LLM off shouldn't depend on LLMService presence")


func test_cooldown_gate_unchanged_in_maybe_fire() -> void:
	# Don't regress the cooldown gate. That still belongs in
	# _maybe_fire_party_line — it gates BOTH LLM and scripted paths.
	var body := _maybe_fire_body()
	assert_true(body.contains("if event_kind != \"victory\" and current_round - last_round < PARTY_LINE_COOLDOWN_ROUNDS:"),
		"cooldown gate must remain in _maybe_fire_party_line — applies to BOTH LLM and scripted paths")


func test_combatant_and_party_membership_gates_preserved() -> void:
	# Don't regress the validity gates either — they apply regardless
	# of LLM toggle.
	var body := _maybe_fire_body()
	assert_true(body.contains("if combatant == null"),
		"combatant validity gate preserved")
	assert_true(body.contains("if not (combatant in player_party):"),
		"party-membership gate preserved")
	assert_true(body.contains("if not combatant.is_alive:"),
		"alive gate preserved")
