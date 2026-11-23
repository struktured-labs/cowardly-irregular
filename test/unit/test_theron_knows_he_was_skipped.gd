extends GutTest

## struktured's easter egg (2026-11-11): kill the Cave Rat King before the Elder's briefing and a scene says so.
## The LLM-driven Elder then has to know it too, or he briefs a party about a rat they already buried.
## A persona may carry `flag_facts` ({when_flag, fact}); each fact joins the persona only while its story flag is set.

const DP := preload("res://src/llm/DialoguePrompts.gd")
const NPC_SCRIPT := "res://src/exploration/OverworldNPC.gd"
const PERSONAS := "res://data/cutscenes/npc_showcase_personas.json"
const CUTSCENES := "res://data/cutscenes"
const FLAG := "rat_king_fell_before_the_briefing"
const DONE := "theron_sparring_done"

var _was: Dictionary = {}


func before_each() -> void:
	_was = {}
	for f in [FLAG, DONE]:
		if GameState.story_flags.has(f):
			_was[f] = GameState.story_flags[f]
		GameState.story_flags.erase(f)


func after_each() -> void:
	for f in [FLAG, DONE]:
		GameState.story_flags.erase(f)
	for f in _was:
		GameState.story_flags[f] = _was[f]


func _personas() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PERSONAS))
	return parsed as Dictionary if parsed is Dictionary else {}


## The fact as authored for `npc_name` under `flag`; "" when that NPC carries none.
func _authored_fact(npc_name: String, flag: String = FLAG) -> String:
	var entry: Variant = _personas().get(npc_name, {})
	if not (entry is Dictionary):
		return ""
	for f in (entry as Dictionary).get("flag_facts", []):
		if f is Dictionary and str((f as Dictionary).get("when_flag", "")) == flag:
			return str((f as Dictionary).get("fact", ""))
	return ""


## The persona a real NPC of that name would hand the LLM right now.
func _prompt_persona(npc_name: String) -> String:
	var npc = (load(NPC_SCRIPT) as Script).new()
	autofree(npc)
	npc.dynamic = true
	npc.npc_name = npc_name
	npc.refresh_persona()
	return str(npc._persona_for_prompt())


## Every story flag a cutscene on disk sets.
func _flags_a_scene_sets() -> Dictionary:
	var out: Dictionary = {}
	for file in DirAccess.get_files_at(CUTSCENES):
		if file.ends_with(".json"):
			_collect_set_flags(JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [CUTSCENES, file])), out)
	return out


func _collect_set_flags(v: Variant, out: Dictionary) -> void:
	if v is Dictionary:
		if str((v as Dictionary).get("type", "")) == "set_flag":
			out[str((v as Dictionary).get("flag", ""))] = true
		for k in (v as Dictionary):
			_collect_set_flags((v as Dictionary)[k], out)
	elif v is Array:
		for item in (v as Array):
			_collect_set_flags(item, out)


func test_a_fact_joins_the_persona_only_while_its_flag_is_set() -> void:
	var facts: Array = [{"when_flag": "a", "fact": "FACT-A."}, {"when_flag": "b", "fact": "FACT-B."},
		{"when_flag": "", "fact": "NO-FLAG."}, {"when_flag": "a", "fact": ""}, "not a dictionary"]
	var only_a: Callable = func(flag: String) -> bool: return flag == "a"
	assert_eq(DP.persona_with_flag_facts("An elder.", facts, only_a), "An elder. FACT-A.",
		"the set flag's fact is appended; the unset one, the flagless one and the malformed ones are not")
	assert_eq(DP.persona_with_flag_facts("An elder.", facts, func(_f: String) -> bool: return false), "An elder.",
		"with no flag set the persona is the authored one, unchanged")
	assert_eq(DP.persona_with_flag_facts("An elder.", []), "An elder.", "a persona with no facts is unchanged")


func test_the_elder_knows_once_the_scene_has_played() -> void:
	var fact: String = _authored_fact("Elder Theron")
	assert_ne(fact, "", "CONTROL: the Elder's persona carries a fact for %s" % FLAG)
	if fact == "":
		return
	var before: String = _prompt_persona("Elder Theron")
	assert_ne(before, "", "CONTROL: the Elder has a persona before the flag is set")
	assert_false(before.contains(fact), "the ordinary order: he was never skipped, so he is not told he was")
	GameState.set_story_flag(FLAG)
	var after: String = _prompt_persona("Elder Theron")
	assert_true(after.begins_with(before) and after.contains(fact), "skipped: his persona is the authored one plus the fact")
	var opening: String = DP.build_npc_opening("Elder Theron", after, "Harmonia Village", [])
	var reply: String = DP.build_npc_reply("Elder Theron", after, "Harmonia Village", [], "Hm.", "We killed the rat.")
	assert_string_contains(opening, fact, "the fact reaches his opening prompt")
	assert_string_contains(reply, fact, "and his reply prompt")



