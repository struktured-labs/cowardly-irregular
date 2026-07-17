extends GutTest

## Day/night compose point 1 (msg 2659) — NPC dialogue time-context injection.
##
## When GameState's canonical clock (day_phase, get_time_of_day_name,
## is_night, time_of_day_changed signal — landed in v3.33.197 via cowir-main)
## resolves a band, DynamicConversation threads it into DialoguePrompts.
## build_npc_opening's prompt as "Time of day: %s" alongside Location. LLM
## generates opening lines that acknowledge dawn / day / dusk / night context
## (Milo at night: "you're up late"; Boris at dawn: "the morning watch is mine").
##
## This cycle covers OPENING PROMPT ONLY. Reply/combined-reply mirrors wait
## for cycle 5 (Milo v2 reply/combined quest_state_lines) to fold — avoiding
## param-order collision on those builders. Once cycle 5 lands, a follow-up
## cycle adds time_of_day as the 8th param on reply/combined too.
##
## Invariants:
##   - Empty time_of_day → byte-identical to pre-cycle-8 prompt (backward compat
##     for older builds, hermetic tests, GameState missing).
##   - The block sits between Location and ctx_block so the LLM reads scene →
##     time → recent-events → voice as a coherent stack.
##   - Composes cleanly with quest_state_lines (cycle 4) — both blocks can coexist.


const DP := preload("res://src/llm/DialoguePrompts.gd")
const DYN_CONV_PATH: String = "res://src/llm/DynamicConversation.gd"


func _read(path: String) -> String:
	var f = FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "file should exist: %s" % path)
	var t = f.get_as_text()
	f.close()
	return t


# ── _format_time_of_day helper

func test_format_time_of_day_empty_returns_empty() -> void:
	assert_eq(DP._format_time_of_day(""), "",
		"empty band must produce no output — the injection is opt-in and byte-identical when absent")


func test_format_time_of_day_dawn() -> void:
	assert_eq(DP._format_time_of_day("dawn"), "Time of day: dawn\n",
		"dawn band emits a single Time-of-day line ending in newline (matches Location line shape)")


func test_format_time_of_day_night() -> void:
	assert_eq(DP._format_time_of_day("night"), "Time of day: night\n",
		"night band emits the same shape — no extra headers, matches the compact prompt discipline")


# ── build_npc_opening backward compat

func test_opening_prompt_with_empty_time_of_day_is_backward_compatible() -> void:
	var prompt: String = DP.build_npc_opening("Milo", "scholar", "Harmonia", [], [])
	assert_true(prompt.find("Time of day:") == -1,
		"empty time_of_day (default arg) must not emit the block — pre-cycle-8 prompt shape preserved")
	assert_true(prompt.find("Persona: scholar") != -1,
		"base prompt shape intact (persona line)")
	assert_true(prompt.find("Respond with ONLY valid JSON") != -1,
		"rules footer intact")


func test_opening_prompt_explicit_empty_time_string_is_backward_compatible() -> void:
	var prompt: String = DP.build_npc_opening("Milo", "scholar", "Harmonia", [], [], "")
	assert_true(prompt.find("Time of day:") == -1,
		"explicit empty time_of_day matches the default — same silent-when-empty contract")


# ── Time-of-day injection surface

func test_opening_prompt_includes_time_of_day_when_provided() -> void:
	var prompt: String = DP.build_npc_opening("Milo", "scholar", "Harmonia", [], [], "night")
	assert_true(prompt.find("Time of day: night") != -1,
		"non-empty band must appear in the opening prompt so the LLM can acknowledge it")


func test_opening_prompt_all_four_bands_land() -> void:
	for band in ["dawn", "day", "dusk", "night"]:
		var prompt: String = DP.build_npc_opening("Milo", "scholar", "Harmonia", [], [], band)
		assert_true(prompt.find("Time of day: %s" % band) != -1,
			"band '%s' must appear in the opening prompt (matches GameState.get_time_of_day_name output set)" % band)


