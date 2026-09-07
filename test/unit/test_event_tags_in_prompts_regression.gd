extends GutTest

## Feature regression: DialoguePrompts._format_events now decorates
## EventLog entries with terse trailing tags drawn from the entry's data
## dict. Closes the loop on tick 4 — the tactics snapshot reached EventLog,
## but _format_events only surfaced summary + type so the LLM never saw it.
##
## Boss-defeat entries get tagged with:
##   • [autobattled]        — when tactics.pure_autobattle == true
##   • [jailbreak landed]   — when tactics.jailbreak_landed == true
##   • [all-out attack]     — when tactics.all_out_attack_used == true
## Multiple truthy flags joined with comma+space inside a single bracket.
##
## Tests cover:
##   • Pure-autobattle defeat surfaces [autobattled].
##   • Multiple truthy flags concatenate inside one bracket.
##   • All-false tactics → no tag (we don't bloat the prompt with negatives).
##   • Missing tactics dict → no tag (defensive: pre-tick-4 saves still work).
##   • Non-boss event types are not decorated (decoration is scoped).
##   • The wider build_npc_opening prompt actually contains the tag (proves
##     end-to-end that the tag survives the prompt-builder pipeline).

const DialoguePromptsScript := preload("res://src/llm/DialoguePrompts.gd")


func _boss_entry(tactics: Dictionary) -> Dictionary:
	return {
		"t":       0,
		"pt":      0,
		"type":    "boss_defeat",
		"summary": "Defeated Rat King",
		"data":    {
			"boss_id":   "cave_rat_king_defeated",
			"boss_name": "Rat King",
			"tactics":   tactics,
		},
	}


func _format(entries: Array) -> String:
	return DialoguePromptsScript._format_events(entries, 10)


# ── Tag content ───────────────────────────────────────────────────────────────

func test_pure_autobattle_entry_gets_autobattled_tag() -> void:
	var out := _format([_boss_entry({
		"pure_autobattle":     true,
		"autobattle_used":     true,
		"manual_turns":        0,
		"autobattle_turns":    4,
		"jailbreak_landed":    false,
		"all_out_attack_used": false,
	})])
	assert_true(out.contains("[boss_defeat] Defeated Rat King [autobattled]"),
		"pure_autobattle defeat must show '[autobattled]' tag, got: %s" % out)


func test_multiple_truthy_flags_join_in_one_bracket() -> void:
	var out := _format([_boss_entry({
		"pure_autobattle":     true,
		"autobattle_used":     true,
		"manual_turns":        0,
		"autobattle_turns":    4,
		"jailbreak_landed":    true,
		"all_out_attack_used": true,
	})])
	# All three truthy flags should appear together in a single bracket.
	# Order matches the source's match block: autobattled → jailbreak → all-out.
	assert_true(out.contains("[autobattled, jailbreak landed, all-out attack]"),
		"multiple truthy flags must concatenate in one bracket, got: %s" % out)
	# And the summary itself must still be present.
	assert_true(out.contains("Defeated Rat King"),
		"summary must survive decoration, got: %s" % out)


func test_all_false_tactics_emit_no_tag() -> void:
	# Don't bloat the prompt with [no autobattle, no jailbreak, no all-out]
	# negatives — the LLM helpfully but pointlessly acknowledges them.
	var out := _format([_boss_entry({
		"pure_autobattle":     false,
		"autobattle_used":     false,
		"manual_turns":        4,
		"autobattle_turns":    0,
		"jailbreak_landed":    false,
		"all_out_attack_used": false,
	})])
	# Summary must still appear, but NO trailing bracket-tag.
	assert_true(out.contains("Defeated Rat King"),
		"summary must still appear when all flags are false")
	assert_false(out.contains("Defeated Rat King ["),
		"all-false tactics must NOT append a trailing bracket-tag, got: %s" % out)


func test_missing_tactics_dict_emits_no_tag() -> void:
	# Defensive: pre-tick-4 saves and any future event without a tactics
	# block must still format cleanly (no crash, no bracket).
	var entry: Dictionary = {
		"t": 0, "pt": 0, "type": "boss_defeat",
		"summary": "Defeated Rat King",
		"data": {"boss_id": "cave_rat_king_defeated"},
	}
	var out := DialoguePromptsScript._format_events([entry], 10)
	assert_true(out.contains("Defeated Rat King"),
		"missing tactics must still render the summary")
	assert_false(out.contains("Defeated Rat King ["),
		"missing tactics must not append any bracket-tag")


func test_non_boss_event_is_not_decorated() -> void:
	# Decoration is type-scoped — area_entered/level_up/etc. must remain
	# untouched even if they happen to carry a 'tactics' key by accident.
	var entry: Dictionary = {
		"t": 0, "pt": 0, "type": "area_entered",
		"summary": "Entered Harmonia",
		"data": {"tactics": {"pure_autobattle": true}},
	}
	var out := DialoguePromptsScript._format_events([entry], 10)
	assert_true(out.contains("[area_entered] Entered Harmonia"),
		"area_entered summary should appear")
	assert_false(out.contains("autobattled"),
		"non-boss entries must not pick up the boss_defeat tags, got: %s" % out)


# ── Pipeline check ────────────────────────────────────────────────────────────

func test_npc_opening_prompt_includes_event_tag() -> void:
	# End-to-end: the tag must survive the build_npc_opening pipeline so the
	# LLM actually sees it. Without this, _format_events could be correct
	# but the wrapping prompt builder could swallow the events block.
	var prompt: String = DialoguePromptsScript.build_npc_opening(
		"Theron", "village elder", "Harmonia",
		[_boss_entry({
			"pure_autobattle":     true,
			"autobattle_used":     true,
			"manual_turns":        0,
			"autobattle_turns":    4,
			"jailbreak_landed":    false,
			"all_out_attack_used": false,
		})],
	)
	assert_true(prompt.contains("Recent events:"),
		"opening prompt must include the Recent events block")
	assert_true(prompt.contains("[autobattled]"),
		"opening prompt must surface the autobattled tag to the LLM")
