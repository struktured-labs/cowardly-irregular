extends GutTest

## Wave F — DynamicConversation live-path coherence test.
##
## Verifies the fix for bug #5: _do_npc_reply must thread the player's chosen
## line and the prior NPC line into the prompt — NOT silently re-invoke
## _fetch_npc_opening, which discards the chosen line.
##
## Strategy:
##   - Install FakeBackend as the active backend on a fresh LLMService.
##   - prime_for_prompt_contains hooks distinguish "opening" vs "reply" prompts.
##   - Drive DynamicConversation through one exchange.
##   - Assert FakeBackend.prompt_history contains a reply-shaped prompt that
##     embeds the player's chosen line — proof the reply path is in use.
##
## NOTE: This test stops short of running the full UI loop (DialogueChoiceMenu
## requires gamepad/keyboard input). Instead, we exercise the LLM-fetch helpers
## directly by setting internal state and calling _fetch_combined_reply.

const FakeBackendScript := preload("res://test/unit/test_llm_fake_backend.gd")


var _svc: Node
var _be: FakeBackendScript.FakeBackend
var _dc: DynamicConversation
var _stashed_original_svc: Node = null  # real autoload, detached during test, restored in after_each


func before_each() -> void:
	# Swap out any existing /root/LLMService for our local one.
	# FLEET BUG FIX (2026-07-01, cowir-ai diagnosis msg 2036): this used
	# to queue_free() the REAL LLMService autoload and never restore it,
	# poisoning every alphabetically-later test file (RuleComposer tests
	# saw null service → "no_llm"/"fallback" instead of their mock path;
	# green in isolation, red in full suite). Now we DETACH and stash the
	# original, and after_each re-attaches it.
	var root := get_tree().root
	var existing := root.get_node_or_null("LLMService")
	if existing != null:
		root.remove_child(existing)
		_stashed_original_svc = existing

	_svc = preload("res://src/llm/LLMService.gd").new()
	_svc.name = "LLMService"
	_svc.llm_enabled = true
	root.add_child(_svc)

	# Replace built-in backends with the FakeBackend.
	for be in _svc._backends:
		if be.request_finished.is_connected(_svc._on_backend_finished):
			be.request_finished.disconnect(_svc._on_backend_finished)
	_be = FakeBackendScript.FakeBackend.new()
	_be.name = "FakeBE"
	_svc.add_child(_be)
	# _backends is a strictly-typed Array[LLMBackend]; reassigning to an
	# untyped Array literal triggers SCRIPT ERROR. Clear + append preserves
	# the typed array.
	_svc._backends.clear()
	_svc._backends.append(_be)
	_be.request_finished.connect(_svc._on_backend_finished)
	_svc._select_backend()

	_dc = DynamicConversation.new()
	_dc.name = "TestDC"
	add_child_autofree(_dc)
	_dc.setup("Test NPC", "a wise sage", "Test Village", null, ["Hello!"])


func after_each() -> void:
	# Tidy up — remove the LLMService we installed, then RESTORE the
	# original autoload we stashed in before_each so later test files
	# see the real service (fleet contamination fix, msg 2036/2037).
	var root := get_tree().root
	var svc := root.get_node_or_null("LLMService")
	if svc != null:
		root.remove_child(svc)
		svc.queue_free()
	if _stashed_original_svc != null and is_instance_valid(_stashed_original_svc):
		root.add_child(_stashed_original_svc)
		_stashed_original_svc = null
	_be = null
	_dc = null


# ─── Tests ───────────────────────────────────────────────────────────────────

func test_llm_available_via_fake() -> void:
	assert_true(_dc._llm_available(), "DynamicConversation should see live FakeBackend")


func test_npc_opening_prompt_received_by_backend() -> void:
	_be.prime_next('{"line": "Greetings, traveler!"}')
	var line: String = await _dc._fetch_npc_opening()
	assert_eq(line, "Greetings, traveler!")
	assert_gt(_be.submit_count, 0, "opening fetch should reach the backend")
	# Opening prompts contain the words "opening line" per DialoguePrompts.
	assert_true(_be.last_prompt.find("opening line") != -1, "opening prompt should describe an opening line")


func test_npc_reply_prompt_includes_player_line_and_prior_npc_line() -> void:
	# Stage internal conversation state: prior NPC line + player choice.
	_dc._last_npc_line = "The dragon stirs again."
	_dc._last_player_line = "What can be done about it?"

	_be.prime_next('{"line": "We must seek the old swords."}')
	var reply: String = await _dc._fetch_npc_reply()
	assert_eq(reply, "We must seek the old swords.")

	# Verify the prompt actually carried both the prior NPC line AND the
	# player's chosen response — the key contract for bug #5.
	var prompt: String = _be.last_prompt
	assert_true(prompt.find("The dragon stirs again.") != -1,
		"reply prompt MUST embed the prior NPC line (bug #5)")
	assert_true(prompt.find("What can be done about it?") != -1,
		"reply prompt MUST embed the player's chosen response (bug #5)")


func test_combined_reply_prompt_threads_history() -> void:
	# The MERGE_REPLY_AND_CHOICES path uses build_combined_reply, which
	# must also thread both prior lines into context.
	_dc._last_npc_line = "Dark times approach."
	_dc._last_player_line = "Tell me of the omen."

	_be.prime_next('{"reply": "The stars have shifted.", "choices": ["Press for detail.", "Farewell."]}')
	var combined: Dictionary = await _dc._fetch_combined_reply()
	assert_eq(str(combined.get("reply", "")), "The stars have shifted.")
	assert_eq((combined.get("choices", []) as Array).size(), 2)

	var prompt: String = _be.last_prompt
	assert_true(prompt.find("Dark times approach.") != -1,
		"combined-reply prompt MUST embed prior NPC line")
	assert_true(prompt.find("Tell me of the omen.") != -1,
		"combined-reply prompt MUST embed player response")
