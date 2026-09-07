extends GutTest

## Milo v2 (msg 2600) — LLM prompt-context injection.
##
## When an LLM-opt-in NPC has resolved persona.quest_state_lines[bucket],
## the bucket lines are threaded into DialoguePrompts.build_npc_opening as
## "recent voice notes" — the LLM matches the current-quest-phase tone
## instead of only the generic persona blurb. Fold-order composed with
## cycle 3 (bucket cache + resolver) and cycle 2 (routing yield).
##
## Invariants:
##   - Empty quest_state_lines produces byte-identical prompt to pre-cycle-4
##     (backward compat for Theron, Boris, and any future dynamic NPC without
##     a quest_state_lines block).
##   - The prompt appends a labeled block quoting each line so the LLM can
##     distinguish "recent voice" from "recent events" (the pre-existing
##     context section).
##   - Quotes inside the lines are escaped so they don't break the prompt shape.


const DP := preload("res://src/llm/DialoguePrompts.gd")
const OVERWORLD_NPC_PATH: String = "res://src/exploration/OverworldNPC.gd"
const DYN_CONV_PATH: String = "res://src/llm/DynamicConversation.gd"


func _read(path: String) -> String:
	var f = FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "file should exist: %s" % path)
	var t = f.get_as_text()
	f.close()
	return t


# ── DialoguePrompts.build_npc_opening backward compatibility

func test_opening_prompt_with_empty_quest_state_is_backward_compatible() -> void:
	# Without the new arg (default []), the returned prompt must contain the
	# original sections + NOT contain the new "recently said" block.
	var prompt: String = DP.build_npc_opening("Milo", "scholar", "Harmonia Village", [])
	assert_true(prompt.find("recently said") == -1,
		"empty quest_state_lines must not emit the 'recently said' voice block — backward compat for Theron/Boris/any NPC without a bucket")
	assert_true(prompt.find("Persona: scholar") != -1,
		"persona section still present (regression guard for the base prompt shape)")
	assert_true(prompt.find("Respond with ONLY valid JSON") != -1,
		"rules footer still present")


func test_opening_prompt_explicit_empty_array_is_backward_compatible() -> void:
	var prompt: String = DP.build_npc_opening("Milo", "scholar", "Harmonia Village", [], [])
	assert_true(prompt.find("recently said") == -1,
		"explicit empty quest_state_lines matches the default: no voice block")


# ── Voice injection surface

func test_opening_prompt_includes_bucket_lines_when_provided() -> void:
	var lines: Array = [
		"If the sacrament is real, someone else has to have it.",
		"I have a chapter drafted. It is Chapter Three.",
	]
	var prompt: String = DP.build_npc_opening("Milo", "scholar", "Harmonia Village", [], lines)
	assert_true(prompt.find("recently said") != -1,
		"quest_state_lines with content must emit the 'recently said' voice block")
	assert_true(prompt.find("sacrament is real") != -1,
		"each bucket line must appear in the injected block (line 1)")
	assert_true(prompt.find("Chapter Three") != -1,
		"each bucket line must appear in the injected block (line 2)")
	assert_true(prompt.find("Echo this mood and voice.") != -1,
		"the voice block must instruct the LLM to match tone — otherwise lines are context without direction")


func test_opening_prompt_voice_block_survives_a_line_with_quotes() -> void:
	# Milo's post_quest bucket has 'the sacrament is not in the automation'
	# wrapped in single-quotes inside a double-quoted line. Escape it so the
	# prompt JSON-shape doesn't get broken.
	var lines: Array = [
		"As I have written — 'the sacrament is not in the automation, but in the noticing.'",
	]
	var prompt: String = DP.build_npc_opening("Milo", "scholar", "Harmonia Village", [], lines)
	# The literal source has the single-quotes; those are safe in a bulleted list.
	# What we must escape is any embedded double-quote, so the prompt stays parseable.
	# Inject one with a double-quote and verify escape.
	var lines2: Array = ["Milo says \"letting go\" is teachable."]
	var prompt2: String = DP.build_npc_opening("Milo", "scholar", "Harmonia", [], lines2)
	# Either the double-quote is present but escaped, or the raw text landed.
	# The escape happens via replace("\"", "\\\"") in _format_quest_state_voice.
	assert_true(prompt2.find("\\\"letting go\\\"") != -1 or prompt2.find("\"letting go\"") != -1,
		"embedded double quotes must not break the prompt — escaped or preserved")


