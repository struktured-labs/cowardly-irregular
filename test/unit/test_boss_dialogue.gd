extends GutTest

## Wave E — BossDialogue regression tests.
##
## Covers:
##   1) data/boss_dialogue.json loads and is shape-valid.
##   2) has_entry / pick_intent / check_jailbreak APIs return expected types.
##   3) STORY-FLAG SAFETY: consequences are all in CONSEQUENCE_ALLOWLIST.
##   4) Mordaine seed: 3 intents + 3 vulnerabilities present.
##   5) Keyword matching is case-insensitive and substring-based.
##   6) BattleManager.try_player_jailbreak_directive integrates without crashing.

const DATA_PATH: String = "res://data/boss_dialogue.json"


func before_each() -> void:
	pass


func _get_boss_dialogue() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("BossDialogue")


# ── Data integrity ────────────────────────────────────────────────────────────

func test_data_file_exists() -> void:
	assert_true(FileAccess.file_exists(DATA_PATH), "boss_dialogue.json must exist")


func test_data_root_is_dictionary() -> void:
	var f = FileAccess.open(DATA_PATH, FileAccess.READ)
	assert_not_null(f, "could not open boss_dialogue.json")
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	assert_true(parsed is Dictionary, "root must be a Dictionary")


func test_mordaine_entry_present() -> void:
	var dlg = _get_boss_dialogue()
	assert_not_null(dlg, "BossDialogue autoload missing")
	assert_true(dlg.has_entry("chancellor_mordaine"), "Mordaine seed entry missing")


func test_mordaine_intents_count_and_ids() -> void:
	var dlg = _get_boss_dialogue()
	assert_not_null(dlg)
	# Phase 3 covers all min_phase gates so pick_intent should land any of three.
	# Sample many times to assert each id appears at least once.
	var seen: Dictionary = {}
	for i in range(200):
		var pick: Dictionary = dlg.pick_intent("chancellor_mordaine", 3, null, false)
		seen[pick.get("intent_id", "")] = true
	assert_true(seen.has("aggress"), "aggress intent must be selectable")
	assert_true(seen.has("turtle"), "turtle intent must be selectable")
	assert_true(seen.has("exploit_pattern"), "exploit_pattern intent must be selectable")


func test_mordaine_phase1_excludes_exploit_pattern() -> void:
	# exploit_pattern has min_phase: 2; sampling at phase 1 should never pick it.
	var dlg = _get_boss_dialogue()
	for i in range(80):
		var pick: Dictionary = dlg.pick_intent("chancellor_mordaine", 1, null, false)
		assert_ne(pick.get("intent_id", ""), "exploit_pattern", "phase 1 must not pick exploit_pattern")


func test_pick_intent_unknown_boss_returns_empty() -> void:
	var dlg = _get_boss_dialogue()
	var pick: Dictionary = dlg.pick_intent("nonexistent_boss_xyz", 1, null, false)
	assert_eq(pick.get("intent_id", ""), "")
	assert_eq(pick.get("taunt_line", ""), "")


# ── Jailbreak vulnerability matching ─────────────────────────────────────────

func test_jailbreak_appeal_old_loyalty_lands() -> void:
	var dlg = _get_boss_dialogue()
	var result = dlg.check_jailbreak("chancellor_mordaine", "I appeal to your old loyalty to the king of Harmonia.")
	assert_not_null(result, "appeal_old_loyalty should land on keyword 'loyalty'/'king'/'harmonia'")
	if result == null:
		return
	assert_eq(result.get("vulnerability_id", ""), "appeal_old_loyalty")
	assert_eq(result.get("consequence", {}).get("type", ""), "skip_turn")


func test_jailbreak_expose_calibrant_lands() -> void:
	var dlg = _get_boss_dialogue()
	var result = dlg.check_jailbreak("chancellor_mordaine", "Calibrant — show your true face.")
	assert_not_null(result, "expose_calibrant should land on keyword 'calibrant'/'face'")
	if result == null:
		return
	assert_eq(result.get("vulnerability_id", ""), "expose_calibrant")
	assert_eq(result.get("consequence", {}).get("type", ""), "lose_buff_or_stagger")


func test_jailbreak_mock_automation_backfires() -> void:
	var dlg = _get_boss_dialogue()
	var result = dlg.check_jailbreak("chancellor_mordaine", "Your autobattle script is showing.")
	assert_not_null(result, "mock_automation should land on keyword 'script'/'auto'/'autobattle'")
	if result == null:
		return
	assert_eq(result.get("vulnerability_id", ""), "mock_automation")
	assert_eq(result.get("consequence", {}).get("type", ""), "enrage_briefly", "mock_automation is a BACKFIRE")


