extends GutTest

## struktured, playing .758, laughed at Voltharion's wipe gloat and asked "why all the dashes tho" (godot.log:2660):
##     FINALLY-FINALLY-FINALLY! The-cowardly-irregulars' pitiful-attempts-at-speedrun-fail!
## His persona hyphenates on purpose, and the model ran it across a whole sentence. Every model line now goes through
## DialoguePrompts.clean_model_text, which spaces out a run of more than MAX_HYPHEN_RUN_WORDS joined words, and every
## boss prompt states the same limit. NOTE: his AUTHORED lines carry longer runs (48 of 98 are 4+ words); they are
## story data and are not touched here.

const HIS_LINE := "FINALLY-FINALLY-FINALLY! The-cowardly-irregulars' pitiful-attempts-at-speedrun-fail!"


func test_his_line_reads_as_a_sentence() -> void:
	var got: String = DialoguePrompts.clean_model_text(HIS_LINE)
	assert_eq(got, "FINALLY-FINALLY-FINALLY! The-cowardly-irregulars' pitiful attempts at speedrun fail!",
		"THE DEFECT: a five-word hyphen run shipped as one unreadable word")


func test_the_gloat_producer_applies_it() -> void:
	## The producer's own call, so a helper-only fix that the producer stopped calling would red here.
	assert_false(BattleManager.strip_wrapping_quotes("\"%s\"" % HIS_LINE).contains("pitiful-attempts"),
		"the gloat path must clean the run, quoted or not")


func test_short_bursts_and_compounds_stay() -> void:
	for line in ["GREAT-fight-though! Best-I've-had!", "A well-known storm.", "FINALLY-FINALLY-FINALLY!"]:
		assert_eq(DialoguePrompts.clean_model_text(line), line,
			"a burst of at most %d words keeps its voice: %s" % [DialoguePrompts.MAX_HYPHEN_RUN_WORDS, line])


func test_the_limit_is_exactly_the_constant() -> void:
	var n: int = DialoguePrompts.MAX_HYPHEN_RUN_WORDS
	var words := PackedStringArray()
	for i in n + 1:
		words.append("w%d" % i)
	var at_limit: String = "-".join(words.slice(0, n))
	assert_eq(DialoguePrompts.clean_model_text(at_limit), at_limit, "a run of exactly the limit stays")
	assert_eq(DialoguePrompts.clean_model_text("-".join(words)), " ".join(words), "one word over is spaced out")


func test_every_boss_prompt_states_the_limit() -> void:
	var rule: String = DialoguePrompts.HYPHEN_RUN_RULE % DialoguePrompts.MAX_HYPHEN_RUN_WORDS
	var bm: Node = get_tree().root.get_node("BattleManager")
	assert_string_contains(bm._build_gloat_prompt("voltharion", "Voltharion", false), rule,
		"the gloat prompt (where his line came from) must state the limit the cleaner enforces")
	var taunt_prompt: String = DialoguePrompts.build_boss_intent("Voltharion", {"persona": "EVERYTHING-IS-URGENT."})
	assert_string_contains(taunt_prompt, rule, "and so must the taunt prompt")


## complete() returns the AUTHORED fallback verbatim on any failure; cleaning it would move a recorded line's key and
## silence cowir-sfx's clip. Driven through the real producer with the model off.
func test_an_authored_fallback_reaches_the_screen_untouched() -> void:
	var authored: String = "I-have-never-been-prouder-to-lose. Full-send-unattended!"
	var bm: Node = get_tree().root.get_node("BattleManager")
	var llm: Node = get_tree().root.get_node("LLMService")
	var was_enabled: bool = llm.llm_enabled
	llm.llm_enabled = false
	var heard: Array = []
	var cb := func(text: String, _v: bool): heard.append(text)
	bm.boss_gloat_line.connect(cb)
	bm._produce_boss_gloat_async("prompt", authored, false)
	var t0 := Time.get_ticks_msec()
	while heard.is_empty() and Time.get_ticks_msec() - t0 < int(bm.GLOAT_WAIT_SEC * 1000.0) + 500:
		await get_tree().process_frame
	bm.boss_gloat_line.disconnect(cb)
	llm.llm_enabled = was_enabled
	assert_eq(heard.size(), 1, "FIXTURE: one line was emitted")
	if heard.size() != 1:
		return
	assert_eq(str(heard[0]), authored, "THE RISK: an authored line was respaced, so its recording no longer matches it")


func test_the_prompts_quote_no_long_run() -> void:
	var bm: Node = get_tree().root.get_node("BattleManager")
	var long_sample: String = "I-have-never-been-prouder-to-lose"
	var gloat: String = bm._build_gloat_prompt("voltharion", "Voltharion", false, long_sample)
	assert_false(gloat.contains(long_sample), "the voice sample must not show the model a run the cleaner removes")
	assert_false(gloat.contains("maximum-DPS-per-second"), "nor may the persona quoted in the gloat prompt")
	var taunt: String = DialoguePrompts.build_boss_intent("Voltharion", {"persona": "maximum-DPS-per-second, always."})
	assert_false(taunt.contains("maximum-DPS-per-second"), "nor may the persona quoted in the taunt prompt")


## cowir-main 20955: the persona said only "You hyphenate.", pulling against the rule; it now says how.
func test_his_persona_agrees_with_the_rule() -> void:
	var persona: String = str(get_tree().root.get_node("BossDialogue").get_persona("voltharion"))
	assert_ne(persona, "", "FIXTURE: Voltharion has a persona")
	assert_false(persona.contains("You hyphenate. "), "the bare instruction to hyphenate is gone")
	assert_string_contains(persona, "never a whole sentence", "it says the same limit the rule states")