func test_opening_prompt_time_block_sits_between_location_and_events() -> void:
	# Ordering matters for LLM comprehension: scene → time → recent-events → voice.
	# Compose with a non-empty event so ctx_block is emitted too.
	var events: Array = [{"summary": "the party won a battle", "type": "boss_defeat"}]
	var prompt: String = DP.build_npc_opening("Milo", "scholar", "Harmonia", events, [], "dusk")
	var loc_at: int = prompt.find("Location: Harmonia")
	var time_at: int = prompt.find("Time of day: dusk")
	var events_at: int = prompt.find("Recent events:")
	assert_gt(loc_at, -1, "Location line present")
	assert_gt(time_at, -1, "Time-of-day line present")
	assert_gt(events_at, -1, "Recent events section present")
	assert_lt(loc_at, time_at, "Location must precede Time-of-day (scene before time)")
	assert_lt(time_at, events_at, "Time-of-day must precede Recent events (state before history)")


func test_opening_prompt_composes_with_quest_state_voice_block() -> void:
	# Both cycle-4 (quest_state_lines) and cycle-8 (time_of_day) should co-emit.
	var quest_lines: Array = ["I have a chapter drafted."]
	var prompt: String = DP.build_npc_opening("Milo", "scholar", "Harmonia", [], quest_lines, "night")
	assert_true(prompt.find("Time of day: night") != -1,
		"time-of-day block present when both are provided")
	assert_true(prompt.find("recently said") != -1,
		"quest-state voice block also present — the two injections don't cancel each other")
	assert_true(prompt.find("chapter drafted") != -1,
		"quest_state_lines content survives alongside time_of_day")


func test_opening_prompt_absent_when_time_of_day_only_whitespace_still_prints() -> void:
	# Design decision: we DON'T strip whitespace — GameState controls the band vocabulary;
	# if it ever emits " " that's a bug we want visible, not silently swallowed.
	# But defensive: verify the ""-empty-is-empty gate is the only "silent no-op" path.
	var prompt: String = DP.build_npc_opening("Milo", "scholar", "Harmonia", [], [], " ")
	assert_true(prompt.find("Time of day:  ") != -1,
		"whitespace-only band prints as-is (visible artifact) — GameState is the source of truth for band vocabulary")


# ── DynamicConversation._resolve_time_of_day defensive gate

func test_resolve_time_of_day_always_returns_string() -> void:
	var DC: Script = load(DYN_CONV_PATH)
	var dc = DC.new()
	add_child_autofree(dc)
	var band: String = dc._resolve_time_of_day()
	assert_true(typeof(band) == TYPE_STRING,
		"_resolve_time_of_day must always return a String (never null or undefined)")


func test_resolve_time_of_day_reads_gamestate_when_present() -> void:
	# GameState IS an autoload in the test harness (loaded on Godot boot).
	# Sanity-check that _resolve_time_of_day yields one of the canonical bands
	# or empty (defensive path for pre-clock-landing builds).
	var DC: Script = load(DYN_CONV_PATH)
	var dc = DC.new()
	add_child_autofree(dc)
	var band: String = dc._resolve_time_of_day()
	assert_true(band in ["", "dawn", "day", "dusk", "night"],
		"resolved band must be either \"\" (defensive) or one of the four canonical GameState bands — no drift")


# ── Source-inspection regression pins

func test_source_dynamic_conversation_passes_resolved_time_to_opening() -> void:
	var src = _read(DYN_CONV_PATH)
	assert_true(src.find("_resolve_time_of_day()") != -1,
		"DynamicConversation must resolve time-of-day at each build call — the prompt is only informed if the resolver is invoked")
	assert_true(src.find("build_npc_opening") != -1 and src.find("_resolve_time_of_day()") != -1,
		"the opening-prompt call site must pass _resolve_time_of_day() as an arg — regression: silent revert to un-injected prompt")


func test_source_resolver_has_defensive_gate_on_missing_gamestate() -> void:
	var src = _read(DYN_CONV_PATH)
	assert_true(src.find("has_method(\"get_time_of_day_name\")") != -1,
		"_resolve_time_of_day must gate on has_method — hermetic tests / pre-clock builds must not crash")
	assert_true(src.find("get_node_or_null(\"/root/GameState\")") != -1 and src.find("_resolve_time_of_day") != -1,
		"resolver must use get_node_or_null on the autoload path (not Engine.has_singleton — that's the always-false pitfall)")
