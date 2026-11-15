extends GutTest

## A reasoning model on a BYOK endpoint (qwen3, deepseek-r1) writes <think>...</think> ahead of its reply. The gloat is
## the one plain-text completion, so its thoughts reached the box; clean_model_text now drops them for every line.


func test_a_closed_thought_is_dropped() -> void:
	var out: String = DialoguePrompts.clean_model_text("<think>They lost. Be smug.</think> \"Kneel, little heroes.\"")
	assert_eq(out, "Kneel, little heroes.", "the thought goes and the reply is cleaned as before")


func test_every_spelling_and_case_is_dropped() -> void:
	for tag in ["think", "THINK", "thinking", "reasoning"]:
		var out: String = DialoguePrompts.clean_model_text("<%s>plan\nmore plan</%s>Down you go." % [tag, tag])
		assert_eq(out, "Down you go.", "<%s> is reasoning, not speech" % tag)


func test_the_gloat_path_drops_a_multiline_thought() -> void:
	var out: String = DialoguePrompts.flatten_line("<think>\nstep one\nstep two\n</think>\nThe crown stays mine.")
	assert_eq(out, "The crown stays mine.", "flatten_line joins lines first, and the thought still goes")


func test_an_unclosed_thought_leaves_nothing_to_say() -> void:
	var out: String = DialoguePrompts.clean_model_text("<think>The token cap cut me off mid-pl")
	assert_eq(out, "", "a reply that is all thought is empty, so the caller's fallback speaks")


func test_a_line_without_thoughts_is_untouched() -> void:
	var line := "I think, therefore I bite. <3"
	assert_eq(DialoguePrompts.clean_model_text(line), line, "CONTROL: the word think and a stray < are speech")
	assert_eq(DialoguePrompts.drop_reasoning("plain"), "plain", "CONTROL: nothing to drop")
