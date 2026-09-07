extends GutTest

## tick 240: ChapterTitles fills 3 missing progression-state gaps
## where the save-slot "Chapter N: Title" stayed stale after key
## story beats.
##
## Pre-fix gaps:
##
##   W1 rat king defeat:
##     - cutscene_flag_world1_rat_king_defeat_complete EXISTS in
##       _CUTSCENE_COMPLETION_FLAGS (set on cutscene finish) but
##       had no ChapterTitles entry.
##     - Result: title stayed "The Whispering Cave" between rat
##       king KO and the chapter4 cutscene firing — sometimes
##       hours of overworld exploration.
##
##   W6 calibrant defeat:
##     - cutscene_flag_world6_calibrant_defeat_complete EXISTS
##       but had no entry. Player defeated Calibrant, save slot
##       still said "Chapter 3: The Answer".
##
##   W6 ending:
##     - cutscene_flag_world6_ending_complete EXISTS (sets
##       game_complete too) but had no ChapterTitles entry.
##       Save slot for a finished game STILL said "The Answer"
##       instead of "The End" — incomplete-feeling end state.
##
## All three flags are durable (set by _play_story_cutscene's
## post-cutscene completion hook, persisted via game_constants
## and mirrored to story_flags). Adding them to CHAPTERS makes
## the save slot reflect the player's actual story position.
##
## ChapterTitles.derive walks the array in order and the LAST
## set flag wins, so new entries must be inserted at the right
## position to bridge the right pair of chapters.

const CHAPTER_TITLES := "res://src/save/ChapterTitles.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── New entries present ─────────────────────────────────────────────

func test_rat_king_defeat_entry_present() -> void:
	var src := _read(CHAPTER_TITLES)
	assert_true(src.contains("\"cutscene_flag_world1_rat_king_defeat_complete\""),
		"W1 rat king defeat completion flag must be in CHAPTERS")
	assert_true(src.contains("\"Rat King Falls\""),
		"W1 rat king title must be 'Rat King Falls'")


func test_calibrant_defeat_entry_present() -> void:
	var src := _read(CHAPTER_TITLES)
	assert_true(src.contains("\"cutscene_flag_world6_calibrant_defeat_complete\""),
		"W6 calibrant defeat completion flag must be in CHAPTERS")
	assert_true(src.contains("\"Calibrant Falls\""),
		"W6 calibrant title must be 'Calibrant Falls'")


func test_ending_entry_present() -> void:
	var src := _read(CHAPTER_TITLES)
	assert_true(src.contains("\"cutscene_flag_world6_ending_complete\""),
		"W6 ending completion flag must be in CHAPTERS")
	assert_true(src.contains("\"The End\""),
		"W6 ending title must be 'The End'")


# ── Ordering: new entries must bridge the right pair ────────────────

func test_rat_king_falls_between_cave_and_warden() -> void:
	# Pin: rat_king_defeat entry comes AFTER chapter3 (Whispering Cave)
	# AND BEFORE chapter4 (Warden's Chain). Order matters because
	# derive() walks the array and the LAST matching flag wins.
	var src := _read(CHAPTER_TITLES)
	var cave_idx: int = src.find("\"cutscene_flag_chapter3_complete\"")
	var rat_idx: int = src.find("\"cutscene_flag_world1_rat_king_defeat_complete\"")
	var warden_idx: int = src.find("\"cutscene_flag_chapter4_complete\"")
	assert_gt(cave_idx, -1)
	assert_gt(rat_idx, -1)
	assert_gt(warden_idx, -1)
	assert_lt(cave_idx, rat_idx,
		"rat_king_defeat entry must come AFTER chapter3 (Whispering Cave) entry")
	assert_lt(rat_idx, warden_idx,
		"rat_king_defeat entry must come BEFORE chapter4 (Warden's Chain) entry")


