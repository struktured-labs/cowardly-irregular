extends GutTest

## Regression: NPC sign-off must use a dedicated farewell builder.
##
## Before fix: _fetch_npc_sign_off() delegated to
##   DialoguePrompts.build_npc_opening_topical(..., "a polite farewell ...")
## whose prompt body literally instructs the LLM:
##   "Generate exactly ONE opening line spoken by the NPC when the player
##    approaches."
## …so the LLM had to fight that framing every time and farewells often read
## like another greeting. Same bug class as the silent-reuse of
## _fetch_npc_opening for _fetch_npc_reply (cowir-ai sharpening #3 / plan
## slice item 5) — sign-offs were the last leftover.
##
## Fix: a dedicated build_npc_sign_off() prompt that frames the line as a
## GOODBYE, threads (last_npc_line, last_player_line) so the closing reacts
## to what was just said, and explicitly tells the LLM "this is NOT a
## greeting; do NOT restart the conversation."
##
## These tests cover both the prompt content (must read as a farewell, must
## include the conversation tail, must NOT use the opening framing) and the
## DynamicConversation wiring (the sign-off code path resolves to the new
## builder, not the old opening-topical one).

const DialoguePromptsScript := preload("res://src/llm/DialoguePrompts.gd")

const OPENING_FRAMING_NEEDLE: String = "opening line spoken by the NPC when the player approaches"


# ── DialoguePrompts.build_npc_sign_off content ────────────────────────────────

func test_sign_off_prompt_frames_as_farewell() -> void:
	var prompt: String = DialoguePromptsScript.build_npc_sign_off(
		"Theron",
		"village elder",
		"Harmonia",
		[],
		"Safe roads, traveler.",
		"Thanks for the help.",
	)
	# Must declare the goal as a closing line, not an opening.
	assert_true(prompt.contains("closing line"),
		"sign-off prompt must explicitly request a closing line")
	assert_true(prompt.contains("farewell"),
		"sign-off prompt must mention farewell")
	assert_false(prompt.contains(OPENING_FRAMING_NEEDLE),
		"sign-off prompt MUST NOT reuse the 'opening line ... when the player approaches' framing")
	# Must guard explicitly against restarting the conversation.
	assert_true(prompt.contains("GOODBYE") or prompt.contains("goodbye"),
		"sign-off prompt must call out that this is a goodbye")
	assert_true(prompt.contains("do NOT restart the conversation"),
		"sign-off prompt must instruct the LLM not to restart the chat")


func test_sign_off_prompt_threads_conversation_tail() -> void:
	var prompt: String = DialoguePromptsScript.build_npc_sign_off(
		"Theron",
		"village elder",
		"Harmonia",
		[],
		"Stick to the southern road — the wolves have been quiet.",
		"I'll keep an eye out. Goodbye.",
	)
	assert_true(prompt.contains("Stick to the southern road"),
		"sign-off prompt must include the prior NPC line so the goodbye can react to it")
	assert_true(prompt.contains("keep an eye out"),
		"sign-off prompt must include the player's last response so the goodbye references it")


func test_sign_off_prompt_omits_empty_tail() -> void:
	# When the conversation ended without a tracked tail (e.g. sign-off fired
	# on the very first turn), the prompt should silently omit the history
	# block rather than emit empty "You previously said:" stubs.
	var prompt: String = DialoguePromptsScript.build_npc_sign_off(
		"Theron",
		"village elder",
		"Harmonia",
		[],
		"",
		"",
	)
	assert_false(prompt.contains("You previously said"),
		"empty last_npc_line must not produce a 'You previously said' stub")
	assert_false(prompt.contains("The player just responded"),
		"empty player_line must not produce a 'The player just responded' stub")


func test_sign_off_response_shape_matches_opening_schema() -> void:
	# We deliberately reuse SCHEMA_NPC_OPENING + validate_npc_opening for the
	# sign-off — same {"line": "<text>"} shape — so the validator pipeline
	# stays simple. Pin the prompt instructs that exact shape.
	var prompt: String = DialoguePromptsScript.build_npc_sign_off(
		"Theron", "elder", "Harmonia", [], "", "",
	)
	assert_true(prompt.contains("{\"line\": \"<text>\"}"),
		"sign-off prompt must instruct the {\"line\": ...} JSON shape so validate_npc_opening still applies")


# ── DynamicConversation wiring ───────────────────────────────────────────────

func test_fetch_sign_off_calls_dedicated_builder() -> void:
	# Pin via source-grep so the wiring can't silently regress back to
	# build_npc_opening_topical (the original bug shape).
	var text: String = FileAccess.get_file_as_string("res://src/llm/DynamicConversation.gd")
	assert_ne(text, "", "DynamicConversation.gd must be readable")
	# Find the _fetch_npc_sign_off function body window.
	var fn_idx: int = text.find("func _fetch_npc_sign_off")
	assert_gt(fn_idx, -1, "_fetch_npc_sign_off must exist")
	# Slice through the next func declaration so we only scan this function.
	var rest: String = text.substr(fn_idx)
	var next_fn: int = rest.find("\nfunc ", 1)
	var body: String = rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("DialoguePrompts.build_npc_sign_off"),
		"_fetch_npc_sign_off must dispatch to DialoguePrompts.build_npc_sign_off")
	assert_false(body.contains("build_npc_opening_topical"),
		"_fetch_npc_sign_off must NOT reuse build_npc_opening_topical (the old bug shape)")


func test_sign_off_threads_conversation_tail_vars() -> void:
	# Same source-pin: confirm the wiring passes _last_npc_line and
	# _last_player_line into the dedicated builder, so the goodbye actually
	# reacts to what was just said. Without these, the sign-off would degrade
	# back to a context-free farewell even after the new builder is wired.
	var text: String = FileAccess.get_file_as_string("res://src/llm/DynamicConversation.gd")
	var fn_idx: int = text.find("func _fetch_npc_sign_off")
	assert_gt(fn_idx, -1, "_fetch_npc_sign_off must exist")
	var rest: String = text.substr(fn_idx)
	var next_fn: int = rest.find("\nfunc ", 1)
	var body: String = rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("_last_npc_line"),
		"_fetch_npc_sign_off must thread _last_npc_line into the prompt")
	assert_true(body.contains("_last_player_line"),
		"_fetch_npc_sign_off must thread _last_player_line into the prompt")
