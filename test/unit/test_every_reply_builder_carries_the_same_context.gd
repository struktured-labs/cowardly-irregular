extends GutTest

## Flip one feature flag and every NPC forgets the player mid-conversation.
##
## DynamicConversation has two reply paths:
##
##     if MERGE_REPLY_AND_CHOICES and _llm_available():  _fetch_combined_reply()
##     else:                                             _fetch_npc_reply()
##
## `MERGE_REPLY_AND_CHOICES` is a const `true`, and the else-branch returns a
## scripted line before reaching its builder when the LLM is down — so
## build_npc_reply is UNREACHABLE in production, and it drifted because of that:
##
##     build_npc_opening      memory · quest · party · time · pronoun
##     build_combined_reply   memory · quest · party · time · pronoun
##     build_npc_reply        pronoun ONLY          <- four blocks behind
##
## Setting that flag to false is an ordinary thing to do — to halve a prompt, to
## debug the choice path, to cut tokens. It would compile, run, and silently strip
## memory, quest state, party state and time-of-day from every NPC reply. The
## opening would remember the player and the very next line would not.
##
## REDUNDANT BY DISCARD, in cowir-adhoc's taxonomy: the drift is invisible only
## because the reader is switched off, and the repair that switches it on is the
## commit that exposes it. Same class as the jobs.json `quest` field, and the
## reason that tripwire earned a slot.
##
## Fixed rather than pinned — the builder now takes the same context and the call
## site passes it — so a flag flip is safe instead of merely announced. This guard
## keeps the three in step.

const DP := preload("res://src/llm/DialoguePrompts.gd")

const MEMORY_MARK := "the player asked about the Chancellor last time"
const QUEST_MARK := "Milo is still counting his sample sizes"
const TIME_MARK := "dusk"
const EVENTS: Array = [{"type": "battle", "summary": "The party defeated the Cave Rat King."}]


func _party() -> Dictionary:
	return {"members": [{"name": "Rilla", "job_id": "cleric", "hp_pct": 22.0}]}


## Every prompt a live NPC conversation can send, built the way the game builds them.
func _reply_prompts() -> Dictionary:
	return {
		"opening": DP.build_npc_opening(
			"Elder Theron", "keeper of records", "Harmonia", EVENTS,
			[QUEST_MARK], TIME_MARK, _party(), [MEMORY_MARK]),
		"reply": DP.build_npc_reply(
			"Elder Theron", "keeper of records", "Harmonia", EVENTS,
			"You came back.", "What happened here?",
			[QUEST_MARK], TIME_MARK, _party(), [MEMORY_MARK]),
		"combined": DP.build_combined_reply(
			"Elder Theron", "keeper of records", "Harmonia", EVENTS,
			"You came back.", "What happened here?", 3,
			[QUEST_MARK], _party(), [MEMORY_MARK], TIME_MARK),
	}


# ── the defect ────────────────────────────────────────────────────────────────

func test_every_reply_builder_remembers_the_player() -> void:
	## THE ARM. An NPC that recalls the player in its opening must not forget by
	## its reply — which is exactly what a flag flip used to cause.
	var missing: Array[String] = []
	for name in _reply_prompts():
		if str(_reply_prompts()[name]).find(MEMORY_MARK) == -1:
			missing.append(str(name))
	assert_eq(missing, ([] as Array[String]),
		"these builders drop the conversation memory: %s" % ", ".join(missing))


func test_every_reply_builder_carries_quest_party_and_time() -> void:
	var gaps: Array[String] = []
	for name in _reply_prompts():
		var p: String = str(_reply_prompts()[name])
		if p.find(QUEST_MARK) == -1:
			gaps.append("%s/quest" % name)
		if p.find(TIME_MARK) == -1:
			gaps.append("%s/time" % name)
		if p.find("Rilla") == -1:
			gaps.append("%s/party" % name)
	assert_eq(gaps, ([] as Array[String]),
		"context a sibling renders and this one does not: %s" % ", ".join(gaps))


# ── the flag that makes it latent ─────────────────────────────────────────────

func test_the_reply_path_is_reached_when_the_flag_is_off() -> void:
	## The premise, and the reason this is worth guarding rather than deleting:
	## the drift is invisible ONLY while the flag is true. A reader who flips it
	## is doing ordinary work and must not lose four context blocks for it.
	##
	## SOURCE CHECK, named as one: driving that branch needs a live conversation
	## with an LLM. What it pins is that the call site passes the context — if the
	## builder gains it and the caller does not, the flip strips it anyway.
	var src: String = _code_only(FileAccess.get_file_as_string("res://src/llm/DynamicConversation.gd"))
	assert_false(src.is_empty(), "CONTROL: source must load")
	assert_true(src.contains("MERGE_REPLY_AND_CHOICES and _llm_available()"),
		"the branch must still exist — if it goes, this guard's subject goes with it")
	var at: int = src.find("build_npc_reply(")
	assert_true(at != -1, "CONTROL: the call site must exist")
	var call_block: String = src.substr(at, 340)
	for arg in ["_quest_state_lines", "_party_state", "_memory_lines", "_resolve_time_of_day()"]:
		assert_true(call_block.find(arg) != -1,
			"the reply call site must pass %s, or flipping the flag strips it" % arg)


# ── controls ──────────────────────────────────────────────────────────────────

func test_the_markers_are_really_distinctive() -> void:
	## CONTROL: every assert above is a substring search. If a marker appeared in
	## the prompt's boilerplate the arms would pass without the context block.
	var bare: String = DP.build_npc_reply("Elder Theron", "keeper of records", "Harmonia", EVENTS,
		"You came back.", "What happened here?")
	for mark in [MEMORY_MARK, QUEST_MARK]:
		assert_eq(bare.find(mark), -1,
			"'%s' must not appear when it was not supplied — otherwise the arms prove nothing" % mark)


func test_all_three_builders_really_rendered() -> void:
	## CONTROL: a builder that returned "" would satisfy nothing and fail loudly,
	## but one that returned a stub could pass a find() by accident.
	var ps: Dictionary = _reply_prompts()
	assert_eq(ps.size(), 3, "all three reply paths must be covered")
	for name in ps:
		assert_gt(str(ps[name]).length(), 200,
			"'%s' rendered almost nothing — the builder failed rather than the check passing" % name)


func _code_only(src: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	for line in src.split("\n"):
		var hash_at: int = line.find("#")
		out.append(line if hash_at == -1 else line.substr(0, hash_at))
	return "\n".join(out)