func test_calibrant_falls_between_answer_and_ending() -> void:
	var src := _read(CHAPTER_TITLES)
	var answer_idx: int = src.find("\"cutscene_flag_world6_chapter3_complete\"")
	var calibrant_idx: int = src.find("\"cutscene_flag_world6_calibrant_defeat_complete\"")
	var ending_idx: int = src.find("\"cutscene_flag_world6_ending_complete\"")
	assert_lt(answer_idx, calibrant_idx,
		"calibrant_defeat entry must come AFTER 'The Answer' entry")
	assert_lt(calibrant_idx, ending_idx,
		"calibrant_defeat entry must come BEFORE 'The End' entry")


# ── Live behavior: derive returns the right title for each flag ─────

func test_derive_returns_rat_king_falls() -> void:
	var cls = load(CHAPTER_TITLES)
	var game_constants := {
		"cutscene_flag_prologue_complete": true,
		"cutscene_flag_chapter1_complete": true,
		"cutscene_flag_chapter3_complete": true,
		"cutscene_flag_world1_rat_king_defeat_complete": true,
		# Chapter4 NOT set yet — title should be Rat King Falls
	}
	var result: Dictionary = cls.derive(game_constants)
	assert_eq(result["title"], "Rat King Falls",
		"derive must return 'Rat King Falls' when rat_king_defeat is the latest flag")
	assert_eq(result["world"], 1, "world should be 1")
	assert_eq(result["chapter"], 3, "chapter should be 3")


func test_derive_returns_calibrant_falls() -> void:
	var cls = load(CHAPTER_TITLES)
	var game_constants := {
		"cutscene_flag_world6_chapter3_complete": true,
		"cutscene_flag_world6_calibrant_defeat_complete": true,
		# Ending NOT set yet
	}
	var result: Dictionary = cls.derive(game_constants)
	assert_eq(result["title"], "Calibrant Falls",
		"derive must return 'Calibrant Falls' when calibrant_defeat is latest")
	assert_eq(result["world"], 6)


func test_derive_returns_the_end() -> void:
	var cls = load(CHAPTER_TITLES)
	var game_constants := {
		"cutscene_flag_world6_chapter3_complete": true,
		"cutscene_flag_world6_calibrant_defeat_complete": true,
		"cutscene_flag_world6_ending_complete": true,
	}
	var result: Dictionary = cls.derive(game_constants)
	assert_eq(result["title"], "The End",
		"derive must return 'The End' when ending_complete is set (finished game)")
	assert_eq(result["world"], 6)
	assert_eq(result["chapter"], 5)


# ── Cross-reference with _CUTSCENE_COMPLETION_FLAGS ─────────────────

func test_added_flags_exist_in_game_loop_map() -> void:
	# Pin: every flag we just added is actually settable — i.e.,
	# _CUTSCENE_COMPLETION_FLAGS in GameLoop maps SOME cutscene id
	# to it. Otherwise the entry is dead config.
	var gl: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true(gl.contains("\"cutscene_flag_world1_rat_king_defeat_complete\""),
		"rat_king_defeat_complete flag must exist in _CUTSCENE_COMPLETION_FLAGS")
	assert_true(gl.contains("\"cutscene_flag_world6_calibrant_defeat_complete\""),
		"calibrant_defeat_complete flag must exist in _CUTSCENE_COMPLETION_FLAGS")
	assert_true(gl.contains("\"cutscene_flag_world6_ending_complete\""),
		"world6_ending_complete flag must exist in _CUTSCENE_COMPLETION_FLAGS")


# ── Pre-existing CHAPTERS preserved ─────────────────────────────────

func test_pre_existing_chapters_intact() -> void:
	# Spot-check that we didn't accidentally drop any pre-existing entries.
	var src := _read(CHAPTER_TITLES)
	for fragment in [
		"\"cutscene_flag_prologue_complete\"",
		"\"cutscene_flag_world1_mordaine_defeated\"",
		"\"cutscene_flag_world2_chapter3_complete\"",
		"\"cutscene_flag_world3_complete\"",
		"\"cutscene_flag_world6_chapter3_complete\"",
		"\"The Beginning\"",
		"\"The Answer\"",
	]:
		assert_true(src.contains(fragment),
			"pre-existing entry preserved: %s" % fragment)