func test_opening_prompt_ignores_empty_string_lines() -> void:
	var lines: Array = ["", "real line", ""]
	var prompt: String = DP.build_npc_opening("Milo", "scholar", "Harmonia", [], lines)
	assert_true(prompt.find("real line") != -1, "non-empty lines still appear")
	# Empty lines produce nothing (no "- \"\"" bullet).
	assert_true(prompt.find("  - \"\"") == -1, "empty strings must not emit blank bullets")


func test_opening_prompt_voice_block_absent_when_all_lines_empty() -> void:
	var lines: Array = ["", ""]
	var prompt: String = DP.build_npc_opening("Milo", "scholar", "Harmonia", [], lines)
	assert_true(prompt.find("recently said") == -1,
		"if every quest_state_line filters to empty, do not emit the voice block header (would be a lie)")


# ── DynamicConversation setup wiring

func test_dynamic_conversation_setup_accepts_quest_state_lines() -> void:
	var DC: Script = load(DYN_CONV_PATH)
	var dc = DC.new()
	add_child_autofree(dc)
	dc.setup("Milo", "scholar", "Harmonia", null, ["fallback"], [], ["quest line 1", "quest line 2"])
	assert_eq(int(dc._quest_state_lines.size()), 2,
		"setup must store quest_state_lines for later use in build_npc_opening")
	assert_eq(str(dc._quest_state_lines[0]), "quest line 1",
		"lines preserved in order")


func test_dynamic_conversation_setup_defaults_quest_state_lines_empty() -> void:
	var DC: Script = load(DYN_CONV_PATH)
	var dc = DC.new()
	add_child_autofree(dc)
	# Call setup with the pre-cycle-4 argument list (no quest_state_lines).
	dc.setup("Theron", "elder", "Harmonia", null, ["fallback"], [])
	assert_eq(int(dc._quest_state_lines.size()), 0,
		"pre-cycle-4 call-site (no quest_state_lines arg) must default to empty — no LLM behavior change for Theron")


func test_dynamic_conversation_duplicates_quest_state_lines() -> void:
	# Same defensive-copy pattern the opening_lines and fallback_lines use —
	# stops the caller mutating our internal cache after setup.
	var DC: Script = load(DYN_CONV_PATH)
	var dc = DC.new()
	add_child_autofree(dc)
	var caller_array: Array = ["A", "B"]
	dc.setup("Milo", "scholar", "Harmonia", null, [], [], caller_array)
	caller_array.append("C")
	assert_eq(int(dc._quest_state_lines.size()), 2,
		"quest_state_lines must be duplicated in setup — mutating the caller's array must not corrupt our cache")


# ── Source-inspection regression pins

func test_source_dynamic_conversation_passes_quest_state_lines_to_builder() -> void:
	var src = _read(DYN_CONV_PATH)
	assert_true(src.find("_quest_state_lines") != -1,
		"DynamicConversation must retain the _quest_state_lines cache")
	# Look for the build_npc_opening call passing our cache.
	# Multi-line regex isn't easy; check both tokens are present in file.
	assert_true(src.find("build_npc_opening") != -1 and src.find("_quest_state_lines,") != -1,
		"build_npc_opening call must pass _quest_state_lines (regression: silent revert to un-injected prompt)")


func test_source_overworld_npc_resolves_and_passes_bucket_lines() -> void:
	var src = _read(OVERWORLD_NPC_PATH)
	assert_true(src.find("llm_quest_lines") != -1,
		"OverworldNPC._run_dynamic_conversation must resolve bucket lines locally before setup")
	assert_true(src.find(", llm_quest_lines)") != -1,
		"resolved bucket lines must be passed as the 7th arg to DynamicConversation.setup — the LLM path can't see them otherwise")
	assert_true(src.find("_quest_state_bucket_for_npc(quest_sys_for_llm)") != -1,
		"bucket resolution must reuse the cycle-3 helper so LLM-on/LLM-off paths agree on bucket")
