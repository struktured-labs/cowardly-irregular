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
	var words: Array[String] = []
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