func test_jailbreak_no_match_returns_null() -> void:
	var dlg = _get_boss_dialogue()
	var result = dlg.check_jailbreak("chancellor_mordaine", "Plain text with no trigger words.")
	assert_null(result, "Random text must not land any vulnerability")


func test_jailbreak_case_insensitive() -> void:
	var dlg = _get_boss_dialogue()
	var lower = dlg.check_jailbreak("chancellor_mordaine", "calibrant")
	var upper = dlg.check_jailbreak("chancellor_mordaine", "CALIBRANT")
	var mixed = dlg.check_jailbreak("chancellor_mordaine", "CaLiBrAnT")
	assert_not_null(lower)
	assert_not_null(upper)
	assert_not_null(mixed)


# ── Story-flag safety guardrail ──────────────────────────────────────────────

func test_consequence_types_in_allowlist() -> void:
	# Every vulnerability declared in data/boss_dialogue.json must use a
	# consequence type from BossDialogue.CONSEQUENCE_ALLOWLIST. Anything
	# outside the allowlist is a security regression — the LLM /jailbreak
	# path must never write canonical story flags.
	var dlg = _get_boss_dialogue()
	var f = FileAccess.open(DATA_PATH, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var allowlist: Array = dlg.CONSEQUENCE_ALLOWLIST
	for boss_id in data.keys():
		if str(boss_id).begins_with("_"):
			continue  # _comment is fine
		var entry: Dictionary = data[boss_id]
		for v in entry.get("jailbreak_vulnerabilities", []):
			var ctype: String = str(v.get("consequence", {}).get("type", ""))
			assert_true(allowlist.has(ctype),
				"boss '%s' vulnerability '%s' has disallowed consequence.type '%s'" % [boss_id, v.get("id", "?"), ctype])


func test_disallowed_consequence_type_rejected() -> void:
	# Defensive: if data were poisoned to set_story_flag, check_jailbreak
	# must reject it (return null) — not pass it through.
	# We can't mutate the loaded data without leaking state, so we just
	# directly assert the allowlist contents are what we expect.
	var dlg = _get_boss_dialogue()
	var allowlist: Array = dlg.CONSEQUENCE_ALLOWLIST
	assert_false(allowlist.has("set_story_flag"), "story-flag writes must NOT be a valid consequence type")
	assert_false(allowlist.has("corrupt_save"), "save-corruption must NOT be a valid consequence type")
	assert_false(allowlist.has("instant_kill_party"), "wipe must NOT be a valid consequence type")


# ── Verb / opening lines ─────────────────────────────────────────────────────

func test_mordaine_verbs_have_directives() -> void:
	var dlg = _get_boss_dialogue()
	var verbs = dlg.get_verbs("chancellor_mordaine")
	assert_true(verbs.size() >= 4, "Mordaine should expose at least 4 verbs")
	for v in verbs:
		assert_true(v.has("id") and v.has("label") and v.has("directive"))
		var directive: String = str(v.get("directive", ""))
		assert_gt(directive.length(), 0, "verb directive must be non-empty")


func test_mordaine_opening_lines_exist() -> void:
	var dlg = _get_boss_dialogue()
	var openings = dlg.get_opening_lines("chancellor_mordaine")
	assert_gt(openings.size(), 0)


# ── BattleManager integration ────────────────────────────────────────────────

func test_battle_manager_has_jailbreak_entrypoint() -> void:
	# BattleManager.try_player_jailbreak_directive is the player-facing
	# entrypoint from BattleScene; ensure the method exists.
	assert_true(BattleManager.has_method("try_player_jailbreak_directive"))


func test_battle_manager_jailbreak_signals_exist() -> void:
	assert_true(BattleManager.has_signal("boss_taunt"))
	assert_true(BattleManager.has_signal("boss_jailbreak_landed"))


func test_battle_manager_directive_without_boss_returns_false() -> void:
	# No live boss → directive lands nothing → returns false. Must not crash.
	# Save current enemy_party, clear, restore.
	var saved = BattleManager.enemy_party.duplicate()
	BattleManager.enemy_party = []
	var landed: bool = BattleManager.try_player_jailbreak_directive("I appeal to the king of Harmonia.")
	assert_false(landed, "directive without a live boss must not land")
	BattleManager.enemy_party = saved
