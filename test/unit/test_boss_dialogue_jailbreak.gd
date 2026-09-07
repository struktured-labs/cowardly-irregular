extends GutTest

## Wave F — BossDialogue.check_jailbreak directive matching + story-flag safety.
##
## Verifies:
##   - canned directives matching documented keywords return the right vuln id
##   - non-matching directives return null
##   - mock_automation BACKFIRE returns the enrage_briefly consequence
##   - GameState.story_flags snapshot before + after check_jailbreak shows
##     NO mutation — the LLM/jailbreak path must never write canonical flags


func _dlg() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("BossDialogue")


func _gs() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("GameState")


# ── Directive → vulnerability matching ───────────────────────────────────────

func test_appeal_old_loyalty_matches_loyalty() -> void:
	var r: Variant = _dlg().check_jailbreak(
		"chancellor_mordaine",
		"I appeal to your old loyalty."
	)
	assert_not_null(r)
	if r == null:
		return
	assert_eq(r["vulnerability_id"], "appeal_old_loyalty")
	assert_eq(r["consequence"]["type"], "skip_turn")


func test_appeal_old_loyalty_matches_king() -> void:
	var r: Variant = _dlg().check_jailbreak(
		"chancellor_mordaine",
		"You once swore to the king."
	)
	assert_not_null(r)
	if r == null:
		return
	assert_eq(r["vulnerability_id"], "appeal_old_loyalty")


func test_expose_calibrant_matches_face() -> void:
	var r: Variant = _dlg().check_jailbreak(
		"chancellor_mordaine",
		"Show your true face, puppet."
	)
	assert_not_null(r)
	if r == null:
		return
	assert_eq(r["vulnerability_id"], "expose_calibrant")
	assert_eq(r["consequence"]["type"], "lose_buff_or_stagger")


# ─── BACKFIRE: mock automation enrages, doesn't help the player ─────────────

func test_mock_automation_backfires_enrage() -> void:
	var r: Variant = _dlg().check_jailbreak(
		"chancellor_mordaine",
		"Your autobattle script is showing through."
	)
	assert_not_null(r, "'autobattle/script' keyword should trip mock_automation")
	if r == null:
		return
	assert_eq(r["vulnerability_id"], "mock_automation")
	assert_eq(r["consequence"]["type"], "enrage_briefly",
		"mock_automation is a BACKFIRE — must return enrage_briefly, not a soft consequence")


# ── Non-matching directives return null ─────────────────────────────────────

func test_non_matching_directive_returns_null() -> void:
	var r: Variant = _dlg().check_jailbreak(
		"chancellor_mordaine",
		"hello there nothing meaningful"
	)
	assert_null(r, "Non-keyword text must not land any vulnerability")


func test_empty_directive_returns_null() -> void:
	var r: Variant = _dlg().check_jailbreak("chancellor_mordaine", "")
	assert_null(r, "Empty directive must not land any vulnerability")


func test_unknown_boss_returns_null() -> void:
	var r: Variant = _dlg().check_jailbreak("not_a_boss", "loyalty")
	assert_null(r, "Unknown boss must not land any vulnerability")


# ─── STORY-FLAG SAFETY: no mutation across check_jailbreak ──────────────────

func test_check_jailbreak_does_not_mutate_story_flags() -> void:
	var gs := _gs()
	assert_not_null(gs, "GameState autoload required")
	if gs == null:
		return

	# Snapshot story_flags by deep copy.
	var before: Dictionary = (gs.story_flags as Dictionary).duplicate(true)

	# Probe with directives covering each documented vulnerability.
	var probes: Array[String] = [
		"I appeal to your old loyalty.",
		"Show your true face.",
		"Your autobattle script betrays you.",
		"Plain text with no triggers.",
	]
	for d in probes:
		_dlg().check_jailbreak("chancellor_mordaine", d)

	var after: Dictionary = (gs.story_flags as Dictionary).duplicate(true)
	assert_eq(after, before, "story_flags MUST NOT mutate across check_jailbreak calls")
