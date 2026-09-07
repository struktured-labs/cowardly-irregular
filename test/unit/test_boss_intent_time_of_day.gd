extends GutTest

## Day/night compose point 2 (msg 2659, approved 2644/2969) — boss strategic
## intent gains the diurnal band.
##
## The LLM picks a boss's posture per phase from `available_intents`; code still
## owns which ability that becomes (`_bias_by_intent`). This adds the day/night
## band to that decision's context so a boss can read the hour — Umbraxis
## pressing at night, a dragon sluggish at dawn — while the deterministic
## ladder keeps owning the actual move.
##
## SCOPE DISCIPLINE, deliberately: `time_of_day` is FLAVOUR. It reaches the
## prompt and nothing else. It does not filter `available_intents`, so a boss
## can neither gain nor lose options by the clock, and the intent validator is
## untouched. That keeps this compose point out of balance territory — night
## multipliers are struktured's open decision (all seams inert at 1.0), and a
## boss whose option set changed with the hour would be a stat change wearing
## a prompt's clothes.
##
## Backward compatibility is the load-bearing property: every existing caller
## builds a context without ever setting the field, so an empty band must
## produce a byte-identical prompt to the pre-change one.

const DP := preload("res://src/llm/DialoguePrompts.gd")
const CTX := preload("res://src/battle/BossIntentContext.gd")

const BOSS_SOURCE: String = "res://src/battle/BattleManager.gd"


func _ctx_dict(band: String) -> Dictionary:
	var c = CTX.new()
	c.boss_id = "chancellor_mordaine"
	c.phase = 2
	c.persona = "Cold, procedural, certain."
	c.available_intents = ["aggress", "turtle"]
	c.time_of_day = band
	return c.to_dict()


# ── BossIntentContext carries the field ──────────────────────────────────────

func test_context_defaults_to_empty_band() -> void:
	var c = CTX.new()
	assert_eq(c.time_of_day, "",
		"an unset clock must default to empty — every pre-existing producer leaves it untouched")


func test_to_dict_surfaces_time_of_day() -> void:
	var d: Dictionary = _ctx_dict("night")
	assert_true(d.has("time_of_day"), "to_dict must surface time_of_day for the prompt builder")
	assert_eq(str(d["time_of_day"]), "night", "band must round-trip through to_dict unchanged")


func test_to_dict_keeps_every_pre_existing_key() -> void:
	# to_dict's key set is pinned by other suites; adding a field must not drop one.
	var d: Dictionary = _ctx_dict("day")
	for key in ["boss_id", "phase", "boss_hp_pct", "boss_mp_pct", "boss_ap", "boss_status",
				"party", "recent_actions", "available_intents", "persona",
				"player_lead_pc_rules", "learned_patterns_counter", "learned_patterns_sample"]:
		assert_true(d.has(key), "pre-existing to_dict key '%s' must survive the addition" % key)


# ── Prompt injection ─────────────────────────────────────────────────────────

func test_prompt_omits_band_when_empty() -> void:
	var prompt: String = DP.build_boss_intent("Chancellor Mordaine", _ctx_dict(""))
	assert_true(prompt.find("Time of day:") == -1,
		"an empty band must emit nothing — pre-change prompt shape preserved for every existing caller")
	assert_true(prompt.find("start of phase 2") != -1, "base prompt shape intact")


func test_prompt_includes_band_when_present() -> void:
	var prompt: String = DP.build_boss_intent("Chancellor Mordaine", _ctx_dict("night"))
	assert_true(prompt.find("Time of day: night") != -1,
		"a resolved band must reach the prompt so the LLM can colour posture by the hour")


func test_prompt_carries_all_four_bands() -> void:
	for band in ["dawn", "day", "dusk", "night"]:
		var prompt: String = DP.build_boss_intent("Pyrroth", _ctx_dict(band))
		assert_true(prompt.find("Time of day: %s" % band) != -1,
			"band '%s' must reach the boss prompt (matches GameState.get_time_of_day_name's output set)" % band)


func test_band_sits_with_phase_not_after_the_intent_list() -> void:
	# Ordering matters: the LLM should read situation (phase, hour, state) before
	# being asked to choose. A band appearing after the intent list would arrive
	# once the decision is already framed.
	var prompt: String = DP.build_boss_intent("Chancellor Mordaine", _ctx_dict("dusk"))
	var phase_at: int = prompt.find("start of phase")
	var band_at: int = prompt.find("Time of day: dusk")
	var pick_at: int = prompt.find("Pick exactly ONE intent")
	assert_gt(band_at, phase_at, "band must follow the phase line — situation reads in order")
	assert_lt(band_at, pick_at, "band must precede the ask, so the choice is made with the hour known")


func test_band_reuses_the_shared_formatter() -> void:
	# Same helper as the NPC-dialogue compose point, so the two surfaces can
	# never drift into describing the same clock two different ways.
	assert_eq(DP._format_time_of_day("night"), "Time of day: night\n",
		"boss and NPC prompts must render the band identically")
	assert_eq(DP._format_time_of_day(""), "", "empty band renders nothing on every surface")


# ── The flavour-not-balance boundary ─────────────────────────────────────────

func test_band_does_not_change_available_intents() -> void:
	# The guarantee that keeps this out of balance territory.
	var day: Dictionary = _ctx_dict("day")
	var night: Dictionary = _ctx_dict("night")
	assert_eq(day["available_intents"], night["available_intents"],
		"the clock must NOT add or remove intents — a boss whose options changed with the hour is a stat change, and night numbers are struktured's open decision")


func test_band_does_not_leak_into_other_context_fields() -> void:
	var d: Dictionary = _ctx_dict("night")
	assert_eq(str(d["persona"]), "Cold, procedural, certain.", "persona untouched by the band")
	assert_eq(int(d["phase"]), 2, "phase untouched by the band")


# ── Producer wiring ──────────────────────────────────────────────────────────

func test_producer_reads_the_canonical_clock_defensively() -> void:
	var src: String = FileAccess.get_file_as_string(BOSS_SOURCE)
	assert_true(src.find("ctx.time_of_day = str(gs_clock.get_time_of_day_name())") != -1,
		"_build_boss_intent_context must populate the band — the prompt can only carry what the producer sets")
	assert_true(src.find("has_method(\"get_time_of_day_name\")") != -1,
		"the read must be guarded — headless battles and pre-clock saves have no GameState clock and must not crash")
	assert_true(src.find("get_node_or_null(\"/root/GameState\")") != -1,
		"resolve the autoload via the tree, never Engine.has_singleton (always false for autoloads in Godot 4)")
