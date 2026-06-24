extends GutTest

## tick 104 regression: W1 Mordaine post-defeat dialogue must be
## reachable. Same DragonCave._on_boss_defeated dead-code class as
## ticks 102-103 — CastleHarmonia declared defeat_cutscene =
## "world1_mordaine_defeat" but the field is read only by the dead
## _on_boss_defeated, so the W1 narrative closer never played. Players
## who beat Mordaine got sent straight to W2 prologue with no
## Mordaine resolution.

const GAME_LOOP := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _pending_cutscene_body() -> String:
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _get_pending_story_cutscene")
	assert_gt(idx, -1, "_get_pending_story_cutscene must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_mordaine_defeat_gate_present() -> void:
	var body := _pending_cutscene_body()
	var pattern: String = (
		"if flags.get(\"cutscene_flag_world1_mordaine_defeated\", false) "
		+ "and not flags.get(\"cutscene_flag_world1_mordaine_defeat_complete\", false):"
	)
	assert_true(body.contains(pattern),
		"_get_pending_story_cutscene must check Mordaine defeat flag + completion guard")
	assert_true(body.contains("return \"world1_mordaine_defeat\""),
		"_get_pending_story_cutscene must return world1_mordaine_defeat")


func test_mordaine_gate_scoped_to_castle_harmonia() -> void:
	var body := _pending_cutscene_body()
	var idx: int = body.find("return \"world1_mordaine_defeat\"")
	assert_gt(idx, -1, "Mordaine defeat return must exist")
	var window_start: int = max(0, idx - 200)
	var window: String = body.substr(window_start, idx - window_start)
	assert_true(window.contains("_current_map_id == \"castle_harmonia\""),
		"Mordaine defeat must be gated on castle_harmonia — castle scene player returns to after victory")


func test_mordaine_gate_precedes_w2_prologue_gate() -> void:
	# Critical ordering: Mordaine defeat dialogue plays IN the castle
	# BEFORE the W2 prologue gate (which fires in suburban_overworld).
	# If the prologue fires first on its trigger map, the player
	# misses the Mordaine closer entirely.
	#
	# In practice the two gates check different maps so ordering doesn't
	# strictly matter at runtime — but pinning ordering keeps the
	# narrative-flow intent explicit.
	var body := _pending_cutscene_body()
	var mordaine_idx: int = body.find("return \"world1_mordaine_defeat\"")
	var w2_prologue_idx: int = body.find("return \"world2_prologue\"")
	assert_gt(mordaine_idx, -1, "Mordaine defeat return must exist")
	assert_gt(w2_prologue_idx, -1, "W2 prologue return must exist")
	assert_lt(mordaine_idx, w2_prologue_idx,
		"Mordaine defeat gate must precede W2 prologue gate in source — closer plays before the W2 transition trigger")


func test_mordaine_defeat_in_completion_flag_map() -> void:
	var src := _read(GAME_LOOP)
	var key_quote: String = "\"world1_mordaine_defeat\":"
	var key_idx: int = src.find(key_quote)
	assert_gt(key_idx, -1,
		"_CUTSCENE_COMPLETION_FLAGS must contain key 'world1_mordaine_defeat'")
	var line_end: int = src.find("\n", key_idx)
	var line: String = src.substr(key_idx, line_end - key_idx) if line_end > -1 else src.substr(key_idx)
	assert_true(line.contains("\"cutscene_flag_world1_mordaine_defeat_complete\""),
		"world1_mordaine_defeat must map to cutscene_flag_world1_mordaine_defeat_complete")


func test_mordaine_defeat_file_exists() -> void:
	assert_true(FileAccess.file_exists("res://data/cutscenes/world1_mordaine_defeat.json"),
		"world1_mordaine_defeat.json must exist on disk")


func test_castle_harmonia_still_sets_mordaine_defeated_flag() -> void:
	# Sanity: CastleHarmonia must still set the defeat flag the gate
	# above predicates on.
	var src := _read("res://src/maps/dungeons/CastleHarmonia.gd")
	assert_true(src.contains("\"cutscene_flag_world1_mordaine_defeated\""),
		"CastleHarmonia must still set cutscene_flag_world1_mordaine_defeated via defeat_cutscene_flags")


func test_full_w1_defeat_cutscene_chain_complete() -> void:
	# Coverage: both W1 boss defeat cutscenes (rat king + Mordaine)
	# now have return paths. Together with ticks 102-103's W2-W5
	# gates, every authored W1-W5 dungeon-boss defeat cutscene is
	# reachable.
	var body := _pending_cutscene_body()
	for cutscene_id in [
		"world1_rat_king_defeat",
		"world1_mordaine_defeat",
		"world2_warden_defeat",
		"world3_tempo_defeat",
		"world4_warden_defeat",
		"world5_arbiter_defeat",
	]:
		assert_true(body.contains("return \"" + cutscene_id + "\""),
			"%s must have a return path — closes the defeat-cutscene series" % cutscene_id)
