extends GutTest

## The fifth party member is the Bard, and a comment claimed it was missing from
## every LLM prompt for two ticks. It was not — and the constant credited with
## the fix governs a builder nothing calls.
##
## `LLMContext.MAX_PARTY_FULL` was bumped 4 → 5 with this justification:
##
##     "Pre-fix the 5th member (typically Bard) was silently omitted from every
##      LLM prompt — boss strategy / party dialogue / NPC context all saw a
##      4-PC party."
##
## ⛔ None of those three reads `LLMContext`. Measured on main:
##
##     LLMContext.build() / build_json() callers in src/      0
##     (the only src/ mentions are two comments in GameLoop)
##     CONTROL  EventLog.  -> real call sites in three files
##
## They each build their own party block — `_format_party_state`,
## `build_boss_intent`'s party loop, `build_party_line`'s — and **none has ever
## capped**. So the constant is right for the day LLMContext is adopted, and the
## claim about what it fixed was wrong. A future reader would have justified more
## work on that file from a sentence describing a surface it does not reach.
##
## THIS FILE PINS THE PROPERTY THE COMMENT WAS ABOUT, in the paths that actually
## ship: every member of a five-person party reaches every live prompt. Behaviour,
## not a source scan — a cap can arrive as a slice, a `for i in 4`, or a MAX_*
## constant, and only rendering the text catches all three.

const DP := preload("res://src/llm/DialoguePrompts.gd")

const NAMES: Array[String] = ["Bram", "Rilla", "Sable", "Kesh", "Wen"]


func _five() -> Array:
	var out: Array = []
	for n in NAMES:
		out.append({
			"name": n, "job": "bard", "job_id": "bard", "condition": "unhurt",
			"hp_pct": 80.0, "mp_pct": 50.0, "ap": 1, "is_alive": true, "status": [],
		})
	return out


## Every prompt a live party state can reach, built the way the game builds them.
func _prompts_with_five() -> Dictionary:
	var five: Array = _five()
	return {
		"npc_reply": DP.build_npc_reply("Theron", "elder", "Harmonia", [], "hi", "hello",
			[], "", {"members": five}, []),
		"npc_opening": DP.build_npc_opening("Theron", "elder", "Harmonia", [],
			[], "", {"members": five}, []),
		"combined_reply": DP.build_combined_reply("Theron", "elder", "Harmonia", [],
			"hi", "hello", 3, [], {"members": five}, [], ""),
		"boss_intent": DP.build_boss_intent("Mordaine", {
			"persona": "The usurper.", "phase": 1, "boss_hp_pct": 50.0,
			"party": five, "available_intents": ["aggress", "turtle"]}),
		## Speaker deliberately NOT one of NAMES: build_party_line renders
		## "You voice <speaker>…" in its header, so a speaker drawn from the roster
		## would satisfy find() from the header even with the party block capped.
		"party_line": DP.build_party_line("a bard who counts exits", [], {
			"event_kind": "turn_start", "speaker_name": "Voice", "speaker_job_id": "bard",
			"party": five, "enemies": [{"name": "Slime", "hp_pct": 100.0}],
			"recent_actions": [], "event_data": {}}),
	}


func _missing_from(text: String) -> Array[String]:
	var gone: Array[String] = []
	for n in NAMES:
		if text.find(n) == -1:
			gone.append(n)
	return gone


# ── the property ──────────────────────────────────────────────────────────────

func test_all_five_reach_every_live_prompt() -> void:
	## THE ARM. Wen is fifth and is the one a cap drops.
	var gaps: Array[String] = []
	for name in _prompts_with_five():
		var missing: Array[String] = _missing_from(str(_prompts_with_five()[name]))
		if not missing.is_empty():
			gaps.append("%s drops %s" % [str(name), ", ".join(missing)])
	assert_eq(gaps, ([] as Array[String]),
		("a five-person party does not reach these prompts in full: %s. "
		+ "Fix in DialoguePrompts — the party block is built per builder "
		+ "(_format_party_state, build_boss_intent's loop, build_party_line's) and none "
		+ "of them may cap. LLMContext.MAX_PARTY_FULL does NOT govern these paths.")
			% ", ".join(gaps))


func test_the_fixture_really_renders_a_party_block() -> void:
	## CONTROL: a builder that dropped the block entirely would also "not cap",
	## and every arm above would pass on a prompt with no party in it at all.
	var ps: Dictionary = _prompts_with_five()
	assert_true(str(ps["npc_reply"]).find("The party standing in front of you") != -1,
		"the NPC party block must render, or its arm proves nothing")
	assert_true(str(ps["boss_intent"]).find("Bram") != -1,
		"the boss roster must render")
	assert_true(str(ps["party_line"]).find("Party state") != -1,
		"the combat party block must render")


func test_a_sixth_member_is_not_silently_dropped() -> void:
	## The party is strict-5 today (CLAUDE.md), so this is the direction a cap
	## would hide in: a limit set to exactly 5 looks correct until the roster grows.
	var six: Array = _five()
	six.append({"name": "Orlin", "job": "guardian", "job_id": "guardian",
		"condition": "unhurt", "hp_pct": 70.0, "is_alive": true, "status": []})
	var p: String = DP.build_npc_reply("Theron", "elder", "Harmonia", [], "hi", "hello",
		[], "", {"members": six}, [])
	assert_true(p.find("Orlin") != -1,
		"a sixth member must render too — a cap at exactly 5 is invisible while the party is 5")


# ── the constant that was credited, and what it actually governs ──────────────

func test_llmcontext_has_no_production_consumer() -> void:
	## The measured fact behind this file's header. ⚠️ GOOD NEWS IF THIS REDS:
	## LLMContext has been adopted, so re-read the corrected comment on
	## MAX_PARTY_FULL, confirm the adopting path renders all five, and delete this
	## arm — it exists to stop the NEXT reader justifying work from a sentence
	## about a surface the file does not reach.
	var callers: Array[String] = []
	for path in _src_gd_files("res://src"):
		if path.ends_with("LLMContext.gd"):
			continue
		var code: String = _code_only(FileAccess.get_file_as_string(path))
		if code.find("LLMContext.build") != -1 or code.find("LLMContext.new") != -1:
			callers.append(path)
	assert_eq(callers, ([] as Array[String]),
		("LLMContext now has a caller: %s. That is GOOD — confirm the adopting path "
		+ "renders all five party members, update the MAX_PARTY_FULL comment, and "
		+ "delete this arm.") % ", ".join(callers))


func test_the_consumer_scan_can_find_a_consumer() -> void:
	## POSITIVE CONTROL: the zero above is worth nothing unless the same scan
	## reports a hit on a class that IS consumed the same way.
	var hits: int = 0
	for path in _src_gd_files("res://src"):
		if path.ends_with("EventLog.gd"):
			continue
		if _code_only(FileAccess.get_file_as_string(path)).find("EventLog.") != -1:
			hits += 1
	assert_gt(hits, 0, "the scan finds no EventLog. consumer either — it is broken, not the data")


func _src_gd_files(root: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(root)
	if d == null:
		return out
	d.list_dir_begin()
	var n: String = d.get_next()
	while n != "":
		var full: String = "%s/%s" % [root, n]
		if d.current_is_dir():
			out.append_array(_src_gd_files(full))
		elif n.ends_with(".gd"):
			out.append(full)
		n = d.get_next()
	d.list_dir_end()
	return out


func _code_only(src: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	for line in src.split("\n"):
		if line.find("\"\"\"") != -1:
			continue
		var hash_at: int = line.find("#")
		out.append(line if hash_at == -1 else line.substr(0, hash_at))
	return "\n".join(out)
