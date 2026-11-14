extends GutTest

## boss_dialogue.json authors opening_lines for every W1 boss and duelist, and BossDialogue.get_opening_lines had no
## caller: nothing a player meets ever read them. The intent prompt now quotes up to MAX_VOICE_LINES of them as the
## boss's register, so the LLM's taunt sounds like the character story wrote. A boss with none gets the prompt it had.

const DP := preload("res://src/llm/DialoguePrompts.gd")
const CTX := preload("res://src/battle/BossIntentContext.gd")


func _ctx(lines: Array) -> Dictionary:
	var c = CTX.new()
	c.boss_id = "glacius"
	c.phase = 1
	c.persona = "Cold."
	c.available_intents = ["aggress", "turtle"]
	c.voice_lines = lines
	return c.to_dict()


func _boss() -> Combatant:
	var boss := Combatant.new()
	boss.initialize({"name": "Boss", "max_hp": 500, "max_mp": 50, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(boss)
	return boss


func test_the_prompt_quotes_the_lines_as_spoken() -> void:
	var prompt: String = DP.build_boss_intent("Glacius", _ctx(["Glacius: 'You took your time.'", "*He yawns.* Glacius: 'Again?'"]))
	assert_string_contains(prompt, "Lines you have said", "the voice block is there")
	assert_string_contains(prompt, "  - You took your time.\n", "a speaker tag and its quotes are stripped to the words")
	assert_false(prompt.contains("Glacius: 'You took"), "the raw tagged form is not quoted")


func test_no_lines_is_the_prompt_it_had() -> void:
	var bare = CTX.new()
	bare.boss_id = "glacius"
	bare.phase = 1
	bare.persona = "Cold."
	bare.available_intents = ["aggress", "turtle"]
	var before: Dictionary = bare.to_dict()
	before.erase("voice_lines")
	assert_eq(DP.build_boss_intent("Glacius", _ctx([])), DP.build_boss_intent("Glacius", before),
		"no authored lines: byte-identical to a context that never had the field")


func test_only_a_few_lines_are_quoted() -> void:
	var many: Array = []
	for i in DP.MAX_VOICE_LINES + 2:
		many.append("Line %d." % i)
	var prompt: String = DP.build_boss_intent("Glacius", _ctx(many))
	assert_string_contains(prompt, "  - Line %d." % (DP.MAX_VOICE_LINES - 1), "CONTROL: the last line inside the cap is quoted")
	assert_false(prompt.contains("  - Line %d." % DP.MAX_VOICE_LINES), "a register, not a script: lines past the cap stay out")


func test_hyphen_runs_are_undone_like_the_persona() -> void:
	var lines: Array = BossDialogue.get_opening_lines("voltharion")
	var hyphenated: Array = lines.filter(func(l): return DP.spoken_line(str(l)) != DP.unrun_hyphens(DP.spoken_line(str(l))))
	assert_false(hyphenated.is_empty(), "CONTROL: Voltharion authors a hyphen-run opening line")
	if hyphenated.is_empty():
		return
	var prompt: String = DP.build_boss_intent("Voltharion", _ctx([hyphenated[0]]))
	assert_string_contains(prompt, "  - %s" % DP.unrun_hyphens(DP.spoken_line(str(hyphenated[0]))), "quoted the way the persona is")
	assert_false(prompt.contains(DP.spoken_line(str(hyphenated[0]))), "the hyphen run the cleaner removes is not modelled")


func test_the_battle_hands_over_the_bosss_own_lines() -> void:
	var authored: Array = BossDialogue.get_opening_lines("glacius")
	assert_false(authored.is_empty(), "CONTROL: Glacius authors opening lines")
	var ctx: BossIntentContext = BattleManager._build_boss_intent_context(_boss(), "glacius", 1, BossDialogue)
	assert_eq(ctx.voice_lines, authored.slice(0, DP.MAX_VOICE_LINES), "the context carries Glacius's own lines, capped")
	var none: BossIntentContext = BattleManager._build_boss_intent_context(_boss(), "nobody_authored_this_boss", 1, BossDialogue)
	assert_eq(none.voice_lines, [], "an unauthored boss hands over none")


func test_a_line_too_long_to_say_is_not_a_model() -> void:
	var cap: int = DP.MAX_BOSS_TAUNT_CHARS
	var fits: String = "a".repeat(cap)
	var over: String = "b".repeat(cap + 1)
	var prompt: String = DP.build_boss_intent("Glacius", _ctx([over, fits]))
	assert_string_contains(prompt, "  - %s\n" % fits, "CONTROL: a line exactly at the taunt cap is quoted")
	assert_false(prompt.contains(over), "a line the validator would cut is not shown as the voice to copy")


func test_the_construct_is_quoted_only_what_it_could_say() -> void:
	var lines: Array = BossDialogue.get_opening_lines("mage_prismatic_construct")
	var too_long: Array = lines.filter(func(l): return DP.spoken_line(str(l)).length() > DP.MAX_BOSS_TAUNT_CHARS)
	assert_false(too_long.is_empty(), "CONTROL: the Construct authors an opening line over the taunt cap")
	var prompt: String = DP.build_boss_intent("Construct", _ctx(lines))
	for l in too_long:
		assert_false(prompt.contains(DP.spoken_line(str(l)).left(60)), "the over-long line stays out of the prompt")
	assert_string_contains(prompt, "Lines you have said", "CONTROL: its shorter line still sets the voice")
