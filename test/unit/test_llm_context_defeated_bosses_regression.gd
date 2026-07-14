extends GutTest

## tick 312: LLMContext._build_progress reads defeated bosses from
## game_constants (canonical store) using the cutscene_flag_*_defeated
## pattern instead of the wrong story_flags + *_boss_defeated pattern.
##
## Pre-fix the bosses array was ALWAYS empty regardless of which
## bosses the player had killed:
##   1. Read from gs.story_flags — wrong dict. Per the dead-flag
##      audit (ticks 277-281), boss-defeated flags live in
##      gs.game_constants ("cutscene_flag_*_defeated"), not story_flags.
##   2. Matched suffix "_boss_defeated" — no flag in the codebase ends
##      with that suffix. The real pattern is "_defeated" with a
##      "cutscene_flag_" prefix.
##
## Result: boss-strategy LLM prompts (BossDialogue + RebalanceDaemon
## context) saw a fresh-game context for every fight. The W3 Tempo
## boss talked to you the same way it would in a no-prior-bosses W1
## save; the rebalance daemon ignored your progression entirely.
##
## Same dead-flag class as the boss_defeated sweep (tick 277-281).

const LLM_CONTEXT_PATH := "res://src/llm/LLMContext.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: reads game_constants, not story_flags ───────────────

func test_reads_from_game_constants() -> void:
	var src := _read(LLM_CONTEXT_PATH)
	var fn_idx: int = src.find("func _build_progress")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nstatic func ", fn_idx + 1)
	if next_fn < 0:
		next_fn = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("gs.get(\"game_constants\")"),
		"_build_progress must read defeated bosses from game_constants (the canonical store)")
	assert_false(body.contains("ends_with(\"_boss_defeated\")"),
		"the dead '_boss_defeated' suffix match must be replaced — no flag in the codebase uses that pattern")


# ── Source pin: matches cutscene_flag_*_defeated pattern ────────────

func test_matches_cutscene_flag_pattern() -> void:
	var src := _read(LLM_CONTEXT_PATH)
	assert_true(src.contains("begins_with(\"cutscene_flag_\")"),
		"_build_progress must filter on cutscene_flag_ prefix (matches the real flag naming)")
	assert_true(src.contains("ends_with(\"_defeated\")"),
		"_build_progress must filter on _defeated suffix")


# ── Behavioral: a defeated boss surfaces in the bosses array ────────

func test_defeated_boss_appears_in_array() -> void:
	# Real LLMContext static call. GameState is a real autoload.
	assert_not_null(GameState, "GameState autoload required")
	if GameState == null:
		return

	# Snapshot+mutate prior flags so we can restore. game_constants is
	# the shared dict — we only touch our test keys.
	var test_keys: Array[String] = [
		"cutscene_flag_rat_king_defeated",
		"cutscene_flag_world1_mordaine_defeated",
		"cutscene_flag_tempo_steampunk_defeated",
		"__not_a_defeated_flag",  # control — wrong prefix, must not appear
	]
	var prior: Dictionary = {}
	for k in test_keys:
		prior[k] = GameState.game_constants.get(k, null)

	GameState.game_constants["cutscene_flag_rat_king_defeated"] = true
	GameState.game_constants["cutscene_flag_world1_mordaine_defeated"] = true
	GameState.game_constants["cutscene_flag_tempo_steampunk_defeated"] = false  # NOT yet defeated
	GameState.game_constants["__not_a_defeated_flag"] = true

	# Invoke the static helper via the loaded script (it's a static
	# method, callable from a class load).
	var script: GDScript = load(LLM_CONTEXT_PATH)
	var progress: Dictionary = script._build_progress(GameState)

	# Restore so other tests aren't disturbed.
	for k in test_keys:
		if prior[k] == null:
			GameState.game_constants.erase(k)
		else:
			GameState.game_constants[k] = prior[k]

	var bosses: Array = progress.get("bosses", [])
	# Defeated bosses must surface (stripped of cutscene_flag_ prefix and
	# _defeated suffix — short ids for tight LLM prompts).
	assert_true("rat_king" in bosses,
		"defeated cutscene_flag_rat_king_defeated must surface as 'rat_king' in the bosses array (pre-fix: always empty)")
	assert_true("world1_mordaine" in bosses,
		"defeated cutscene_flag_world1_mordaine_defeated must surface as 'world1_mordaine'")
	# A flag set to FALSE must not appear (still in progress, not yet beaten).
	assert_false("tempo_steampunk" in bosses,
		"undefeated boss (flag=false) must NOT appear")
	# A flag with wrong prefix must not appear.
	assert_false("__not_a_defeated_flag" in bosses,
		"non-cutscene_flag-prefixed key must NOT appear")


# ── Behavioral: no defeated bosses → empty array, no crash ──────────

func test_no_bosses_defeated_returns_empty() -> void:
	# Build a minimal stub-gs that has game_constants but no defeated flags.
	var stub := RefCounted.new()
	# The static helper uses gs.get(key) — RefCounted's get() works only
	# if we route via an Object subclass. Use a Node so .get() works.
	var stub_node := Node.new()
	add_child_autofree(stub_node)
	stub_node.set("game_constants", {"unrelated_key": true})
	stub_node.set("current_world", 1)
	stub_node.set("worlds_unlocked", 1)
	stub_node.set("corruption_level", 0.0)
	stub_node.set("macro_volatility", 0.0)

	var script: GDScript = load(LLM_CONTEXT_PATH)
	var progress: Dictionary = script._build_progress(stub_node)
	var bosses: Array = progress.get("bosses", [])
	assert_eq(bosses.size(), 0,
		"empty game_constants (no defeated flags) must return an empty bosses array")