## He offers the skipped trials as sparring (cutscenes 10d212f3e); once all five are won the LLM Elder knows that too, not only that he was skipped.
func test_the_elder_knows_his_trials_were_won() -> void:
	var fact: String = _authored_fact("Elder Theron", DONE)
	assert_ne(fact, "", "CONTROL: the Elder's persona carries a fact for %s" % DONE)
	if fact == "":
		return
	GameState.set_story_flag(FLAG)
	var skipped: String = _prompt_persona("Elder Theron")
	assert_string_contains(skipped, _authored_fact("Elder Theron"), "CONTROL: skipped, he is told he was skipped")
	assert_false(skipped.contains(fact), "trials still open: he is not told they were all won")
	GameState.set_story_flag(DONE)
	var done: String = _prompt_persona("Elder Theron")
	assert_true(done.begins_with(skipped) and done.contains(fact), "all five won: his persona keeps the skip and adds the win")
	assert_string_contains(DP.build_npc_opening("Elder Theron", done, "Harmonia Village", []), fact, "the win reaches his opening prompt")


## The gate guard saw them go (cowir-story): a fact reaches exactly the NPCs it is authored for, in their own words.
func test_only_those_it_is_authored_for_are_told() -> void:
	GameState.set_story_flag(FLAG)
	var wrong: Array = []
	var untold: int = 0
	var told: int = 0
	for npc_name in _personas():
		var entry: Variant = _personas()[npc_name]
		if not (entry is Dictionary) or not (entry as Dictionary).has("persona"):
			continue
		var authored: String = str((entry as Dictionary)["persona"])
		var fact: String = _authored_fact(str(npc_name))
		var handed: String = _prompt_persona(str(npc_name))
		if fact == "":
			untold += 1
			if handed != authored:
				wrong.append("%s was told and authors no fact" % npc_name)
		else:
			told += 1
			if not (handed.begins_with(authored) and handed.contains(fact)):
				wrong.append("%s authors a fact and was not handed it" % npc_name)
			for other in _personas():
				var theirs: String = _authored_fact(str(other))
				if str(other) != str(npc_name) and theirs != "" and theirs != fact and handed.contains(theirs):
					wrong.append("%s was handed %s's fact" % [npc_name, other])
	assert_gt(untold, 0, "CONTROL: a showcase NPC with no fact exists, and stays as authored")
	assert_gt(told, 1, "CONTROL: more than the Elder is told (the gate guard watched them go)")
	assert_eq(wrong, [], "a flag fact reaches the NPCs it is authored for, each their own, and nobody else")


func test_a_flag_fact_keys_on_a_flag_a_scene_sets() -> void:
	var set_by_scenes: Dictionary = _flags_a_scene_sets()
	assert_true(set_by_scenes.has(FLAG), "CONTROL: a cutscene on disk sets %s" % FLAG)
	var orphans: Array = []
	var seen: int = 0
	for npc_name in _personas():
		var entry: Variant = _personas()[npc_name]
		if not (entry is Dictionary):
			continue
		for f in (entry as Dictionary).get("flag_facts", []):
			seen += 1
			var flag: String = str((f as Dictionary).get("when_flag", "")) if f is Dictionary else ""
			if not set_by_scenes.has(flag) or str((f as Dictionary).get("fact", "")).strip_edges() == "":
				orphans.append("%s:%s" % [npc_name, flag])
	assert_gt(seen, 0, "CONTROL: at least one flag fact is authored")
	assert_eq(orphans, [], "a flag fact whose flag no scene sets (or with no sentence) can never be heard")


func test_the_conversation_is_handed_the_resolved_persona() -> void:
	var src: String = FileAccess.get_file_as_string(NPC_SCRIPT)
	assert_string_contains(src, "_dynamic_conv.setup(npc_name, _persona_for_prompt(),",
		"the LLM conversation is set up with the persona resolved at talk time, not the bare authored one")
